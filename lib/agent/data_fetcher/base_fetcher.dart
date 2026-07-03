import 'models.dart';

/// Abstract interface for all data fetchers.
/// Each fetcher wraps a single data source (EastMoney, Sina, Tencent, Yahoo, etc.)
abstract class BaseFetcher {
  String get name;
  int get priority;

  Future<List<StockQuote>> getQuotes(List<String> codes);
  Future<List<KlineBar>> getKline(
    String code, {
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
  });
  Future<List<MoneyFlow>> getMoneyFlow(String code);

  /// Market detection: which codes does this fetcher handle?
  bool canHandle(String code);
}
