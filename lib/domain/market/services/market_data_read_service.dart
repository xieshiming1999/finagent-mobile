import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/models.dart';
import '../../../agent/tool_context.dart';
import '../repositories/local_market_data_repository.dart';

class MarketDataReadService {
  final LocalMarketDataRepository _repository;

  MarketDataReadService({DataManager? dataManager})
    : this._internal(dataManager ?? DataManager());

  MarketDataReadService._internal(DataManager dataManager)
    : _repository = LocalMarketDataRepository(dataManager);

  ({List<StockQuote> data, List<String> missing}) readRecentQuotes(
    List<String> symbols, {
    ToolContext? context,
    Duration maxAge = const Duration(seconds: 15),
    String? source,
  }) {
    return _repository.readRecentQuotes(
      symbols,
      context: context,
      maxAge: maxAge,
      source: source,
    );
  }

  List<KlineBar> readPersistedKline(
    String symbol, {
    ToolContext? context,
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
    String? source,
    int? limit,
  }) {
    return _repository.readPersistedKline(
      symbol,
      context: context,
      startDate: startDate,
      endDate: endDate,
      adjust: adjust,
      source: source,
      limit: limit,
    );
  }

  List<StockQuote> queryPersistedQuotes(
    ToolContext context,
    String symbol, {
    int limit = 20,
    String? source,
  }) {
    return _repository.queryQuotes(
      context,
      symbol,
      limit: limit,
      source: source,
    );
  }

  List<KlineBar> queryPersistedKline(
    ToolContext context,
    String symbol, {
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
    String? source,
    int? limit,
  }) {
    return _repository.queryKline(
      context,
      symbol,
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
    _repository.saveQuotes(quotes, context: context, source: source);
  }

  void saveKline(
    String symbol,
    List<KlineBar> bars, {
    ToolContext? context,
    required String source,
    String adjust = 'qfq',
  }) {
    _repository.saveKline(
      symbol,
      bars,
      context: context,
      source: source,
      adjust: adjust,
    );
  }
}
