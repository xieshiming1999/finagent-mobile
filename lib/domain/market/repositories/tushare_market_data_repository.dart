import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../../../agent/tool_context.dart';

class TushareMarketDataRepository {
  ReusableDataStore? _store;
  String? _storeBasePath;
  final DataManager _dataManager;

  TushareMarketDataRepository(this._dataManager);

  ReusableDataStore? _storeForContext(ToolContext context) {
    final basePath = context.basePath;
    if (basePath.isEmpty) return null;
    if (_store == null || _storeBasePath != basePath) {
      _storeBasePath = basePath;
      _store = ReusableDataStore(basePath)..cleanup();
    }
    return _store;
  }

  Map<String, dynamic>? saveRows(
    String apiName,
    List<Map<String, dynamic>> rows, {
    Map<String, dynamic>? params,
  }) {
    return _dataManager.saveTushareRows(
      apiName,
      rows,
      params: params ?? const {},
    );
  }

  List<Map<String, dynamic>> queryFundamental(
    ToolContext context,
    String symbol, {
    String? source,
    int limit = 8,
  }) {
    return _storeForContext(
          context,
        )?.queryFundamental(symbol, source: source, limit: limit) ??
        _dataManager.queryFundamental(symbol, source: source, limit: limit);
  }

  List<Map<String, dynamic>> queryFundamentalSample(
    ToolContext context, {
    String? source,
    int limit = 50,
    double? peLte,
    double? peGte,
    double? roeGte,
    bool latestOnly = true,
  }) {
    return _storeForContext(context)?.queryFundamentalSample(
          source: source,
          limit: limit,
          peLte: peLte,
          peGte: peGte,
          roeGte: roeGte,
          latestOnly: latestOnly,
        ) ??
        _dataManager.queryFundamentalSample(
          source: source,
          limit: limit,
          peLte: peLte,
          peGte: peGte,
          roeGte: roeGte,
          latestOnly: latestOnly,
        );
  }

  List<Map<String, dynamic>> queryMoneyFlow(
    ToolContext context,
    String symbol, {
    String? source,
    int limit = 30,
  }) {
    return _storeForContext(
          context,
        )?.queryMoneyFlow(symbol, source: source, limit: limit) ??
        _dataManager.queryMoneyFlowRows(symbol, source: source, limit: limit);
  }

  List<Map<String, dynamic>> queryFundNav(
    ToolContext context,
    String symbol, {
    String startDate = '',
    String endDate = '',
    String? source,
    int? limit,
  }) {
    return _storeForContext(context)?.queryFundNav(
          symbol,
          startDate: startDate,
          endDate: endDate,
          source: source,
          limit: limit,
        ) ??
        _dataManager.queryFundNav(
          symbol,
          startDate: startDate,
          endDate: endDate,
          source: source,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryFundMoneyYield(
    ToolContext context,
    String symbol, {
    String startDate = '',
    String endDate = '',
    String? source,
    int? limit,
  }) {
    return _storeForContext(context)?.queryFundMoneyYield(
          symbol,
          startDate: startDate,
          endDate: endDate,
          source: source,
          limit: limit,
        ) ??
        _dataManager.queryFundMoneyYield(
          symbol,
          startDate: startDate,
          endDate: endDate,
          source: source,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryFundDividendFactor(
    ToolContext context,
    String symbol, {
    String startDate = '',
    String endDate = '',
    String? source,
    int? limit,
  }) {
    return _storeForContext(context)?.queryFundDividendFactor(
          symbol,
          startDate: startDate,
          endDate: endDate,
          source: source,
          limit: limit,
        ) ??
        _dataManager.queryFundDividendFactor(
          symbol,
          startDate: startDate,
          endDate: endDate,
          source: source,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryIntradayOhlcvBars(
    ToolContext context,
    String symbol, {
    String startDate = '',
    String endDate = '',
    int intervalMinutes = 5,
    String? source,
    int? limit,
  }) {
    return _storeForContext(context)?.queryIntradayOhlcvBars(
          symbol,
          startDate: startDate,
          endDate: endDate,
          intervalMinutes: intervalMinutes,
          source: source,
          limit: limit,
        ) ??
        _dataManager.queryIntradayOhlcvBars(
          symbol,
          startDate: startDate,
          endDate: endDate,
          intervalMinutes: intervalMinutes,
          source: source,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryFundList(
    ToolContext context, {
    String? fundType,
    String? company,
    List<String> codes = const [],
    int limit = 50,
  }) {
    return _storeForContext(context)?.queryFundList(
          fundType: fundType,
          company: company,
          codes: codes,
          limit: limit,
        ) ??
        _dataManager.queryFundList(
          fundType: fundType,
          company: company,
          codes: codes,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryStockList(
    ToolContext context, {
    String? market,
    String? industry,
    String? stockType,
    String? keyword,
    int limit = 50,
  }) {
    return _storeForContext(context)?.queryStockList(
          market: market,
          industry: industry,
          stockType: stockType,
          keyword: keyword,
          limit: limit,
        ) ??
        _dataManager.queryStockList(
          market: market,
          industry: industry,
          stockType: stockType,
          keyword: keyword,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryTradeCalendar(
    ToolContext context, {
    String? market,
    String? start,
    String? end,
    int limit = 100,
    bool descending = false,
  }) {
    return _storeForContext(context)?.queryTradeCalendar(
          market: market,
          start: start,
          end: end,
          limit: limit,
          descending: descending,
        ) ??
        _dataManager.queryTradeCalendar(
          market: market,
          start: start,
          end: end,
          limit: limit,
          descending: descending,
        );
  }

  Map<String, dynamic>? queryTradeCalendarCoverage(
    ToolContext context, {
    String? market,
  }) {
    return _storeForContext(
          context,
        )?.queryTradeCalendarCoverage(market: market) ??
        _dataManager.queryTradeCalendarCoverage(market: market);
  }
}
