import '../../../agent/data_fetcher/models.dart';
import '../repositories/extdx_market_data_repository.dart';

class ExTdxMarketDataPersistenceService {
  final ExTdxMarketDataRepository _repository;

  ExTdxMarketDataPersistenceService(this._repository);

  void saveCategories(List<ExCategoryItem> data) =>
      _repository.saveCategories(data);

  void saveCount(int count) => _repository.saveCount(count);

  void saveTableEntries(List<Map<String, dynamic>> rows) =>
      _repository.saveTableEntries(rows);

  void saveSampling(int category, String code, Map<String, dynamic> payload) =>
      _repository.saveSampling(category, code, payload);

  void saveKline(int category, String code, List<ExKlineBar> rows) =>
      _repository.saveKline(category, code, rows);

  void saveQuote(ExQuoteData data) => _repository.saveQuote(data);

  void saveList(List<ExListItem> data) => _repository.saveList(data);
}
