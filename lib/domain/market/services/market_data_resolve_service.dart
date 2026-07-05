import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/models.dart';
import '../../../agent/tool_context.dart';
import 'cache_policy.dart';
import 'market_data_fetch_service.dart';
import 'market_data_read_service.dart';

class MarketDataResolveService {
  final MarketDataReadService _readService;
  final MarketDataFetchService _fetchService;
  final DataManager _dataManager;

  MarketDataResolveService({
    DataManager? dataManager,
    MarketDataReadService? readService,
    MarketDataFetchService? fetchService,
  }) : this._internal(dataManager ?? DataManager(), readService, fetchService);

  MarketDataResolveService._internal(
    DataManager dataManager,
    MarketDataReadService? readService,
    MarketDataFetchService? fetchService,
  ) : _dataManager = dataManager,
      _readService =
          readService ?? MarketDataReadService(dataManager: dataManager),
      _fetchService =
          fetchService ?? MarketDataFetchService(dataManager: dataManager);

  List<String> get sourceNames => _fetchService.sourceNames;

  Future<({List<StockQuote> data, String source})> resolveQuotes(
    List<String> symbols, {
    ToolContext? context,
    String? source,
    CachePolicy policy = const CachePolicy(),
  }) async {
    if (policy.shouldReadCache) {
      final cached = _readService.readRecentQuotes(
        symbols,
        context: context,
        maxAge: policy.quoteMaxAge,
        source: source,
      );
      if (cached.missing.isEmpty && cached.data.isNotEmpty) {
        return (data: cached.data, source: 'local quote_snapshot');
      }
      if (policy.mode == CachePolicyMode.cacheOnly) {
        return (data: cached.data, source: 'local quote_snapshot');
      }
      if (cached.data.isNotEmpty) {
        final fresh = await _fetchService.fetchQuotes(cached.missing);
        _saveQuotes(fresh.data, source: fresh.source, context: context);
        return (
          data: [...cached.data, ...fresh.data],
          source: 'local quote_snapshot, ${fresh.source}',
        );
      }
    }

    if (!policy.shouldFetchAfterMiss) {
      return (data: const <StockQuote>[], source: 'local quote_snapshot');
    }

    final result = await _fetchService.fetchQuotes(symbols, source: source);
    _saveQuotes(result.data, source: result.source, context: context);
    return result;
  }

  Future<({List<KlineBar> bars, String source})> resolveKline(
    String symbol, {
    ToolContext? context,
    String? source,
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
    CachePolicy policy = const CachePolicy(),
  }) async {
    if (policy.shouldReadCache && period == 'daily') {
      final local = _readService.readPersistedKline(
        symbol,
        context: context,
        startDate: startDate,
        endDate: endDate,
        adjust: adjust,
        source: source,
        limit: startDate.isEmpty && endDate.isEmpty ? 120 : null,
      );
      if (local.length >= policy.klineMinRows &&
          _localKlineCovers(local, startDate: startDate, endDate: endDate)) {
        return (bars: local, source: 'local kline_daily');
      }
      if (policy.mode == CachePolicyMode.cacheOnly) {
        return (bars: local, source: 'local kline_daily');
      }
    }

    if (!policy.shouldFetchAfterMiss) {
      return (bars: const <KlineBar>[], source: 'local kline_daily');
    }

    final result = await _fetchService.fetchKline(
      symbol,
      source: source,
      period: period,
      startDate: startDate,
      endDate: endDate,
      adjust: adjust,
    );
    if (period == 'daily') {
      _saveKline(
        symbol,
        result.bars,
        context: context,
        source: result.source,
        adjust: adjust,
      );
    }
    return result;
  }

  bool _localKlineCovers(
    List<KlineBar> bars, {
    required String startDate,
    required String endDate,
  }) {
    if (bars.isEmpty) return false;
    if (startDate.isNotEmpty && bars.first.date.compareTo(startDate) > 0) {
      return false;
    }
    if (endDate.isNotEmpty && bars.last.date.compareTo(endDate) < 0) {
      return false;
    }
    return true;
  }

  void _saveQuotes(
    List<StockQuote> quotes, {
    required String source,
    ToolContext? context,
  }) {
    if (quotes.isEmpty) return;
    if (context != null) {
      _readService.saveQuotes(quotes, context: context, source: source);
      return;
    }
    _dataManager.saveQuoteSnapshots(quotes, source: source);
  }

  void _saveKline(
    String symbol,
    List<KlineBar> bars, {
    required String source,
    required String adjust,
    ToolContext? context,
  }) {
    if (bars.isEmpty) return;
    if (context != null) {
      _readService.saveKline(
        symbol,
        bars,
        context: context,
        source: source,
        adjust: adjust,
      );
      return;
    }
    _dataManager.saveKlineRows(symbol, bars, source: source, adjust: adjust);
  }
}
