import '../repositories/eastmoney_advanced_repository.dart';

class EastmoneyAdvancedPersistenceService {
  final EastmoneyAdvancedRepository _repository;

  EastmoneyAdvancedPersistenceService(this._repository);

  void persistLimitPool(
    String poolType,
    List<Map<String, dynamic>> rows, {
    String? tradeDate,
  }) {
    _repository.saveLimitPool(poolType, rows, tradeDate: tradeDate);
  }

  void persistHotRank(List<Map<String, dynamic>> rows, {String? tradeDate}) {
    _repository.saveHotRank(rows, tradeDate: tradeDate);
  }

  void persistDragonTiger(
    List<Map<String, dynamic>> rows, {
    String? tradeDate,
  }) {
    _repository.saveDragonTiger(rows, tradeDate: tradeDate);
  }

  void persistNorthboundHolding(
    List<Map<String, dynamic>> rows, {
    required String code,
  }) {
    _repository.saveNorthboundHolding(rows, code: code);
  }

  void persistNorthboundFlow(List<Map<String, dynamic>> rows) {
    _repository.saveNorthboundFlow(rows);
  }

  void persistUnusualActivity(
    List<Map<String, dynamic>> rows, {
    String? eventDate,
  }) {
    _repository.saveUnusualActivity(rows, eventDate: eventDate);
  }

  void persistFlowRank(
    String period,
    List<Map<String, dynamic>> rows, {
    String? tradeDate,
  }) {
    _repository.saveFlowRank(period, rows, tradeDate: tradeDate);
  }

  void persistStockListRows(List<Map<String, dynamic>> rows) {
    _repository.saveStockListRows(rows);
  }
}
