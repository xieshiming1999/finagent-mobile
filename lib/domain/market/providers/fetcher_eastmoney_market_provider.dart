import '../../../agent/data_fetcher/cache.dart';
import '../../../agent/data_fetcher/cn_fetchers.dart';
import '../../../agent/data_fetcher/eastmoney_fetcher.dart';
import '../../../agent/data_fetcher/models.dart';
import '../../../agent/data_fetcher/provider_policy.dart';
import '../../../agent/data_fetcher/sector_chip_fetcher.dart';
import 'data_api_interface_contract.dart';
import 'data_api_interface_router.dart';
import 'eastmoney_market_provider.dart';

class FetcherEastmoneyMarketProvider implements EastmoneyMarketProvider {
  final EastMoneyFetcher _eastMoneyFetcher;
  final SinaFetcher _sinaFetcher;
  final TencentFetcher _tencentFetcher;
  final EastMoneySectorFetcher _sectorFetcher;
  final DataCache<List<MoneyFlow>> _flowCache;
  final DataCache<List<Map<String, dynamic>>> _sectorCache;
  final String? Function()? _runtimeBasePathProvider;
  late final DataApiInterfaceRouter _router;

  FetcherEastmoneyMarketProvider({
    required EastMoneyFetcher eastMoneyFetcher,
    required SinaFetcher sinaFetcher,
    required TencentFetcher tencentFetcher,
    required EastMoneySectorFetcher sectorFetcher,
    required DataCache<List<MoneyFlow>> flowCache,
    required DataCache<List<Map<String, dynamic>>> sectorCache,
    String? Function()? runtimeBasePathProvider,
  }) : _eastMoneyFetcher = eastMoneyFetcher,
       _sinaFetcher = sinaFetcher,
       _tencentFetcher = tencentFetcher,
       _sectorFetcher = sectorFetcher,
       _flowCache = flowCache,
       _sectorCache = sectorCache,
       _runtimeBasePathProvider = runtimeBasePathProvider {
    _router = DataApiInterfaceRouter(
      runtimeBasePathProvider: _runtimeBasePathProvider,
    );
  }

  @override
  Future<({List<MoneyFlow> data, String source})> readMoneyFlow(
    String symbol,
  ) async {
    final cached = _flowCache.getTracked('flow:$symbol');
    if (cached != null) return (data: cached, source: 'cache');

    final result = await _eastMoneyFetcher.getMoneyFlow(symbol);
    _flowCache.set('flow:$symbol', result);
    return (data: result, source: _eastMoneyFetcher.name);
  }

  @override
  Future<({List<StockQuote> data, String source})> readEtfQuotes({
    String? source,
  }) async {
    final constraint = source == null
        ? const DataApiProviderConstraint()
        : DataApiProviderConstraint(
            provider: _providerFromSource(source),
            providerMode: DataApiProviderMode.strict,
            allowFallback: false,
          );
    final result = await _router.runCapability<List<StockQuote>>(
      interfaceId: 'fund.etf_quote',
      call: (capability) async {
        if (capability.provider == FinanceProvider.eastmoneyDirect) {
          return DataApiProviderExecution(
            data: await _eastMoneyFetcher.getETFQuotes(),
            source: _eastMoneyFetcher.name,
            providerName: _eastMoneyFetcher.name,
          );
        }
        if (capability.provider == FinanceProvider.sina) {
          return DataApiProviderExecution(
            data: await _sinaFetcher.getETFQuotes(),
            source: _sinaFetcher.name,
            providerName: _sinaFetcher.name,
          );
        }
        if (capability.provider == FinanceProvider.tencent) {
          return DataApiProviderExecution(
            data: await _tencentFetcher.getETFQuotes(limit: 20),
            source: _tencentFetcher.name,
            providerName: _tencentFetcher.name,
          );
        }
        return null;
      },
      isUsable: (quotes) => quotes.isNotEmpty,
      emptyMessage: 'returned empty ETF quote rows',
      failureMessage: 'All ETF quote sources failed',
      constraint: constraint,
    );
    return (data: result.data, source: result.source);
  }

  @override
  Future<({List<StockQuote> data, String source})> readListedFundQuotes({
    String? source,
  }) async {
    final constraint = source == null
        ? const DataApiProviderConstraint()
        : DataApiProviderConstraint(
            provider: _providerFromSource(source),
            providerMode: DataApiProviderMode.strict,
            allowFallback: false,
          );
    final result = await _router.runCapability<List<StockQuote>>(
      interfaceId: 'fund.listed_fund_quote',
      call: (capability) async {
        if (capability.provider == FinanceProvider.tencent) {
          return DataApiProviderExecution(
            data: await _tencentFetcher.getListedFundQuotes(limit: 20),
            source: _tencentFetcher.name,
            providerName: _tencentFetcher.name,
          );
        }
        return null;
      },
      isUsable: (quotes) => quotes.isNotEmpty,
      emptyMessage: 'returned empty listed-fund quote rows',
      failureMessage: 'All listed-fund quote sources failed',
      constraint: constraint,
    );
    return (data: result.data, source: result.source);
  }

  @override
  Future<({List<Map<String, dynamic>> data, String source})> readStockList({
    String? source,
  }) async {
    final constraint = source == null
        ? const DataApiProviderConstraint()
        : DataApiProviderConstraint(
            provider: _providerFromSource(source),
            providerMode: DataApiProviderMode.strict,
            allowFallback: false,
          );
    final result = await _router.runCapability<List<Map<String, dynamic>>>(
      interfaceId: 'stock.identity_list',
      call: (capability) async {
        if (capability.provider == FinanceProvider.eastmoneyDirect) {
          return DataApiProviderExecution(
            data: await _eastMoneyFetcher.getStockList(),
            source: _eastMoneyFetcher.name,
            providerName: _eastMoneyFetcher.name,
          );
        }
        if (capability.provider == FinanceProvider.tencent) {
          return DataApiProviderExecution(
            data: await _tencentFetcher.getStockList(limit: 200),
            source: _tencentFetcher.name,
            providerName: _tencentFetcher.name,
          );
        }
        return null;
      },
      isUsable: (rows) => rows.isNotEmpty,
      emptyMessage: 'returned empty stock identity rows',
      failureMessage: 'All stock identity list sources failed',
      constraint: constraint,
    );
    return (data: result.data, source: result.source);
  }

  @override
  Future<({List<Map<String, dynamic>> data, String source})>
  readFundList() async {
    final rows = await _eastMoneyFetcher.getFundList();
    return (data: rows, source: _eastMoneyFetcher.name);
  }

  @override
  Future<({List<Map<String, dynamic>> data, String source})> readFundNav(
    String fundCode,
  ) async {
    final rows = await _eastMoneyFetcher.getFundNav(fundCode);
    return (data: rows, source: _eastMoneyFetcher.name);
  }

  @override
  Future<({List<Map<String, dynamic>> data, String source})> readFundMoneyYield(
    String fundCode,
  ) async {
    final rows = await _eastMoneyFetcher.getFundMoneyYield(fundCode);
    return (data: rows, source: _eastMoneyFetcher.name);
  }

  @override
  Future<({List<Map<String, dynamic>> data, String source})> readFundHolding(
    String fundCode,
  ) async {
    final rows = await _eastMoneyFetcher.getFundHolding(fundCode);
    return (data: rows, source: _eastMoneyFetcher.name);
  }

  @override
  Future<({List<Map<String, dynamic>> data, String source})>
  readFundManagers() async {
    final rows = await _eastMoneyFetcher.getFundManagers();
    return (data: rows, source: _eastMoneyFetcher.name);
  }

  @override
  Future<({List<Map<String, dynamic>> data, String source})>
  readFundPerformance() async {
    final rows = await _eastMoneyFetcher.getFundPerformance();
    return (data: rows, source: _eastMoneyFetcher.name);
  }

  @override
  Future<({List<Map<String, dynamic>> data, String source})>
  readStockShareholders(String code, {String? reportDate}) async {
    final rows = await _eastMoneyFetcher.getStockShareholders(
      code,
      reportDate: reportDate,
    );
    return (data: rows, source: _eastMoneyFetcher.name);
  }

  @override
  Future<({Map<String, dynamic> data, String source})> readStockCompanyInfo(
    String code,
  ) async {
    final row = await _eastMoneyFetcher.getStockCompanyInfo(code);
    return (data: row, source: _eastMoneyFetcher.name);
  }

  @override
  Future<List<Map<String, dynamic>>> readSectorRanking({
    required String boardType,
  }) async {
    final cached = _sectorCache.getTracked('sector:$boardType');
    if (cached != null) return cached;
    final result = await _sectorFetcher.getSectorRanking(boardType: boardType);
    _sectorCache.set('sector:$boardType', result);
    return result;
  }

  @override
  Future<List<StockQuote>> readSectorStocks(
    String sectorCode, {
    String? sectorName,
    String? source,
  }) async {
    if (source != null) {
      final provider = _providerFromSource(source);
      if (provider == FinanceProvider.sina) {
        return _sinaFetcher.getSectorStocks(sectorCode);
      }
      if (provider != FinanceProvider.eastmoneyDirect) {
        throw ArgumentError(
          'unknown sector-constituent provider "$source". Available: eastmoney, sina',
        );
      }
    }
    final quotes = await _sectorFetcher.getSectorStocks(sectorCode);
    return quotes;
  }

  @override
  Future<Map<String, dynamic>> readChipDistribution(String symbol) async {
    final result = await _sectorFetcher.getChipDistribution(symbol);
    return result;
  }

  FinanceProvider _providerFromSource(String source) {
    final lower = source.toLowerCase();
    if (lower == 'eastmoney' ||
        lower == 'eastmoneydirect' ||
        lower == 'eastmoney_direct' ||
        lower.contains('东方财富')) {
      return FinanceProvider.eastmoneyDirect;
    }
    if (lower == 'sina' || lower.contains('新浪')) return FinanceProvider.sina;
    if (lower == 'tencent' || lower.contains('腾讯')) {
      return FinanceProvider.tencent;
    }
    if (lower == 'akshare') return FinanceProvider.akshare;
    if (lower == 'wind') return FinanceProvider.wind;
    throw ArgumentError(
      'unknown market data provider "$source". Available: eastmoney, sina, tencent, akshare, wind',
    );
  }
}
