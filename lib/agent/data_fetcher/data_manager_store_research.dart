part of 'data_manager.dart';

extension DataManagerResearchStoreAccess on DataManager {
  void saveRawApiPayload({
    required String source,
    required String endpoint,
    required Map<String, dynamic> request,
    required Object? response,
    bool isError = false,
  }) {
    _store?.saveRawApiPayload(
      source: source,
      endpoint: endpoint,
      request: request,
      response: response,
      isError: isError,
    );
  }

  List<Map<String, dynamic>> queryRawApiPayload({
    String? source,
    String? endpoint,
    int limit = 20,
  }) {
    return _store?.queryRawApiPayload(
          source: source,
          endpoint: endpoint,
          limit: limit,
        ) ??
        const [];
  }

  Map<String, dynamic>? saveTushareRows(
    String apiName,
    List<Map<String, dynamic>> rows, {
    Map<String, dynamic> params = const {},
  }) {
    return _store?.saveTushareRows(apiName, rows, params: params);
  }

  Map<String, dynamic>? saveStockListRows(
    List<Map<String, dynamic>> rows, {
    String source = '通达信',
    String? market,
  }) {
    return _store?.saveStockListRows(rows, source: source, market: market);
  }

  void saveYfinanceProfileFields(List<Map<String, dynamic>> rows) {
    _store?.saveYfinanceProfileFields(rows);
  }

  void saveYfinanceStatementItems(List<Map<String, dynamic>> rows) {
    _store?.saveYfinanceStatementItems(rows);
  }

  void saveYfinanceRecommendations(List<Map<String, dynamic>> rows) {
    _store?.saveYfinanceRecommendations(rows);
  }

  void saveYfinanceNews(List<Map<String, dynamic>> rows) {
    _store?.saveYfinanceNews(rows);
  }

  Map<String, dynamic>? saveFinanceNews(List<Map<String, dynamic>> rows) {
    return _store?.saveFinanceNews(rows);
  }

  List<Map<String, dynamic>> queryFinanceNews({
    String? keyword,
    String? source,
    int limit = 50,
  }) {
    return _store?.queryFinanceNews(
          keyword: keyword,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  void saveYfinanceOptionExpiries(List<Map<String, dynamic>> rows) {
    _store?.saveYfinanceOptionExpiries(rows);
  }

  void saveYfinanceOptionContracts(List<Map<String, dynamic>> rows) {
    _store?.saveYfinanceOptionContracts(rows);
  }

  void saveYfinanceCorporateActions(List<Map<String, dynamic>> rows) {
    _store?.saveYfinanceCorporateActions(rows);
  }

  void saveYfinanceHolders(List<Map<String, dynamic>> rows) {
    _store?.saveYfinanceHolders(rows);
  }

  void saveYfinanceInsiderTransactions(List<Map<String, dynamic>> rows) {
    _store?.saveYfinanceInsiderTransactions(rows);
  }

  List<Map<String, dynamic>> queryYfinanceProfile(
    String symbol, {
    int limit = 100,
  }) {
    return _store?.queryYfinanceProfile(symbol, limit: limit) ?? const [];
  }

  List<Map<String, dynamic>> queryYfinanceStatements(
    String symbol, {
    String? statementType,
    int limit = 200,
  }) {
    return _store?.queryYfinanceStatements(
          symbol,
          statementType: statementType,
          limit: limit,
        ) ??
        const [];
  }

  List<Map<String, dynamic>> queryYfinanceDataset(
    String dataset,
    String symbol, {
    int limit = 100,
  }) {
    return _store?.queryYfinanceDataset(dataset, symbol, limit: limit) ??
        const [];
  }

  Map<String, dynamic>? saveFundPerformanceMetrics(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    return _store?.saveFundPerformanceMetrics(rows, source: source);
  }

  Map<String, dynamic>? saveFundManagerRows(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    return _store?.saveFundManagerRows(rows, source: source);
  }

  Map<String, dynamic>? saveFundHolding(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    return _store?.saveFundHolding(rows, source: source);
  }

  Map<String, dynamic>? saveFundList(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    return _store?.saveFundList(
      rows
          .map(
            (row) => {...row, if (!row.containsKey('source')) 'source': source},
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic>? saveFundNav(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    return _store?.saveFundNav(
      rows
          .map(
            (row) => {...row, if (!row.containsKey('source')) 'source': source},
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic>? saveFundMoneyYield(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    return _store?.saveFundMoneyYield(
      rows
          .map(
            (row) => {...row, if (!row.containsKey('source')) 'source': source},
          )
          .toList(growable: false),
    );
  }

  void saveMarginTradingRows(List<Map<String, dynamic>> rows) {
    _store?.saveMarginTradingRows(rows);
  }

  List<Map<String, dynamic>> queryFundPerformanceMetrics({
    String? code,
    String? provider,
    String? metricDate,
    int limit = 100,
  }) {
    return _store?.queryFundPerformanceMetrics(
          code: code,
          provider: provider,
          metricDate: metricDate,
          limit: limit,
        ) ??
        const [];
  }

  Map<String, dynamic>? saveIndexConstituents(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    return _store?.saveIndexConstituents(rows, source: source);
  }

  List<Map<String, dynamic>> queryIndexConstituents({
    String? indexCode,
    String? stockCode,
    String? asOfDate,
    String? provider,
    int limit = 300,
  }) {
    return _store?.queryIndexConstituents(
          indexCode: indexCode,
          stockCode: stockCode,
          asOfDate: asOfDate,
          provider: provider,
          limit: limit,
        ) ??
        const [];
  }

  Map<String, dynamic>? saveTechnicalIndicatorSeries(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    return _store?.saveTechnicalIndicatorSeries(rows, source: source);
  }

  List<Map<String, dynamic>> queryTechnicalIndicatorSeries({
    String? symbol,
    String? indicator,
    String? fieldName,
    String? since,
    String? provider,
    int limit = 200,
  }) {
    return _store?.queryTechnicalIndicatorSeries(
          symbol: symbol,
          indicator: indicator,
          fieldName: fieldName,
          since: since,
          provider: provider,
          limit: limit,
        ) ??
        const [];
  }

  Map<String, dynamic>? saveAlphaFactors(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    return _store?.saveAlphaFactors(rows, source: source);
  }

  List<Map<String, dynamic>> queryAlphaFactors({
    String? symbol,
    String? factorName,
    String? since,
    String? provider,
    int limit = 200,
  }) {
    return _store?.queryAlphaFactors(
          symbol: symbol,
          factorName: factorName,
          since: since,
          provider: provider,
          limit: limit,
        ) ??
        const [];
  }

  List<Map<String, dynamic>> queryFundamental(
    String code, {
    String? reportDate,
    String? source,
    int limit = 8,
  }) {
    return _store?.queryFundamental(
          code,
          reportDate: reportDate,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  List<Map<String, dynamic>> queryFundamentalSample({
    String? source,
    int limit = 50,
    double? peLte,
    double? peGte,
    double? roeGte,
    bool latestOnly = true,
  }) {
    return _store?.queryFundamentalSample(
          source: source,
          limit: limit,
          peLte: peLte,
          peGte: peGte,
          roeGte: roeGte,
          latestOnly: latestOnly,
        ) ??
        const [];
  }

  Map<String, dynamic>? saveFundamentalRows(
    List<Map<String, dynamic>> rows, {
    String source = '东方财富',
  }) {
    return _store?.saveFundamentalRows(rows, source: source);
  }

  List<Map<String, dynamic>> queryMoneyFlowRows(
    String code, {
    String? source,
    int limit = 30,
  }) {
    return _store?.queryMoneyFlow(code, source: source, limit: limit) ??
        const [];
  }

  Map<String, dynamic>? saveMoneyFlowRows(
    String code,
    List<MoneyFlow> rows, {
    String source = '东方财富',
  }) {
    return _store?.saveMoneyFlowRows(code, rows, source: source);
  }

  List<Map<String, dynamic>> queryFundNav(
    String code, {
    String startDate = '',
    String endDate = '',
    String? source,
    int? limit,
  }) {
    return _store?.queryFundNav(
          code,
          startDate: startDate,
          endDate: endDate,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  List<Map<String, dynamic>> queryFundNavRows({
    String startDate = '',
    String endDate = '',
    String? source,
    int limit = 100,
  }) {
    return _store?.queryFundNavRows(
          startDate: startDate,
          endDate: endDate,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  List<Map<String, dynamic>> queryFundMoneyYield(
    String code, {
    String startDate = '',
    String endDate = '',
    String? source,
    int? limit,
  }) {
    return _store?.queryFundMoneyYield(
          code,
          startDate: startDate,
          endDate: endDate,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  List<Map<String, dynamic>> queryFundDividendFactor(
    String code, {
    String startDate = '',
    String endDate = '',
    String? source,
    int? limit,
  }) {
    return _store?.queryFundDividendFactor(
          code,
          startDate: startDate,
          endDate: endDate,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  void saveFundDividendFactors(
    String code,
    List<Map<String, dynamic>> rows, {
    String source = '新浪财经',
  }) {
    _store?.saveFundDividendFactors(code, rows, source: source);
  }

  List<Map<String, dynamic>> queryIntradayOhlcvBars(
    String code, {
    String startDate = '',
    String endDate = '',
    int intervalMinutes = 5,
    String? source,
    int? limit,
  }) {
    return _store?.queryIntradayOhlcvBars(
          code,
          startDate: startDate,
          endDate: endDate,
          intervalMinutes: intervalMinutes,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  void saveIntradayOhlcvBars(
    String code,
    List<Map<String, dynamic>> rows, {
    String source = '新浪财经',
    int intervalMinutes = 5,
  }) {
    _store?.saveIntradayOhlcvBars(
      code,
      rows,
      source: source,
      intervalMinutes: intervalMinutes,
    );
  }

  List<Map<String, dynamic>> queryFundList({
    String? fundType,
    String? company,
    List<String> codes = const [],
    int limit = 50,
  }) {
    return _store?.queryFundList(
          fundType: fundType,
          company: company,
          codes: codes,
          limit: limit,
        ) ??
        const [];
  }

  List<Map<String, dynamic>> queryFundManager({
    String? company,
    String? manager,
    String? fundCode,
    int limit = 100,
  }) {
    return _store?.queryFundManager(
          company: company,
          manager: manager,
          fundCode: fundCode,
          limit: limit,
        ) ??
        const [];
  }

  List<Map<String, dynamic>> queryStockList({
    String? market,
    String? industry,
    String? stockType,
    int limit = 50,
  }) {
    return _store?.queryStockList(
          market: market,
          industry: industry,
          stockType: stockType,
          limit: limit,
        ) ??
        const [];
  }

  Map<String, dynamic>? queryStockIdentity(String code) {
    return _store?.queryStockIdentity(code);
  }

  List<Map<String, dynamic>> queryTradeCalendar({
    String? market,
    String? start,
    String? end,
    int limit = 100,
  }) {
    return _store?.queryTradeCalendar(
          market: market,
          start: start,
          end: end,
          limit: limit,
        ) ??
        const [];
  }
}
