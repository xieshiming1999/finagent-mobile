import '../repositories/tushare_market_data_repository.dart';

class TushareMarketDataPersistenceService {
  final TushareMarketDataRepository _repository;

  TushareMarketDataPersistenceService(this._repository);

  Map<String, dynamic>? persistRows(
    String apiName,
    List<Map<String, dynamic>> rows, {
    required Map<String, dynamic> params,
  }) {
    return _repository.saveRows(apiName, rows, params: params);
  }
}
