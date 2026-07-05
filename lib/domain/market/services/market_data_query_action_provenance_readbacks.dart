part of 'market_data_query_action_service.dart';

extension _MarketDataQueryActionProvenanceReadbacks
    on MarketDataQueryActionService {
  Map<String, dynamic> _queryApiCalls(
    String action,
    Map<String, dynamic> input,
  ) {
    final minutes = (input['minutes'] as num?)?.toInt() ?? 30;
    final source = input['source'] as String?;
    final rows = ApiStats.instance.getRecentFailures(
      range: Duration(minutes: minutes.clamp(1, 1440)),
      source: source,
      limit: _inputLimit(input, 50),
    );
    return {
      'action': action,
      'source': source,
      'minutes': minutes.clamp(1, 1440),
      'interfaceId': 'provider.api_call_log',
      'provider': 'local',
      'capabilityId': 'local.provider.api_call_log',
      'cacheStatus': 'local-evidence',
      'canonicalSchema': 'api_call_log',
      'canonicalTable': 'api_requests',
      'count': rows.length,
      'data': rows.map((row) => row.toJson()).toList(),
    };
  }

  Map<String, dynamic> _queryMarketScreening(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final store = ReusableDataStore(context.basePath);
    final providerConstraint = _providerCacheConstraint(input);
    final symbol = symbols.isEmpty ? input['symbol'] as String? : symbols.first;
    final rows = _queryMapsWithProviderConstraint(
      constraint: providerConstraint,
      query: (provider) => store.queryMarketScreeningSnapshots(
        provider: provider,
        symbol: symbol,
        sourceAction:
            input['sourceAction'] as String? ?? input['actionName'] as String?,
        since: input['since'] as String?,
        limit: _inputLimit(input, 50),
      ),
    );
    return {
      'action': 'query_market_screening',
      'symbol': symbol,
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      'count': rows.length,
      'source': 'local market_screening_snapshot',
      'interfaceId': 'market.screening',
      'providerId': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no market_screening_snapshot rows matched the requirement'
                : 'cacheFirst read reusable local data; no market_screening_snapshot rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable market_screening_snapshot rows',
      'schemaId': 'screening_result',
      'canonicalSchema': 'screening_result',
      'canonicalTable': 'market_screening_snapshot',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryMarginTrading(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final store = _storeForContext(context);
    final providerConstraint = _providerCacheConstraint(input);
    final code =
        input['code'] as String? ??
        input['symbol'] as String? ??
        (symbols.isEmpty ? null : symbols.first);
    final rows = _queryMapsWithProviderConstraint(
      constraint: providerConstraint,
      query: (provider) =>
          store?.queryMarginTradingRows(
            code: code,
            tradeDate:
                input['date'] as String? ?? input['tradeDate'] as String?,
            provider: provider,
            limit: _inputLimit(input, 100),
          ) ??
          const <Map<String, dynamic>>[],
    );
    final sourceDataTime = _latestValue(rows, const ['trade_date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    return {
      'action': 'query_margin_trading',
      if (code != null) 'code': code,
      if (input['date'] != null) 'date': input['date'],
      if (input['tradeDate'] != null) 'tradeDate': input['tradeDate'],
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      'provider': 'local',
      'interfaceId': 'market.margin_trading',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no margin_trading rows matched the requirement'
                : 'cacheFirst read reusable local data; no margin_trading rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable margin_trading rows',
      'canonicalSchema': 'margin_trading',
      'canonicalTable': 'margin_trading',
      'sourceDataTime': sourceDataTime,
      'asOf': sourceDataTime,
      'fetchedAt': fetchedAt,
      'count': rows.length,
      'source': 'local margin_trading',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryTechnicalIndicator(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final store = _storeForContext(context);
    final providerConstraint = _providerCacheConstraint(input);
    final symbol =
        input['symbol'] as String? ??
        input['code'] as String? ??
        (symbols.isEmpty ? null : symbols.first);
    final indicator = input['indicator'] as String? ?? input['func'] as String?;
    final rows = _queryMapsWithProviderConstraint(
      constraint: providerConstraint,
      query: (provider) =>
          store?.queryTechnicalIndicatorSeries(
            symbol: symbol,
            indicator: indicator,
            fieldName: input['fieldName'] as String?,
            since: input['since'] as String? ?? input['startDate'] as String?,
            provider: provider,
            limit: _inputLimit(input, 200),
          ) ??
          _dataManager?.queryTechnicalIndicatorSeries(
            symbol: symbol,
            indicator: indicator,
            fieldName: input['fieldName'] as String?,
            since: input['since'] as String? ?? input['startDate'] as String?,
            provider: provider,
            limit: _inputLimit(input, 200),
          ) ??
          const <Map<String, dynamic>>[],
    );
    final sourceDataTime = _latestValue(rows, const ['source_date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    return {
      'action': 'query_technical_indicator',
      if (symbol != null) 'symbol': symbol,
      if (indicator != null) 'indicator': indicator,
      if (input['fieldName'] != null) 'fieldName': input['fieldName'],
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      'interfaceId': 'technical.indicator_series',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no technical_indicator_series rows matched the requirement'
                : 'cacheFirst read reusable local data; no technical_indicator_series rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable technical_indicator_series rows',
      'canonicalSchema': 'technical_indicator_series',
      'canonicalTable': 'technical_indicator_series',
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      if (fetchedAt != null) 'fetchedAt': fetchedAt,
      'count': rows.length,
      'source': 'local technical_indicator_series',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryAlphaFactors(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final store = _storeForContext(context);
    final providerConstraint = _providerCacheConstraint(input);
    final symbol =
        input['symbol'] as String? ??
        input['code'] as String? ??
        (symbols.isEmpty ? null : symbols.first);
    final factorName =
        input['factorName'] as String? ?? input['factor'] as String?;
    final rows = _queryMapsWithProviderConstraint(
      constraint: providerConstraint,
      query: (provider) =>
          store?.queryAlphaFactors(
            symbol: symbol,
            factorName: factorName,
            since: input['since'] as String? ?? input['startDate'] as String?,
            provider: provider,
            limit: _inputLimit(input, 200),
          ) ??
          _dataManager?.queryAlphaFactors(
            symbol: symbol,
            factorName: factorName,
            since: input['since'] as String? ?? input['startDate'] as String?,
            provider: provider,
            limit: _inputLimit(input, 200),
          ) ??
          const <Map<String, dynamic>>[],
    );
    final sourceDataTime = _latestValue(rows, const ['source_date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    return {
      'action': 'query_alpha_factors',
      if (symbol != null) 'symbol': symbol,
      if (factorName != null) 'factorName': factorName,
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      'interfaceId': 'stock.alpha_factors',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no alpha_factor rows matched the requirement'
                : 'cacheFirst read reusable local data; no alpha_factor rows matched the requirement'
          : 'cacheFirst read reusable local data before recomputing alpha factors; cache reader returned usable alpha_factor rows',
      'canonicalSchema': 'alpha_factor',
      'canonicalTable': 'alpha_factor',
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      if (fetchedAt != null) 'fetchedAt': fetchedAt,
      'count': rows.length,
      'source': 'local alpha_factor',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryWindFundamentalReadback(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context, {
    required String action,
    required String interfaceId,
  }) {
    final code =
        input['code'] as String? ??
        input['symbol'] as String? ??
        (symbols.isEmpty ? null : symbols.first);
    if (code == null || code.isEmpty) {
      throw ArgumentError(_fundamentalError);
    }
    final reportDate =
        input['reportDate'] as String? ?? input['date'] as String?;
    final limit = _inputLimit(input, 20);
    final providerConstraint = _providerCacheConstraint(input);
    final rows = _queryMapsWithProviderConstraint(
      constraint: providerConstraint,
      fallbackProvider: 'Wind',
      query: (provider) =>
          _storeForContext(context)?.queryFundamental(
            code,
            reportDate: reportDate,
            source: provider,
            limit: limit,
          ) ??
          _dataManager?.queryFundamental(
            code,
            reportDate: reportDate,
            source: provider,
            limit: limit,
          ) ??
          const <Map<String, dynamic>>[],
    );
    final sourceDataTime = _latestValue(rows, const ['report_date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    return {
      'action': action,
      'symbol': code,
      if (reportDate != null) 'reportDate': reportDate,
      'interfaceId': interfaceId,
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      'provider': 'local',
      'providerId': 'wind',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no Wind fundamental rows matched the requirement'
                : 'cacheFirst read reusable local Wind fundamental rows; no matching canonical rows were found'
          : 'cacheFirst read reusable local Wind fundamental rows before provider routing; cache reader returned governed canonical rows',
      'canonicalSchema': 'fundamental',
      'canonicalTable': 'fundamental',
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      if (fetchedAt != null) 'fetchedAt': fetchedAt,
      'count': rows.length,
      'source': 'local fundamental',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryWindCompanyInfoReadback(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context, {
    required String action,
    required String interfaceId,
    required String defaultInfoType,
  }) {
    final code =
        input['code'] as String? ??
        input['symbol'] as String? ??
        (symbols.isEmpty ? null : symbols.first);
    if (code == null || code.isEmpty) {
      throw ArgumentError(_companyInfoError);
    }
    final infoType =
        input['infoType'] as String? ??
        input['type'] as String? ??
        input['info_type'] as String? ??
        defaultInfoType;
    final limit = _inputLimit(input, 20);
    final providerConstraint = _providerCacheConstraint(input);
    final rows = _queryMapsWithProviderConstraint(
      constraint: providerConstraint,
      fallbackProvider: 'Wind',
      query: (provider) =>
          _storeForContext(context)
              ?.queryCompanyInfo(code, infoType: infoType, limit: limit)
              .where((row) => row['source']?.toString() == provider)
              .toList() ??
          _dataManager
              ?.queryCompanyInfo(code, infoType: infoType, limit: limit)
              .where((row) => row['source']?.toString() == provider)
              .toList() ??
          const <Map<String, dynamic>>[],
    );
    final sourceDataTime = _latestValue(rows, const ['updated_at']);
    return {
      'action': action,
      'symbol': code,
      'infoType': infoType,
      'interfaceId': interfaceId,
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      'provider': 'local',
      'providerId': 'wind',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no Wind company-info rows matched the requirement'
                : 'cacheFirst read reusable local Wind company-info rows; no matching canonical rows were found'
          : 'cacheFirst read reusable local Wind company-info rows before provider routing; cache reader returned governed canonical rows',
      'canonicalSchema': 'stock_company_info',
      'canonicalTable': 'stock_company_info',
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      if (sourceDataTime != null) 'fetchedAt': sourceDataTime,
      'count': rows.length,
      'source': 'local stock_company_info',
      'data': rows,
      if (interfaceId == 'stock.risk_metrics')
        'analysisEvidence': _stockRiskMetricsAnalysisEvidence(
          code: code,
          rows: rows,
          sourceDataTime: sourceDataTime,
          readbackAction: action,
        ),
    };
  }

  Map<String, dynamic> _stockRiskMetricsAnalysisEvidence({
    required String code,
    required List<Map<String, dynamic>> rows,
    required String? sourceDataTime,
    required String readbackAction,
  }) {
    final top = rows.isEmpty ? null : rows.first;
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.risk,
      subjectType: AnalysisSubjectType.stock,
      subjectId: code,
      subjectName: code,
      observedFacts: [
        'rows=${rows.length}',
        if (sourceDataTime != null) 'sourceDataTime=$sourceDataTime',
        if (top != null && top['title'] != null) 'topTitle=${top['title']}',
        if (top != null && top['content'] != null)
          'topContent=${top['content']}',
      ],
      interpretations: [
        rows.isEmpty
            ? 'stock.risk_metrics:missing'
            : 'stock.risk_metrics:available',
        'risk_context:readback_evidence',
      ],
      missingEvidence: const [
        'technical_risk_confirmation',
        'position_size_context',
        'liquidity_confirmation',
        'strategy_validation',
      ],
      confidence: rows.isEmpty
          ? AnalysisConfidence.low
          : AnalysisConfidence.medium,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: AnalysisSourceCoverage(
        sources: const ['local stock_company_info'],
        interfaceId: 'stock.risk_metrics',
        capabilityId: 'local.cache',
        canonicalSchema: 'stock_company_info',
        canonicalTable: 'stock_company_info',
        readbackAction: readbackAction,
        sourceDataTime: sourceDataTime ?? '',
        fetchedAt: sourceDataTime ?? '',
        cacheStatus: rows.isEmpty ? 'cache-miss' : 'cache-hit',
        coverageStatus: rows.isEmpty
            ? AnalysisCoverageStatus.none
            : AnalysisCoverageStatus.sufficientForAnalysis,
      ),
    ).toJson();
  }

  ReusableDataStore? _storeForContext(ToolContext context) {
    if (context.basePath.isEmpty) return null;
    return ReusableDataStore(context.basePath);
  }

  String? _latestValue(List<Map<String, dynamic>> rows, List<String> keys) {
    for (final key in keys) {
      String? latest;
      for (final row in rows) {
        final value = row[key];
        if (value == null) continue;
        final text = '$value'.trim();
        if (text.isEmpty) continue;
        if (latest == null || text.compareTo(latest) > 0) latest = text;
      }
      if (latest != null) return latest;
    }
    return null;
  }
}
