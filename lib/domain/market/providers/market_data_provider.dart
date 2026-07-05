import '../../../agent/data_fetcher/models.dart';

abstract class MarketDataProvider {
  List<String> get sourceNames;

  Future<({List<StockQuote> data, String source})> readQuotes(
    List<String> symbols, {
    String? source,
  });

  Future<({List<KlineBar> bars, String source})> readKline(
    String symbol, {
    String? source,
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
  });

  Future<({List<MoneyFlow> data, String source})> readMoneyFlow(
    String symbol, {
    String? source,
  });

  Future<({List<Map<String, dynamic>> data, String source})> readSectorRanking({
    String boardType = 'industry',
    String? source,
  });
}
