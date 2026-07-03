import 'dart:convert';
import 'dart:io';

import 'api_failure_classifier.dart';
import 'data_fetcher/api_stats.dart';
import 'data_fetcher/finance_schema_census.dart';
import 'data_fetcher/reusable_data_store.dart';
import 'data_task_engine.dart';
import 'artifact_registry.dart';
import 'goal_automation_types.dart';

class GoalContextPack {
  final String id;
  final GoalTemplateId templateId;
  final String trigger;
  final DateTime createdAt;
  final List<Map<String, dynamic>> recentApiFailures;
  final List<Map<String, dynamic>> recentApiFailureClasses;
  final List<Map<String, dynamic>> providerHealth;
  final List<Map<String, dynamic>> activeTasks;
  final Map<String, dynamic> sessionState;
  final Map<String, dynamic> watchlists;
  final Map<String, dynamic> dataCoverage;
  final List<Map<String, dynamic>> dataArtifacts;
  final List<String> relevantFiles;
  final List<String> relevantSkills;

  const GoalContextPack({
    required this.id,
    required this.templateId,
    required this.trigger,
    required this.createdAt,
    required this.recentApiFailures,
    required this.recentApiFailureClasses,
    required this.providerHealth,
    required this.activeTasks,
    required this.sessionState,
    required this.watchlists,
    required this.dataCoverage,
    required this.dataArtifacts,
    required this.relevantFiles,
    required this.relevantSkills,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'templateId': templateId.wireName,
    'trigger': trigger,
    'createdAt': createdAt.toIso8601String(),
    'recentApiFailures': recentApiFailures,
    'recentApiFailureClasses': recentApiFailureClasses,
    'providerHealth': providerHealth,
    'activeTasks': activeTasks,
    'sessionState': sessionState,
    'watchlists': watchlists,
    'dataCoverage': dataCoverage,
    'dataArtifacts': dataArtifacts,
    'relevantFiles': relevantFiles,
    'relevantSkills': relevantSkills,
  };
}

class GoalContextPackResult {
  final GoalContextPack pack;
  final String path;
  final String summary;

  const GoalContextPackResult({
    required this.pack,
    required this.path,
    required this.summary,
  });
}

GoalContextPackResult buildGoalContextPack({
  required String basePath,
  required GoalTemplateId templateId,
  required String trigger,
  DataTaskEngine? dataTaskEngine,
  Map<String, dynamic> sessionState = const {},
  Duration window = const Duration(minutes: 30),
}) {
  final boundedWindow = Duration(minutes: window.inMinutes.clamp(1, 24 * 60));
  final id = '${templateId.wireName}-${DateTime.now().millisecondsSinceEpoch}';
  final rawRecentFailures = ApiStats.instance
      .getRecentFailures(range: boundedWindow, limit: 80)
      .map((row) => row.toJson())
      .toList();
  final recentFailures = templateId == GoalTemplateId.apiErrorTriage
      ? rawRecentFailures.where(isFinanceApiFailure).toList()
      : rawRecentFailures;
  final recentFailureClasses = classifyApiFailures(recentFailures);
  final rawProviderHealth = ApiStats.instance
      .getSummary(range: boundedWindow)
      .map(
        (row) => {
          'source': row.source,
          'total': row.totalRequests,
          'success': row.successCount,
          'failCount': row.failCount,
          'failRate': row.failRate,
          'avgLatencyMs': row.avgLatencyMs,
          'lastError': row.lastError,
          'lastRequest': row.lastRequest?.toIso8601String(),
        },
      )
      .toList();
  final providerHealth = templateId == GoalTemplateId.apiErrorTriage
      ? rawProviderHealth.where(isFinanceApiFailure).toList()
      : rawProviderHealth;
  final activeTasks =
      dataTaskEngine
          ?.list()
          .where(
            (task) =>
                task.status == DataTaskStatus.pending ||
                task.status == DataTaskStatus.running ||
                task.status == DataTaskStatus.failed,
          )
          .map((task) => task.toJson())
          .toList() ??
      const <Map<String, dynamic>>[];
  final pack = GoalContextPack(
    id: id,
    templateId: templateId,
    trigger: trigger,
    createdAt: DateTime.now(),
    recentApiFailures: recentFailures,
    recentApiFailureClasses: recentFailureClasses,
    providerHealth: providerHealth,
    activeTasks: activeTasks,
    sessionState: sessionState,
    watchlists: _readWatchlists(basePath),
    dataCoverage: ReusableDataStore(basePath).reusableSummary(),
    dataArtifacts: _buildDataArtifacts(basePath),
    relevantFiles: _relevantFilesForTemplate(templateId),
    relevantSkills: _skillsForTemplate(templateId),
  );
  final dir = Directory('$basePath/memory/goal-context');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final path = '${dir.path}/$id.json';
  File(path).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(pack.toJson()),
  );
  _registerContextArtifacts(basePath, pack, path, boundedWindow);
  return GoalContextPackResult(
    pack: pack,
    path: path,
    summary: _summarize(pack, path, boundedWindow),
  );
}

void _registerContextArtifacts(
  String basePath,
  GoalContextPack pack,
  String path,
  Duration window,
) {
  final registry = ArtifactRegistry(basePath);
  final expiresAt = pack.createdAt.add(window);
  registry.register(
    kind: ArtifactKind.contextPack,
    path: path,
    title: 'Goal context pack: ${pack.templateId.wireName}',
    source: 'goal-context-pack',
    id: 'context_pack:${pack.id}',
    ownerTask: pack.templateId.wireName,
    expiresAt: expiresAt,
    verificationStatus: ArtifactVerificationStatus.verified,
    freshness: {
      'sourceTime': pack.createdAt.toIso8601String(),
      'fetchedAt': pack.createdAt.toIso8601String(),
      'windowMinutes': window.inMinutes,
      'status': 'fresh',
    },
    provenance: {
      'source': 'goal-context-pack',
      'trigger': pack.trigger,
      'dataSources': [
        'api_stats',
        'data_task_engine',
        'watchlists',
        'reusable_data_summary',
        'data_artifacts',
      ],
    },
    links: pack.dataArtifacts
        .expand(
          (artifact) => [
            artifact['stableRef']?.toString(),
            artifact['path']?.toString(),
          ],
        )
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toList(),
    metadata: {
      'templateId': pack.templateId.wireName,
      'trigger': pack.trigger,
      'recentApiFailures': pack.recentApiFailures.length,
      'activeTasks': pack.activeTasks.length,
      'dataArtifacts': pack.dataArtifacts.length,
      'windowMinutes': window.inMinutes,
    },
  );
  if (pack.recentApiFailures.isNotEmpty ||
      pack.templateId == GoalTemplateId.apiErrorTriage) {
    registry.register(
      kind: ArtifactKind.apiError,
      path: path,
      title: 'API error context: ${pack.templateId.wireName}',
      source: 'goal-context-pack',
      id: 'api_error:${pack.id}',
      ownerTask: pack.templateId.wireName,
      expiresAt: expiresAt,
      verificationStatus: ArtifactVerificationStatus.verified,
      freshness: {
        'sourceTime': pack.createdAt.toIso8601String(),
        'fetchedAt': pack.createdAt.toIso8601String(),
        'windowMinutes': window.inMinutes,
        'status': pack.recentApiFailures.isNotEmpty ? 'fresh' : 'unknown',
      },
      provenance: {
        'source': 'api_stats',
        'trigger': pack.trigger,
        'classifier': 'goal_context_pack',
      },
      metadata: {
        'trigger': pack.trigger,
        'recentApiFailures': pack.recentApiFailures.length,
        'classes': pack.recentApiFailureClasses,
        'windowMinutes': window.inMinutes,
      },
    );
  }
}

Map<String, dynamic> _readWatchlists(String basePath) {
  final out = <String, dynamic>{};
  for (final entry in {
    'stock': '$basePath/memory/watchlist.json',
    'fund': '$basePath/memory/fund-watchlist.json',
  }.entries) {
    final file = File(entry.value);
    if (!file.existsSync()) continue;
    try {
      out[entry.key] = jsonDecode(file.readAsStringSync());
    } catch (_) {
      out[entry.key] = 'unreadable';
    }
  }
  return out;
}

List<Map<String, dynamic>> _buildDataArtifacts(String basePath) {
  final records = <ArtifactRecord>[];
  try {
    records.add(
      FinanceSchemaCensusRegistry(basePath).register(runtime: 'mobile_finance'),
    );
  } catch (_) {
    // Context packs should still be usable when local artifact registration is
    // blocked by filesystem state.
  }
  records.addAll(
    ArtifactRegistry(basePath).list(kind: ArtifactKind.dataSnapshot),
  );

  final byId = <String, ArtifactRecord>{};
  for (final record in records) {
    byId[record.id] = record;
  }
  return byId.values
      .map(
        (record) => {
          'id': record.id,
          'stableRef': record.stableRef,
          'path': record.path,
          'title': record.title,
          'source': record.source,
          'ownerTask': record.ownerTask,
          'verificationStatus': record.verificationStatus.wireName,
          'freshness': record.freshness,
          'provenance': record.provenance,
          'metadata': record.metadata,
        },
      )
      .toList(growable: false);
}

List<String> _skillsForTemplate(GoalTemplateId templateId) =>
    switch (templateId) {
      GoalTemplateId.apiErrorTriage ||
      GoalTemplateId.providerContractProbe => ['data-sources'],
      GoalTemplateId.dailyDataHealth => ['data-sources'],
      GoalTemplateId.marketPulseRefresh => ['market-overview', 'fund'],
      GoalTemplateId.watchlistMonitor => [
        'monitor-templates',
        'scheduled-analysis',
      ],
      GoalTemplateId.dashboardRefresh => ['monitor-dashboard', 'html-artifact'],
      GoalTemplateId.reportGeneration => ['finance-report', 'html-artifact'],
    };

List<String> _relevantFilesForTemplate(GoalTemplateId templateId) =>
    switch (templateId) {
      GoalTemplateId.apiErrorTriage || GoalTemplateId.providerContractProbe => [
        'app/lib/agent/data_fetcher/provider_policy.dart',
        'app/lib/agent/data_fetcher/finance_schema_census.dart',
        'app/lib/domain/market/services/market_data_query_action_service.dart',
        'app/lib/agent/data_fetcher/api_stats.dart',
      ],
      GoalTemplateId.dailyDataHealth => [
        'app/lib/agent/data_task_engine.dart',
        'finagent/lib/features/finance/build_helpers_api_health.dart',
      ],
      GoalTemplateId.marketPulseRefresh => [
        'app/lib/agent/data_processor/market_snapshot.dart',
        'finagent/assets/finance/skills/market-overview/skill.md',
      ],
      GoalTemplateId.watchlistMonitor => [
        'app/lib/agent/watchlist_refresher.dart',
        'app/lib/agent/watchlist.dart',
      ],
      GoalTemplateId.dashboardRefresh => [
        'finagent/assets/finance/skills/monitor-dashboard/skill.md',
        'finagent/assets/finance/skills/html-artifact/skill.md',
      ],
      GoalTemplateId.reportGeneration => [
        'finagent/assets/finance/skills/finance-report/skill.md',
        'finagent/assets/finance/skills/html-artifact/skill.md',
      ],
    };

String _summarize(GoalContextPack pack, String path, Duration window) {
  final failures = pack.recentApiFailures.take(8).map((row) {
    final source = row['source'] ?? '-';
    final url = (row['url'] ?? '').toString();
    final error = row['error'] == null
        ? ''
        : ' error=${row['error'].toString().substring(0, row['error'].toString().length.clamp(0, 120))}';
    return '- ${row['requestedAt'] ?? '-'} $source $url$error';
  });
  return [
    'Context pack path: $path',
    'Recent failure window: ${window.inMinutes} minutes',
    'Recent API failures: ${pack.recentApiFailures.length}',
    'Recent API failure classes: ${pack.recentApiFailureClasses.map((row) => '${row['classification']}:${row['count']}').join(', ').ifEmpty('-')}',
    ...failures,
    'Active/failed data tasks: ${pack.activeTasks.length}',
    'Session state keys: ${pack.sessionState.keys.join(', ')}',
    'Provider health rows: ${pack.providerHealth.length}',
    'Data artifacts: ${pack.dataArtifacts.map((row) => row['stableRef']).join(', ').ifEmpty('-')}',
    'Relevant files: ${pack.relevantFiles.join(', ')}',
    'Relevant skills: ${pack.relevantSkills.join(', ')}',
  ].join('\n');
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
