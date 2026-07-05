import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/tushare_fetcher.dart';

abstract class TushareMarketProvider {
  Future<Map<String, dynamic>> callRaw(
    String apiName,
    Map<String, dynamic> params, {
    String fields = '',
  });
}

class FetcherTushareMarketProvider implements TushareMarketProvider {
  final TushareFetcher _fetcher;

  FetcherTushareMarketProvider(DataManager dataManager)
    : _fetcher = _requireFetcher(dataManager);

  static TushareFetcher _requireFetcher(DataManager dataManager) {
    final fetcher = dataManager.getFetcher<TushareFetcher>();
    if (fetcher == null) {
      throw StateError(
        'Tushare not available. Please set TUSHARE_TOKEN in Settings -> Data Sources.',
      );
    }
    return fetcher;
  }

  @override
  Future<Map<String, dynamic>> callRaw(
    String apiName,
    Map<String, dynamic> params, {
    String fields = '',
  }) {
    return _fetcher.callRaw(apiName, params, fields: fields);
  }
}
