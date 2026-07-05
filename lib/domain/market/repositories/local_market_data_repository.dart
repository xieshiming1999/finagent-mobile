import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/models.dart';
import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../../../agent/tool_context.dart';

class LocalMarketDataRepository {
  ReusableDataStore? _store;
  String? _storeBasePath;
  final DataManager _dataManager;

  LocalMarketDataRepository(this._dataManager);

  ReusableDataStore? _storeForContext(ToolContext context) {
    final basePath = context.basePath;
    if (basePath.isEmpty) return null;
    if (_store == null || _storeBasePath != basePath) {
      _storeBasePath = basePath;
      _store = ReusableDataStore(basePath)..cleanup();
    }
    return _store;
  }

  List<StockQuote> queryQuotes(
    ToolContext context,
    String code, {
    int limit = 20,
    String? source,
  }) {
    return _storeForContext(
          context,
        )?.queryQuotes(code, limit: limit, source: source) ??
        _dataManager.queryQuotes(code, limit: limit, source: source);
  }

  ({List<StockQuote> data, List<String> missing}) readRecentQuotes(
    List<String> codes, {
    ToolContext? context,
    Duration maxAge = const Duration(seconds: 15),
    String? source,
  }) {
    final data = <StockQuote>[];
    final missing = <String>[];
    final contextStore = context == null ? null : _storeForContext(context);
    for (final code in codes) {
      final quote =
          contextStore?.getRecentQuote(code, maxAge, source: source) ??
          _dataManager.getRecentQuote(code, maxAge, source: source);
      if (quote == null) {
        missing.add(code);
      } else {
        data.add(quote);
      }
    }
    return (data: data, missing: missing);
  }

  List<KlineBar> readPersistedKline(
    String code, {
    ToolContext? context,
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
    String? source,
    int? limit,
  }) {
    final contextRows = context == null
        ? const <KlineBar>[]
        : _storeForContext(context)?.queryKline(
                code,
                startDate: startDate,
                endDate: endDate,
                adjust: adjust,
                source: source,
                limit: limit,
              ) ??
              const <KlineBar>[];
    if (contextRows.isNotEmpty) return contextRows;
    return _dataManager.queryKline(
      code,
      startDate: startDate,
      endDate: endDate,
      adjust: adjust,
      source: source,
      limit: limit,
    );
  }

  void saveQuotes(
    List<StockQuote> quotes, {
    ToolContext? context,
    required String source,
  }) {
    if (context != null) {
      _storeForContext(context)?.saveQuoteSnapshots(quotes, source);
      return;
    }
    _dataManager.saveQuoteSnapshots(quotes, source: source);
  }

  void saveKline(
    String code,
    List<KlineBar> bars, {
    ToolContext? context,
    required String source,
    String adjust = 'qfq',
  }) {
    if (context != null) {
      _storeForContext(
        context,
      )?.saveKline(code, bars, source: source, adjust: adjust);
      return;
    }
    _dataManager.saveKlineRows(code, bars, source: source, adjust: adjust);
  }

  List<KlineBar> queryKline(
    ToolContext context,
    String code, {
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
    String? source,
    int? limit,
  }) {
    return _storeForContext(context)?.queryKline(
          code,
          startDate: startDate,
          endDate: endDate,
          adjust: adjust,
          source: source,
          limit: limit,
        ) ??
        _dataManager.queryKline(
          code,
          startDate: startDate,
          endDate: endDate,
          adjust: adjust,
          source: source,
          limit: limit,
        );
  }
}
