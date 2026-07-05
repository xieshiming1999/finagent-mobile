import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/models.dart';
import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../../../agent/tool_context.dart';

class YahooMarketDataRepository {
  ReusableDataStore? _store;
  String? _storeBasePath;
  final DataManager _dataManager;

  YahooMarketDataRepository(this._dataManager);

  ReusableDataStore? _storeForContext(ToolContext? context) {
    final basePath = context?.basePath ?? '';
    if (basePath.isEmpty) return null;
    if (_store == null || _storeBasePath != basePath) {
      _storeBasePath = basePath;
      _store = ReusableDataStore(basePath)..cleanup();
    }
    return _store;
  }

  void saveQuoteSnapshots(
    ToolContext context,
    List<StockQuote> quotes, {
    String source = 'yahoo',
  }) {
    _storeForContext(context)?.saveQuoteSnapshots(quotes, source);
  }

  void saveKline(
    ToolContext? context,
    String symbol,
    List<KlineBar> bars, {
    String source = 'yahoo',
    String adjust = 'none',
  }) {
    _storeForContext(context)?.saveKline(
      symbol,
      bars,
      source: source,
      adjust: adjust,
    );
  }

  void saveProfileFields(ToolContext context, List<Map<String, dynamic>> rows) {
    _storeForContext(context)?.saveYfinanceProfileFields(rows);
  }

  void saveStatementItems(
    ToolContext context,
    List<Map<String, dynamic>> rows,
  ) {
    _storeForContext(context)?.saveYfinanceStatementItems(rows);
  }

  void saveRecommendations(
    ToolContext context,
    List<Map<String, dynamic>> rows,
  ) {
    _storeForContext(context)?.saveYfinanceRecommendations(rows);
  }

  void saveNews(ToolContext context, List<Map<String, dynamic>> rows) {
    _storeForContext(context)?.saveYfinanceNews(rows);
  }

  void saveOptionExpiries(
    ToolContext context,
    List<Map<String, dynamic>> rows,
  ) {
    _storeForContext(context)?.saveYfinanceOptionExpiries(rows);
  }

  void saveOptionContracts(
    ToolContext context,
    List<Map<String, dynamic>> rows,
  ) {
    _storeForContext(context)?.saveYfinanceOptionContracts(rows);
  }

  void saveCorporateActions(
    ToolContext context,
    List<Map<String, dynamic>> rows,
  ) {
    _storeForContext(context)?.saveYfinanceCorporateActions(rows);
  }

  void saveHolders(ToolContext context, List<Map<String, dynamic>> rows) {
    _storeForContext(context)?.saveYfinanceHolders(rows);
  }

  void saveInsiderTransactions(
    ToolContext context,
    List<Map<String, dynamic>> rows,
  ) {
    _storeForContext(context)?.saveYfinanceInsiderTransactions(rows);
  }

  List<Map<String, dynamic>> queryProfile(
    ToolContext context,
    String symbol, {
    int limit = 100,
  }) {
    return _storeForContext(context)?.queryYfinanceProfile(symbol, limit: limit) ??
        _dataManager.queryYfinanceProfile(symbol, limit: limit);
  }

  List<Map<String, dynamic>> queryStatements(
    ToolContext context,
    String symbol, {
    String? statementType,
    int limit = 200,
  }) {
    return _storeForContext(context)?.queryYfinanceStatements(
          symbol,
          statementType: statementType,
          limit: limit,
        ) ??
        _dataManager.queryYfinanceStatements(
          symbol,
          statementType: statementType,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryDataset(
    ToolContext context,
    String dataset,
    String symbol, {
    int limit = 200,
  }) {
    return _storeForContext(context)?.queryYfinanceDataset(
          dataset,
          symbol,
          limit: limit,
        ) ??
        _dataManager.queryYfinanceDataset(dataset, symbol, limit: limit);
  }
}
