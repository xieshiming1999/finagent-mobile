import '../../../agent/data_fetcher/data_manager.dart';
import 'tushare_market_data_service.dart';

class MarketDataTushareActionService {
  final DataManager? _dataManager;
  TushareMarketDataService? _tushare;

  MarketDataTushareActionService({
    DataManager? dataManager,
    TushareMarketDataService? tushare,
  }) : _dataManager = dataManager,
       _tushare = tushare;

  Future<Map<String, dynamic>> run(
    String action,
    Map<String, dynamic> input,
  ) {
    switch (action) {
      case 'tushare':
        return _requireTushare().fetchRaw(input);
      default:
        throw ArgumentError('Unsupported MarketData Tushare action: $action');
    }
  }

  TushareMarketDataService _requireTushare() {
    return _tushare ??= TushareMarketDataService(dataManager: _dataManager);
  }
}
