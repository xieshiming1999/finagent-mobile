import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/tool_context.dart';
import '../repositories/wind_market_data_repository.dart';

class WindMarketDataService {
  final WindMarketDataRepository _repository;

  WindMarketDataService({DataManager? dataManager})
    : _repository = WindMarketDataRepository(dataManager ?? DataManager());

  Map<String, dynamic> queryDocuments(
    ToolContext context,
    Map<String, dynamic> input, {
    int limit = 50,
  }) {
    final providerConstraint = _ReadbackProviderConstraint.fromInput(input);
    final rows = _queryWithProviderAliases(
      providerConstraint,
      (provider) => _repository.queryDocuments(
        context,
        query: input['query'] as String?,
        tool: input['tool'] as String?,
        entityCode: input['code'] as String?,
        source: provider,
        limit: limit,
      ),
    );
    return _withProvenance(
      action: 'query_wind_document',
      interfaceId: 'wind.financial_document',
      canonicalSchema: 'wind_document',
      canonicalTable: 'wind_document',
      source: 'local wind_document',
      rows: rows,
      sourceTimeKeys: const ['published_at', 'updated_at'],
      extra: {
        'action': 'query_wind_document',
        'interfaceId': 'wind.financial_document',
        'canonicalSchema': 'wind_document',
        'canonicalTable': 'wind_document',
        if (input['query'] != null) 'query': input['query'],
        if (input['tool'] != null) 'tool': input['tool'],
        if (input['code'] != null) 'code': input['code'],
        ..._providerConstraintExtra(providerConstraint),
      },
    );
  }

  Map<String, dynamic> queryEconomic(
    ToolContext context,
    Map<String, dynamic> input, {
    int limit = 100,
  }) {
    final providerConstraint = _ReadbackProviderConstraint.fromInput(input);
    final rows = _queryWithProviderAliases(
      providerConstraint,
      (provider) => _repository.queryEconomicSeries(
        context,
        metricQuery: input['metricQuery'] as String?,
        source: provider,
        limit: limit,
      ),
    );
    return _withProvenance(
      action: 'query_wind_economic',
      interfaceId: 'wind.economic_series',
      canonicalSchema: 'wind_economic_series',
      canonicalTable: 'wind_economic_series',
      source: 'local wind_economic_series',
      rows: rows,
      sourceTimeKeys: const ['date', 'updated_at'],
      extra: {
        'action': 'query_wind_economic',
        'interfaceId': 'wind.economic_series',
        'canonicalSchema': 'wind_economic_series',
        'canonicalTable': 'wind_economic_series',
        if (input['metricQuery'] != null) 'metricQuery': input['metricQuery'],
        ..._providerConstraintExtra(providerConstraint),
      },
    );
  }

  Map<String, dynamic> queryAnalytics(
    ToolContext context,
    Map<String, dynamic> input, {
    int limit = 100,
  }) {
    final providerConstraint = _ReadbackProviderConstraint.fromInput(input);
    final rows = _queryWithProviderAliases(
      providerConstraint,
      (provider) => _repository.queryAnalyticsResults(
        context,
        question: input['question'] as String?,
        source: provider,
        limit: limit,
      ),
    );
    return _withProvenance(
      action: 'query_wind_analytics',
      interfaceId: 'wind.analytics_result',
      canonicalSchema: 'wind_analytics_result',
      canonicalTable: 'wind_analytics_result',
      source: 'local wind_analytics_result',
      rows: rows,
      sourceTimeKeys: const ['value_date', 'updated_at'],
      extra: {
        'action': 'query_wind_analytics',
        'interfaceId': 'wind.analytics_result',
        'canonicalSchema': 'wind_analytics_result',
        'canonicalTable': 'wind_analytics_result',
        if (input['question'] != null) 'question': input['question'],
        ..._providerConstraintExtra(providerConstraint),
      },
    );
  }

  Map<String, dynamic> queryFundPerformance(
    ToolContext context,
    Map<String, dynamic> input, {
    int limit = 100,
  }) {
    final providerConstraint = _ReadbackProviderConstraint.fromInput(input);
    final rows = _queryWithProviderAliases(
      providerConstraint,
      (provider) => _repository.queryFundPerformanceMetrics(
        context,
        code: input['code'] as String? ?? input['fundCode'] as String?,
        provider: provider,
        metricDate: input['metricDate'] as String? ?? input['date'] as String?,
        limit: limit,
      ),
    );
    return _withProvenance(
      action: 'query_fund_performance',
      interfaceId: 'fund.performance_metrics',
      canonicalSchema: 'fund_performance_metrics',
      canonicalTable: 'fund_performance_metrics',
      source: 'local fund_performance_metrics',
      rows: rows,
      sourceTimeKeys: const ['metric_date', 'fetched_at'],
      extra: {
        'action': 'query_fund_performance',
        'interfaceId': 'fund.performance_metrics',
        'canonicalSchema': 'fund_performance_metrics',
        'canonicalTable': 'fund_performance_metrics',
        if (input['code'] != null) 'code': input['code'],
        if (input['fundCode'] != null) 'fundCode': input['fundCode'],
        ..._providerConstraintExtra(providerConstraint),
        if (input['metricDate'] != null) 'metricDate': input['metricDate'],
      },
    );
  }

  List<Map<String, dynamic>> _queryWithProviderAliases(
    _ReadbackProviderConstraint constraint,
    List<Map<String, dynamic>> Function(String? provider) query,
  ) {
    if (!constraint.isStrict) return query(constraint.requestedProvider);
    for (final provider in constraint.providerAliases) {
      final rows = query(provider);
      if (rows.isNotEmpty) {
        constraint.effectiveProvider = provider;
        return rows;
      }
    }
    return const [];
  }

  Map<String, dynamic> _providerConstraintExtra(
    _ReadbackProviderConstraint constraint,
  ) {
    return {
      if (constraint.requestedProvider != null)
        'providerFilter': constraint.requestedProvider,
      if (constraint.providerMode != null)
        'providerMode': constraint.providerMode,
      if (constraint.effectiveProvider != null)
        'cacheSourceFilter': constraint.effectiveProvider,
    };
  }

  Map<String, dynamic> _withProvenance({
    required String action,
    required String interfaceId,
    required String canonicalSchema,
    required String canonicalTable,
    required String source,
    required List<Map<String, dynamic>> rows,
    required List<String> sourceTimeKeys,
    required Map<String, dynamic> extra,
  }) {
    final cacheStatus = rows.isEmpty ? 'cache-miss' : 'cache-hit';
    final sourceDataTime = _latestValue(rows, sourceTimeKeys);
    final provenance = {
      'interfaceId': interfaceId,
      'capabilityId': 'local.cache',
      'provider': 'local',
      'providerName': 'local',
      'canonicalSchema': canonicalSchema,
      'canonicalTable': canonicalTable,
      'cacheStatus': cacheStatus,
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? 'cacheFirst read reusable local data; no canonical rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable canonical rows',
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
    };
    return {
      ...extra,
      'action': action,
      'interfaceId': interfaceId,
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': cacheStatus,
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': provenance['cacheDecision'],
      'canonicalSchema': canonicalSchema,
      'canonicalTable': canonicalTable,
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      'fetchedAt': provenance['fetchedAt'],
      'count': rows.length,
      'source': source,
      'provenance': provenance,
      'data': rows,
    };
  }

  String? _latestValue(List<Map<String, dynamic>> rows, List<String> keys) {
    for (final key in keys) {
      String? latestForKey;
      for (final row in rows) {
        final value = row[key];
        if (value == null) continue;
        final text = '$value'.trim();
        if (text.isEmpty) continue;
        if (latestForKey == null || text.compareTo(latestForKey) > 0) {
          latestForKey = text;
        }
      }
      if (latestForKey != null) return latestForKey;
    }
    return null;
  }
}

class _ReadbackProviderConstraint {
  final String? requestedProvider;
  final String? providerMode;
  final List<String> providerAliases;
  String? effectiveProvider;

  _ReadbackProviderConstraint({
    required this.requestedProvider,
    required this.providerMode,
    required this.providerAliases,
  });

  factory _ReadbackProviderConstraint.fromInput(Map<String, dynamic> input) {
    final requested = input['provider']?.toString().trim();
    final providerMode = input['providerMode']?.toString().trim();
    final strict =
        requested != null &&
        requested.isNotEmpty &&
        providerMode?.toLowerCase() == 'strict';
    return _ReadbackProviderConstraint(
      requestedProvider: requested == null || requested.isEmpty
          ? null
          : requested,
      providerMode: providerMode == null || providerMode.isEmpty
          ? null
          : providerMode,
      providerAliases: strict ? _providerAliases(requested) : const <String>[],
    );
  }

  bool get isStrict =>
      requestedProvider != null &&
      providerMode?.toLowerCase() == 'strict' &&
      providerAliases.isNotEmpty;

  static List<String> _providerAliases(String provider) {
    switch (provider.trim().toLowerCase()) {
      case 'wind':
      case '万得':
        return const ['wind', 'Wind', '万得'];
      default:
        return [provider];
    }
  }
}
