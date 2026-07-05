import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/provider_policy.dart';
import '../../../agent/tool_context.dart';
import '../analysis/analysis_evidence_contract.dart';
import '../providers/eastmoney_market_provider.dart';
import '../repositories/eastmoney_market_data_repository.dart';
import 'eastmoney_market_data_persistence_service.dart';

class EastmoneyMarketDataService {
  final EastmoneyMarketProvider _provider;
  final EastmoneyMarketDataRepository _repository;
  final EastmoneyMarketDataPersistenceService _persistence;
  final DataManager _dataManager;
  final bool _useDataApiMarketProvider;

  EastmoneyMarketDataService({
    DataManager? dataManager,
    EastmoneyMarketProvider? provider,
  }) : this._internal(dataManager ?? DataManager(), provider);

  EastmoneyMarketDataService._internal(
    DataManager dataManager,
    EastmoneyMarketProvider? provider,
  ) : _dataManager = dataManager,
      _provider = provider ?? dataManager.eastmoneyMarketProvider,
      _repository = EastmoneyMarketDataRepository(dataManager),
      _persistence = EastmoneyMarketDataPersistenceService(
        EastmoneyMarketDataRepository(dataManager),
      ),
      _useDataApiMarketProvider = provider == null;

  Future<Map<String, dynamic>> flow(String symbol) async {
    final result = _useDataApiMarketProvider
        ? await _dataManager.getMoneyFlow(symbol)
        : await _provider.readMoneyFlow(symbol);
    final flows = result.data;
    _persistence.persistMoneyFlow(symbol, flows, source: result.source);
    final recent = flows.length > 10 ? flows.sublist(flows.length - 10) : flows;
    return {
      'action': 'flow',
      'symbol': symbol,
      'source': result.source,
      'days': flows.length,
      'recent10': recent.map((f) => f.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> etf({String? source}) async {
    final result = await _provider.readEtfQuotes(source: source);
    final quotes = result.data;
    _persistence.persistEtfQuotes(quotes, source: result.source);
    return {
      'action': 'etf',
      'source': result.source,
      'total': quotes.length,
      'top20': quotes.take(20).map((q) => q.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> listedFundQuote({String? source}) async {
    final result = await _provider.readListedFundQuotes(source: source);
    final quotes = result.data;
    _persistence.persistListedFundQuotes(quotes, source: result.source);
    return {
      'action': 'listed_fund_quote',
      'interfaceId': 'fund.listed_fund_quote',
      'provider': source ?? result.source,
      'capabilityId': 'tencent.fund.listed_fund_quote',
      'canonicalSchema': 'quote_snapshot',
      'canonicalTable': 'quote_snapshot',
      'readbackAction': 'query_listed_fund_quote',
      'cacheStatus': 'provider-hit',
      'cacheDecision':
          'provider fetch returned quote_snapshot rows and persisted them for same-runtime query_listed_fund_quote readback',
      'source': result.source,
      'total': quotes.length,
      'top20': quotes.take(20).map((q) => q.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> stockList({String? source}) async {
    final result = await _provider.readStockList(source: source);
    _persistence.persistStockListRows(result.data, source: result.source);
    final isTencent =
        _isTencentSource(source) || _isTencentSource(result.source);
    return {
      'action': 'stock_list',
      'interfaceId': 'stock.identity_list',
      'provider': source ?? result.source,
      'capabilityId': isTencent
          ? 'tencent.stock.identity_list'
          : 'eastmoney.stock.identity_list',
      'canonicalSchema': 'stock_list',
      'canonicalTable': 'stock_list',
      'readbackAction': 'query_stock_list',
      'cacheStatus': 'provider-hit',
      'cacheDecision':
          'provider fetch returned stock_list rows and persisted them for same-runtime query_stock_list readback',
      'source': result.source,
      'count': result.data.length,
      'persisted': result.data.isNotEmpty,
      'tables': result.data.isEmpty ? const [] : const ['stock_list'],
      'data': result.data.take(50).toList(),
      if (result.data.length > 50)
        'note': '${result.data.length} total, showing first 50',
    };
  }

  Future<Map<String, dynamic>> fundList() async {
    final result = await _provider.readFundList();
    _persistence.persistFundList(result.data, source: result.source);
    return {
      'action': 'fund_list',
      'source': result.source,
      'count': result.data.length,
      'persisted': result.data.isNotEmpty,
      'tables': result.data.isEmpty ? const [] : const ['fund_list'],
      'data': result.data.take(50).toList(),
      if (result.data.length > 50)
        'note': '${result.data.length} total, showing first 50',
    };
  }

  bool _isTencentSource(String? source) {
    final normalized = source?.trim().toLowerCase();
    return normalized == 'tencent' ||
        normalized == 'qq' ||
        normalized == '腾讯' ||
        normalized == '腾讯财经';
  }

  Future<Map<String, dynamic>> fundNav(String fundCode) async {
    final cleanCode = fundCode.trim();
    if (cleanCode.isEmpty) {
      throw ArgumentError('fundCode required for fund_nav');
    }
    final result = await _provider.readFundNav(cleanCode);
    _persistence.persistFundNav(result.data, source: result.source);
    return {
      'action': 'fund_nav',
      'fundCode': cleanCode,
      'source': result.source,
      'count': result.data.length,
      'persisted': result.data.isNotEmpty,
      'tables': result.data.isEmpty ? const [] : const ['fund_nav'],
      'data': result.data.take(50).toList(),
      if (result.data.length > 50)
        'note': '${result.data.length} total, showing first 50',
    };
  }

  Future<Map<String, dynamic>> fundMoneyYield(String fundCode) async {
    final cleanCode = fundCode.trim();
    if (cleanCode.isEmpty) {
      throw ArgumentError('fundCode required for fund_money_yield');
    }
    final result = await _provider.readFundMoneyYield(cleanCode);
    _persistence.persistFundMoneyYield(result.data, source: result.source);
    return {
      'action': 'fund_money_yield',
      'interfaceId': 'fund.money_yield_history',
      'provider': 'eastmoneyDirect',
      'capabilityId': 'eastmoney.fund.money_yield_history',
      'canonicalSchema': 'fund_money_yield',
      'canonicalTable': 'fund_money_yield',
      'readbackAction': 'query_fund_money_yield',
      'cacheStatus': 'provider-hit',
      'cacheDecision':
          'provider fetch returned money-fund yield rows and persisted them for same-runtime query_fund_money_yield readback',
      'fundCode': cleanCode,
      'source': result.source,
      'count': result.data.length,
      'persisted': result.data.isNotEmpty,
      'tables': result.data.isEmpty ? const [] : const ['fund_money_yield'],
      'data': result.data.take(50).toList(),
      if (result.data.length > 50)
        'note': '${result.data.length} total, showing first 50',
    };
  }

  Future<Map<String, dynamic>> fundManager() async {
    final result = await _provider.readFundManagers();
    _persistence.persistFundManagers(result.data, source: result.source);
    return {
      'action': 'fund_manager',
      'source': result.source,
      'count': result.data.length,
      'persisted': result.data.isNotEmpty,
      'tables': result.data.isEmpty ? const [] : const ['fund_manager'],
      'data': result.data.take(50).toList(),
      if (result.data.length > 50)
        'note': '${result.data.length} total, showing first 50',
    };
  }

  Future<Map<String, dynamic>> fundHolding(String fundCode) async {
    final cleanCode = fundCode.trim();
    if (cleanCode.isEmpty) {
      throw ArgumentError('fundCode required for fund_holding');
    }
    final result = await _provider.readFundHolding(cleanCode);
    _persistence.persistFundHolding(result.data, source: result.source);
    return {
      'action': 'fund_holding',
      'fundCode': cleanCode,
      'source': result.source,
      'count': result.data.length,
      'persisted': result.data.isNotEmpty,
      'tables': result.data.isEmpty
          ? const []
          : const ['fund_holding', 'stock_list'],
      'data': result.data.take(50).toList(),
      if (result.data.length > 50)
        'note': '${result.data.length} total, showing first 50',
    };
  }

  Future<Map<String, dynamic>> fundPerformance() async {
    final result = await _provider.readFundPerformance();
    _persistence.persistFundPerformance(result.data, source: result.source);
    return {
      'action': 'fund_performance',
      'source': result.source,
      'count': result.data.length,
      'persisted': result.data.isNotEmpty,
      'tables': result.data.isEmpty
          ? const []
          : const ['fund_performance_metrics'],
      'data': result.data.take(50).toList(),
      if (result.data.length > 50)
        'note': '${result.data.length} total, showing first 50',
    };
  }

  Future<Map<String, dynamic>> stockShareholders(
    String code, {
    String? reportDate,
  }) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) {
      throw ArgumentError('symbol/code required for stock_shareholders');
    }
    final result = await _provider.readStockShareholders(
      cleanCode,
      reportDate: reportDate,
    );
    _persistence.persistStockShareholders(result.data, source: result.source);
    final resolvedDate = result.data.isEmpty
        ? reportDate
        : '${result.data.first['report_date'] ?? reportDate ?? ''}';
    return {
      'action': 'stock_shareholders',
      'symbol': cleanCode,
      if (resolvedDate != null && resolvedDate.isNotEmpty)
        'reportDate': resolvedDate,
      'source': result.source,
      'count': result.data.length,
      'persisted': result.data.isNotEmpty,
      'tables': result.data.isEmpty ? const [] : const ['stock_shareholder'],
      'data': result.data.take(50).toList(),
      if (result.data.length > 50)
        'note': '${result.data.length} total, showing first 50',
    };
  }

  Future<Map<String, dynamic>> stockCompanyInfo(String code) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) {
      throw ArgumentError('symbol/code required for stock_company_info');
    }
    final result = await _provider.readStockCompanyInfo(cleanCode);
    if (result.data.isNotEmpty) {
      _persistence.persistStockCompanyInfo(
        cleanCode,
        result.data,
        source: result.source,
      );
    }
    return {
      'action': 'stock_company_info',
      'symbol': cleanCode,
      'source': result.source,
      'persisted': result.data.isNotEmpty,
      'tables': result.data.isEmpty ? const [] : const ['stock_company_info'],
      'data': result.data,
    };
  }

  Future<Map<String, dynamic>> sector(Map<String, dynamic> input) async {
    final sectorCode =
        ((input['sectorCode'] as String?) ??
                (input['boardCode'] as String?) ??
                '')
            .trim();
    if (sectorCode.isNotEmpty) {
      final sectorName =
          ((input['sectorName'] as String?) ??
                  (input['boardName'] as String?) ??
                  '')
              .trim();
      final boardType =
          ((input['boardType'] as String?) ?? (input['type'] as String?) ?? '')
              .trim();
      final interfaceId = boardType == 'concept' || input['boardCode'] != null
          ? 'market.board_members'
          : 'market.sector_constituents';
      final providerInfo = _sectorProviderInfo(input['provider'] as String?);
      final stocks = await _provider.readSectorStocks(
        sectorCode,
        sectorName: sectorName.isEmpty ? null : sectorName,
        source: input['provider'] as String?,
      );
      _persistence.persistSectorStocks(
        stocks,
        source: providerInfo.source,
        sectorCode: sectorCode,
        sectorName: sectorName.isEmpty ? null : sectorName,
      );
      return {
        'action': 'sector',
        'source': providerInfo.source,
        'interfaceId': interfaceId,
        'provider': providerInfo.provider,
        'capabilityId': '${providerInfo.provider}.$interfaceId',
        'canonicalSchema': 'industry_map',
        'canonicalTable': 'industry_map',
        'cacheStatus': 'provider-hit',
        'cacheDecision':
            'provider fetch returned industry_map rows and persisted them for same-runtime ${interfaceId == 'market.board_members' ? 'query_board_members' : 'query_sector_constituents'} readback',
        'readbackAction': interfaceId == 'market.board_members'
            ? 'query_board_members'
            : 'query_sector_constituents',
        'sectorCode': sectorCode,
        'sectorName': sectorName.isNotEmpty ? sectorName : null,
        'count': stocks.length,
        'persisted': stocks.isNotEmpty,
        'tables': stocks.isEmpty
            ? const []
            : const ['quote_snapshot', 'industry_map'],
        'data': stocks.take(50).map((quote) => quote.toJson()).toList(),
        if (stocks.length > 50)
          'note': '${stocks.length} total, showing first 50',
      };
    }
    final boardType = input['boardType'] as String? ?? 'industry';
    final result = _useDataApiMarketProvider
        ? await _dataManager.marketDataProvider.readSectorRanking(
            boardType: boardType,
            source: input['provider'] as String?,
          )
        : (
            data: await _provider.readSectorRanking(boardType: boardType),
            source: '东方财富',
          );
    final sectors = result.data;
    _persistence.persistSectorRanking(
      boardType,
      sectors,
      source: result.source,
    );
    return {
      'action': 'sector',
      'source': result.source,
      'boardType': boardType,
      'total': sectors.length,
      'top20': sectors.take(20).toList(),
    };
  }

  _SectorProviderInfo _sectorProviderInfo(String? rawProvider) {
    final providers = rawProvider == null
        ? const <FinanceProvider>[]
        : const ProviderPolicy().normalizeProviders(rawProvider);
    final provider = providers.isEmpty
        ? FinanceProvider.eastmoneyDirect
        : providers.first;
    return switch (provider) {
      FinanceProvider.sina => const _SectorProviderInfo(
        provider: 'sina',
        source: '新浪财经',
      ),
      _ => const _SectorProviderInfo(provider: 'eastmoney', source: '东方财富'),
    };
  }

  Future<Map<String, dynamic>> chip(String symbol) async {
    final chip = await _provider.readChipDistribution(symbol);
    _persistence.persistChipDistribution(symbol, chip, source: '东方财富');
    return {'action': 'chip', 'source': '东方财富', ...chip};
  }

  Map<String, dynamic> queryAction(
    String action,
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    switch (action) {
      case 'query_board_members':
      case 'query_sector_constituents':
        return queryIndustryMap(
          action,
          context,
          input,
          limit: _inputLimit(input, 50),
        );
      case 'query_board_ranking':
        return querySector(
          action,
          context,
          input,
          tradeDate: _inputDate(input),
          limit: _inputLimit(input, 50),
        );
      case 'query_sector_ranking':
      case 'query_sector':
        return querySector(
          action,
          context,
          input,
          tradeDate: _inputDate(input),
          limit: _inputLimit(input, 12),
        );
      case 'query_industry_map':
        return queryIndustryMap(
          action,
          context,
          input,
          limit: _inputLimit(input, 50),
        );
      case 'query_chip':
        return queryChip(
          context,
          symbols.first,
          input: input,
          tradeDate: _inputDate(input),
          limit: _inputLimit(input, 20),
        );
      default:
        throw ArgumentError('Unsupported EastMoney query action: $action');
    }
  }

  Map<String, dynamic> querySector(
    String action,
    ToolContext context,
    Map<String, dynamic> input, {
    required String? tradeDate,
    int limit = 50,
  }) {
    final boardType =
        (input['boardType'] as String?) ?? (input['type'] as String?);
    final providerConstraint = _EastmoneyReadbackProviderConstraint.fromInput(
      input,
    );
    final rows = _queryMapsWithProviderConstraint(
      providerConstraint,
      (source) => _repository.querySectorRanking(
        context,
        boardType: boardType,
        tradeDate: tradeDate,
        source: source,
        limit: limit,
      ),
    );
    final interfaceId = action == 'query_board_ranking'
        ? 'market.board_ranking'
        : 'market.sector_ranking';
    final sourceDataTime =
        tradeDate ?? _latestValue(rows, const ['trade_date', 'date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at', 'updated_at']);
    return {
      'action': action,
      ...?boardType == null ? null : {'boardType': boardType},
      'interfaceId': interfaceId,
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no sector_rank rows matched the requirement'
                : 'cacheFirst read reusable local data; no sector_rank rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable sector_rank rows',
      'canonicalSchema': 'sector_rank',
      'canonicalTable': 'sector_rank',
      if (sourceDataTime != null && sourceDataTime.isNotEmpty)
        'sourceDataTime': sourceDataTime,
      if (fetchedAt != null && fetchedAt.isNotEmpty) 'fetchedAt': fetchedAt,
      'count': rows.length,
      'source': 'local sector_rank',
      'data': rows,
      'analysisEvidence': _sectorRankingAnalysisEvidence(
        action: action,
        interfaceId: interfaceId,
        boardType: boardType,
        rows: rows,
        sourceDataTime: sourceDataTime,
        fetchedAt: fetchedAt,
      ),
    };
  }

  Map<String, dynamic> _sectorRankingAnalysisEvidence({
    required String action,
    required String interfaceId,
    required String? boardType,
    required List<Map<String, dynamic>> rows,
    required String? sourceDataTime,
    required String? fetchedAt,
  }) {
    final top = rows.isEmpty ? null : rows.first;
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.sector,
      subjectType: AnalysisSubjectType.sector,
      subjectId: boardType ?? 'market-sector-ranking',
      subjectName: action == 'query_board_ranking'
          ? 'Board ranking'
          : 'Sector ranking',
      observedFacts: [
        'rows=${rows.length}',
        if (boardType != null) 'boardType=$boardType',
        if (sourceDataTime != null) 'sourceDataTime=$sourceDataTime',
        if (top != null) 'top=${top['name'] ?? top['code'] ?? '-'}',
        if (top != null && top['change_pct'] != null)
          'topChangePct=${top['change_pct']}',
      ],
      interpretations: [
        rows.isEmpty ? 'sector_rank:missing' : 'sector_rank:available',
        'sector_rotation:readback_evidence',
      ],
      missingEvidence: const [
        'sector_constituents',
        'money_flow_confirmation',
        'news_context',
        'strategy_validation',
      ],
      confidence: rows.isEmpty
          ? AnalysisConfidence.low
          : AnalysisConfidence.medium,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: AnalysisSourceCoverage(
        sources: const ['local sector_rank'],
        interfaceId: interfaceId,
        capabilityId: 'local.cache',
        canonicalSchema: 'sector_rank',
        canonicalTable: 'sector_rank',
        readbackAction: action,
        sourceDataTime: sourceDataTime ?? '',
        fetchedAt: fetchedAt ?? '',
        cacheStatus: rows.isEmpty ? 'cache-miss' : 'cache-hit',
        coverageStatus: rows.isEmpty
            ? AnalysisCoverageStatus.none
            : AnalysisCoverageStatus.sufficientForAnalysis,
      ),
    ).toJson();
  }

  Map<String, dynamic> queryIndustryMap(
    String action,
    ToolContext context,
    Map<String, dynamic> input, {
    int limit = 50,
  }) {
    final code =
        (input['code'] as String?) ??
        (input['boardCode'] as String?) ??
        (input['sectorCode'] as String?);
    final industry =
        (input['industry'] as String?) ??
        (input['sectorName'] as String?) ??
        (input['boardName'] as String?);
    final rows = _repository.queryIndustryMap(
      context,
      code: code,
      industry: industry,
      limit: limit,
    );
    final interfaceId = action == 'query_board_members'
        ? 'market.board_members'
        : 'market.sector_constituents';
    final cacheHit = rows.isNotEmpty;
    return {
      'action': action,
      if (code != null && code.isNotEmpty) 'code': code,
      if (industry != null && industry.isNotEmpty) 'industry': industry,
      'interfaceId': interfaceId,
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': cacheHit ? 'cache-hit' : 'cache-miss',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': cacheHit
          ? 'cacheFirst read reusable local data before provider routing; cache reader returned usable industry_map rows'
          : 'cacheFirst read reusable local data before provider routing; no industry_map rows matched the requirement',
      'canonicalSchema': 'industry_map',
      'canonicalTable': 'industry_map',
      'count': rows.length,
      'source': 'local industry_map',
      'data': rows,
    };
  }

  Map<String, dynamic> queryChip(
    ToolContext context,
    String symbol, {
    required Map<String, dynamic> input,
    String? tradeDate,
    int limit = 20,
  }) {
    final providerConstraint = _EastmoneyReadbackProviderConstraint.fromInput(
      input,
    );
    final rows = _queryMapsWithProviderConstraint(
      providerConstraint,
      (source) => _repository.queryChipDistribution(
        context,
        symbol,
        tradeDate: tradeDate,
        source: source,
        limit: limit,
      ),
    );
    final sourceDataTime = _latestValue(rows, const ['trade_date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    return {
      'action': 'query_chip',
      'symbol': symbol,
      'interfaceId': 'stock.chip_distribution',
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no chip_distribution rows matched the requirement'
                : 'cacheFirst read reusable local data; no chip_distribution rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable chip_distribution rows',
      'canonicalSchema': 'chip_distribution',
      'canonicalTable': 'chip_distribution',
      ...?sourceDataTime == null ? null : {'sourceDataTime': sourceDataTime},
      ...?fetchedAt == null ? null : {'fetchedAt': fetchedAt},
      'count': rows.length,
      'source': 'local chip_distribution',
      'data': rows,
    };
  }
}

class _SectorProviderInfo {
  final String provider;
  final String source;

  const _SectorProviderInfo({required this.provider, required this.source});
}

List<Map<String, dynamic>> _queryMapsWithProviderConstraint(
  _EastmoneyReadbackProviderConstraint constraint,
  List<Map<String, dynamic>> Function(String? source) query,
) {
  if (!constraint.isStrict) return query(constraint.requestedProvider);
  for (final source in constraint.sourceAliases) {
    final rows = query(source);
    if (rows.isNotEmpty) {
      constraint.effectiveSource = source;
      return rows;
    }
  }
  return const [];
}

class _EastmoneyReadbackProviderConstraint {
  final String? requestedProvider;
  final String? providerMode;
  final List<String> sourceAliases;
  String? effectiveSource;

  _EastmoneyReadbackProviderConstraint({
    required this.requestedProvider,
    required this.providerMode,
    required this.sourceAliases,
  });

  factory _EastmoneyReadbackProviderConstraint.fromInput(
    Map<String, dynamic> input,
  ) {
    final requested = input['provider']?.toString().trim();
    final providerMode = input['providerMode']?.toString().trim();
    final strict =
        requested != null &&
        requested.isNotEmpty &&
        providerMode?.toLowerCase() == 'strict';
    return _EastmoneyReadbackProviderConstraint(
      requestedProvider: requested == null || requested.isEmpty
          ? null
          : requested,
      providerMode: providerMode == null || providerMode.isEmpty
          ? null
          : providerMode,
      sourceAliases: strict ? _providerSourceAliases(requested) : const [],
    );
  }

  bool get isStrict =>
      requestedProvider != null &&
      providerMode?.toLowerCase() == 'strict' &&
      sourceAliases.isNotEmpty;

  static List<String> _providerSourceAliases(String provider) {
    switch (provider.trim().toLowerCase()) {
      case 'eastmoney':
      case 'em':
      case '东方财富':
        return const ['eastmoney', 'eastmoneyDirect', '东方财富'];
      case 'sina':
      case '新浪':
      case '新浪财经':
        return const ['sina', '新浪', '新浪财经'];
      case 'tencent':
      case 'qq':
      case '腾讯':
      case '腾讯财经':
        return const ['tencent', 'qq', '腾讯', '腾讯财经'];
      default:
        return [provider];
    }
  }
}

int _inputLimit(Map<String, dynamic> input, int fallback) {
  final value = input['limit'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return fallback;
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

String? _latestValue(List<Map<String, dynamic>> rows, List<String> keys) {
  for (final row in rows) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.isNotEmpty) return '$value';
    }
  }
  return null;
}
