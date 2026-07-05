import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/eastmoney_advanced_fetcher.dart';
import '../../../agent/data_fetcher/provider_policy.dart';
import '../../../agent/tool_context.dart';
import '../analysis/analysis_evidence_contract.dart';
import '../providers/data_api_interface_router.dart';
import '../providers/eastmoney_advanced_provider.dart';
import '../repositories/eastmoney_advanced_repository.dart';
import '../repositories/local_market_data_repository.dart';
import 'eastmoney_advanced_persistence_service.dart';

class EastmoneyAdvancedService {
  final EastmoneyAdvancedProvider _provider;
  final EastmoneyAdvancedRepository _repository;
  final LocalMarketDataRepository _localMarketRepository;
  final EastmoneyAdvancedPersistenceService _persistence;
  final DataApiInterfaceRouter _router;

  EastmoneyAdvancedService({
    DataManager? dataManager,
    EastMoneyAdvancedFetcher? fetcher,
    EastmoneyAdvancedProvider? provider,
    DataApiInterfaceRouter? router,
  }) : this._internal(dataManager ?? DataManager(), fetcher, provider, router);

  EastmoneyAdvancedService._internal(
    DataManager dataManager,
    EastMoneyAdvancedFetcher? fetcher,
    EastmoneyAdvancedProvider? provider,
    DataApiInterfaceRouter? router,
  ) : _provider =
          provider ??
          FetcherEastmoneyAdvancedProvider(
            fetcher ?? EastMoneyAdvancedFetcher(),
          ),
      _repository = EastmoneyAdvancedRepository(dataManager),
      _localMarketRepository = LocalMarketDataRepository(dataManager),
      _persistence = EastmoneyAdvancedPersistenceService(
        EastmoneyAdvancedRepository(dataManager),
      ),
      _router =
          router ??
          DataApiInterfaceRouter(
            runtimeBasePathProvider: () => dataManager.basePath,
          );

  Future<Map<String, dynamic>> limitUp(Map<String, dynamic> input) async {
    return _limitPool(
      input,
      action: 'limit_up',
      poolType: 'limit_up',
      read: (date) => _provider.readLimitUp(date: date),
    );
  }

  Future<Map<String, dynamic>> limitDown(Map<String, dynamic> input) async {
    return _limitPool(
      input,
      action: 'limit_down',
      poolType: 'limit_down',
      read: (date) => _provider.readLimitDown(date: date),
    );
  }

  Future<Map<String, dynamic>> _limitPool(
    Map<String, dynamic> input, {
    required String action,
    required String poolType,
    required Future<List<Map<String, dynamic>>> Function(String? date) read,
  }) async {
    final date = _requestDate(input);
    final tradeDate = _inputDate(input);
    final result = await _router.runCapability<List<Map<String, dynamic>>>(
      interfaceId: 'market.limit_pool',
      call: (capability) async {
        if (capability.provider != FinanceProvider.eastmoneyDirect) {
          return null;
        }
        return DataApiProviderExecution(data: await read(date), source: '东方财富');
      },
      isUsable: (_) => true,
      emptyMessage: 'returned empty limit-pool rows',
      failureMessage: 'All limit-pool sources failed',
    );
    final data = result.data;
    _persistence.persistLimitPool(poolType, data, tradeDate: tradeDate);
    _persistence.persistStockListRows(
      _stockRows(data, industryKey: 'industry'),
    );
    return _payload(
      action: action,
      count: data.length,
      data: data.take(30).toList(),
      noteLimit: 30,
      source: result.source,
      provenance: result.provenance.toJson(),
    );
  }

  Future<Map<String, dynamic>> hotRank(Map<String, dynamic> input) async {
    final pageSize = input['limit'] as int? ?? 50;
    final tradeDate = _inputDate(input);
    final result = await _eastmoneyRows(
      interfaceId: 'market.hot_rank',
      read: () => _provider.readHotRank(pageSize: pageSize),
      emptyMessage: 'returned empty hot-rank rows',
      failureMessage: 'All hot-rank sources failed',
    );
    final data = result.data;
    _persistence.persistHotRank(data, tradeDate: tradeDate);
    _persistence.persistStockListRows(_stockRows(data));
    return _payload(
      action: 'hot_rank',
      count: data.length,
      data: data,
      source: result.source,
      provenance: result.provenance.toJson(),
    );
  }

  Future<Map<String, dynamic>> dragonTiger(Map<String, dynamic> input) async {
    final date = input['startDate'] as String?;
    final tradeDate = _inputDate(input);
    final result = await _eastmoneyRows(
      interfaceId: 'market.dragon_tiger',
      read: () => _provider.readDragonTiger(date: date, pageSize: 30),
      emptyMessage: 'returned empty dragon-tiger rows',
      failureMessage: 'All dragon-tiger sources failed',
    );
    final data = result.data;
    _persistence.persistDragonTiger(data, tradeDate: tradeDate);
    _persistence.persistStockListRows(
      _stockRows(data, codeKey: 'SECURITY_CODE', nameKey: 'SECURITY_NAME_ABBR'),
    );
    return _payload(
      action: 'dragon_tiger',
      count: data.length,
      data: data.take(20).toList(),
      noteLimit: 20,
      source: result.source,
      provenance: result.provenance.toJson(),
    );
  }

  Future<Map<String, dynamic>> northbound(Map<String, dynamic> input) async {
    final symbols = (input['symbols'] as List?)?.cast<String>() ?? [];
    if (symbols.isNotEmpty) {
      final code = _normalizeSymbol(symbols.first);
      final result = await _router.runCapability<List<Map<String, dynamic>>>(
        interfaceId: 'market.northbound_holding',
        call: (capability) async {
          if (capability.provider != FinanceProvider.eastmoneyDirect) {
            return null;
          }
          return DataApiProviderExecution(
            data: await _provider.readNorthboundHolding(code: code),
            source: '东方财富',
          );
        },
        isUsable: (_) => true,
        emptyMessage: 'returned empty northbound holding rows',
        failureMessage: 'All northbound sources failed',
      );
      final data = result.data;
      _persistence.persistNorthboundHolding(data, code: code);
      _persistence.persistStockListRows(
        _stockRows(
          data,
          codeKey: 'SECURITY_CODE',
          nameKey: 'SECURITY_NAME_ABBR',
        ),
      );
      return {
        'action': 'northbound_holding',
        'source': result.source,
        'provenance': result.provenance.toJson(),
        'symbol': code,
        'count': data.length,
        'data': data.take(10).toList(),
      };
    }
    final days = input['limit'] as int? ?? 20;
    final result = await _router.runCapability<List<Map<String, dynamic>>>(
      interfaceId: 'market.northbound_flow',
      call: (capability) async {
        if (capability.provider != FinanceProvider.eastmoneyDirect) {
          return null;
        }
        return DataApiProviderExecution(
          data: await _provider.readNorthboundFlow(days: days),
          source: '东方财富',
        );
      },
      isUsable: (_) => true,
      emptyMessage: 'returned empty northbound flow rows',
      failureMessage: 'All northbound sources failed',
    );
    final data = result.data;
    _persistence.persistNorthboundFlow(data);
    return {
      'action': 'northbound_flow',
      'source': result.source,
      'provenance': result.provenance.toJson(),
      'days': data.length,
      'data': data.take(20).toList(),
    };
  }

  Future<Map<String, dynamic>> unusual(Map<String, dynamic> input) async {
    final eventDate = _inputDate(input);
    final result = await _eastmoneyRows(
      interfaceId: 'market.unusual_activity',
      read: () => _provider.readUnusual(pageSize: 50),
      emptyMessage: 'returned empty unusual-activity rows',
      failureMessage: 'All unusual-activity sources failed',
    );
    final data = result.data;
    _persistence.persistUnusualActivity(data, eventDate: eventDate);
    _persistence.persistStockListRows(_stockRows(data));
    return _payload(
      action: 'unusual',
      count: data.length,
      data: data.take(30).toList(),
      noteLimit: 30,
      source: result.source,
      provenance: result.provenance.toJson(),
    );
  }

  Future<Map<String, dynamic>> flowRank(Map<String, dynamic> input) async {
    final period = input['period'] as String? ?? 'today';
    final tradeDate = _inputDate(input);
    final result = await _eastmoneyRows(
      interfaceId: 'market.flow_rank',
      read: () => _provider.readFlowRank(period: period, pageSize: 30),
      emptyMessage: 'returned empty flow-rank rows',
      failureMessage: 'All flow-rank sources failed',
    );
    final data = result.data;
    _persistence.persistFlowRank(period, data, tradeDate: tradeDate);
    _persistence.persistStockListRows(_stockRows(data));
    return {
      'action': 'flow_rank',
      'source': result.source,
      'provenance': result.provenance.toJson(),
      'period': period,
      'count': data.length,
      'data': data.take(30).toList(),
    };
  }

  Future<DataApiRouteResult<List<Map<String, dynamic>>>> _eastmoneyRows({
    required String interfaceId,
    required Future<List<Map<String, dynamic>>> Function() read,
    required String emptyMessage,
    required String failureMessage,
  }) {
    return _router.runCapability<List<Map<String, dynamic>>>(
      interfaceId: interfaceId,
      call: (capability) async {
        if (capability.provider != FinanceProvider.eastmoneyDirect) {
          return null;
        }
        return DataApiProviderExecution(data: await read(), source: '东方财富');
      },
      isUsable: (_) => true,
      emptyMessage: emptyMessage,
      failureMessage: failureMessage,
    );
  }

  Map<String, dynamic> queryAction(
    String action,
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    switch (action) {
      case 'query_hot_rank':
        return _queryHotRank(symbols, input, context);
      case 'query_dragon_tiger':
        return _queryDragonTiger(symbols, input, context);
      case 'query_limit_pool':
        return _queryLimitPool(symbols, input, context);
      case 'query_northbound_flow':
        return _queryNorthboundFlow(symbols, input, context);
      case 'query_northbound_holding':
        return _queryNorthboundHolding(symbols, input, context);
      case 'query_northbound':
        return _queryNorthbound(symbols, input, context);
      case 'query_unusual':
        return _queryUnusual(symbols, input, context);
      case 'query_flow_rank':
        return _queryFlowRank(symbols, input, context);
      default:
        throw ArgumentError(
          'Unsupported EastMoney advanced query action: $action',
        );
    }
  }

  String _normalizeSymbol(String code) {
    final stripped = code.replaceAll(
      RegExp(r'\.(SH|SZ|BJ|HK)$', caseSensitive: false),
      '',
    );
    return stripped.replaceAll(
      RegExp(r'^(SH|SZ|BJ)', caseSensitive: false),
      '',
    );
  }

  String? _requestDate(Map<String, dynamic> input) {
    final raw = input['startDate'] as String?;
    return raw?.replaceAll('-', '');
  }

  String? _inputDate(Map<String, dynamic> input) {
    final value = input['date'] ?? input['startDate'];
    if (value == null) return null;
    final text = '$value'.replaceAll('/', '-');
    if (text.length == 8 && !text.contains('-')) {
      return '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6, 8)}';
    }
    return text.isEmpty ? null : text;
  }

  List<Map<String, dynamic>> _stockRows(
    List<Map<String, dynamic>> rows, {
    String codeKey = 'code',
    String nameKey = 'name',
    String? industryKey,
  }) {
    return rows
        .where(
          (row) =>
              ('${row[codeKey] ?? ''}'.trim().isNotEmpty) &&
              ('${row[nameKey] ?? ''}'.trim().isNotEmpty),
        )
        .map(
          (row) => {
            'code': row[codeKey],
            'name': row[nameKey],
            'market': _repository.normalizeCnMarket(
              '${row[codeKey] ?? ''}',
              row['marketCode'],
            ),
            if (industryKey != null) 'industry': row[industryKey],
            'stock_type': 'stock',
          },
        )
        .toList();
  }

  Map<String, dynamic> _payload({
    required String action,
    required int count,
    required List<dynamic> data,
    int? noteLimit,
    String source = '东方财富',
    Map<String, Object?>? provenance,
  }) {
    return {
      'action': action,
      'source': source,
      ...(provenance == null
          ? const <String, Object?>{}
          : {'provenance': provenance}),
      'count': count,
      'data': data,
      if (noteLimit != null && count > noteLimit)
        'note': '$count total, showing top $noteLimit',
    };
  }

  Map<String, dynamic> _queryHotRank(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows = _repository.queryHotRank(
      context,
      code: symbols.isEmpty ? null : symbols.first,
      tradeDate: _inputDate(input),
      limit: _inputLimit(input, 12),
    );
    final firstRow = rows.isEmpty ? null : rows.first;
    final data = _enrichRowsWithCachedQuotes(rows, context);
    return {
      'action': 'query_hot_rank',
      'interfaceId': 'market.hot_rank',
      'provider': firstRow?['source'] ?? 'local',
      'capabilityId': 'local.market.hot_rank',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'canonicalSchema': 'hot_rank',
      'canonicalTable': 'hot_rank',
      'readbackAction': 'query_hot_rank',
      if (firstRow?['trade_date'] != null)
        'sourceDataTime': firstRow?['trade_date'],
      if (firstRow?['fetched_at'] != null) 'fetchedAt': firstRow?['fetched_at'],
      if (symbols.isNotEmpty) 'symbol': symbols.first,
      'count': data.length,
      'source': 'local hot_rank',
      'data': data,
      if (data.isNotEmpty) 'workflowHint': _broadReadbackWorkflowHint,
    };
  }

  Map<String, dynamic> _queryDragonTiger(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows = _repository.queryDragonTiger(
      context,
      code: symbols.isEmpty ? null : symbols.first,
      tradeDate: _inputDate(input),
      limit: _inputLimit(input, 50),
    );
    final firstRow = rows.isEmpty ? null : rows.first;
    return {
      'action': 'query_dragon_tiger',
      'interfaceId': 'market.dragon_tiger',
      'provider': firstRow?['source'] ?? 'local',
      'capabilityId': 'local.market.dragon_tiger',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'canonicalSchema': 'dragon_tiger',
      'canonicalTable': 'dragon_tiger',
      'readbackAction': 'query_dragon_tiger',
      if (firstRow?['trade_date'] != null)
        'sourceDataTime': firstRow?['trade_date'],
      if (firstRow?['fetched_at'] != null) 'fetchedAt': firstRow?['fetched_at'],
      if (symbols.isNotEmpty) 'symbol': symbols.first,
      'count': rows.length,
      'source': 'local dragon_tiger',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryLimitPool(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows = _repository.queryLimitPool(
      context,
      poolType: input['poolType'] as String?,
      code: symbols.isEmpty ? null : symbols.first,
      tradeDate: _inputDate(input),
      limit: _inputLimit(input, 50),
    );
    final firstRow = rows.isEmpty ? null : rows.first;
    final data = _enrichRowsWithCachedQuotes(rows, context);
    return {
      'action': 'query_limit_pool',
      'interfaceId': 'market.limit_pool',
      'provider': firstRow?['source'] ?? 'local',
      'capabilityId': 'local.market.limit_pool',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'canonicalSchema': 'limit_pool',
      'canonicalTable': 'limit_pool',
      'readbackAction': 'query_limit_pool',
      if (firstRow?['trade_date'] != null)
        'sourceDataTime': firstRow?['trade_date'],
      if (firstRow?['fetched_at'] != null) 'fetchedAt': firstRow?['fetched_at'],
      if (input['poolType'] != null) 'poolType': input['poolType'],
      if (symbols.isNotEmpty) 'symbol': symbols.first,
      'count': data.length,
      'source': 'local limit_pool',
      'data': data,
      if (data.isNotEmpty) 'workflowHint': _broadReadbackWorkflowHint,
    };
  }

  Map<String, dynamic> _queryNorthbound(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final kind = '${input['kind'] ?? (symbols.isEmpty ? 'flow' : 'holding')}';
    final rows = kind == 'holding'
        ? _repository.queryNorthboundHolding(
            context,
            code: symbols.isEmpty ? input['code'] as String? : symbols.first,
            tradeDate: _inputDate(input),
            limit: _inputLimit(input, 50),
          )
        : _repository.queryNorthboundFlow(
            context,
            tradeDate: _inputDate(input),
            limit: _inputLimit(input, 50),
          );
    final firstRow = rows.isEmpty ? null : rows.first;
    final interfaceId = kind == 'holding'
        ? 'market.northbound_holding'
        : 'market.northbound_flow';
    final canonicalTable = kind == 'holding'
        ? 'northbound_holding'
        : 'northbound_flow';
    final readbackAction = kind == 'holding'
        ? 'query_northbound_holding'
        : 'query_northbound_flow';
    return {
      'action': 'query_northbound',
      'kind': kind,
      'interfaceId': interfaceId,
      'provider': firstRow?['source'] ?? 'local',
      'capabilityId': 'local.$interfaceId',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'canonicalSchema': canonicalTable,
      'canonicalTable': canonicalTable,
      'readbackAction': readbackAction,
      if (firstRow?['trade_date'] != null)
        'sourceDataTime': firstRow?['trade_date'],
      if (firstRow?['fetched_at'] != null) 'fetchedAt': firstRow?['fetched_at'],
      if (symbols.isNotEmpty) 'symbol': symbols.first,
      'count': rows.length,
      'source': kind == 'holding'
          ? 'local northbound_holding'
          : 'local northbound_flow',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryNorthboundFlow(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) => _queryNorthbound(symbols, {...input, 'kind': 'flow'}, context);

  Map<String, dynamic> _queryNorthboundHolding(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) => _queryNorthbound(symbols, {...input, 'kind': 'holding'}, context);

  Map<String, dynamic> _queryUnusual(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows = _repository.queryUnusualActivity(
      context,
      code: symbols.isEmpty ? null : symbols.first,
      eventDate: _inputDate(input),
      limit: _inputLimit(input, 50),
    );
    final sourceDataTime = _latestValue(rows, const ['event_date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    final data = _enrichRowsWithCachedQuotes(rows, context);
    return {
      'action': 'query_unusual',
      if (symbols.isNotEmpty) 'symbol': symbols.first,
      'interfaceId': 'market.unusual_activity',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? 'cacheFirst read reusable local data; no unusual_activity rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable unusual_activity rows',
      'canonicalSchema': 'unusual_activity',
      'canonicalTable': 'unusual_activity',
      ...?sourceDataTime == null ? null : {'sourceDataTime': sourceDataTime},
      ...?fetchedAt == null ? null : {'fetchedAt': fetchedAt},
      'count': data.length,
      'source': 'local unusual_activity',
      'data': data,
      if (data.isNotEmpty) 'workflowHint': _broadReadbackWorkflowHint,
    };
  }

  Map<String, dynamic> _queryFlowRank(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows = _repository.queryFlowRank(
      context,
      period: input['period'] as String?,
      code: symbols.isEmpty ? null : symbols.first,
      tradeDate: _inputDate(input),
      limit: _inputLimit(input, 50),
    );
    final sourceDataTime = _latestValue(rows, const ['trade_date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    final data = _enrichRowsWithCachedQuotes(rows, context);
    return {
      'action': 'query_flow_rank',
      if (input['period'] != null) 'period': input['period'],
      if (symbols.isNotEmpty) 'symbol': symbols.first,
      'interfaceId': 'market.flow_rank',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? 'cacheFirst read reusable local data; no flow_rank rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable flow_rank rows',
      'canonicalSchema': 'flow_rank',
      'canonicalTable': 'flow_rank',
      ...?sourceDataTime == null ? null : {'sourceDataTime': sourceDataTime},
      ...?fetchedAt == null ? null : {'fetchedAt': fetchedAt},
      'count': data.length,
      'source': 'local flow_rank',
      'data': data,
      'analysisEvidence': _flowRankAnalysisEvidence(
        symbols: symbols,
        rows: data,
        sourceDataTime: sourceDataTime,
        fetchedAt: fetchedAt,
      ),
      if (data.isNotEmpty) 'workflowHint': _broadReadbackWorkflowHint,
    };
  }

  Map<String, dynamic> _flowRankAnalysisEvidence({
    required List<String> symbols,
    required List<Map<String, dynamic>> rows,
    required String? sourceDataTime,
    required String? fetchedAt,
  }) {
    final top = rows.isEmpty ? null : rows.first;
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.flow,
      subjectType: AnalysisSubjectType.flow,
      subjectId: symbols.isEmpty ? 'market-flow-rank' : symbols.first,
      subjectName: symbols.isEmpty ? 'Market flow rank' : symbols.first,
      observedFacts: [
        'rows=${rows.length}',
        if (symbols.isNotEmpty) 'symbol=${symbols.first}',
        if (sourceDataTime != null) 'sourceDataTime=$sourceDataTime',
        if (top != null) 'top=${top['name'] ?? top['code'] ?? '-'}',
        if (top != null && top['main_net'] != null)
          'topMainNet=${top['main_net']}',
      ],
      interpretations: [
        rows.isEmpty ? 'flow_rank:missing' : 'flow_rank:available',
        'capital_flow:readback_evidence',
      ],
      missingEvidence: const [
        'sector_rotation_context',
        'price_confirmation',
        'news_context',
        'strategy_validation',
      ],
      confidence: rows.isEmpty
          ? AnalysisConfidence.low
          : AnalysisConfidence.medium,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: AnalysisSourceCoverage(
        sources: const ['local flow_rank'],
        interfaceId: 'market.flow_rank',
        capabilityId: 'local.cache',
        canonicalSchema: 'flow_rank',
        canonicalTable: 'flow_rank',
        readbackAction: 'query_flow_rank',
        sourceDataTime: sourceDataTime ?? '',
        fetchedAt: fetchedAt ?? '',
        cacheStatus: rows.isEmpty ? 'cache-miss' : 'cache-hit',
        coverageStatus: rows.isEmpty
            ? AnalysisCoverageStatus.none
            : AnalysisCoverageStatus.sufficientForAnalysis,
      ),
    ).toJson();
  }

  List<Map<String, dynamic>> _enrichRowsWithCachedQuotes(
    List<Map<String, dynamic>> rows,
    ToolContext context,
  ) {
    if (rows.isEmpty) return rows;
    return rows
        .map((row) {
          final code = _rowCode(row);
          if (code == null) return row;
          final quotes = _localMarketRepository.queryQuotes(
            context,
            code,
            limit: 1,
          );
          if (quotes.isEmpty) return row;
          final quote = quotes.first;
          final enriched = Map<String, dynamic>.from(row);
          enriched
            ..putIfAbsent('quote_price', () => quote.price)
            ..putIfAbsent('quote_change', () => quote.change)
            ..putIfAbsent('quote_change_pct', () => quote.changePct)
            ..putIfAbsent('quote_open', () => quote.open)
            ..putIfAbsent('quote_high', () => quote.high)
            ..putIfAbsent('quote_low', () => quote.low)
            ..putIfAbsent('quote_prev_close', () => quote.prevClose)
            ..putIfAbsent('quote_volume', () => quote.volume)
            ..putIfAbsent('quote_amount', () => quote.amount)
            ..putIfAbsent('quote_source', () => quote.source);
          if ((enriched['name'] == null || '${enriched['name']}'.isEmpty) &&
              quote.name.isNotEmpty) {
            enriched['name'] = quote.name;
          }
          if (quote.timestamp != null && quote.timestamp!.isNotEmpty) {
            enriched.putIfAbsent('quote_data_time', () => quote.timestamp);
          }
          if (quote.fetchedAt != null && quote.fetchedAt!.isNotEmpty) {
            enriched.putIfAbsent('quote_fetched_at', () => quote.fetchedAt);
          }
          return enriched;
        })
        .toList(growable: false);
  }

  String? _rowCode(Map<String, dynamic> row) {
    for (final key in const ['code', 'symbol', 'stock_code', 'secucode']) {
      final value = row[key];
      if (value == null) continue;
      final raw = '$value'.trim();
      if (raw.isEmpty) continue;
      final match = RegExp(r'(\d{6})').firstMatch(raw);
      return match?.group(1) ?? raw;
    }
    return null;
  }
}

const _broadReadbackWorkflowHint =
    'Rows include cached quote fields when available; broad first-pass answers should use this reusable evidence before live quote refresh.';

int _inputLimit(Map<String, dynamic> input, int fallback) {
  final value = input['limit'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return fallback;
}

String? _latestValue(List<Map<String, dynamic>> rows, List<String> keys) {
  for (final row in rows) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.isNotEmpty) return '$value';
    }
  }
  return null;
}
