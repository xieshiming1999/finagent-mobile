import 'dart:convert';

import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/tool_context.dart';
import '../analysis/analysis_evidence_contract.dart';
import '../providers/tushare_market_provider.dart';
import '../repositories/tushare_market_data_repository.dart';
import 'tushare_market_data_persistence_service.dart';

class TushareMarketDataService {
  final DataManager? _dataManager;
  TushareMarketProvider? _provider;
  final TushareMarketDataRepository _repository;
  final TushareMarketDataPersistenceService _persistence;

  TushareMarketDataService({
    DataManager? dataManager,
    TushareMarketProvider? provider,
  }) : this._internal(dataManager ?? DataManager(), provider);

  TushareMarketDataService._internal(
    DataManager dataManager,
    TushareMarketProvider? provider,
  ) : _dataManager = dataManager,
      _provider = provider,
      _repository = TushareMarketDataRepository(dataManager),
      _persistence = TushareMarketDataPersistenceService(
        TushareMarketDataRepository(dataManager),
      );

  Future<Map<String, dynamic>> fetchRaw(Map<String, dynamic> input) async {
    final apiName = input['api_name'] as String?;
    if (apiName == null || apiName.isEmpty) {
      throw ArgumentError(
        'api_name required. Example: MarketData(action:"tushare", api_name:"daily", params:{ts_code:"600519.SH"})\n\nRead Skill "tushare" for full API catalog.',
      );
    }

    final params = requestParams(input);
    final symbols =
        (input['symbols'] as List?)?.cast<String>() ?? const <String>[];
    if (symbols.isNotEmpty &&
        !params.containsKey('ts_code') &&
        !params.containsKey('trade_date')) {
      params['ts_code'] = _toTsCode(symbols.first);
    }

    final fields = input['fields'] as String? ?? '';
    final data = await _requireProvider().callRaw(
      apiName,
      params,
      fields: fields,
    );
    final items = data['items'] as List? ?? const [];
    final fieldList = data['fields'] as List? ?? const [];
    final rows = _rowsFromItems(items, fieldList);
    final previewRows = rows.take(30).toList();
    final persist = input['persist'] != false;
    final ingestion = persist
        ? _persistence.persistRows(apiName, rows, params: params)
        : null;

    return {
      'action': 'tushare',
      'source': 'Tushare',
      'api_name': apiName,
      'total': items.length,
      'showing': previewRows.length,
      'fields': fieldList,
      if (persist)
        'ingestion':
            ingestion ??
            {'persisted': false, 'reason': 'schema not registered'},
      'data': previewRows,
      if (items.length > 30)
        'note':
            'Showing first 30 of ${items.length} rows. Narrow params for fewer results.',
    };
  }

  Future<Map<String, dynamic>> fetchIndexConstituents(
    ToolContext context,
    String indexCode, {
    String? asOfDate,
  }) async {
    final tsIndexCode = _toTsIndexCode(indexCode);
    final params = <String, dynamic>{'index_code': tsIndexCode};
    if (asOfDate != null && asOfDate.trim().isNotEmpty) {
      params['trade_date'] = _normalizeCompactDate(asOfDate);
    }
    final data = await _requireProvider().callRaw(
      'index_weight',
      params,
      fields: 'index_code,con_code,trade_date,weight',
    );
    final items = data['items'] as List? ?? const [];
    final fieldList = data['fields'] as List? ?? const [];
    final rows = _rowsFromItems(items, fieldList);
    final previewRows = rows.take(30).toList(growable: false);
    final ingestion =
        _persistence.persistRows('index_weight', rows, params: params) ??
        {'persisted': false, 'reason': 'schema not registered'};
    final sourceDataTime = _latestValue(rows, const [
      'trade_date',
      'end_date',
      'date',
    ]);
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    return {
      'action': 'index_constituents',
      'indexCode': _stripTsSuffix(tsIndexCode),
      if (asOfDate != null && asOfDate.trim().isNotEmpty)
        'asOfDate': _normalizeDashedDate(asOfDate),
      'interfaceId': 'index.constituents',
      'provider': 'Tushare',
      'capabilityId': 'tushare.index.constituents',
      'cacheStatus': 'provider-hit',
      'cacheDecision':
          'provider fetch returned index_constituent rows and persisted them for same-runtime query_index_constituents readback',
      'canonicalSchema': 'index_constituent',
      'canonicalTable': 'index_constituent',
      if (sourceDataTime != null)
        'sourceDataTime':
            _normalizeDashedDate(sourceDataTime) ?? sourceDataTime,
      'fetchedAt': fetchedAt,
      'ingestion': ingestion,
      'count': rows.length,
      'showing': previewRows.length,
      'source': 'Tushare',
      'data': previewRows,
      if (rows.length > previewRows.length)
        'note':
            'Showing first ${previewRows.length} of ${rows.length} rows. Use query_index_constituents for reusable readback.',
    };
  }

  Map<String, dynamic> queryFundamental(
    ToolContext context,
    String symbol, {
    Map<String, dynamic> input = const {},
    int limit = 8,
    String action = 'query_fundamental',
  }) {
    final providerConstraint = _TushareReadbackProviderConstraint.fromInput(
      input,
    );
    final rows = _queryWithProviderAliases(
      providerConstraint,
      (source) => _repository.queryFundamental(
        context,
        symbol,
        source: source,
        limit: limit,
      ),
    );
    final compactRows = rows.map(_compactFundamentalRow).toList();
    final sourceDataTime = _latestValue(compactRows, const ['report_date']);
    final fetchedAt = _latestValue(compactRows, const ['fetched_at']);
    return {
      'action': action,
      'symbol': symbol,
      'interfaceId': 'stock.daily_valuation',
      'provider': 'local',
      ..._providerConstraintExtra(providerConstraint),
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no fundamental rows matched the requirement'
                : 'cacheFirst read reusable local data; no fundamental rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable fundamental rows',
      'canonicalSchema': 'fundamental',
      'canonicalTable': 'fundamental',
      ..._optionalString('sourceDataTime', sourceDataTime),
      ..._optionalString('fetchedAt', fetchedAt),
      'count': rows.length,
      'source': 'local fundamental',
      'data': compactRows,
      'analysisEvidence': _valuationAnalysisEvidence(
        rows: compactRows,
        sourceDataTime: sourceDataTime,
        fetchedAt: fetchedAt,
        subjectId: symbol,
        readbackAction: action,
        cacheStatus: rows.isEmpty ? 'cache-miss' : 'cache-hit',
      ),
      if (rows.any((row) => row['raw_json'] != null))
        'rawPayloadPolicy':
            'raw_json retained in local diagnostics only; normal readback output exposes compact canonical fields plus selected source fields needed for risk checks',
    };
  }

  Map<String, dynamic> _optionalString(String key, String? value) =>
      value == null ? const <String, dynamic>{} : <String, dynamic>{key: value};

  Map<String, dynamic> queryFundamentalSample(
    ToolContext context, {
    Map<String, dynamic> input = const {},
    int limit = 50,
    String action = 'query_stock_daily_valuation',
  }) {
    final providerConstraint = _TushareReadbackProviderConstraint.fromInput(
      input,
    );
    final peLte = _numericInput(
      input['pe_lte'] ??
          input['peLte'] ??
          input['pe_max'] ??
          input['max_pe'] ??
          _nestedInput(input, 'pe_lte') ??
          _nestedInput(input, 'pe_max') ??
          _nestedInput(input, 'max_pe'),
    );
    final peGte = _numericInput(
      input['pe_gte'] ??
          input['peGte'] ??
          input['pe_min'] ??
          input['min_pe'] ??
          _nestedInput(input, 'pe_gte') ??
          _nestedInput(input, 'pe_min') ??
          _nestedInput(input, 'min_pe'),
    );
    final roeGte = _numericInput(
      input['roe_gte'] ??
          input['roeGte'] ??
          input['roe_min'] ??
          input['min_roe'] ??
          _nestedInput(input, 'roe_gte') ??
          _nestedInput(input, 'roe_min') ??
          _nestedInput(input, 'min_roe'),
    );
    final latestOnly = input['latestOnly'] != false;
    final rows = _queryWithProviderAliases(
      providerConstraint,
      (source) => _repository.queryFundamentalSample(
        context,
        source: source,
        limit: limit,
        peLte: peLte,
        peGte: peGte,
        roeGte: roeGte,
        latestOnly: latestOnly,
      ),
    );
    final compactRows = rows.map(_compactFundamentalRow).toList();
    final availableRows = rows.isEmpty
        ? _repository
              .queryFundamentalSample(
                context,
                source: providerConstraint.effectiveProvider,
                limit: 8,
                latestOnly: latestOnly,
              )
              .map(_compactFundamentalRow)
              .toList()
        : const <Map<String, dynamic>>[];
    final sourceDataTime = _latestValue(compactRows, const ['report_date']);
    final fetchedAt = _latestValue(compactRows, const ['fetched_at']);
    return {
      'action': action,
      'interfaceId': 'stock.daily_valuation',
      'provider': 'local',
      ..._providerConstraintExtra(providerConstraint),
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'local-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? 'cacheFirst read reusable stock.daily_valuation data; no local rows matched the requested bounded sample/filter'
          : 'cacheFirst read reusable stock.daily_valuation data before provider routing; local rows matched the requested filter',
      'canonicalSchema': 'fundamental',
      'canonicalTable': 'fundamental',
      'request': {
        'peLte': ?peLte,
        'peGte': ?peGte,
        'roeGte': ?roeGte,
        'latestOnly': latestOnly,
      },
      ..._optionalString('sourceDataTime', sourceDataTime),
      ..._optionalString('fetchedAt', fetchedAt),
      'count': compactRows.length,
      'source': 'local fundamental',
      'data': compactRows,
      'analysisEvidence': _valuationAnalysisEvidence(
        rows: compactRows,
        sourceDataTime: sourceDataTime,
        fetchedAt: fetchedAt,
        subjectId: 'stock-daily-valuation-sample',
        readbackAction: action,
        cacheStatus: rows.isEmpty ? 'local-miss' : 'cache-hit',
      ),
      if (availableRows.isNotEmpty) 'availableLocalSample': availableRows,
      if (rows.isEmpty)
        'note':
            'No local stock.daily_valuation rows matched the requested filter. For first-answer stock selection, disclose this governed valuation coverage gap and stop instead of treating selected-code fundamental refresh, broad screen, or quote-only data as proof of a full-market PE/ROE shortlist.',
    };
  }

  Map<String, dynamic> _valuationAnalysisEvidence({
    required List<Map<String, dynamic>> rows,
    required String? sourceDataTime,
    required String? fetchedAt,
    required String subjectId,
    required String readbackAction,
    required String cacheStatus,
  }) {
    final top = rows.isEmpty ? null : rows.first;
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.valuation,
      subjectType: AnalysisSubjectType.stock,
      subjectId: subjectId,
      subjectName: subjectId == 'stock-daily-valuation-sample'
          ? 'Stock daily valuation sample'
          : subjectId,
      observedFacts: [
        'rows=${rows.length}',
        if (sourceDataTime != null) 'sourceDataTime=$sourceDataTime',
        if (top != null && top['code'] != null) 'topCode=${top['code']}',
        if (top != null && top['pe_ttm'] != null) 'peTtm=${top['pe_ttm']}',
        if (top != null && top['pb'] != null) 'pb=${top['pb']}',
        if (top != null && top['roe'] != null) 'roe=${top['roe']}',
      ],
      interpretations: [
        rows.isEmpty
            ? 'stock.daily_valuation:missing'
            : 'stock.daily_valuation:available',
        'valuation_context:readback_evidence',
      ],
      missingEvidence: const [
        'industry_peer_valuation',
        'earnings_quality_confirmation',
        'cash_flow_confirmation',
        'strategy_validation',
      ],
      confidence: rows.isEmpty
          ? AnalysisConfidence.low
          : AnalysisConfidence.medium,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: AnalysisSourceCoverage(
        sources: const ['local fundamental'],
        interfaceId: 'stock.daily_valuation',
        capabilityId: 'local.cache',
        canonicalSchema: 'fundamental',
        canonicalTable: 'fundamental',
        readbackAction: readbackAction,
        sourceDataTime: sourceDataTime ?? '',
        fetchedAt: fetchedAt ?? '',
        cacheStatus: cacheStatus,
        coverageStatus: rows.isEmpty
            ? AnalysisCoverageStatus.none
            : AnalysisCoverageStatus.sufficientForAnalysis,
      ),
    ).toJson();
  }

  Map<String, dynamic> _compactFundamentalRow(Map<String, dynamic> row) {
    final compact = Map<String, dynamic>.from(row)..remove('raw_json');
    final raw = _decodeRawJson(row['raw_json']);
    if (raw != null) {
      compact.addAll({
        if (raw['REPORT_TYPE'] != null) 'report_type': raw['REPORT_TYPE'],
        if (raw['REPORT_DATE_NAME'] != null)
          'report_date_name': raw['REPORT_DATE_NAME'],
        if (raw['NOTICE_DATE'] != null)
          'notice_date': _datePrefix(raw['NOTICE_DATE']),
        if (raw['UPDATE_DATE'] != null)
          'update_date': _datePrefix(raw['UPDATE_DATE']),
        if (raw['BPS'] != null) 'bps': _toNullableDouble(raw['BPS']),
        if (raw['EPSJB'] != null) 'eps_basic': _toNullableDouble(raw['EPSJB']),
        if (raw['TOTAL_ASSETS'] != null)
          'total_assets':
              compact['total_assets'] ?? _toNullableDouble(raw['TOTAL_ASSETS']),
        if (raw['TOTAL_LIABILITIES'] != null)
          'total_liabilities':
              compact['total_liabilities'] ??
              _toNullableDouble(raw['TOTAL_LIABILITIES']),
      });
    }
    return compact;
  }

  Map<String, dynamic>? _decodeRawJson(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _datePrefix(Object? value) {
    if (value == null) return null;
    final text = '$value';
    return text.length >= 10 ? text.substring(0, 10) : text;
  }

  double? _toNullableDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  Map<String, dynamic> queryMoneyFlow(
    ToolContext context,
    String symbol, {
    Map<String, dynamic> input = const {},
    int limit = 30,
  }) {
    final providerConstraint = _TushareReadbackProviderConstraint.fromInput(
      input,
    );
    final rows = _queryWithProviderAliases(
      providerConstraint,
      (source) => _repository.queryMoneyFlow(
        context,
        symbol,
        source: source,
        limit: limit,
      ),
    );
    final sourceDataTime = _latestValue(rows, const ['date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    return {
      'action': 'query_money_flow',
      'symbol': symbol,
      'interfaceId': 'stock.money_flow',
      'provider': 'local',
      ..._providerConstraintExtra(providerConstraint),
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no money_flow rows matched the requirement'
                : 'cacheFirst read reusable local data; no money_flow rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable money_flow rows',
      'canonicalSchema': 'money_flow',
      'canonicalTable': 'money_flow',
      ...?sourceDataTime == null ? null : {'sourceDataTime': sourceDataTime},
      ...?fetchedAt == null ? null : {'fetchedAt': fetchedAt},
      'count': rows.length,
      'source': 'local money_flow',
      'data': rows,
    };
  }

  Map<String, dynamic> queryFundNav(
    ToolContext context,
    String symbol, {
    Map<String, dynamic> input = const {},
    String startDate = '',
    String endDate = '',
    int? limit,
  }) {
    final providerConstraint = _TushareReadbackProviderConstraint.fromInput(
      input,
    );
    final rows = _queryWithProviderAliases(
      providerConstraint,
      (source) => _repository.queryFundNav(
        context,
        symbol,
        startDate: startDate,
        endDate: endDate,
        source: source,
        limit: limit,
      ),
    );
    return {
      'action': 'query_fund_nav',
      'symbol': symbol,
      'interfaceId': 'fund.nav_history',
      'provider': 'local',
      ..._providerConstraintExtra(providerConstraint),
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no fund_nav rows matched the requirement'
                : 'cacheFirst read reusable local data; no fund_nav rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable fund_nav rows',
      'canonicalSchema': 'fund_nav',
      'canonicalTable': 'fund_nav',
      'count': rows.length,
      'source': 'local fund_nav',
      'data': rows,
    };
  }

  Map<String, dynamic> queryFundMoneyYield(
    ToolContext context,
    String symbol, {
    Map<String, dynamic> input = const {},
    String startDate = '',
    String endDate = '',
    int? limit,
  }) {
    final providerConstraint = _TushareReadbackProviderConstraint.fromInput(
      input,
    );
    final rows = _queryWithProviderAliases(
      providerConstraint,
      (source) => _repository.queryFundMoneyYield(
        context,
        symbol,
        startDate: startDate,
        endDate: endDate,
        source: source,
        limit: limit,
      ),
    );
    return {
      'action': 'query_fund_money_yield',
      'symbol': symbol,
      'interfaceId': 'fund.money_yield_history',
      'provider': 'local',
      ..._providerConstraintExtra(providerConstraint),
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no fund_money_yield rows matched the requirement'
                : 'cacheFirst read reusable local data; no fund_money_yield rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable fund_money_yield rows',
      'canonicalSchema': 'fund_money_yield',
      'canonicalTable': 'fund_money_yield',
      'count': rows.length,
      'source': 'local fund_money_yield',
      'data': rows,
    };
  }

  Map<String, dynamic> queryFundDividendFactor(
    ToolContext context,
    String symbol, {
    Map<String, dynamic> input = const {},
    String startDate = '',
    String endDate = '',
    int? limit,
  }) {
    final providerConstraint = _TushareReadbackProviderConstraint.fromInput(
      input,
    );
    final rows = _queryWithProviderAliases(
      providerConstraint,
      (source) => _repository.queryFundDividendFactor(
        context,
        symbol,
        startDate: startDate,
        endDate: endDate,
        source: source,
        limit: limit,
      ),
    );
    return {
      'action': 'query_fund_dividend_factor',
      'symbol': symbol,
      'interfaceId': 'fund.dividend_factor',
      'provider': 'local',
      ..._providerConstraintExtra(providerConstraint),
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no fund_dividend_factor rows matched the requirement'
                : 'cacheFirst read reusable local data; no fund_dividend_factor rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable fund_dividend_factor rows',
      'canonicalSchema': 'fund_dividend_factor',
      'canonicalTable': 'fund_dividend_factor',
      'count': rows.length,
      'source': 'local fund_dividend_factor',
      'data': rows,
    };
  }

  Map<String, dynamic> queryIntradayOhlcvBars(
    ToolContext context,
    String symbol, {
    Map<String, dynamic> input = const {},
    String startDate = '',
    String endDate = '',
    int intervalMinutes = 5,
    int? limit,
  }) {
    final providerConstraint = _TushareReadbackProviderConstraint.fromInput(
      input,
    );
    final rows = _queryWithProviderAliases(
      providerConstraint,
      (source) => _repository.queryIntradayOhlcvBars(
        context,
        symbol,
        startDate: startDate,
        endDate: endDate,
        intervalMinutes: intervalMinutes,
        source: source,
        limit: limit,
      ),
    );
    return {
      'action': 'query_intraday_ohlcv_bars',
      'symbol': symbol,
      'interfaceId': 'market.intraday_ohlcv_bars',
      'provider': 'local',
      ..._providerConstraintExtra(providerConstraint),
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no intraday_ohlcv_bars rows matched the requirement'
                : 'cacheFirst read reusable local data; no intraday_ohlcv_bars rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable intraday_ohlcv_bars rows',
      'canonicalSchema': 'intraday_ohlcv_bars',
      'canonicalTable': 'intraday_ohlcv_bars',
      'count': rows.length,
      'source': 'local intraday_ohlcv_bars',
      'data': rows,
    };
  }

  Map<String, dynamic> queryFundList(
    ToolContext context, {
    String? fundType,
    String? company,
    List<String> codes = const [],
    int limit = 50,
  }) {
    final rows = _repository.queryFundList(
      context,
      fundType: fundType,
      company: company,
      codes: codes,
      limit: limit,
    );
    return {
      'action': 'query_fund_list',
      'interfaceId': 'fund.identity_list',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? 'cacheFirst read reusable local data; no fund_list rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable fund_list rows',
      'canonicalSchema': 'fund_list',
      'canonicalTable': 'fund_list',
      'count': rows.length,
      'source': 'local fund_list',
      'data': rows,
    };
  }

  Map<String, dynamic> queryStockList(
    ToolContext context, {
    String? market,
    String? industry,
    String? stockType,
    String? keyword,
    int limit = 50,
  }) {
    final rows = _repository.queryStockList(
      context,
      market: market,
      industry: industry,
      stockType: stockType,
      keyword: keyword,
      limit: limit,
    );
    return {
      'action': 'query_stock_list',
      'interfaceId': 'stock.identity_list',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? 'cacheFirst read reusable local data; no stock_list rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable stock_list rows',
      'canonicalSchema': 'stock_list',
      'canonicalTable': 'stock_list',
      'count': rows.length,
      'source': 'local stock_list',
      'data': rows,
    };
  }

  Map<String, dynamic> queryTradeCalendar(
    ToolContext context, {
    String? market,
    String? start,
    String? end,
    int limit = 100,
  }) {
    final hasRange =
        (start != null && start.trim().isNotEmpty) ||
        (end != null && end.trim().isNotEmpty);
    final rows = _repository.queryTradeCalendar(
      context,
      market: market,
      start: start,
      end: end,
      limit: limit,
      descending: !hasRange,
    );
    final coverage = _repository.queryTradeCalendarCoverage(
      context,
      market: market,
    );
    final displayRows = hasRange ? rows : rows.reversed.toList();
    return {
      'action': 'query_trade_calendar',
      'interfaceId': 'calendar.trade_days',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? 'cacheFirst read reusable local data; no trade_calendar rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable trade_calendar rows',
      'canonicalSchema': 'trade_calendar',
      'canonicalTable': 'trade_calendar',
      'count': rows.length,
      'pageRows': rows.length,
      if (coverage != null) 'coverage': coverage,
      if (coverage != null) 'coverageStart': coverage['earliestDate'],
      if (coverage != null) 'coverageEnd': coverage['latestDate'],
      if (coverage != null) 'coverageRows': coverage['rowCount'],
      'source': 'local trade_calendar',
      'data': displayRows,
    };
  }

  Map<String, dynamic> requestParams(Map<String, dynamic> input) {
    final nested = input['params'];
    if (nested is Map) return Map<String, dynamic>.from(nested);

    final params = <String, dynamic>{};
    const ignored = {
      'action',
      'api_name',
      'fields',
      'symbols',
      'persist',
      'source',
      'sourceName',
    };
    for (final entry in input.entries) {
      if (!ignored.contains(entry.key) && entry.value != null) {
        params[entry.key] = entry.value;
      }
    }
    return params;
  }

  String _toTsCode(String symbol) {
    if (symbol.contains('.')) return symbol;
    return '$symbol.${symbol.startsWith('6') ? 'SH' : 'SZ'}';
  }

  String _toTsIndexCode(String symbol) {
    if (symbol.contains('.')) return symbol.toUpperCase();
    final code = symbol.trim();
    if (code.startsWith('399')) return '$code.SZ';
    return '$code.SH';
  }

  String _stripTsSuffix(String value) {
    final trimmed = value.trim();
    final idx = trimmed.indexOf('.');
    if (idx <= 0) return trimmed;
    return trimmed.substring(0, idx);
  }

  List<Map<String, dynamic>> _rowsFromItems(List items, List fields) {
    final rows = <Map<String, dynamic>>[];
    for (final row in items) {
      if (row is! List) continue;
      final mapped = <String, dynamic>{};
      for (var i = 0; i < fields.length && i < row.length; i++) {
        mapped['${fields[i]}'] = row[i];
      }
      rows.add(mapped);
    }
    return rows;
  }

  TushareMarketProvider _requireProvider() {
    return _provider ??= FetcherTushareMarketProvider(
      _dataManager ?? DataManager(),
    );
  }
}

String _normalizeCompactDate(String value) {
  final text = value.trim().replaceAll('/', '-');
  if (text.length == 8 && !text.contains('-')) return text;
  final digits = text.replaceAll('-', '');
  return digits.length == 8 ? digits : text;
}

String? _normalizeDashedDate(String? value) {
  if (value == null) return null;
  final text = value.trim().replaceAll('/', '-');
  if (text.length == 8 && !text.contains('-')) {
    return '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6, 8)}';
  }
  return text.isEmpty ? null : text;
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

Object? _nestedInput(Map<String, dynamic> input, String key) {
  final params = input['params'];
  if (params is Map && params.containsKey(key)) return params[key];
  final filters = input['filters'];
  if (filters is Map && filters.containsKey(key)) return filters[key];
  return null;
}

double? _numericInput(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

class _TushareReadbackProviderConstraint {
  final String? requestedProvider;
  final String? providerMode;
  final List<String> providerAliases;
  String? effectiveProvider;

  _TushareReadbackProviderConstraint({
    required this.requestedProvider,
    required this.providerMode,
    required this.providerAliases,
  });

  factory _TushareReadbackProviderConstraint.fromInput(
    Map<String, dynamic> input,
  ) {
    final requested = (input['provider'] ?? input['source'])?.toString().trim();
    final providerMode = input['providerMode']?.toString().trim();
    final strict =
        requested != null &&
        requested.isNotEmpty &&
        providerMode?.toLowerCase() == 'strict';
    return _TushareReadbackProviderConstraint(
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
      case 'tushare':
      case 'ts':
        return const ['tushare', 'Tushare', 'TuShare'];
      case 'eastmoney':
      case 'em':
      case '东方财富':
        return const ['eastmoney', 'EastMoney', '东方财富', '东方财富:earnings'];
      case 'akshare':
      case 'ak':
        return const ['akshare', 'AkShare'];
      case 'sina':
      case '新浪':
      case '新浪财经':
        return const ['sina', 'Sina', '新浪财经', '新浪财经:intraday_ohlcv'];
      case 'wind':
      case '万得':
        return const ['wind', 'Wind', '万得'];
      default:
        return [provider];
    }
  }
}

List<Map<String, dynamic>> _queryWithProviderAliases(
  _TushareReadbackProviderConstraint constraint,
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
  _TushareReadbackProviderConstraint constraint,
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
