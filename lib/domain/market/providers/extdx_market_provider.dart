import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/ex_tdx_fetcher.dart';
import '../../../agent/data_fetcher/models.dart';

abstract class ExTdxMarketProvider {
  Future<List<ExCategoryItem>> readCategories();
  Future<int> readCount();
  Future<String> readTable({required bool detail});
  Future<Map<String, dynamic>> readSampling({
    required int category,
    required String code,
  });
  Future<List<ExKlineBar>> readKline({
    required int category,
    required String code,
    required int period,
    required int count,
  });
  Future<ExQuoteData> readQuote({
    required int category,
    required String code,
  });
  Future<List<ExListItem>> readList({
    required int start,
    required int count,
  });
}

class FetcherExTdxMarketProvider implements ExTdxMarketProvider {
  final ExTdxFetcher _fetcher;

  FetcherExTdxMarketProvider(DataManager dataManager)
    : _fetcher = _requireFetcher(dataManager);

  static ExTdxFetcher _requireFetcher(DataManager dataManager) {
    final ex = dataManager.getFetcher<ExTdxFetcher>();
    if (ex == null) throw StateError('ExTDX not available');
    return ex;
  }

  @override
  Future<List<ExCategoryItem>> readCategories() {
    return _fetcher.getExCategories();
  }

  @override
  Future<int> readCount() {
    return _fetcher.getExCount();
  }

  @override
  Future<String> readTable({required bool detail}) {
    return _fetcher.getExTable(detail: detail);
  }

  @override
  Future<Map<String, dynamic>> readSampling({
    required int category,
    required String code,
  }) {
    return _fetcher.getExChartSampling(category, code);
  }

  @override
  Future<List<ExKlineBar>> readKline({
    required int category,
    required String code,
    required int period,
    required int count,
  }) {
    return _fetcher.getExKline(category, code, period: period, count: count);
  }

  @override
  Future<ExQuoteData> readQuote({
    required int category,
    required String code,
  }) {
    return _fetcher.getExQuote(category, code);
  }

  @override
  Future<List<ExListItem>> readList({
    required int start,
    required int count,
  }) {
    return _fetcher.getExList(start: start, count: count);
  }
}
