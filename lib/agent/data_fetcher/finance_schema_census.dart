import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../artifact_registry.dart';
import '../../domain/market/providers/data_api_interface_contract.dart';

const financeSchemaCensusOwnerTask = 'data_schema_live_probe';
const financeSchemaCensusArtifactId =
    'data_snapshot:finance_schema_census:mobile';

class FinanceSchemaSurfaceContract {
  final String id;
  final String dataClass;
  final String kind;
  final String cachePolicy;
  final String providerPolicy;
  final String normalizer;
  final String persistTarget;
  final String readbackAction;
  final String failureSink;
  final String timestampPolicy;
  final String liveProbeStatus;
  final String runtimeDependency;
  final String classification;
  final bool uiSurfaceRequired;
  final List<String> fetchActions;
  final List<String> queryActions;
  final List<String> canonicalTables;

  const FinanceSchemaSurfaceContract({
    required this.id,
    required this.dataClass,
    this.kind = 'reusable',
    this.cachePolicy = 'cache-first',
    this.providerPolicy = 'policy-owned',
    this.normalizer = 'code-owned',
    this.persistTarget = 'canonical',
    this.readbackAction = 'same-runtime',
    this.failureSink = 'api-health-no-persist',
    this.timestampPolicy = 'source-and-ingest-separated',
    this.liveProbeStatus = 'contract-tested',
    this.runtimeDependency = 'mobile-native',
    this.classification = 'supported-reusable-schema',
    this.uiSurfaceRequired = false,
    this.fetchActions = const [],
    this.queryActions = const [],
    this.canonicalTables = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'dataClass': dataClass,
    'kind': kind,
    'cachePolicy': cachePolicy,
    'providerPolicy': providerPolicy,
    'normalizer': normalizer,
    'persistTarget': persistTarget,
    'readbackAction': readbackAction,
    'failureSink': failureSink,
    'timestampPolicy': timestampPolicy,
    'liveProbeStatus': liveProbeStatus,
    'runtimeDependency': runtimeDependency,
    'classification': classification,
    'uiSurfaceRequired': uiSurfaceRequired,
    'fetchActions': fetchActions,
    'queryActions': queryActions,
    'canonicalTables': canonicalTables,
  };
}

class FinanceSchemaCensus {
  final String runtime;
  final DateTime generatedAt;
  final List<FinanceSchemaSurfaceContract> surfaces;
  final Map<String, dynamic> provenance;

  const FinanceSchemaCensus({
    required this.runtime,
    required this.generatedAt,
    required this.surfaces,
    required this.provenance,
  });

  int get reusableCount =>
      surfaces.where((surface) => surface.kind == 'reusable').length;

  int get fetchOnlyCount =>
      surfaces.where((surface) => surface.kind == 'fetch-only').length;

  Map<String, dynamic> toJson() => {
    'runtime': runtime,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'ownerTask': financeSchemaCensusOwnerTask,
    'surfaces': surfaces.map((surface) => surface.toJson()).toList(),
    'summary': {
      'total': surfaces.length,
      'reusable': reusableCount,
      'fetchOnly': fetchOnlyCount,
      'uiRequired': surfaces
          .where((surface) => surface.uiSurfaceRequired)
          .length,
    },
    'provenance': provenance,
  };
}

class FinanceSchemaCensusRegistry {
  final String basePath;

  const FinanceSchemaCensusRegistry(this.basePath);

  ArtifactRecord register({
    required String runtime,
    DateTime? now,
    List<FinanceSchemaSurfaceContract>? surfaces,
  }) {
    final generatedAt = (now ?? DateTime.now()).toUtc();
    final effectiveSurfaces = surfaces ?? mobileFinanceSchemaSurfaces;
    final census = FinanceSchemaCensus(
      runtime: runtime,
      generatedAt: generatedAt,
      surfaces: effectiveSurfaces,
      provenance: const {
        'source': 'code-owned mobile finance schema contract',
        'matrix': 'reports/designs/provider-api-persistence-matrix.md',
        'sharedImplementation': 'app/lib/agent and app/lib/domain/market',
        'finagentReuse': 'finagent/lib/agent and finagent/lib/domain/market',
      },
    );
    final outputPath = p.join(
      basePath,
      'memory',
      'data',
      'finance_schema_census_mobile.json',
    );
    final file = File(outputPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(census.toJson()),
    );

    return ArtifactRegistry(basePath).register(
      id: financeSchemaCensusArtifactId,
      kind: ArtifactKind.dataSnapshot,
      path: outputPath,
      title: 'Mobile finance schema census',
      source: 'FinanceSchemaCensusRegistry',
      ownerTask: financeSchemaCensusOwnerTask,
      verificationStatus: ArtifactVerificationStatus.verified,
      freshness: {
        'status': 'fresh',
        'generatedAt': generatedAt.toIso8601String(),
      },
      provenance: census.provenance,
      metadata: {
        'runtime': runtime,
        'total': effectiveSurfaces.length,
        'reusable': census.reusableCount,
        'fetchOnly': census.fetchOnlyCount,
      },
    );
  }
}

final List<FinanceSchemaSurfaceContract> mobileFinanceSchemaSurfaces = [
  ...dataApiInterfaceContract.interfaces.map(_surfaceFromDataApiInterface),
  ...mobileOperationalSchemaSurfaces,
];

FinanceSchemaSurfaceContract _surfaceFromDataApiInterface(
  DataApiInterfaceDefinition definition,
) {
  final credentialGated = definition.capabilities.any(
    (capability) =>
        capability.status == DataApiCapabilityStatus.credentialGated ||
        capability.status == DataApiCapabilityStatus.quotaGated,
  );
  final eligible = definition.capabilities.any(
    (capability) => capability.isEligible,
  );
  return FinanceSchemaSurfaceContract(
    id: definition.id,
    dataClass: definition.canonicalSchema,
    cachePolicy: definition.freshnessPolicy,
    providerPolicy: 'provider-capability-registry',
    normalizer: 'code-owned-interface-normalizer',
    persistTarget: eligible || credentialGated ? 'canonical' : 'none',
    readbackAction: definition.queryActions.isEmpty
        ? 'not-implemented'
        : 'same-runtime:${definition.queryActions.join(",")}',
    liveProbeStatus: eligible
        ? 'contract-tested'
        : credentialGated
        ? 'credential-gated-live'
        : 'not-supported',
    runtimeDependency: eligible
        ? 'mobile-native'
        : credentialGated
        ? 'configured-provider-credential'
        : 'provider-adapter-required',
    classification: eligible
        ? 'supported-reusable-schema'
        : credentialGated
        ? 'supported-reusable-schema-with-credential-gated-live-probe'
        : 'registered-interface-without-native-provider',
    uiSurfaceRequired: _uiRequiredInterfaceIds.contains(definition.id),
    fetchActions: [
      definition.id,
      ...definition.capabilities.map((capability) => capability.id),
    ],
    queryActions: definition.queryActions,
    canonicalTables: definition.dataStoreTables,
  );
}

const _uiRequiredInterfaceIds = {
  'stock.quote',
  'stock.daily_kline',
  'stock.identity_list',
  'fund.identity_list',
  'fund.etf_quote',
  'fund.nav_history',
  'market.hot_rank',
  'market.sector_ranking',
  'news.finance_feed',
  'data.health',
};

const mobileOperationalSchemaSurfaces = [
  FinanceSchemaSurfaceContract(
    id: 'api_failure_triage',
    dataClass: 'api_health',
    fetchActions: ['query_api_calls', 'query_api_errors'],
    queryActions: ['query_api_calls', 'query_api_errors', 'getRecentFailures'],
    canonicalTables: ['api_stats.db', 'api_requests'],
  ),
  FinanceSchemaSurfaceContract(
    id: 'data_health_surface',
    dataClass: 'api_health',
    kind: 'fetch-only',
    cachePolicy: 'none',
    normalizer: 'none',
    persistTarget: 'none',
    readbackAction: 'none',
    failureSink: 'api-health-visible',
    timestampPolicy: 'none',
    liveProbeStatus: 'local-observability',
    classification: 'interface-backed-operational-surface',
    fetchActions: ['data_health'],
    queryActions: [
      'MarketDataSupportService.dataHealth',
      'DataApiInterfaceContract',
      'ApiStats.instance.getSummary',
    ],
    canonicalTables: ['data_api_interface_contract', 'api_stats.db'],
  ),
  FinanceSchemaSurfaceContract(
    id: 'data_task_observability',
    dataClass: 'data_task_api_health',
    kind: 'fetch-only',
    cachePolicy: 'none',
    normalizer: 'none',
    persistTarget: 'none',
    readbackAction: 'none',
    failureSink: 'api-health-visible',
    timestampPolicy: 'none',
    liveProbeStatus: 'local-observability',
    classification: 'interface-backed-operational-surface',
    fetchActions: [
      'DataTaskEngine',
      'screen_advanced',
      'batch_quote',
      'batch_score',
      'stock.quote',
      'stock.daily_kline',
    ],
  ),
  FinanceSchemaSurfaceContract(
    id: 'technical_indicator_series',
    dataClass: 'technical_indicator_data',
    fetchActions: ['DataProcess', 'technical_indicator'],
    queryActions: ['query_technical_indicator'],
    canonicalTables: ['technical_indicator_series'],
  ),
  FinanceSchemaSurfaceContract(
    id: 'provider_routing_policy',
    dataClass: 'provider_policy',
    kind: 'fetch-only',
    cachePolicy: 'none',
    normalizer: 'none',
    persistTarget: 'none',
    readbackAction: 'none',
    failureSink: 'api-health-visible',
    timestampPolicy: 'none',
    liveProbeStatus: 'code-owned-policy',
    classification: 'fetch-only-policy-surface',
    fetchActions: ['preferredProviders', 'normalizeProviders'],
    queryActions: ['provider policy'],
  ),
];
