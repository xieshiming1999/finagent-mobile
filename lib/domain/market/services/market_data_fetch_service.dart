import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/models.dart';
import '../providers/market_data_provider.dart';

class MarketDataFetchService {
  final MarketDataProvider _provider;

  MarketDataFetchService({
    DataManager? dataManager,
    MarketDataProvider? provider,
  }) : _provider =
           provider ?? (dataManager ?? DataManager()).marketDataProvider;

  List<String> get sourceNames => _provider.sourceNames;

  Future<({List<StockQuote> data, String source})> fetchQuotes(
    List<String> symbols, {
    String? source,
  }) {
    return _provider.readQuotes(symbols, source: source);
  }

  Future<({List<KlineBar> bars, String source})> fetchKline(
    String symbol, {
    String? source,
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
  }) {
    return _provider.readKline(
      symbol,
      source: source,
      period: period,
      startDate: startDate,
      endDate: endDate,
      adjust: adjust,
    );
  }
}
