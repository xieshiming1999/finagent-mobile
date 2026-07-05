import 'dart:convert';
import 'dart:io';

import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/tool_context.dart';

typedef MarketRuntimeProbeActionRunner =
    Future<Object> Function(
      String action,
      List<String> symbols,
      Map<String, dynamic> input,
      ToolContext context,
    );

class MarketRuntimeProbeService {
  static bool fixtureModeForTest = false;

  final MarketRuntimeProbeActionRunner _runAction;
  final Map<String, dynamic> Function() _getHealth;

  MarketRuntimeProbeService({
    required DataManager dataManager,
    required MarketRuntimeProbeActionRunner runAction,
    required Map<String, dynamic> Function() getHealth,
  }) : _runAction = runAction,
       _getHealth = getHealth;

  Map<String, dynamic> status(String basePath) {
    final report = loadRuntimeLiveStatusReport(basePath);
    final status = _loadStatus(basePath);
    final guidance = _buildRuntimeProbeGuidance(_getHealth());
    return {
      'action': 'runtime_probe',
      'probeAction': 'status',
      'probeMode': status['mode'],
      'interfaceId': 'data.runtime_probe',
      'provider': 'local',
      'providerId': 'local',
      'capabilityId': 'local.data.runtime_probe',
      'providerMode': 'local-runtime-control',
      'cacheStatus': 'runtime-evidence',
      'cacheDecision':
          'runtime_probe reads durable operational evidence for provider health and route control; it does not return reusable market data rows',
      'canonicalSchema': 'runtime_probe_status',
      'canonicalTable': 'runtime_probe_status',
      'readbackAction': 'runtime_probe',
      'status': {...status, ...guidance},
      'liveStatus': report,
      ...guidance,
    };
  }

  Future<Map<String, dynamic>> run(
    String basePath,
    ToolContext context, {
    String mode = 'all',
    List<String> probeIds = const [],
  }) async {
    final normalizedMode = _normalizeMode(mode);
    final health = _getHealth();
    final guidance = _buildRuntimeProbeGuidance(health);
    final selected = probeIds.isNotEmpty
        ? _selectExplicitProbeSpecs(probeIds)
        : _selectSupportedProbeSpecs(normalizedMode, health);
    final selectedTargets =
        _targetsForProbeIds(selected.map((spec) => spec.id).toList(), [
          ..._asRows(guidance['recommendedTargets']),
          ..._asRows(guidance['blockedTargets']),
        ]);
    final startedAt = DateTime.now().toUtc().toIso8601String();
    final runningStatus = {
      'running': true,
      'mode': normalizedMode,
      'runId': _runtimeProbeRunId(startedAt),
      'startedAt': startedAt,
      'finishedAt': null,
      'selectedProbeIds': selected.map((spec) => spec.id).toList(),
      'selectedTargets': selectedTargets,
      'selectedCount': selected.length,
      'outputPath': _liveStatusPath(basePath),
      'summary': null,
      'error': null,
      ...guidance,
    };
    _persistStatus(basePath, runningStatus);

    try {
      final passedApis = <Map<String, dynamic>>[];
      final failures = <Map<String, dynamic>>[];
      if (fixtureModeForTest ||
          Platform.environment['FINAGENT_RUNTIME_PROBE_FIXTURE'] == '1') {
        for (final spec in selected) {
          passedApis.add({
            'id': spec.id,
            'provider': spec.provider,
            'family': spec.family,
            'status': 'passed',
            'validationState': 'fixture-live-validated',
            'failureClass': null,
            'parsedCount': 1,
            'providerTime': DateTime.now().toUtc().toIso8601String(),
            'durationMs': null,
            'error': null,
            'fixture': true,
          });
        }
      } else {
        for (final spec in selected) {
          final row = await _runOne(spec, context);
          if (row['status'] == 'passed') {
            passedApis.add(row);
          } else {
            failures.add(row);
          }
        }
      }
      final report = {
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'summary': _buildSummary(passedApis, failures),
        'byProvider': _countByProvider(passedApis, failures),
        'passedApis': passedApis,
        'failures': failures,
      };
      _persistLiveStatus(basePath, report);
      final finalStatus = {
        'running': false,
        'mode': normalizedMode,
        'runId': runningStatus['runId'],
        'startedAt': startedAt,
        'finishedAt': DateTime.now().toUtc().toIso8601String(),
        'selectedProbeIds': selected.map((spec) => spec.id).toList(),
        'selectedTargets': selectedTargets,
        'selectedCount': selected.length,
        'outputPath': _liveStatusPath(basePath),
        'summary': report['summary'],
        'error': null,
        ...guidance,
      };
      _persistStatus(basePath, finalStatus);
      return {
        'action': 'runtime_probe',
        'probeAction': 'run',
        'probeMode': normalizedMode,
        'interfaceId': 'data.runtime_probe',
        'provider': 'local',
        'providerId': 'local',
        'capabilityId': 'local.data.runtime_probe',
        'providerMode': 'local-runtime-control',
        'cacheStatus': 'runtime-evidence',
        'cacheDecision':
            'runtime_probe generated durable operational evidence for provider health and route control; use interface_availability before normal provider routing',
        'canonicalSchema': 'runtime_probe_status',
        'canonicalTable': 'runtime_probe_status',
        'readbackAction': 'runtime_probe',
        'status': finalStatus,
        'liveStatus': report,
        ...guidance,
      };
    } catch (error) {
      final failedStatus = {
        ...runningStatus,
        'running': false,
        'finishedAt': DateTime.now().toUtc().toIso8601String(),
        'error': '$error',
      };
      _persistStatus(basePath, failedStatus);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _runOne(
    _ProbeSpec spec,
    ToolContext context,
  ) async {
    try {
      final result = await _runAction(
        spec.action,
        spec.symbols,
        spec.input,
        context,
      );
      final payload = result is Map<String, dynamic>
          ? result
          : {'result': result};
      return {
        'id': spec.id,
        'provider': spec.provider,
        'family': spec.family,
        'status': 'passed',
        'validationState': 'configured-live-validated',
        'failureClass': null,
        'parsedCount': _parsedCount(payload),
        'providerTime': _providerTime(payload),
        'durationMs': null,
        'error': null,
      };
    } catch (error) {
      final failureClass = _classifyFailure('$error');
      final temporaryUntil = _temporaryBlockUntil(failureClass);
      return {
        'id': spec.id,
        'provider': spec.provider,
        'family': spec.family,
        'status': 'failed',
        'validationState': 'runtime-blocked',
        'failureClass': failureClass,
        'parsedCount': 0,
        'providerTime': null,
        'durationMs': null,
        'error': '$error',
        'temporaryBlockUntil': temporaryUntil,
        'routeBlockScope': temporaryUntil == null ? null : 'capability',
        'nextProbeAfter': temporaryUntil,
      };
    }
  }

  List<_ProbeSpec> _selectSupportedProbeSpecs(
    String mode,
    Map<String, dynamic> health,
  ) {
    final ids = <String>{};
    if (mode == 'credential' || mode == 'all') {
      for (final row in _asRows(health['credentialActivationQueue'])) {
        final probeId = row['probeId'] as String?;
        if (probeId != null) ids.add(probeId);
      }
    }
    if (mode == 'unstable' || mode == 'all') {
      for (final row in _asRows(health['providerGapQueue'])) {
        if (row['gapClass'] != 'serial-live-retry') continue;
        final probeId = row['probeId'] as String?;
        if (probeId != null) ids.add(probeId);
      }
    }
    if (mode == 'failures' || mode == 'all') {
      for (final row in _asRows(health['failureActionQueue'])) {
        if (!_isRetryableFailureProbeRow(row)) continue;
        final probeId = row['probeId'] as String?;
        if (probeId != null) ids.add(probeId);
      }
    }
    if (mode == 'all') {
      for (final row in _routingCriticalTargets(health)) {
        final probeId = row['probeId'] as String?;
        if (probeId != null) ids.add(probeId);
      }
    }
    return ids
        .map((id) => _supportedProbeSpecs[id])
        .whereType<_ProbeSpec>()
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }

  List<_ProbeSpec> _selectExplicitProbeSpecs(List<String> probeIds) {
    return probeIds
        .toSet()
        .map((id) => _supportedProbeSpecs[id])
        .whereType<_ProbeSpec>()
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }

  List<Map<String, dynamic>> _asRows(Object? rows) {
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) {
          return row.map((key, value) => MapEntry('$key', value));
        })
        .toList(growable: false);
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Object>()
        .map((item) => '$item')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> _loadStatus(String basePath) {
    final file = File(_statusPath(basePath));
    if (!file.existsSync()) {
      return _emptyStatus();
    }
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is Map<String, dynamic>) {
        return {..._emptyStatus(), ...json};
      }
    } catch (_) {}
    return _emptyStatus();
  }

  void _persistStatus(String basePath, Map<String, dynamic> status) {
    final file = File(_statusPath(basePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(status)}\n',
    );
  }

  void _persistLiveStatus(String basePath, Map<String, dynamic> report) {
    final file = File(_liveStatusPath(basePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  }

  Map<String, dynamic> _emptyStatus() => {
    'running': false,
    'mode': null,
    'runId': null,
    'startedAt': null,
    'finishedAt': null,
    'selectedProbeIds': const [],
    'selectedTargets': const [],
    'selectedCount': 0,
    'outputPath': null,
    'summary': null,
    'error': null,
    ..._emptyGuidance(),
  };

  String _normalizeMode(String mode) {
    return switch (mode.trim().toLowerCase()) {
      'credential' => 'credential',
      'unstable' => 'unstable',
      'failures' => 'failures',
      _ => 'all',
    };
  }

  Map<String, dynamic> _buildSummary(
    List<Map<String, dynamic>> passedApis,
    List<Map<String, dynamic>> failures,
  ) {
    final failureClasses = failures
        .map((row) => '${row['failureClass'] ?? 'provider-error'}')
        .toList();
    final runtimeBlocked = failureClasses
        .where((item) => item == 'runtime-blocked')
        .length;
    final transport = failureClasses
        .where((item) => item == 'transport' || item == 'timeout')
        .length;
    final credential = failureClasses
        .where((item) => item == 'credential-or-permission')
        .length;
    final quota = failureClasses
        .where((item) => item == 'quota-or-rate-limit')
        .length;
    return {
      'total': passedApis.length + failures.length,
      'passed': passedApis.length,
      'failed': failures.length,
      'blocked': runtimeBlocked,
      'skipped': 0,
      'credentialGated': credential,
      'quotaGated': quota,
      'unsupported': 0,
      'invalidParameters': 0,
      'transportOrProviderUnstable': transport,
      'runtimeBlocked': runtimeBlocked,
    };
  }

  Map<String, int> _countByProvider(
    List<Map<String, dynamic>> passedApis,
    List<Map<String, dynamic>> failures,
  ) {
    final counts = <String, int>{};
    for (final row in [...passedApis, ...failures]) {
      final provider = '${row['provider'] ?? 'unknown'}';
      counts[provider] = (counts[provider] ?? 0) + 1;
    }
    return counts;
  }

  int _parsedCount(Map<String, dynamic> payload) {
    final count = payload['count'];
    if (count is int) return count;
    if (count is num) return count.toInt();
    final data = payload['data'];
    if (data is List) return data.length;
    return 1;
  }

  String? _providerTime(Map<String, dynamic> payload) {
    final provenance = payload['provenance'];
    if (provenance is Map && provenance['sourceDataTime'] != null) {
      return '${provenance['sourceDataTime']}';
    }
    if (payload['latestSourceTime'] != null) {
      return '${payload['latestSourceTime']}';
    }
    if (payload['timestamp'] != null) {
      return '${payload['timestamp']}';
    }
    return null;
  }

  Map<String, dynamic> _buildRuntimeProbeGuidance(Map<String, dynamic> health) {
    final recommendedTargets = _dedupeTargets([
      ..._asRows(
        health['credentialActivationQueue'],
      ).expand(_targetFromCredentialRow),
      ..._asRows(health['providerGapQueue']).expand(_targetFromProviderGapRow),
      ..._asRows(health['failureActionQueue']).expand(_targetFromFailureRow),
      ..._routingCriticalTargets(health),
    ]);
    final blockedTargets = _dedupeTargets([
      ..._asRows(
        health['credentialActivationQueue'],
      ).expand(_blockedTargetFromCredentialRow),
      ..._asRows(
        health['policyDisabledQueue'],
      ).expand((row) => _blockedTargetFromGapRow(row, 'policy-disabled')),
      ..._asRows(
        health['providerGapQueue'],
      ).expand((row) => _blockedTargetFromGapRow(row, 'not-actionable-gap')),
      ..._asRows(
        health['failureActionQueue'],
      ).expand(_blockedTargetFromFailureRow),
    ]);
    return {
      'availableModes': const ['credential', 'unstable', 'failures', 'all'],
      'recommendedTargets': recommendedTargets,
      'blockedTargets': blockedTargets,
      'providerProbePacks': _providerProbePacks(),
      'guidance': const {
        'progressiveDisclosurePath': [
          'interfaces',
          'interface_describe',
          'interface_availability',
          'data_health',
          'runtime_probe',
        ],
        'normalWorkflowRule':
            'Use cache/readback or validated provider routes first. Do not use unsupported, deferred, reference-only, or unknown-schema routes as normal workflow.',
        'rerunPolicy':
            'Run only recommended or explicitly selected bounded probe IDs. Do not broad-probe on startup or retry provider-rejected routes.',
      },
    };
  }

  Map<String, dynamic> _emptyGuidance() => {
    'availableModes': const ['credential', 'unstable', 'failures', 'all'],
    'recommendedTargets': const [],
    'blockedTargets': const [],
    'providerProbePacks': _providerProbePacks(),
    'guidance': const {
      'progressiveDisclosurePath': [
        'interfaces',
        'interface_describe',
        'interface_availability',
        'data_health',
        'runtime_probe',
      ],
      'normalWorkflowRule':
          'Use governed interfaces and validated provider evidence before live provider calls.',
      'rerunPolicy':
          'Run bounded probes only when current health or explicit user selection justifies them.',
    },
  };

  Iterable<Map<String, dynamic>> _targetFromCredentialRow(
    Map<String, dynamic> row,
  ) {
    final probeId = row['probeId'] as String?;
    if (probeId == null || row['activationState'] == 'credential-missing') {
      return const [];
    }
    return [
      _buildTarget(
        row,
        probeId: probeId,
        currentStatus:
            '${row['liveStatus'] ?? row['activationState'] ?? row['status']}',
        reason:
            '${row['reason'] ?? 'Credential or quota-gated capability has configuration/evidence that can be revalidated.'}',
        expectedExitCondition:
            'Leaves credential action list when live validation passes, or when provider reports permission/quota/config failure.',
        normalWorkflowAllowedBeforeSuccess: false,
        recommendedMode: 'credential',
        sourceQueue: 'credentialActivationQueue',
        riskPolicy:
            'Credential/quota scoped; run only selected capability probes.',
        nextAction:
            '${row['nextAction'] ?? 'Run credential probe after confirming credentials/quota are configured.'}',
      ),
    ];
  }

  Iterable<Map<String, dynamic>> _targetFromProviderGapRow(
    Map<String, dynamic> row,
  ) {
    final probeId = row['probeId'] as String?;
    if (probeId == null || row['gapClass'] != 'serial-live-retry') {
      return const [];
    }
    return [
      _buildTarget(
        row,
        probeId: probeId,
        currentStatus: '${row['liveStatus'] ?? row['status']}',
        reason:
            '${row['reason'] ?? 'Provider gap has a registered serial live probe and needs fresh evidence.'}',
        expectedExitCondition:
            'Leaves provider gap after live evidence validates the route, or after failure is classified as provider/runtime/schema work.',
        normalWorkflowAllowedBeforeSuccess: false,
        recommendedMode: 'unstable',
        sourceQueue: 'providerGapQueue',
        riskPolicy: 'Transport/schema validation; serial probe only.',
        nextAction:
            '${row['nextAction'] ?? 'Run unstable probe, then inspect data_health/interface_availability.'}',
      ),
    ];
  }

  Iterable<Map<String, dynamic>> _targetFromFailureRow(
    Map<String, dynamic> row,
  ) {
    final probeId = row['probeId'] as String?;
    if (probeId == null) return const [];
    if (!_isRetryableFailureProbeRow(row)) {
      return const [];
    }
    return [
      {
        'interfaceId':
            (row['affectedInterfaces'] is List &&
                (row['affectedInterfaces'] as List).isNotEmpty)
            ? '${(row['affectedInterfaces'] as List).first}'
            : null,
        'provider': '${row['provider'] ?? 'unknown'}',
        'capabilityId': row['capabilityId'],
        'probeId': probeId,
        'currentStatus':
            '${row['status'] ?? row['validationState'] ?? row['failureClass'] ?? 'failed'}',
        'reason':
            '${row['reason'] ?? row['error'] ?? 'A classified failure has a registered probe that can be rechecked.'}',
        'expectedExitCondition':
            'Leaves failure action list when fresh evidence passes or the failure is reclassified as non-retryable implementation/provider work.',
        'riskPolicy':
            'Failure retry; run bounded probe only, keep cache/readback first.',
        'timeoutPolicy': _timeoutPolicyForProvider('${row['provider'] ?? ''}'),
        'normalWorkflowAllowedBeforeSuccess': false,
        'recommendedMode': 'failures',
        'nextAction':
            '${row['nextAction'] ?? 'Run failure probe, then inspect refreshed failure class and route readiness.'}',
        'sourceQueue': 'failureActionQueue',
      },
    ];
  }

  Iterable<Map<String, dynamic>> _routingCriticalTargets(
    Map<String, dynamic> health,
  ) {
    const critical = {
      'stock.quote',
      'index.quote',
      'fund.etf_quote',
      'news.finance_feed',
      'stock.daily_kline',
      'index.daily_kline',
    };
    final targets = <Map<String, dynamic>>[];
    for (final row in _asRows(health['interfaces'] ?? health['rows'])) {
      final interfaceId = '${row['interfaceId'] ?? ''}';
      if (!critical.contains(interfaceId)) continue;
      if ('${row['liveStatus'] ?? ''}' == 'passed') continue;
      final liveProbeIds = _stringList(row['liveProbeIds']);
      if (liveProbeIds.isEmpty) continue;
      final supportedProviders = _stringList(row['supportedProviders']);
      final gatedProviders = _stringList(row['gatedProviders']);
      final provider = supportedProviders.isNotEmpty
          ? supportedProviders.first
          : gatedProviders.isNotEmpty
          ? gatedProviders.first
          : 'unknown';
      final capabilities = _asRows(row['capabilities']);
      final localRows = row['localRows'];
      for (final probeId in liveProbeIds) {
        Map<String, dynamic>? capability;
        for (final candidate in capabilities) {
          if (candidate['probeId'] == probeId) {
            capability = candidate;
            break;
          }
        }
        targets.add({
          'interfaceId': interfaceId,
          'provider': provider,
          'capabilityId': capability?['capabilityId'],
          'probeId': probeId,
          'currentStatus': '${row['liveStatus'] ?? row['health'] ?? 'unknown'}',
          'reason':
              'Routing-critical interface lacks fresh passed runtime evidence.',
          'expectedExitCondition':
              'Runtime evidence passes, or the interface remains cache/readback/fallback-first until a provider route is validated.',
          'riskPolicy':
              'Routing-critical bounded probe; keep provider-specific limits.',
          'timeoutPolicy': _timeoutPolicyForProvider(provider),
          'normalWorkflowAllowedBeforeSuccess':
              localRows is num && localRows > 0,
          'recommendedMode': 'all',
          'nextAction':
              'Run bounded probe only if live route freshness is needed; otherwise prefer cache/readback.',
          'sourceQueue': 'runtimeCritical',
        });
      }
    }
    return targets;
  }

  Iterable<Map<String, dynamic>> _blockedTargetFromFailureRow(
    Map<String, dynamic> row,
  ) {
    final probeId = row['probeId'] as String?;
    if (probeId == null || _isRetryableFailureProbeRow(row)) {
      return const [];
    }
    final failureClass = '${row['failureClass'] ?? 'unknown'}';
    return [
      _buildTarget(
        row,
        probeId: probeId,
        currentStatus:
            '${row['status'] ?? row['validationState'] ?? failureClass}',
        reason:
            '${row['reason'] ?? row['error'] ?? 'Failure class $failureClass is not retryable without root-cause change.'}',
        expectedExitCondition:
            '${row['exitCondition'] ?? 'Resolve credential/quota/provider-contract/schema/unsupported-route root cause, then reclassify before probing.'}',
        normalWorkflowAllowedBeforeSuccess: false,
        recommendedMode: 'failures',
        sourceQueue: 'failureActionQueue',
        riskPolicy:
            'Blocked from runtime_probe retry selection; resolve root cause before probing.',
        nextAction:
            '${row['nextAction'] ?? 'Do not probe automatically; fix the listed root cause or select an explicit bounded probe after user decision.'}',
      ),
    ];
  }

  Iterable<Map<String, dynamic>> _blockedTargetFromCredentialRow(
    Map<String, dynamic> row,
  ) {
    final probeId = row['probeId'] as String?;
    if (probeId == null || row['activationState'] != 'credential-missing') {
      return const [];
    }
    return [
      _buildTarget(
        row,
        probeId: probeId,
        currentStatus: '${row['activationState']}',
        reason:
            'Credential is missing; live probe would only confirm missing configuration.',
        expectedExitCondition:
            'Configure credential/quota, then run credential probe.',
        normalWorkflowAllowedBeforeSuccess: false,
        recommendedMode: 'credential',
        sourceQueue: 'credentialActivationQueue',
        riskPolicy: 'Blocked before network call.',
        nextAction:
            '${row['nextAction'] ?? 'Configure credential before probing.'}',
      ),
    ];
  }

  bool _isRetryableFailureProbeRow(Map<String, dynamic> row) {
    final retryPolicy = '${row['retryPolicy'] ?? ''}'.toLowerCase();
    if (retryPolicy == 'do-not-retry' ||
        retryPolicy.contains('do not retry') ||
        retryPolicy.contains('no automatic retry')) {
      return false;
    }
    final failureClass = '${row['failureClass'] ?? ''}'.toLowerCase();
    const nonRetryable = {
      'credential-or-permission',
      'quota-or-rate-limit',
      'provider_rejected_or_unsupported_route',
      'runtime-blocked',
      'schema-contract',
      'schema-mismatch',
      'unsupported',
      'not-supported',
    };
    if (nonRetryable.contains(failureClass)) return false;
    return failureClass == 'transport' ||
        failureClass == 'timeout' ||
        failureClass == 'provider-error' ||
        failureClass == 'runtime-unavailable' ||
        failureClass == 'transport-unstable';
  }

  Iterable<Map<String, dynamic>> _blockedTargetFromGapRow(
    Map<String, dynamic> row,
    String label,
  ) {
    final probeId = row['probeId'] as String?;
    if (probeId == null || row['gapClass'] == 'serial-live-retry') {
      return const [];
    }
    const nonActionable = {
      'disabled',
      'not-supported',
      'credential-gated',
      'quota-gated',
      'output-only',
      'deferred',
    };
    if (!nonActionable.contains('${row['status']}') &&
        label != 'policy-disabled') {
      return const [];
    }
    return [
      _buildTarget(
        row,
        probeId: probeId,
        currentStatus: '${row['liveStatus'] ?? row['status']}',
        reason:
            '${row['reason'] ?? '$label is not a runtime-probe candidate without implementation/configuration change.'}',
        expectedExitCondition:
            'Reclassify capability, implement route/normalizer/readback, or configure required provider state before probing.',
        normalWorkflowAllowedBeforeSuccess: false,
        recommendedMode: 'all',
        sourceQueue: 'providerGapQueue',
        riskPolicy:
            'Blocked to avoid repeating known non-actionable provider calls.',
        nextAction:
            '${row['nextAction'] ?? 'Do not probe as normal workflow; resolve the listed implementation or policy gap first.'}',
      ),
    ];
  }

  Map<String, dynamic> _buildTarget(
    Map<String, dynamic> row, {
    required String probeId,
    required String currentStatus,
    required String reason,
    required String expectedExitCondition,
    required bool normalWorkflowAllowedBeforeSuccess,
    required String recommendedMode,
    required String sourceQueue,
    required String riskPolicy,
    required String nextAction,
  }) {
    return {
      'interfaceId': row['interfaceId'],
      'provider': '${row['provider'] ?? 'unknown'}',
      'capabilityId': row['capabilityId'],
      'probeId': probeId,
      'currentStatus': currentStatus,
      'reason': reason,
      'expectedExitCondition': expectedExitCondition,
      'riskPolicy': riskPolicy,
      'timeoutPolicy': _timeoutPolicyForProvider('${row['provider'] ?? ''}'),
      'normalWorkflowAllowedBeforeSuccess': normalWorkflowAllowedBeforeSuccess,
      'recommendedMode': recommendedMode,
      'nextAction': nextAction,
      'sourceQueue': sourceQueue,
    };
  }

  List<Map<String, dynamic>> _targetsForProbeIds(
    List<String> probeIds,
    Object? targets,
  ) {
    final byId = {
      for (final target in _asRows(targets))
        if (target['probeId'] is String) target['probeId'] as String: target,
    };
    return probeIds
        .map((probeId) {
          return byId[probeId] ??
              {
                'interfaceId': null,
                'provider': _providerFromProbeId(probeId),
                'capabilityId': null,
                'probeId': probeId,
                'currentStatus': 'explicit-selection',
                'reason': 'Explicit user/agent selected bounded probe ID.',
                'expectedExitCondition':
                    'Probe run writes durable evidence or reports unsupported/failed status.',
                'riskPolicy':
                    'Explicit bounded probe selection; no arbitrary endpoint discovery.',
                'timeoutPolicy': _timeoutPolicyForProvider(
                  _providerFromProbeId(probeId),
                ),
                'normalWorkflowAllowedBeforeSuccess': false,
                'recommendedMode': 'all',
                'nextAction':
                    'Run selected probe, then inspect data_health/interface_availability.',
                'sourceQueue': 'runtimeCritical',
              };
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _dedupeTargets(
    Iterable<Map<String, dynamic>> targets,
  ) {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final target in targets) {
      final probeId = target['probeId'] as String?;
      if (probeId == null || !seen.add(probeId)) continue;
      result.add(target);
    }
    result.sort((a, b) {
      final providerCompare = '${a['provider']}'.compareTo('${b['provider']}');
      if (providerCompare != 0) return providerCompare;
      return '${a['probeId']}'.compareTo('${b['probeId']}');
    });
    return result;
  }

  String _providerFromProbeId(String probeId) {
    if (probeId.contains('.')) return probeId.split('.').first;
    if (probeId.contains('_')) return probeId.split('_').first;
    return 'unknown';
  }

  String _timeoutPolicyForProvider(String provider) {
    switch (provider.toLowerCase()) {
      case 'eastmoney':
      case 'akshare':
        return 'serial, provider-aware timeout; EastMoney/AkShare may need longer timeout.';
      case 'wind':
      case 'tushare':
        return 'serial credential/quota-aware probe; stop on quota or permission block.';
      case 'tdx':
        return 'serial local/native probe; classify parser/runtime separately.';
      default:
        return 'serial bounded probe with default runtime timeout.';
    }
  }

  List<Map<String, dynamic>> _providerProbePacks() => const [
    {
      'provider': 'tencent',
      'label': 'Tencent Finance direct and Tencent-origin routes',
      'status': 'active',
      'sourceRouteFamilies': [
        'qt.gtimg.cn quote',
        'proxy.finance.qq.com rank/kline',
        'stock.gtimg.cn transactions/AH',
        'web.ifzq.gtimg.cn HK/reference',
      ],
      'boundedProbeIds': [
        'tencent.direct.stock_quote',
        'tencent.direct.index_quote',
        'tencent.direct.fund_etf_quote',
        'tencent.direct.stock_rank_list',
        'tencent.direct.stock_daily_kline',
        'tencent.direct.index_daily_kline',
        'tencent.direct.stock_transactions',
        'tencent.quote.listed_fund_batch',
        'tencent.quote.convertible_bond_batch',
        'tencent.kline.convertible_bond_none',
        'tencent.kline.etf_none',
        'tencent.transactions.etf_page_0',
      ],
      'rawEvidenceLocation':
          'reports/integrations/tencent-broad-raw-2026-06-23/',
      'timeoutPolicy': 'serial, bounded runtime probes; no broad startup probe',
      'concurrencyPolicy': 'concurrency 1 for runtime live probes',
      'schemaClassification':
          'supported, typed-output-only, deferred, reference-only, unsupported',
      'governanceMapping':
          'Supported interfaces enter normal workflow only after capability, normalizer, persistence/readback, provenance, and tests are present; remaining broad discovery rows stay evidence-only until promoted.',
      'promotionRequirements': [
        'interface contract',
        'provider capability',
        'adapter/normalizer',
        'cache/readback',
        'provenance fields',
        'focused tests',
        'cross-runtime status',
      ],
      'finElectronStatus':
          '13 governed Tencent provider capabilities under interface contracts; HK/US quote is global-only under stock.quote, while HK K-line, AH rows, and provider metadata remain evidence-only until promoted.',
      'finAgentStatus':
          'stock.quote includes A-share and global-only Tencent HK/US quote capabilities; index.quote, unadjusted stock/index daily K-line, stock transactions, bounded fund.etf_quote, bounded fund.listed_fund_quote, unadjusted ETF daily OHLCV, ETF transactions, convertible-bond quote, and unadjusted convertible-bond daily K-line are supported; adjusted stock/index/ETF/convertible-bond daily K-line, HK K-line, and AH routes remain explicit not-supported/deferred until native adapters exist.',
    },
    {
      'provider': 'sina',
      'label': 'Sina Finance direct and wrapper-origin routes',
      'status': 'active',
      'sourceRouteFamilies': [
        'direct Sina quote/kline/news/sector/transactions',
        'AkShare *_sina wrapper reference rows',
      ],
      'boundedProbeIds': [
        'sina.direct.stock_quote',
        'sina.direct.index_quote',
        'sina.direct.stock_daily_kline',
        'sina.direct.stock_transactions',
        'sina.direct.news_finance_feed',
      ],
      'rawEvidenceLocation':
          'reports/integrations/sina-wrapper-reprobe-raw/',
      'timeoutPolicy': 'serial direct probes; wrapper references stay bounded',
      'concurrencyPolicy': 'concurrency 1 for live/provider verification',
      'schemaClassification':
          'supported, output-only, wrapper-reference, deferred, failed/diagnostic',
      'governanceMapping':
          'Direct Sina capabilities can enter normal workflow only through interfaces; wrapper evidence remains AkShare/Sina-origin unless promoted.',
      'promotionRequirements': [
        'interface contract',
        'provider capability',
        'adapter/normalizer',
        'cache/readback',
        'provenance fields',
        'focused tests',
        'cross-runtime status',
      ],
      'finElectronStatus':
          '13 governed Sina interfaces including intraday OHLCV and fund dividend/factor; transaction-count and classification/ESG remain output-only evidence; direct Sina ETF daily K-line remains not-supported until a native decoder exists.',
      'finAgentStatus':
          '13 governed native Sina interfaces including intraday OHLCV and fund dividend/factor; wrapper/batch paths stay bounded evidence or not-supported',
    },
  ];

  String _runtimeProbeRunId(String startedAt) =>
      'runtime-probe-${startedAt.replaceAll(RegExp(r'[:.]'), '-')}';
}

Map<String, dynamic>? loadRuntimeLiveStatusReport(String? basePath) {
  if (basePath == null || basePath.trim().isEmpty) return null;
  final file = File(_liveStatusPath(basePath));
  if (!file.existsSync()) return null;
  try {
    final json = jsonDecode(file.readAsStringSync());
    return json is Map<String, dynamic> ? json : null;
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> overlayDataHealthWithRuntimeEvidence(
  Map<String, dynamic> payload,
  Map<String, dynamic>? report,
) {
  if (report == null) return payload;
  final merged = Map<String, dynamic>.from(payload);
  final summary = Map<String, dynamic>.from(
    (merged['summary'] as Map<String, dynamic>?) ?? const {},
  );
  final reportSummary =
      (report['summary'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  summary['liveStatusRows'] = reportSummary['total'] ?? 0;
  summary['liveStatusPassed'] = reportSummary['passed'] ?? 0;
  summary['liveStatusFailedOrBlocked'] =
      (reportSummary['failed'] ?? 0) + (reportSummary['blocked'] ?? 0);
  merged['summary'] = summary;
  merged['runtimeProbeStatus'] = report;
  merged['providerGapQueue'] = _overlayGapRows(
    merged['providerGapQueue'],
    report,
  );
  merged['providerGaps'] = merged['providerGapQueue'];
  merged['credentialActivationQueue'] = _overlayGapRows(
    merged['credentialActivationQueue'],
    report,
  );
  merged['credentialActivations'] = merged['credentialActivationQueue'];
  merged['policyDisabledQueue'] = _overlayGapRows(
    merged['policyDisabledQueue'],
    report,
  );
  merged['policyDisabled'] = merged['policyDisabledQueue'];
  merged['failureActionQueue'] = _overlayFailureRows(
    merged['failureActionQueue'],
    report,
  );
  merged['failureActions'] = merged['failureActionQueue'];
  return merged;
}

List<Map<String, dynamic>> _overlayGapRows(
  Object? rows,
  Map<String, dynamic> report,
) {
  if (rows is! List) return const [];
  final index = _runtimeRowsById(report);
  return rows
      .whereType<Map>()
      .map((row) {
        final mapped = row.map((key, value) => MapEntry('$key', value));
        final probeId = mapped['probeId'] as String?;
        if (probeId == null) return mapped;
        final runtime = index[probeId];
        if (runtime == null) return mapped;
        return {
          ...mapped,
          'liveStatus': runtime['status'],
          'liveValidationState': runtime['validationState'],
          'liveFailureClass': runtime['failureClass'],
          'liveProviderTime': runtime['providerTime'],
          'liveError': runtime['error'],
        };
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> _overlayFailureRows(
  Object? rows,
  Map<String, dynamic> report,
) {
  final current = rows is List
      ? rows.whereType<Map>().map((row) {
          return row.map((key, value) => MapEntry('$key', value));
        }).toList()
      : <Map<String, dynamic>>[];
  final indexByProbeId = <String, int>{};
  for (var i = 0; i < current.length; i++) {
    final probeId = current[i]['probeId'];
    if (probeId is String && probeId.isNotEmpty) {
      indexByProbeId[probeId] = i;
    }
  }
  for (final runtime in _runtimeRows(report, 'failures')) {
    final probeId = runtime['id'] as String? ?? '';
    final failureClass = '${runtime['failureClass'] ?? ''}';
    final validationState = '${runtime['validationState'] ?? ''}';
    final mapped = {
      'id': 'failure:$probeId',
      'probeId': probeId,
      'provider': runtime['provider'],
      'family': runtime['family'],
      'status': runtime['status'],
      'validationState': runtime['validationState'],
      'failureClass': runtime['failureClass'],
      'retryPolicy': _runtimeFailureRetryPolicy(failureClass, validationState),
      'cacheDecision': _runtimeFailureCacheDecision(
        failureClass,
        validationState,
      ),
      'presenceReason':
          runtime['error'] ??
          _runtimeFailurePresenceReason(failureClass, validationState),
      'exitCondition': _runtimeFailureExitCondition(
        failureClass,
        validationState,
      ),
      'nextAction': _runtimeFailureNextAction(failureClass, validationState),
      'error': runtime['error'],
    };
    final index = indexByProbeId[probeId];
    if (index != null) {
      current[index] = {...current[index], ...mapped};
    } else {
      current.add(mapped);
    }
  }
  return current;
}

String _runtimeFailureRetryPolicy(String failureClass, String validationState) {
  if (failureClass == 'credential-or-permission' ||
      validationState == 'credential-gated') {
    return 'no automatic retry until credential or permission changes';
  }
  if (failureClass == 'quota-or-rate-limit' ||
      validationState == 'quota-gated') {
    return 'no broad retry until quota reset; cache/readback first';
  }
  if (failureClass == 'schema-or-contract' ||
      validationState == 'unsupported-by-provider') {
    return 'no retry until adapter or schema contract is fixed';
  }
  if (failureClass == 'transport' ||
      failureClass == 'timeout' ||
      validationState == 'transport-or-provider-unstable') {
    return 'serial retry only after provider/network recovery';
  }
  if (failureClass == 'runtime_unavailable' ||
      failureClass == 'runtime-blocked' ||
      validationState == 'runtime-blocked') {
    return 'retry only after runtime dependency is restored';
  }
  return 'manual triage required before retry';
}

String _runtimeFailureCacheDecision(
  String failureClass,
  String validationState,
) {
  if (failureClass == 'credential-or-permission' ||
      validationState == 'credential-gated') {
    return 'Keep provider gate active and avoid live refresh until credentials or permissions change. Use local cache/readback or healthy fallback providers when available.';
  }
  if (failureClass == 'quota-or-rate-limit' ||
      validationState == 'quota-gated') {
    return 'Do not spend more quota on broad retry; prefer cache/readback and fallback providers. Use local cache/readback or healthy fallback providers when available.';
  }
  if (failureClass == 'schema-or-contract' ||
      validationState == 'unsupported-by-provider') {
    return 'Do not persist or reuse new provider output until adapter, parser, normalizer, and readback contract are fixed.';
  }
  if (failureClass == 'transport' ||
      failureClass == 'timeout' ||
      validationState == 'transport-or-provider-unstable') {
    return 'Preserve existing cached data; retry only with a bounded serial probe after provider/network recovery. Use local cache/readback or healthy fallback providers when available.';
  }
  if (failureClass == 'runtime_unavailable' ||
      failureClass == 'runtime-blocked' ||
      validationState == 'runtime-blocked') {
    return 'Provider refresh is blocked by runtime dependency; use cache/readback until the dependency is restored. Use local cache/readback or healthy fallback providers when available.';
  }
  return 'Classify root cause before widening live routing. Use local cache/readback or healthy fallback providers when available.';
}

String _runtimeFailurePresenceReason(
  String failureClass,
  String validationState,
) {
  if (failureClass == 'credential-or-permission' ||
      validationState == 'credential-gated') {
    return 'Provider credentials or permissions are not accepted for this route.';
  }
  if (failureClass == 'quota-or-rate-limit' ||
      validationState == 'quota-gated') {
    return 'Provider quota or rate limit blocks this route.';
  }
  if (failureClass == 'schema-or-contract' ||
      validationState == 'unsupported-by-provider') {
    return 'Provider response does not satisfy the expected interface contract.';
  }
  if (failureClass == 'transport' ||
      failureClass == 'timeout' ||
      validationState == 'transport-or-provider-unstable') {
    return 'Provider route is failing due to transport, timeout, or provider instability.';
  }
  if (failureClass == 'runtime_unavailable' ||
      failureClass == 'runtime-blocked' ||
      validationState == 'runtime-blocked') {
    return 'Runtime dependency is unavailable for this provider route.';
  }
  return 'Provider failure requires classified triage before widening use.';
}

String _runtimeFailureExitCondition(
  String failureClass,
  String validationState,
) {
  if (failureClass == 'credential-or-permission' ||
      validationState == 'credential-gated') {
    return 'Leaves this queue after credential or permission changes are verified by a bounded probe, or after the capability is reclassified as gated, disabled, unsupported, or supported.';
  }
  if (failureClass == 'quota-or-rate-limit' ||
      validationState == 'quota-gated') {
    return 'Leaves this queue after quota availability is verified or the capability is reclassified with explicit quota policy.';
  }
  if (failureClass == 'schema-or-contract' ||
      validationState == 'unsupported-by-provider') {
    return 'Leaves this queue after adapter/parser/normalizer contract is fixed and focused readback verification passes, or after the path is marked unsupported/diagnostic.';
  }
  if (failureClass == 'transport' ||
      failureClass == 'timeout' ||
      validationState == 'transport-or-provider-unstable') {
    return 'Leaves this queue after serial retry produces stable evidence or the provider is reclassified as unstable, disabled, unsupported, or gated.';
  }
  if (failureClass == 'runtime_unavailable' ||
      failureClass == 'runtime-blocked' ||
      validationState == 'runtime-blocked') {
    return 'Leaves this queue after the runtime dependency is restored and the registered probe is rerun successfully or reclassified.';
  }
  return 'Leaves this queue after root cause classification, provider evidence update, and focused verification.';
}

String _runtimeFailureNextAction(String failureClass, String validationState) {
  if (validationState == 'runtime-blocked' ||
      failureClass == 'runtime_unavailable' ||
      failureClass == 'runtime-blocked') {
    return 'Restore the runtime dependency, then retry only the bounded registered probe.';
  }
  if (validationState == 'transport-or-provider-unstable' ||
      failureClass == 'transport' ||
      failureClass == 'timeout') {
    return 'Retry only after provider/network recovery; keep the failure classified if it repeats.';
  }
  if (validationState == 'credential-gated' ||
      validationState == 'quota-gated') {
    return 'Use configured credential/quota gate before retrying this route.';
  }
  if (validationState == 'unsupported-by-provider') {
    return 'Keep this route unsupported or replace it with a provider-supported interface.';
  }
  return 'Inspect the failure and update provider classification before retrying.';
}

Map<String, Map<String, dynamic>> _runtimeRowsById(
  Map<String, dynamic> report,
) {
  final index = <String, Map<String, dynamic>>{};
  for (final row in [
    ..._runtimeRows(report, 'passedApis'),
    ..._runtimeRows(report, 'failures'),
  ]) {
    final id = row['id'] as String?;
    if (id != null && id.isNotEmpty) {
      index[id] = row;
    }
  }
  return index;
}

List<Map<String, dynamic>> _runtimeRows(
  Map<String, dynamic> report,
  String key,
) {
  final rows = report[key];
  if (rows is! List) return const [];
  return rows
      .whereType<Map>()
      .map((row) {
        return row.map((k, v) => MapEntry('$k', v));
      })
      .toList(growable: false);
}

String _statusPath(String basePath) =>
    '$basePath/data/runtime-probes/status.json';

String _liveStatusPath(String basePath) =>
    '$basePath/data/runtime-probes/live-status/latest.json';

String _classifyFailure(String error) {
  final value = error.toLowerCase();
  if (value.contains('timeout') || value.contains('abort')) return 'timeout';
  if (value.contains('permission') ||
      value.contains('token') ||
      value.contains('api key') ||
      value.contains('权限')) {
    return 'credential-or-permission';
  }
  if (value.contains('quota') ||
      value.contains('rate limit') ||
      value.contains('frequency')) {
    return 'quota-or-rate-limit';
  }
  if (value.contains('network') ||
      value.contains('fetch failed') ||
      value.contains('socket') ||
      value.contains('proxy')) {
    return 'transport';
  }
  if (value.contains('unsupported') || value.contains('not implemented')) {
    return 'runtime-blocked';
  }
  return 'provider-error';
}

String? _temporaryBlockUntil(String failureClass) {
  final now = DateTime.now().toUtc();
  if (failureClass == 'timeout') {
    return now.add(const Duration(minutes: 15)).toIso8601String();
  }
  if (failureClass == 'transport') {
    return now.add(const Duration(minutes: 30)).toIso8601String();
  }
  return null;
}

const Map<String, _ProbeSpec> _supportedProbeSpecs = {
  'mobile_marketdata_tdx_count': _ProbeSpec(
    id: 'mobile_marketdata_tdx_count',
    action: 'tdx_count',
    provider: 'tdx',
    family: 'tdx',
  ),
  'mobile_marketdata_ex_categories': _ProbeSpec(
    id: 'mobile_marketdata_ex_categories',
    action: 'ex_categories',
    provider: 'tdx',
    family: 'extdx',
  ),
  'mobile_yahoo_earnings': _ProbeSpec(
    id: 'mobile_yahoo_earnings',
    action: 'yahoo_earnings',
    provider: 'yfinance',
    family: 'yahoo',
    symbols: ['AAPL'],
    input: {
      'provider': 'yfinance',
      'providerMode': 'strict',
      'cacheMode': 'live-only',
    },
  ),
};

class _ProbeSpec {
  final String id;
  final String action;
  final String provider;
  final String family;
  final List<String> symbols;
  final Map<String, dynamic> input;

  const _ProbeSpec({
    required this.id,
    required this.action,
    required this.provider,
    required this.family,
    this.symbols = const [],
    this.input = const {},
  });
}
