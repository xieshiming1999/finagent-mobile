import '../repositories/tdx_market_data_repository.dart';

class TdxMarketDataPersistenceService {
  final TdxMarketDataRepository _repository;

  TdxMarketDataPersistenceService(this._repository);

  void saveTickChart(
    String symbol,
    List<Map<String, dynamic>> rows, {
    String? tradeDate,
  }) => _repository.saveTickChart(symbol, rows, tradeDate: tradeDate);

  void saveTransactions(
    String symbol,
    List<Map<String, dynamic>> rows, {
    String? tradeDate,
  }) => _repository.saveTransactions(symbol, rows, tradeDate: tradeDate);

  void saveFinance(String symbol, Map<String, dynamic> payload) =>
      _repository.saveFinance(symbol, payload);

  void saveXdxr(String symbol, List<Map<String, dynamic>> rows) =>
      _repository.saveXdxr(symbol, rows);

  void saveUnusualActivity(List<Map<String, dynamic>> rows) =>
      _repository.saveUnusualActivity(rows);

  void saveIndexInfo(String symbol, Map<String, dynamic> payload) =>
      _repository.saveIndexInfo(symbol, payload);

  void saveStockList(List<Map<String, dynamic>> rows, int market) =>
      _repository.saveStockList(rows, market);

  void saveSecurityCount(int market, int count) =>
      _repository.saveSecurityCount(market, count);

  void saveSampling(String symbol, Map<String, dynamic> payload) =>
      _repository.saveSampling(symbol, payload);

  void saveVolumeProfile(String symbol, Map<String, dynamic> payload) =>
      _repository.saveVolumeProfile(symbol, payload);

  void saveAuction(
    String symbol,
    List<Map<String, dynamic>> rows, {
    String? tradeDate,
  }) => _repository.saveAuction(symbol, rows, tradeDate: tradeDate);

  void saveMomentum(
    String symbol,
    Map<String, dynamic> payload, {
    String? tradeDate,
  }) => _repository.saveMomentum(symbol, payload, tradeDate: tradeDate);

  void saveTopBoard(Map<String, dynamic> payload, {required int category}) =>
      _repository.saveTopBoard(payload, category: category);

  void saveQuotesList(List<Map<String, dynamic>> rows) =>
      _repository.saveQuotesList(rows);

  void saveIndexBars(String symbol, List<Map<String, dynamic>> rows) =>
      _repository.saveIndexBars(symbol, rows);

  void saveCompanyInfo(String symbol, Map<String, dynamic> result) =>
      _repository.saveCompanyInfo(symbol, result);

  void saveCompanyCategoryPreview(
    String symbol,
    String title,
    Map<String, dynamic> entry,
  ) => _repository.saveCompanyCategoryPreview(symbol, title, entry);

  void saveCompanyContent(
    String symbol,
    String title,
    Map<String, dynamic> entry,
    String content,
  ) => _repository.saveCompanyContent(symbol, title, entry, content);

  void saveBlockMembers(List<Map<String, dynamic>> rows) =>
      _repository.saveBlockMembers(rows);
}
