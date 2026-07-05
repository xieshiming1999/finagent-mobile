import '../../../agent/data_fetcher/base_fetcher.dart';
import '../../../agent/data_fetcher/cache.dart';
import '../../../agent/data_fetcher/cn_fetchers.dart';
import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/eastmoney_fetcher.dart';
import '../../../agent/data_fetcher/models.dart';
import '../../../agent/data_fetcher/normalizers.dart';
import '../../../agent/data_fetcher/provider_policy.dart';
import '../../../agent/data_fetcher/sector_chip_fetcher.dart';
import '../../../agent/data_fetcher/tdx_fetcher.dart';
import '../../../agent/data_fetcher/tushare_fetcher.dart';
import '../market_index_universe.dart';
import 'data_api_interface_contract.dart';
import 'data_api_interface_router.dart';
import 'market_data_provider.dart';

class FetcherMarketDataProvider implements MarketDataProvider {
  final DataManager _dataManager;
  final TdxFetcher _tdxFetcher;
  final EastMoneyFetcher _eastMoneyFetcher;
  final SinaFetcher _sinaFetcher;
  final TencentFetcher _tencentFetcher;
  final EastMoneySectorFetcher _sectorFetcher;
  final TushareFetcher? _tushareFetcher;
  final List<BaseFetcher> _registeredFetchers;
  final DataCache<List<KlineBar>> _klineCache;
  late final DataApiInterfaceRouter _router;

  FetcherMarketDataProvider({
    required DataManager dataManager,
    required TdxFetcher tdxFetcher,
    required EastMoneyFetcher eastMoneyFetcher,
    required SinaFetcher sinaFetcher,
    required TencentFetcher tencentFetcher,
    required EastMoneySectorFetcher sectorFetcher,
    required TushareFetcher? tushareFetcher,
    required List<BaseFetcher> registeredFetchers,
    required DataCache<List<KlineBar>> klineCache,
  }) : _dataManager = dataManager,
       _tdxFetcher = tdxFetcher,
       _eastMoneyFetcher = eastMoneyFetcher,
       _sinaFetcher = sinaFetcher,
       _tencentFetcher = tencentFetcher,
       _sectorFetcher = sectorFetcher,
       _tushareFetcher = tushareFetcher,
       _registeredFetchers = List<BaseFetcher>.unmodifiable(registeredFetchers),
       _klineCache = klineCache {
    _router = DataApiInterfaceRouter(
      fetcherForProvider: _fetcherForProvider,
      runtimeBasePathProvider: () => _dataManager.basePath,
    );
  }

  @override
  List<String> get sourceNames => _registeredFetchers
      .map((fetcher) => fetcher.name)
      .toList(growable: false);

  @override
  Future<({List<StockQuote> data, String source})> readQuotes(
    List<String> symbols, {
    String? source,
  }) async {
    if (_isConvertibleBondQuoteRequest(symbols)) {
      return _fetchConvertibleBondQuotesFromSources(
        symbols,
        constraint: source == null
            ? const DataApiProviderConstraint()
            : _strictProviderConstraint(source),
      );
    }
    if (_isIndexQuoteRequest(symbols)) {
      return _fetchIndexQuotesFromSources(
        symbols,
        constraint: source == null
            ? const DataApiProviderConstraint()
            : _strictProviderConstraint(source),
      );
    }
    if (source != null) {
      return _fetchQuotesFromSources(
        symbols,
        constraint: _strictProviderConstraint(source),
      );
    }
    return _fetchQuotesFromSources(symbols);
  }

  @override
  Future<({List<KlineBar> bars, String source})> readKline(
    String symbol, {
    String? source,
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
  }) async {
    if (_isConvertibleBondKlineRequest(symbol)) {
      return _fetchConvertibleBondKlineFromSources(
        symbol,
        period: period,
        startDate: startDate,
        endDate: endDate,
        adjust: adjust,
        constraint: source == null
            ? const DataApiProviderConstraint()
            : _strictProviderConstraint(source),
      );
    }
    if (_isEtfKlineRequest(symbol) && (source != null || adjust == 'none')) {
      return _fetchEtfKlineFromSources(
        symbol,
        period: period,
        startDate: startDate,
        endDate: endDate,
        adjust: adjust,
        constraint: source == null
            ? const DataApiProviderConstraint()
            : _strictProviderConstraint(source),
      );
    }
    if (source != null) {
      return _fetchKlineFromSources(
        symbol,
        period: period,
        startDate: startDate,
        endDate: endDate,
        adjust: adjust,
        constraint: _strictProviderConstraint(source),
      );
    }

    final cacheKey = '$symbol|$period|$startDate|$endDate|$adjust';
    final cached = _klineCache.getTracked(cacheKey);
    if (cached != null) return (bars: cached, source: 'cache');
    final result = await _fetchKlineFromSources(
      symbol,
      period: period,
      startDate: startDate,
      endDate: endDate,
      adjust: adjust,
    );
    _klineCache.set(cacheKey, result.bars);
    return result;
  }

  Future<({List<StockQuote> data, String source})> _fetchQuotesFromSources(
    List<String> symbols, {
    DataApiProviderConstraint constraint = const DataApiProviderConstraint(),
  }) async {
    final normalizedSymbols = symbols.map((symbol) => symbol.trim()).toList();
    final result = await _router.runCapability<List<StockQuote>>(
      interfaceId: 'stock.quote',
      call: (capability) async {
        final fetcher = _fetcherForProvider(capability.provider);
        if (fetcher == null) return null;
        if (capability.provider == FinanceProvider.tencent) {
          final globalSymbols = normalizedSymbols.any(
            _isTencentGlobalQuoteSymbol,
          );
          if (capability.id == 'tencent.global.stock_quote' && !globalSymbols) {
            return null;
          }
          if (capability.id == 'tencent.stock.quote' && globalSymbols) {
            return null;
          }
        }
        return DataApiProviderExecution(
          data: normalizeQuotes(
            await fetcher.getQuotes(normalizedSymbols),
            fetcher.name,
          ),
          source: fetcher.name,
          providerName: fetcher.name,
        );
      },
      isUsable: (quotes) => quotes.isNotEmpty,
      emptyMessage: 'returned empty',
      failureMessage: 'All quote sources failed',
      constraint: constraint,
    );
    return (data: result.data, source: result.source);
  }

  Future<({List<StockQuote> data, String source})>
  _fetchConvertibleBondQuotesFromSources(
    List<String> symbols, {
    DataApiProviderConstraint constraint = const DataApiProviderConstraint(),
  }) async {
    final normalizedSymbols = symbols.map(_cleanCode).toList();
    final result = await _router.runCapability<List<StockQuote>>(
      interfaceId: 'bond.convertible_quote',
      call: (capability) async {
        if (capability.provider == FinanceProvider.tencent) {
          return DataApiProviderExecution(
            data: normalizeQuotes(
              await _tencentFetcher.getConvertibleBondQuotes(normalizedSymbols),
              '${_tencentFetcher.name}:convertible_bond',
            ),
            source: '${_tencentFetcher.name}:convertible_bond',
            providerName: _tencentFetcher.name,
          );
        }
        return null;
      },
      isUsable: (quotes) => quotes.isNotEmpty,
      emptyMessage: 'returned empty convertible-bond quote rows',
      failureMessage: 'All convertible-bond quote sources failed',
      constraint: constraint,
    );
    return (data: result.data, source: result.source);
  }

  Future<({List<StockQuote> data, String source})> _fetchIndexQuotesFromSources(
    List<String> symbols, {
    DataApiProviderConstraint constraint = const DataApiProviderConstraint(),
  }) async {
    final normalizedSymbols = symbols.map(_normalizeIndexSymbol).toList();
    final result = await _router.runCapability<List<StockQuote>>(
      interfaceId: 'index.quote',
      call: (capability) async {
        final fetcher = _fetcherForProvider(capability.provider);
        if (fetcher == null) return null;
        final requestSymbols =
            capability.provider == FinanceProvider.tdx ||
                capability.provider == FinanceProvider.tencent
            ? normalizedSymbols
            : normalizedSymbols
                  .map(coreCnMarketIndexQualifiedSymbol)
                  .toList(growable: false);
        final quotes = capability.provider == FinanceProvider.tdx
            ? await _getTdxIndexQuotes(normalizedSymbols)
            : capability.provider == FinanceProvider.tencent
            ? await _tencentFetcher.getIndexQuotes(normalizedSymbols)
            : await fetcher.getQuotes(requestSymbols);
        final source = '${fetcher.name}:index_quote';
        return DataApiProviderExecution(
          data: normalizeQuotes(quotes, source)
              .where((quote) => normalizedSymbols.contains(quote.code))
              .where(_hasIndexQuoteIdentity)
              .where(_hasPlausibleIndexQuoteScale)
              .toList(),
          source: source,
          providerName: fetcher.name,
        );
      },
      isUsable: (quotes) => quotes.isNotEmpty,
      emptyMessage: 'returned empty index quote rows',
      failureMessage: 'All index quote sources failed',
      constraint: constraint,
    );
    return (data: result.data, source: result.source);
  }

  Future<List<StockQuote>> _getTdxIndexQuotes(List<String> symbols) async {
    final quotes = <StockQuote>[];
    for (final symbol in symbols) {
      try {
        final row = await _tdxFetcher.getIndexInfo(symbol);
        if (row.containsKey('error')) continue;
        final price = _toDouble(row['close']);
        final prevClose = _toDouble(row['preClose']);
        final quote = StockQuote(
          code: symbol,
          name: _indexDisplayName(symbol),
          price: price,
          change: _toDouble(row['change']),
          changePct: _toDouble(row['changePct']),
          open: _toDouble(row['open']),
          high: _toDouble(row['high']),
          low: _toDouble(row['low']),
          prevClose: prevClose == 0 ? price : prevClose,
          volume: _toDouble(row['volume']),
          amount: _toDouble(row['amount']),
          source: '${_tdxFetcher.name}:index_quote',
        );
        if (_hasIndexQuoteIdentity(quote) &&
            _hasPlausibleIndexQuoteScale(quote)) {
          quotes.add(quote);
        }
      } catch (_) {
        continue;
      }
    }
    return quotes;
  }

  Future<({List<KlineBar> bars, String source})> _fetchKlineFromSources(
    String symbol, {
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
    DataApiProviderConstraint constraint = const DataApiProviderConstraint(),
  }) async {
    final normalizedSymbol = _normalizeKlineSymbol(symbol);
    final interfaceId = _klineInterfaceId(symbol);
    final result = await _router.runCapability<List<KlineBar>>(
      interfaceId: interfaceId,
      call: (capability) async {
        final fetcher = _fetcherForProvider(capability.provider);
        if (fetcher == null) return null;
        final bars = capability.provider == FinanceProvider.tencent
            ? interfaceId == 'index.daily_kline'
                  ? await _tencentFetcher.getIndexDailyKline(
                      normalizedSymbol,
                      period: period,
                      startDate: startDate,
                      endDate: endDate,
                      adjust: adjust,
                    )
                  : await _tencentFetcher.getStockDailyKline(
                      normalizedSymbol,
                      period: period,
                      startDate: startDate,
                      endDate: endDate,
                      adjust: adjust,
                    )
            : await fetcher.getKline(
                normalizedSymbol,
                period: period,
                startDate: startDate,
                endDate: endDate,
                adjust: adjust,
              );
        final source = capability.provider == FinanceProvider.tencent
            ? interfaceId == 'index.daily_kline'
                  ? '${fetcher.name}:index_kline'
                  : '${fetcher.name}:stock_kline'
            : fetcher.name;
        return DataApiProviderExecution(
          data: normalizeKlineBars(bars),
          source: source,
          providerName: fetcher.name,
        );
      },
      isUsable: (bars) => bars.isNotEmpty,
      emptyMessage:
          'returned empty (code=$normalizedSymbol may be invalid format)',
      failureMessage: 'All kline sources failed for "$normalizedSymbol"',
      constraint: constraint,
    );
    return (bars: result.data, source: result.source);
  }

  Future<({List<KlineBar> bars, String source})> _fetchEtfKlineFromSources(
    String symbol, {
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'none',
    DataApiProviderConstraint constraint = const DataApiProviderConstraint(),
  }) async {
    if (period != 'daily') {
      throw DataFetchError('ETF K-line supports only daily period');
    }
    if (adjust != 'none') {
      throw DataFetchError(
        'ETF daily OHLCV is governed on mobile only for adjust=none',
      );
    }
    final normalizedSymbol = _cleanCode(symbol);
    final result = await _router.runCapability<List<KlineBar>>(
      interfaceId: 'fund.etf_daily_ohlcv_bars',
      call: (capability) async {
        if (capability.provider == FinanceProvider.tencent) {
          return DataApiProviderExecution(
            data: normalizeKlineBars(
              await _tencentFetcher.getEtfDailyKline(
                normalizedSymbol,
                startDate: startDate,
                endDate: endDate,
                adjust: adjust,
              ),
            ),
            source: '${_tencentFetcher.name}:etf_kline',
            providerName: _tencentFetcher.name,
          );
        }
        return null;
      },
      isUsable: (bars) => bars.isNotEmpty,
      emptyMessage: 'returned empty ETF daily OHLCV rows',
      failureMessage:
          'All ETF daily OHLCV sources failed for "$normalizedSymbol"',
      constraint: constraint,
    );
    return (bars: result.data, source: result.source);
  }

  Future<({List<KlineBar> bars, String source})>
  _fetchConvertibleBondKlineFromSources(
    String symbol, {
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'none',
    DataApiProviderConstraint constraint = const DataApiProviderConstraint(),
  }) async {
    if (period != 'daily') {
      throw DataFetchError(
        'Convertible-bond K-line supports only daily period',
      );
    }
    if (adjust != 'none') {
      throw DataFetchError(
        'Convertible-bond daily K-line is governed only for adjust=none',
      );
    }
    final normalizedSymbol = _cleanCode(symbol);
    final result = await _router.runCapability<List<KlineBar>>(
      interfaceId: 'bond.convertible_daily_kline',
      call: (capability) async {
        if (capability.provider == FinanceProvider.tencent) {
          return DataApiProviderExecution(
            data: normalizeKlineBars(
              await _tencentFetcher.getConvertibleBondDailyKline(
                normalizedSymbol,
                startDate: startDate,
                endDate: endDate,
                adjust: adjust,
              ),
            ),
            source: '${_tencentFetcher.name}:convertible_bond_kline',
            providerName: _tencentFetcher.name,
          );
        }
        return null;
      },
      isUsable: (bars) => bars.isNotEmpty,
      emptyMessage: 'returned empty convertible-bond daily K-line rows',
      failureMessage:
          'All convertible-bond daily K-line sources failed for "$normalizedSymbol"',
      constraint: constraint,
    );
    return (bars: result.data, source: result.source);
  }

  String _klineInterfaceId(String symbol) {
    return _isGovernedIndexSymbol(symbol)
        ? 'index.daily_kline'
        : 'stock.daily_kline';
  }

  bool _isConvertibleBondKlineRequest(String symbol) {
    final clean = _cleanCode(symbol);
    return RegExp(r'^(11|12)\d{4}$').hasMatch(clean);
  }

  bool _isEtfKlineRequest(String symbol) {
    final clean = _cleanCode(symbol);
    return RegExp(
      r'^(510|512|513|515|516|518|588|589|159)\d{3}$',
    ).hasMatch(clean);
  }

  String _normalizeKlineSymbol(String symbol) {
    final text = symbol.trim();
    if (text.toUpperCase().startsWith('INDEX:')) {
      return _cleanCode(text.substring(6));
    }
    return text;
  }

  bool _isGovernedIndexSymbol(String symbol) {
    final text = symbol.trim();
    if (text.toUpperCase().startsWith('INDEX:')) return true;
    final clean = _cleanCode(text);
    final localIdentity = _dataManager.queryStockIdentity(clean);
    if ('${localIdentity?['stock_type'] ?? ''}'.trim().toLowerCase() ==
        'index') {
      return true;
    }
    return coreCnMarketIndexCodeSet.contains(clean) && clean != '000001';
  }

  bool _isIndexQuoteRequest(List<String> symbols) {
    if (symbols.isEmpty) return false;
    if (symbols.every(
      (symbol) => symbol.trim().toUpperCase().startsWith('INDEX:'),
    )) {
      return true;
    }
    if (symbols.length > 1 &&
        symbols.every(
          (symbol) => coreCnMarketIndexCodeSet.contains(_cleanCode(symbol)),
        )) {
      return true;
    }
    return symbols.every(
      (symbol) =>
          unambiguousCoreCnMarketIndexCodes.contains(_cleanCode(symbol)),
    );
  }

  bool _isConvertibleBondQuoteRequest(List<String> symbols) {
    if (symbols.isEmpty) return false;
    return symbols.every((symbol) {
      final clean = _cleanCode(symbol);
      return RegExp(r'^(11|12)\d{4}$').hasMatch(clean);
    });
  }

  String _normalizeIndexSymbol(String symbol) {
    final text = symbol.trim();
    if (text.toUpperCase().startsWith('INDEX:')) {
      return _cleanCode(text.substring(6));
    }
    return _cleanCode(text);
  }

  String _cleanCode(String value) {
    return value
        .replaceAll(RegExp(r'^(SH|SZ|BJ|CSI)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\.(SH|SZ|BJ|CSI)$', caseSensitive: false), '')
        .trim();
  }

  @override
  Future<({List<MoneyFlow> data, String source})> readMoneyFlow(
    String symbol, {
    String? source,
  }) async {
    final constraint = source == null
        ? const DataApiProviderConstraint()
        : _strictProviderConstraint(source);
    final result = await _router.run<List<MoneyFlow>>(
      interfaceId: 'stock.money_flow',
      call: (fetcher) => fetcher.getMoneyFlow(symbol),
      isUsable: (rows) => rows.isNotEmpty,
      emptyMessage: 'returned empty money-flow rows',
      failureMessage: 'All money-flow sources failed for "$symbol"',
      constraint: constraint,
    );
    return (data: result.data, source: result.source);
  }

  @override
  Future<({List<Map<String, dynamic>> data, String source})> readSectorRanking({
    String boardType = 'industry',
    String? source,
  }) async {
    final constraint = source == null
        ? const DataApiProviderConstraint()
        : _strictProviderConstraint(source);
    final interfaceId = boardType == 'concept'
        ? 'market.board_ranking'
        : 'market.sector_ranking';
    final result = await _router.runCapability<List<Map<String, dynamic>>>(
      interfaceId: interfaceId,
      call: (capability) async {
        if (capability.provider == FinanceProvider.eastmoneyDirect) {
          return DataApiProviderExecution(
            data: await _sectorFetcher.getSectorRanking(boardType: boardType),
            source: _eastMoneyFetcher.name,
            providerName: _eastMoneyFetcher.name,
          );
        }
        if (capability.provider == FinanceProvider.sina) {
          return DataApiProviderExecution(
            data: await _sinaFetcher.getSectorRanking(boardType: boardType),
            source: _sinaFetcher.name,
            providerName: _sinaFetcher.name,
          );
        }
        return null;
      },
      isUsable: (rows) => rows.isNotEmpty,
      emptyMessage: 'returned empty sector ranking rows',
      failureMessage: 'All sector ranking sources failed',
      constraint: constraint,
    );
    return (data: result.data, source: result.source);
  }

  DataApiProviderConstraint _strictProviderConstraint(String source) {
    return DataApiProviderConstraint(
      provider: _providerFromSource(source),
      providerMode: DataApiProviderMode.strict,
      allowFallback: false,
    );
  }

  FinanceProvider _providerFromSource(String source) {
    final lower = source.toLowerCase();
    if (lower == 'tdx' || lower.contains('通达信')) return FinanceProvider.tdx;
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
    if (lower == 'tushare') return FinanceProvider.tushare;
    if (lower == 'akshare') return FinanceProvider.akshare;
    throw ArgumentError(
      'unknown provider "$source". Available: tdx, eastmoney, sina, tencent, tushare, akshare',
    );
  }

  BaseFetcher? _fetcherForProvider(FinanceProvider provider) {
    return switch (provider) {
      FinanceProvider.local => null,
      FinanceProvider.tdx => _tdxFetcher,
      FinanceProvider.eastmoneyDirect => _eastMoneyFetcher,
      FinanceProvider.sina => _sinaFetcher,
      FinanceProvider.tencent => _tencentFetcher,
      FinanceProvider.tushare => _tushareFetcher,
      _ => null,
    };
  }
}

bool _isTencentGlobalQuoteSymbol(String symbol) {
  final value = symbol.trim();
  return RegExp(r'^hk\d{5}$', caseSensitive: false).hasMatch(value) ||
      RegExp(r'^us[A-Za-z0-9.]+$', caseSensitive: false).hasMatch(value);
}

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? 0.0;
}

String _indexDisplayName(String symbol) {
  return coreCnMarketIndexDisplayName(symbol);
}

bool _hasIndexQuoteIdentity(StockQuote quote) {
  final expectedName = coreCnMarketIndexNameByCode[quote.code];
  if (expectedName == null) return true;
  final name = quote.name.trim();
  return name == expectedName || name.contains('指数') || name.contains('指');
}

bool _hasPlausibleIndexQuoteScale(StockQuote quote) {
  return coreCnMarketIndexHasPlausiblePrice(quote.code, quote.price);
}
