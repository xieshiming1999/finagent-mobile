import '../../../agent/data_fetcher/base_fetcher.dart';
import '../../../agent/data_fetcher/models.dart';
import '../../../agent/data_fetcher/provider_policy.dart';
import '../services/cache_policy.dart';
import '../services/market_data_runtime_probe_service.dart';
import 'data_api_interface_contract.dart';

typedef DataApiProviderCall<T> = Future<T> Function(BaseFetcher fetcher);
typedef DataApiCapabilityCall<T> =
    Future<DataApiProviderExecution<T>?> Function(
      DataApiProviderCapability capability,
    );
typedef DataApiProviderIsUsable<T> = bool Function(T result);
typedef DataApiCacheRead<T> = Future<DataApiLocalCacheResult<T>?> Function();

class DataApiLocalCacheResult<T> {
  final T data;
  final String source;
  final String? providerName;
  final String? capabilityId;

  const DataApiLocalCacheResult({
    required this.data,
    this.source = 'local',
    this.providerName,
    this.capabilityId,
  });
}

class DataApiProviderExecution<T> {
  final T data;
  final String source;
  final String? providerName;

  const DataApiProviderExecution({
    required this.data,
    required this.source,
    this.providerName,
  });
}

class DataApiRouteProvenance {
  final String interfaceId;
  final String capabilityId;
  final String provider;
  final String providerName;
  final String? cachedProvider;
  final String? cachedSource;
  final String? cachedCapabilityId;
  final String canonicalSchema;
  final String? canonicalTable;
  final String cacheStatus;
  final String cachePolicyMode;
  final String cacheDecision;
  final String providerMode;
  final String? requestedProvider;
  final bool allowFallback;

  const DataApiRouteProvenance({
    required this.interfaceId,
    required this.capabilityId,
    required this.provider,
    required this.providerName,
    this.cachedProvider,
    this.cachedSource,
    this.cachedCapabilityId,
    required this.canonicalSchema,
    this.canonicalTable,
    required this.cacheStatus,
    this.cachePolicyMode = 'cacheFirst',
    this.cacheDecision = 'cache decision not recorded',
    this.providerMode = 'auto',
    this.requestedProvider,
    this.allowFallback = true,
  });

  Map<String, Object?> toJson() => {
    'interfaceId': interfaceId,
    'capabilityId': capabilityId,
    'provider': provider,
    'providerName': providerName,
    'cachedProvider': cachedProvider,
    'cachedSource': cachedSource,
    'cachedCapabilityId': cachedCapabilityId,
    'canonicalSchema': canonicalSchema,
    'canonicalTable': canonicalTable,
    'cacheStatus': cacheStatus,
    'cachePolicyMode': cachePolicyMode,
    'cacheDecision': cacheDecision,
    'providerMode': providerMode,
    'requestedProvider': requestedProvider,
    'allowFallback': allowFallback,
  };

  Map<String, Object?> routePolicyJson() => {
    'providerMode': providerMode,
    'requestedProvider': requestedProvider,
    'allowFallback': allowFallback,
  };
}

class DataApiRouteResult<T> {
  final T data;
  final String source;
  final DataApiRouteProvenance provenance;

  const DataApiRouteResult({
    required this.data,
    required this.source,
    required this.provenance,
  });
}

class DataApiInterfaceRouter {
  final DataApiInterfaceContract contract;
  final BaseFetcher? Function(FinanceProvider provider) fetcherForProvider;
  final String? Function()? runtimeBasePathProvider;

  const DataApiInterfaceRouter({
    this.contract = dataApiInterfaceContract,
    this.fetcherForProvider = _noFetcherForProvider,
    this.runtimeBasePathProvider,
  });

  Future<DataApiRouteResult<T>> run<T>({
    required String interfaceId,
    required DataApiProviderCall<T> call,
    required DataApiProviderIsUsable<T> isUsable,
    required String emptyMessage,
    required String failureMessage,
    DataApiProviderConstraint constraint = const DataApiProviderConstraint(),
    CachePolicy cachePolicy = const CachePolicy(),
    DataApiCacheRead<T>? readCache,
  }) async {
    return runCapability<T>(
      interfaceId: interfaceId,
      call: (capability) async {
        final fetcher = fetcherForProvider(capability.provider);
        if (fetcher == null) return null;
        final result = await call(fetcher);
        return DataApiProviderExecution<T>(
          data: result,
          source: fetcher.name,
          providerName: fetcher.name,
        );
      },
      isUsable: isUsable,
      emptyMessage: emptyMessage,
      failureMessage: failureMessage,
      constraint: constraint,
      cachePolicy: cachePolicy,
      readCache: readCache,
    );
  }

  Future<DataApiRouteResult<T>> runCapability<T>({
    required String interfaceId,
    required DataApiCapabilityCall<T> call,
    required DataApiProviderIsUsable<T> isUsable,
    required String emptyMessage,
    required String failureMessage,
    DataApiProviderConstraint constraint = const DataApiProviderConstraint(),
    CachePolicy cachePolicy = const CachePolicy(),
    DataApiCacheRead<T>? readCache,
  }) async {
    final definition = contract.getInterface(interfaceId);
    if (definition == null) {
      throw DataFetchError('Unknown data API interface: $interfaceId');
    }

    final cacheDecision = _cacheReadDecision(constraint, cachePolicy);
    final providerMode = constraint.provider == null
        ? DataApiProviderMode.auto.name
        : constraint.providerMode.name;
    final requestedProvider = constraint.provider?.name;
    final allowFallback = constraint.allowFallback;
    String? cacheMissDetail;
    if (readCache != null && cacheDecision.readCache) {
      final cached = await readCache();
      if (cached != null && isUsable(cached.data)) {
        final cachedProvider = cached.providerName ?? cached.source;
        final cachedSource = cached.source;
        final cachedCapabilityId = cached.capabilityId ?? 'local.cache';
        if (_cacheHitSatisfiesProviderConstraint(
          cachedProvider: cachedProvider,
          cachedSource: cachedSource,
          requestedProvider: constraint.provider,
          providerMode: constraint.providerMode,
        )) {
          return DataApiRouteResult<T>(
            data: cached.data,
            source: cached.source,
            provenance: DataApiRouteProvenance(
              interfaceId: definition.id,
              capabilityId: cachedCapabilityId,
              provider: cachedProvider,
              providerName: cached.providerName ?? cached.source,
              cachedProvider: cachedProvider,
              cachedSource: cachedSource,
              cachedCapabilityId: cachedCapabilityId,
              canonicalSchema: definition.canonicalSchema,
              canonicalTable: definition.dataStoreTables.isEmpty
                  ? null
                  : definition.dataStoreTables.first,
              cacheStatus: 'cache-hit',
              cachePolicyMode: cacheDecision.mode,
              cacheDecision:
                  '${cacheDecision.reason}; cache reader returned usable canonical rows from $cachedSource',
              providerMode: providerMode,
              requestedProvider: requestedProvider,
              allowFallback: allowFallback,
            ),
          );
        }
        cacheMissDetail =
            'cache rows came from $cachedSource, which does not satisfy strict provider $requestedProvider';
      }
    }
    if (cachePolicy.mode == CachePolicyMode.cacheOnly) {
      throw DataFetchError(
        '$failureMessage: cache-only lookup missed; ${cacheMissDetail ?? cacheDecision.reason}',
      );
    }

    final errors = <String>[];
    final capabilities = contract.eligibleCapabilities(
      interfaceId,
      constraint: constraint,
    );
    final routedCapabilities = _applyRuntimeEvidence(
      interfaceId,
      capabilities,
      constraint,
    );
    for (final capability in routedCapabilities) {
      try {
        final result = await call(capability);
        if (result == null) continue;
        if (isUsable(result.data)) {
          return DataApiRouteResult<T>(
            data: result.data,
            source: result.source,
            provenance: DataApiRouteProvenance(
              interfaceId: definition.id,
              capabilityId: capability.id,
              provider: capability.provider.name,
              providerName: result.providerName ?? result.source,
              canonicalSchema: definition.canonicalSchema,
              canonicalTable: capability.canonicalTable,
              cacheStatus: 'provider-hit',
              cachePolicyMode: cacheDecision.mode,
              cacheDecision: cacheDecision.readCache
                  ? '${cacheDecision.reason}; ${cacheMissDetail ?? 'no usable cache rows matched the requirement'}'
                  : cacheDecision.reason,
              providerMode: providerMode,
              requestedProvider: requestedProvider,
              allowFallback: allowFallback,
            ),
          );
        }
        errors.add('${result.providerName ?? result.source}: $emptyMessage');
      } catch (e) {
        errors.add('${capability.provider.name}: $e');
        if (_shouldStop(e)) break;
      }
    }

    final runtimeBlocked = _runtimeBlockedDetails(
      interfaceId,
      contract.registeredCapabilities(interfaceId, constraint: constraint),
      constraint,
    );
    final blocked = contract
        .registeredCapabilities(interfaceId, constraint: constraint)
        .where((capability) => !capability.isEligible)
        .map(
          (capability) =>
              '${capability.provider.name}:${capability.status.name}'
              '${capability.reason == null ? '' : ' (${capability.reason})'}',
        )
        .join('; ');
    final detail = errors.isNotEmpty
        ? errors.join('; ')
        : capabilities.isNotEmpty && routedCapabilities.isEmpty
        ? 'no runtime-eligible providers after probe evidence gating'
              '${runtimeBlocked.isEmpty ? '' : ': ${runtimeBlocked.join('; ')}'}'
        : blocked.isNotEmpty
        ? 'no eligible providers; blocked capabilities: $blocked'
        : 'no compatible providers registered';
    throw DataFetchError('$failureMessage: $detail');
  }

  List<DataApiProviderCapability> _applyRuntimeEvidence(
    String interfaceId,
    List<DataApiProviderCapability> capabilities,
    DataApiProviderConstraint constraint,
  ) {
    final basePath = runtimeBasePathProvider?.call();
    final report = loadRuntimeLiveStatusReport(basePath);
    if (report == null) return capabilities;
    final rankByCapability = <String, int>{};
    final allowed = <DataApiProviderCapability>[];
    for (final capability in capabilities) {
      final decision = _runtimeRouteDecision(
        interfaceId,
        capability,
        report,
        allowDegraded: constraint.allowDegraded,
      );
      if (!decision.eligible) continue;
      rankByCapability[capability.id] = decision.sortRank;
      allowed.add(capability);
    }
    allowed.sort((a, b) {
      final rank = (rankByCapability[a.id] ?? 9).compareTo(
        rankByCapability[b.id] ?? 9,
      );
      if (rank != 0) return rank;
      return a.priority.compareTo(b.priority);
    });
    return allowed;
  }

  List<String> _runtimeBlockedDetails(
    String interfaceId,
    List<DataApiProviderCapability> capabilities,
    DataApiProviderConstraint constraint,
  ) {
    final basePath = runtimeBasePathProvider?.call();
    final report = loadRuntimeLiveStatusReport(basePath);
    if (report == null) return const [];
    return capabilities
        .map((capability) {
          final decision = _runtimeRouteDecision(
            interfaceId,
            capability,
            report,
            allowDegraded: constraint.allowDegraded,
          );
          if (decision.eligible) return null;
          return '${capability.provider.name}:${decision.routeState}'
              ' (${decision.reason})';
        })
        .whereType<String>()
        .toList(growable: false);
  }

  bool _shouldStop(Object error) {
    final message = error.toString().toLowerCase();
    final providerGateStatus = RegExp(r'\b(401|403|429)\b');
    return message.contains('permission') ||
        message.contains('unauthorized') ||
        message.contains('forbidden') ||
        message.contains('credential') ||
        message.contains('token') ||
        message.contains('api key') ||
        providerGateStatus.hasMatch(message) ||
        message.contains('权限') ||
        message.contains('rate limit') ||
        message.contains('too many requests') ||
        message.contains('quota') ||
        message.contains('frequency') ||
        message.contains('频率') ||
        message.contains('参数') ||
        message.contains('invalid argument');
  }

  _CacheReadDecision _cacheReadDecision(
    DataApiProviderConstraint constraint,
    CachePolicy cachePolicy,
  ) {
    final mode = cachePolicy.mode.name;
    if (!cachePolicy.shouldReadCache) {
      return _CacheReadDecision(
        readCache: false,
        mode: mode,
        reason: 'liveOnly bypasses reusable local data',
      );
    }
    return _CacheReadDecision(
      readCache: true,
      mode: mode,
      reason: '$mode reads reusable local data before provider routing',
    );
  }

  bool _cacheHitSatisfiesProviderConstraint({
    required String cachedProvider,
    required String cachedSource,
    required FinanceProvider? requestedProvider,
    required DataApiProviderMode providerMode,
  }) {
    if (providerMode != DataApiProviderMode.strict ||
        requestedProvider == null) {
      return true;
    }
    final requested = _canonicalProviderToken(requestedProvider.name);
    return _canonicalProviderToken(cachedProvider) == requested ||
        _canonicalProviderToken(cachedSource) == requested;
  }

  String _canonicalProviderToken(String value) {
    final clean = value.trim().toLowerCase();
    return switch (clean) {
      'eastmoney' || 'eastmoneydirect' || '东方财富' => 'eastmoneydirect',
      'tdx' || '通达信' => 'tdx',
      'wind' || '万得' => 'wind',
      'yahoo' || 'yfinance' => 'yfinance',
      'akshare' => 'akshare',
      'tushare' => 'tushare',
      'sina' || '新浪' => 'sina',
      'tencent' || '腾讯' => 'tencent',
      'szse' || '深交所' => 'szse',
      'tradingview' => 'tradingview',
      'local' => 'local',
      _ => clean,
    };
  }
}

class _RuntimeRouteDecision {
  final bool eligible;
  final int sortRank;
  final String routeState;
  final String reason;

  const _RuntimeRouteDecision({
    required this.eligible,
    required this.sortRank,
    required this.routeState,
    required this.reason,
  });
}

_RuntimeRouteDecision _runtimeRouteDecision(
  String interfaceId,
  DataApiProviderCapability capability,
  Map<String, dynamic> report, {
  bool allowDegraded = false,
}) {
  final probeId = capability.probeId;
  if ((probeId == null || probeId.isEmpty) && capability.id.isEmpty) {
    return const _RuntimeRouteDecision(
      eligible: true,
      sortRank: 1,
      routeState: 'allowed-unvalidated',
      reason:
          'No runtime probe is registered for this capability; treat it as available but prefer validated providers when possible.',
    );
  }
  final runtime = _runtimeRowForCapability(report, capability);
  if (runtime == null) {
    return const _RuntimeRouteDecision(
      eligible: true,
      sortRank: 1,
      routeState: 'allowed-unvalidated',
      reason:
          'No blocking runtime evidence is recorded for this capability; treat it as available but prefer validated providers when possible.',
    );
  }
  final status = '${runtime['status'] ?? ''}'.trim().toLowerCase();
  final validationState = '${runtime['validationState'] ?? ''}'
      .trim()
      .toLowerCase();
  final failureClass = '${runtime['failureClass'] ?? ''}'.trim().toLowerCase();
  final temporaryBlockUntil = _runtimeTemporaryBlockUntil(runtime, report);
  if (status == 'passed' &&
      (validationState == 'configured-live-validated' ||
          validationState == 'valid-schema-observed' ||
          validationState.isEmpty)) {
    return const _RuntimeRouteDecision(
      eligible: true,
      sortRank: 0,
      routeState: 'validated',
      reason: 'Recent runtime probe validated this provider capability.',
    );
  }
  if (failureClass == 'transport' || failureClass == 'timeout') {
    if (_isExpiredIsoTime(temporaryBlockUntil)) {
      return _RuntimeRouteDecision(
        eligible: true,
        sortRank: 1,
        routeState: 'allowed-unvalidated',
        reason:
            'Previous transient runtime block expired at $temporaryBlockUntil; route may be retried through bounded provider routing or runtime_probe.',
      );
    }
    return _RuntimeRouteDecision(
      eligible: allowDegraded,
      sortRank: allowDegraded ? 2 : 9,
      routeState: allowDegraded
          ? 'degraded-allowed'
          : temporaryBlockUntil == null
          ? 'blocked-transport'
          : 'temporarily-blocked',
      reason: allowDegraded
          ? temporaryBlockUntil == null
                ? 'Recent runtime evidence shows transport instability; degraded routing is explicitly allowed.'
                : 'Transient provider block is active until $temporaryBlockUntil; degraded routing is explicitly allowed.'
          : temporaryBlockUntil == null
          ? 'Recent runtime evidence shows transport instability; keep retry narrow and avoid normal routing.'
          : 'Transient provider block is active until $temporaryBlockUntil; use cache/readback or fallback providers before retrying.',
    );
  }
  if (failureClass == 'credential-or-permission' ||
      failureClass == 'quota-or-rate-limit' ||
      failureClass == 'runtime-blocked' ||
      validationState == 'runtime-blocked') {
    return _RuntimeRouteDecision(
      eligible: false,
      sortRank: 9,
      routeState: failureClass == 'credential-or-permission'
          ? 'blocked-credential'
          : failureClass == 'quota-or-rate-limit'
          ? 'blocked-quota'
          : 'blocked-runtime',
      reason: failureClass == 'credential-or-permission'
          ? 'Recent runtime evidence shows credential or permission rejection; do not retry normal routing until credentials or permissions change.'
          : failureClass == 'quota-or-rate-limit'
          ? 'Recent runtime evidence shows quota or rate-limit blocking; stop broad retries.'
          : 'Recent runtime evidence marks this capability blocked; do not treat it as ready.',
    );
  }
  return const _RuntimeRouteDecision(
    eligible: true,
    sortRank: 1,
    routeState: 'allowed-unvalidated',
    reason:
        'Runtime evidence is not blocking this capability; treat it as available but prefer validated providers when possible.',
  );
}

String? _runtimeTemporaryBlockUntil(
  Map<String, dynamic> runtime,
  Map<String, dynamic> report,
) {
  final explicit = '${runtime['temporaryBlockUntil'] ?? ''}'.trim();
  if (explicit.isNotEmpty) return explicit;
  final failureClass = '${runtime['failureClass'] ?? ''}'.trim().toLowerCase();
  if (failureClass != 'transport' && failureClass != 'timeout') return null;
  final generatedAt = DateTime.tryParse('${report['generatedAt'] ?? ''}');
  if (generatedAt == null) return null;
  final ttl = failureClass == 'timeout'
      ? const Duration(minutes: 15)
      : const Duration(minutes: 30);
  return generatedAt.toUtc().add(ttl).toIso8601String();
}

bool _isExpiredIsoTime(String? value) {
  if (value == null || value.isEmpty) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null && !parsed.toUtc().isAfter(DateTime.now().toUtc());
}

Map<String, dynamic>? _runtimeRowForCapability(
  Map<String, dynamic> report,
  DataApiProviderCapability capability,
) {
  final rows = <Map<String, dynamic>>[
    ..._runtimeRows(report['passedApis']),
    ..._runtimeRows(report['failures']),
  ];
  for (final row in rows) {
    if (_runtimeProbeIdMatches(capability.probeId, row['id'])) {
      return row;
    }
    if (row['capabilityId'] == capability.id) return row;
  }
  return null;
}

bool _runtimeProbeIdMatches(String? capabilityProbeId, Object? rowId) {
  if (capabilityProbeId == null || capabilityProbeId.isEmpty) return false;
  final runtimeId = '$rowId';
  if (runtimeId == capabilityProbeId) return true;
  const aliases = {
    'mobile_yahoo_earnings': ['mobile_marketdata_yahoo_earnings'],
    'mobile_yahoo_options': ['mobile_marketdata_yahoo_options'],
  };
  return aliases[capabilityProbeId]?.contains(runtimeId) ?? false;
}

List<Map<String, dynamic>> _runtimeRows(Object? rows) {
  if (rows is! List) return const [];
  return rows
      .whereType<Map>()
      .map((row) => row.map((key, value) => MapEntry('$key', value)))
      .toList(growable: false);
}

BaseFetcher? _noFetcherForProvider(FinanceProvider provider) => null;

class _CacheReadDecision {
  final bool readCache;
  final String mode;
  final String reason;

  const _CacheReadDecision({
    required this.readCache,
    required this.mode,
    required this.reason,
  });
}
