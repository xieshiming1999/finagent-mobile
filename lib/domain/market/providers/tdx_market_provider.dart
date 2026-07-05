import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/tdx_fetcher.dart';

abstract class TdxMarketProvider {
  Future<List<Map<String, dynamic>>> readTickChart(String symbol);
  Future<List<Map<String, dynamic>>> readTransactions(
    String symbol, {
    required int count,
  });
  Future<Map<String, dynamic>> readFinance(String symbol);
  Future<List<Map<String, dynamic>>> readXdxr(String symbol);
  Future<List<Map<String, dynamic>>> readUnusual({
    required int market,
    required int count,
  });
  Future<Map<String, dynamic>> readIndexInfo(String symbol);
  Future<List<Map<String, dynamic>>> readStockList({
    required int market,
    required int count,
  });
  Future<int> readCount({required int market});
  Future<Map<String, dynamic>> readSampling(String symbol);
  Future<Map<String, dynamic>> readVolumeProfile(String symbol);
  Future<List<Map<String, dynamic>>> readAuction(String symbol);
  Future<List<Map<String, dynamic>>> readHistoryTick(String symbol, int date);
  Future<Map<String, dynamic>> readMomentum(String symbol);
  Future<List<Map<String, dynamic>>> readHistoryTransactions(
    String symbol,
    int date,
  );
  Future<Map<String, dynamic>> readTopBoard({
    required int category,
    required int size,
  });
  Future<List<Map<String, dynamic>>> readQuotesList({
    required int count,
    required int sortType,
  });
  Future<List<Map<String, dynamic>>> readIndexBars(
    String symbol, {
    required int count,
  });
  Future<List<Map<String, dynamic>>> readCompanyCategories(String symbol);
  Future<String> readCompanyContent(String symbol, String filename);
  Future<List<Map<String, dynamic>>> readBlockMembers({
    required String filename,
    String? blockName,
  });
}

class FetcherTdxMarketProvider implements TdxMarketProvider {
  final TdxFetcher _fetcher;

  FetcherTdxMarketProvider(DataManager dataManager)
    : _fetcher = _requireFetcher(dataManager);

  static TdxFetcher _requireFetcher(DataManager dataManager) {
    final tdx = dataManager.getFetcher<TdxFetcher>();
    if (tdx == null) throw StateError('TDX not available');
    return tdx;
  }

  @override
  Future<List<Map<String, dynamic>>> readTickChart(String symbol) {
    return _fetcher.getTickChart(symbol);
  }

  @override
  Future<List<Map<String, dynamic>>> readTransactions(
    String symbol, {
    required int count,
  }) {
    return _fetcher.getTransactions(symbol, count: count);
  }

  @override
  Future<Map<String, dynamic>> readFinance(String symbol) {
    return _fetcher.getFinanceInfo(symbol);
  }

  @override
  Future<List<Map<String, dynamic>>> readXdxr(String symbol) {
    return _fetcher.getXDXRInfo(symbol);
  }

  @override
  Future<List<Map<String, dynamic>>> readUnusual({
    required int market,
    required int count,
  }) {
    return _fetcher.getUnusualActivity(market: market, count: count);
  }

  @override
  Future<Map<String, dynamic>> readIndexInfo(String symbol) {
    return _fetcher.getIndexInfo(symbol);
  }

  @override
  Future<List<Map<String, dynamic>>> readStockList({
    required int market,
    required int count,
  }) {
    return _fetcher.getStockList(market: market, count: count);
  }

  @override
  Future<int> readCount({required int market}) {
    return _fetcher.getStockCount(market: market);
  }

  @override
  Future<Map<String, dynamic>> readSampling(String symbol) {
    return _fetcher.getChartSampling(symbol);
  }

  @override
  Future<Map<String, dynamic>> readVolumeProfile(String symbol) {
    return _fetcher.getVolumeProfile(symbol);
  }

  @override
  Future<List<Map<String, dynamic>>> readAuction(String symbol) {
    return _fetcher.getAuction(symbol);
  }

  @override
  Future<List<Map<String, dynamic>>> readHistoryTick(String symbol, int date) {
    return _fetcher.getHistoryTickChart(symbol, date);
  }

  @override
  Future<Map<String, dynamic>> readMomentum(String symbol) {
    return _fetcher.getIndexMomentum(symbol);
  }

  @override
  Future<List<Map<String, dynamic>>> readHistoryTransactions(
    String symbol,
    int date,
  ) {
    return _fetcher.getHistoryTransactions(symbol, date);
  }

  @override
  Future<Map<String, dynamic>> readTopBoard({
    required int category,
    required int size,
  }) {
    return _fetcher.getTopBoard(category: category, size: size);
  }

  @override
  Future<List<Map<String, dynamic>>> readQuotesList({
    required int count,
    required int sortType,
  }) {
    return _fetcher.getQuotesList(count: count, sortType: sortType);
  }

  @override
  Future<List<Map<String, dynamic>>> readIndexBars(
    String symbol, {
    required int count,
  }) {
    return _fetcher.getIndexBars(symbol, count: count);
  }

  @override
  Future<List<Map<String, dynamic>>> readCompanyCategories(String symbol) {
    return _fetcher.getCompanyCategories(symbol);
  }

  @override
  Future<String> readCompanyContent(String symbol, String filename) {
    return _fetcher.getCompanyContent(symbol, filename);
  }

  @override
  Future<List<Map<String, dynamic>>> readBlockMembers({
    required String filename,
    String? blockName,
  }) {
    return _fetcher.getBlockMembers(filename: filename, blockName: blockName);
  }
}
