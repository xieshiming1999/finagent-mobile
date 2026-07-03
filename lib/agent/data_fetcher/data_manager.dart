import 'base_fetcher.dart';
import 'cache.dart';
import 'eastmoney_fetcher.dart';
import 'cn_fetchers.dart';
import 'ex_tdx_fetcher.dart';
import 'models.dart';
import 'provider_policy.dart';
import 'reusable_data_store.dart';
import 'sector_chip_fetcher.dart';
import 'tdx_fetcher.dart';
import 'tushare_fetcher.dart';
import '../../domain/market/providers/eastmoney_market_provider.dart';
import '../../domain/market/providers/fetcher_eastmoney_market_provider.dart';
import '../../domain/market/providers/fetcher_market_data_provider.dart';
import '../../domain/market/providers/market_data_provider.dart';
import '../../domain/market/services/market_data_resolve_service.dart';

part 'data_manager_status.dart';
part 'data_manager_store_market.dart';
part 'data_manager_store_research.dart';
part 'data_manager_store_reference.dart';

/// Compatibility facade for shared mobile market data access.
///
/// Quote/K-line and EastMoney/Tushare orchestration lives behind
/// `app/lib/domain/market/**` providers and services. This class keeps the
/// existing fetcher/store/status surface stable while delegating read paths to
/// those domain boundaries.
class DataManager {
  late final TdxFetcher _tdxFetcher;
  late final EastMoneyFetcher _eastMoneyFetcher;
  late final SinaFetcher _sinaFetcher;
  late final TencentFetcher _tencentFetcher;
  late final TushareFetcher? _tushareFetcher;
  late final List<BaseFetcher> _registeredFetchers;
  late final ExTdxFetcher _exTdxFetcher;
  late final FetcherEastmoneyMarketProvider _eastmoneyMarketProvider;
  late final FetcherMarketDataProvider _marketDataProvider;
  late final MarketDataResolveService _marketDataResolveService;
  ReusableDataStore? _store;
  String? _basePath;

  final _policy = const ProviderPolicy();
  late final EastMoneySectorFetcher _sectorFetcher;
  final _klineCache = DataCache<List<KlineBar>>(
    ttl: Duration(minutes: 30),
    maxEntries: 100,
  );
  final _flowCache = DataCache<List<MoneyFlow>>(
    ttl: Duration(minutes: 10),
    maxEntries: 50,
  );
  final _sectorCache = DataCache<List<Map<String, dynamic>>>(
    ttl: Duration(minutes: 10),
  );

  DataManager({
    String? tushareToken,
    TushareFetcher? tushareFetcher,
    String? basePath,
    TdxFetcher? tdxFetcher,
    ExTdxFetcher? exTdxFetcher,
    EastMoneyFetcher? eastMoneyFetcher,
    EastMoneySectorFetcher? sectorFetcher,
  }) {
    final tdx = tdxFetcher ?? TdxFetcher();
    final exTdx = exTdxFetcher ?? ExTdxFetcher();
    final eastMoney = eastMoneyFetcher ?? EastMoneyFetcher();
    _tdxFetcher = tdx;
    _eastMoneyFetcher = eastMoney;
    _sectorFetcher = sectorFetcher ?? EastMoneySectorFetcher();
    _sinaFetcher = SinaFetcher();
    _tencentFetcher = TencentFetcher();
    _tushareFetcher =
        tushareFetcher ??
        (tushareToken != null && tushareToken.isNotEmpty
            ? TushareFetcher(token: tushareToken)
            : null);
    _exTdxFetcher = exTdx;
    _registeredFetchers = [
      _tdxFetcher,
      _eastMoneyFetcher,
      if (_tushareFetcher != null) _tushareFetcher,
      _sinaFetcher,
      _tencentFetcher,
    ];
    _marketDataProvider = FetcherMarketDataProvider(
      dataManager: this,
      tdxFetcher: _tdxFetcher,
      eastMoneyFetcher: _eastMoneyFetcher,
      sinaFetcher: _sinaFetcher,
      tencentFetcher: _tencentFetcher,
      sectorFetcher: _sectorFetcher,
      tushareFetcher: _tushareFetcher,
      registeredFetchers: _registeredFetchers,
      klineCache: _klineCache,
    );
    _marketDataResolveService = MarketDataResolveService(
      dataManager: this,
      fetchService: null,
    );
    _eastmoneyMarketProvider = FetcherEastmoneyMarketProvider(
      eastMoneyFetcher: _eastMoneyFetcher,
      sinaFetcher: _sinaFetcher,
      tencentFetcher: _tencentFetcher,
      sectorFetcher: _sectorFetcher,
      flowCache: _flowCache,
      sectorCache: _sectorCache,
      runtimeBasePathProvider: () => _basePath,
    );
    ensureBasePath(basePath);
  }

  void ensureBasePath(String? basePath) {
    final trimmed = basePath?.trim() ?? '';
    if (trimmed.isEmpty) return;
    if (_basePath == trimmed && _store != null) return;
    _basePath = trimmed;
    _tdxFetcher.basePath = trimmed;
    _exTdxFetcher.basePath = trimmed;
    _store = ReusableDataStore(trimmed)..cleanup();
  }

  String? get basePath => _basePath;

  EastmoneyMarketProvider get eastmoneyMarketProvider =>
      _eastmoneyMarketProvider;

  MarketDataProvider get marketDataProvider => _marketDataProvider;

  /// Compatibility quote read delegating to the market-data provider boundary.
  Future<({List<StockQuote> data, String source})> getQuotes(
    List<String> codes,
  ) => _marketDataResolveService.resolveQuotes(codes);

  /// Compatibility K-line read delegating to the market-data provider boundary.
  Future<({List<KlineBar> bars, String source})> getKline(
    String code, {
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
  }) => _marketDataResolveService.resolveKline(
    code,
    period: period,
    startDate: startDate,
    endDate: endDate,
    adjust: adjust,
  );

  /// Compatibility EastMoney market read delegating to the provider boundary.
  Future<({List<MoneyFlow> data, String source})> getMoneyFlow(String code) =>
      _marketDataProvider.readMoneyFlow(code);

  /// Get ETF quotes.
  Future<List<StockQuote>> getETFQuotes() =>
      _eastmoneyMarketProvider.readEtfQuotes().then((result) => result.data);

  /// Get sector/board rankings.
  Future<List<Map<String, dynamic>>> getSectorRanking({
    String boardType = 'industry',
  }) async =>
      (await _marketDataProvider.readSectorRanking(boardType: boardType)).data;

  /// Get sector constituent stocks.
  Future<List<StockQuote>> getSectorStocks(
    String sectorCode, {
    String? sectorName,
  }) => _eastmoneyMarketProvider.readSectorStocks(
    sectorCode,
    sectorName: sectorName,
  );

  /// Get chip distribution for a stock.
  Future<Map<String, dynamic>> getChipDistribution(String code) =>
      _eastmoneyMarketProvider.readChipDistribution(code);

  ProviderGates get _gates =>
      ProviderGates(tushareConfigured: _tushareFetcher != null);

  String _providerLabel(FinanceProvider provider) {
    return switch (provider) {
      FinanceProvider.local => 'Local',
      FinanceProvider.tdx => _tdxFetcher.name,
      FinanceProvider.eastmoneyDirect => _eastMoneyFetcher.name,
      FinanceProvider.akshare => 'AkShare',
      FinanceProvider.wind => 'Wind',
      FinanceProvider.tushare => _tushareFetcher?.name ?? 'Tushare',
      FinanceProvider.sina => _sinaFetcher.name,
      FinanceProvider.tencent => _tencentFetcher.name,
      FinanceProvider.yfinance => 'yfinance',
      FinanceProvider.szse => 'SZSE',
      FinanceProvider.tradingview => 'TradingView',
    };
  }
}
