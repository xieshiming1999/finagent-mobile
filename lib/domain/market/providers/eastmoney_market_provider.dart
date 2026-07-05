import '../../../agent/data_fetcher/models.dart';

abstract class EastmoneyMarketProvider {
  Future<({List<MoneyFlow> data, String source})> readMoneyFlow(String symbol);
  Future<({List<StockQuote> data, String source})> readEtfQuotes({
    String? source,
  });
  Future<({List<StockQuote> data, String source})> readListedFundQuotes({
    String? source,
  });
  Future<({List<Map<String, dynamic>> data, String source})> readStockList({
    String? source,
  });
  Future<({List<Map<String, dynamic>> data, String source})> readFundList();
  Future<({List<Map<String, dynamic>> data, String source})> readFundNav(
    String fundCode,
  );
  Future<({List<Map<String, dynamic>> data, String source})> readFundMoneyYield(
    String fundCode,
  );
  Future<({List<Map<String, dynamic>> data, String source})> readFundHolding(
    String fundCode,
  );
  Future<({List<Map<String, dynamic>> data, String source})> readFundManagers();
  Future<({List<Map<String, dynamic>> data, String source})>
  readFundPerformance();
  Future<({List<Map<String, dynamic>> data, String source})>
  readStockShareholders(String code, {String? reportDate});
  Future<({Map<String, dynamic> data, String source})> readStockCompanyInfo(
    String code,
  );
  Future<List<StockQuote>> readSectorStocks(
    String sectorCode, {
    String? sectorName,
    String? source,
  });
  Future<List<Map<String, dynamic>>> readSectorRanking({
    required String boardType,
  });
  Future<Map<String, dynamic>> readChipDistribution(String symbol);
}
