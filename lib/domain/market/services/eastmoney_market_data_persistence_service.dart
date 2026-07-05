import '../../../agent/data_fetcher/models.dart';
import '../repositories/eastmoney_market_data_repository.dart';

class EastmoneyMarketDataPersistenceService {
  final EastmoneyMarketDataRepository _repository;

  EastmoneyMarketDataPersistenceService(this._repository);

  void persistMoneyFlow(
    String symbol,
    List<MoneyFlow> rows, {
    required String source,
  }) {
    _repository.saveMoneyFlow(symbol, rows, source: source);
  }

  void persistEtfQuotes(List<StockQuote> quotes, {required String source}) {
    _repository.saveEtfQuotes(quotes, source: source);
  }

  void persistListedFundQuotes(
    List<StockQuote> quotes, {
    required String source,
  }) {
    _repository.saveListedFundQuotes(quotes, source: source);
  }

  void persistStockListRows(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _repository.saveStockListRows(rows, source: source);
  }

  void persistSectorRanking(
    String boardType,
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _repository.saveSectorRanking(boardType, rows, source: source);
  }

  void persistSectorStocks(
    List<StockQuote> quotes, {
    required String source,
    required String sectorCode,
    String? sectorName,
  }) {
    _repository.saveSectorStocks(
      quotes,
      source: source,
      sectorCode: sectorCode,
      sectorName: sectorName,
    );
  }

  void persistChipDistribution(
    String symbol,
    Map<String, dynamic> payload, {
    required String source,
  }) {
    _repository.saveChipDistribution(symbol, payload, source: source);
  }

  void persistFundManagers(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _repository.saveFundManagers(rows, source: source);
  }

  void persistFundList(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _repository.saveFundList(rows, source: source);
  }

  void persistFundNav(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _repository.saveFundNav(rows, source: source);
  }

  void persistFundMoneyYield(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _repository.saveFundMoneyYield(rows, source: source);
  }

  void persistFundHolding(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _repository.saveFundHolding(rows, source: source);
  }

  void persistFundPerformance(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _repository.saveFundPerformance(rows, source: source);
  }

  void persistStockShareholders(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _repository.saveStockShareholders(rows, source: source);
  }

  void persistStockCompanyInfo(
    String code,
    Map<String, dynamic> row, {
    required String source,
  }) {
    _repository.saveStockCompanyInfo(code, row, source: source);
  }
}
