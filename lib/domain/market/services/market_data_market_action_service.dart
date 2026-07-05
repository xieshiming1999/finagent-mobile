import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/cn_fetchers.dart';
import '../../../agent/data_fetcher/provider_policy.dart';
import '../../../agent/tool_context.dart';
import '../market_index_universe.dart';
import '../providers/data_api_interface_router.dart';
import 'earnings_market_data_service.dart';
import 'eastmoney_advanced_service.dart';
import 'eastmoney_market_data_service.dart';
import 'finance_news_market_data_service.dart';
import 'margin_trading_market_data_service.dart';
import 'cache_policy.dart';
import 'market_data_resolve_service.dart';
import '../providers/data_api_interface_contract.dart';
import 'trade_calendar_data_api_service.dart';
import 'tushare_market_data_service.dart';
import 'tradingview_market_data_service.dart';
import 'wind_structured_market_data_service.dart';
import 'yahoo_market_data_service.dart';

class MarketDataMarketActionService {
  final DataManager _dataManager;
  final DataApiInterfaceRouter _router;
  final MarketDataResolveService _resolveService;
  final EastmoneyAdvancedService _eastmoneyAdvanced;
  final EastmoneyMarketDataService _eastmoney;
  final EarningsMarketDataService _earnings;
  final MarginTradingMarketDataService _marginTrading;
  final FinanceNewsMarketDataService _financeNews;
  final TradeCalendarDataApiService Function(String basePath)
  _tradeCalendarServiceFactory;
  final TushareMarketDataService _tushare;
  final TradingviewMarketDataService _tradingview;
  final WindStructuredMarketDataService _windStructured;
  final YahooMarketDataService _yahoo;
  final SinaFetcher _sinaFetcher;

  MarketDataMarketActionService({
    DataManager? dataManager,
    MarketDataResolveService? resolveService,
    EastmoneyAdvancedService? eastmoneyAdvanced,
    EastmoneyMarketDataService? eastmoney,
    EarningsMarketDataService? earnings,
    FinanceNewsMarketDataService? financeNews,
    MarginTradingMarketDataService? marginTrading,
    TradeCalendarDataApiService Function(String basePath)?
    tradeCalendarServiceFactory,
    TushareMarketDataService? tushare,
    TradingviewMarketDataService? tradingview,
    WindStructuredMarketDataService? windStructured,
    YahooMarketDataService? yahoo,
    SinaFetcher? sinaFetcher,
    DataApiInterfaceRouter? router,
  }) : this._withManager(
         dataManager ?? DataManager(),
         resolveService: resolveService,
         eastmoneyAdvanced: eastmoneyAdvanced,
         eastmoney: eastmoney,
         earnings: earnings,
         financeNews: financeNews,
         marginTrading: marginTrading,
         tradeCalendarServiceFactory: tradeCalendarServiceFactory,
         tushare: tushare,
         tradingview: tradingview,
         windStructured: windStructured,
         yahoo: yahoo,
         sinaFetcher: sinaFetcher,
         router: router,
       );

  MarketDataMarketActionService._withManager(
    DataManager dataManager, {
    MarketDataResolveService? resolveService,
    EastmoneyAdvancedService? eastmoneyAdvanced,
    EastmoneyMarketDataService? eastmoney,
    EarningsMarketDataService? earnings,
    FinanceNewsMarketDataService? financeNews,
    MarginTradingMarketDataService? marginTrading,
    TradeCalendarDataApiService Function(String basePath)?
    tradeCalendarServiceFactory,
    TushareMarketDataService? tushare,
    TradingviewMarketDataService? tradingview,
    WindStructuredMarketDataService? windStructured,
    YahooMarketDataService? yahoo,
    SinaFetcher? sinaFetcher,
    DataApiInterfaceRouter? router,
  }) : _dataManager = dataManager,
       _router =
           router ??
           DataApiInterfaceRouter(
             runtimeBasePathProvider: () => dataManager.basePath,
           ),
       _resolveService =
           resolveService ?? MarketDataResolveService(dataManager: dataManager),
       _eastmoneyAdvanced =
           eastmoneyAdvanced ??
           EastmoneyAdvancedService(
             dataManager: dataManager,
             router:
                 router ??
                 DataApiInterfaceRouter(
                   runtimeBasePathProvider: () => dataManager.basePath,
                 ),
           ),
       _eastmoney =
           eastmoney ?? EastmoneyMarketDataService(dataManager: dataManager),
       _earnings =
           earnings ?? EarningsMarketDataService(dataManager: dataManager),
       _financeNews =
           financeNews ??
           FinanceNewsMarketDataService(
             dataManager: dataManager,
             router:
                 router ??
                 DataApiInterfaceRouter(
                   runtimeBasePathProvider: () => dataManager.basePath,
                 ),
           ),
       _marginTrading =
           marginTrading ??
           MarginTradingMarketDataService(dataManager: dataManager),
       _tradeCalendarServiceFactory =
           tradeCalendarServiceFactory ??
           ((basePath) => TradeCalendarDataApiService(
             basePath: basePath,
             dataManager: dataManager,
             router:
                 router ??
                 DataApiInterfaceRouter(
                   runtimeBasePathProvider: () => dataManager.basePath,
                 ),
           )),
       _tushare = tushare ?? TushareMarketDataService(dataManager: dataManager),
       _tradingview = tradingview ?? TradingviewMarketDataService(),
       _windStructured = windStructured ?? WindStructuredMarketDataService(),
       _yahoo =
           yahoo ??
           YahooMarketDataService(
             dataManager: dataManager,
             router:
                 router ??
                 DataApiInterfaceRouter(
                   runtimeBasePathProvider: () => dataManager.basePath,
                 ),
           ),
       _sinaFetcher = sinaFetcher ?? SinaFetcher();

  Future<Map<String, dynamic>> run(
    String action,
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    switch (action) {
      case 'quote':
        return _quote(_firstSymbols(symbols, _quoteError), input, context);
      case 'kline':
        return _kline(_firstSymbol(symbols, _klineError), input, context);
      case 'flow':
        return _eastmoney.flow(_firstSymbol(symbols, _flowError));
      case 'flow_rank':
        return _eastmoneyAdvanced.flowRank(input);
      case 'sector':
        return _eastmoney.sector(input);
      case 'chip':
        return _eastmoney.chip(_firstSymbol(symbols, _chipError));
      case 'etf':
        return _eastmoney.etf(source: input['provider'] as String?);
      case 'listed_fund_quote':
        return _eastmoney.listedFundQuote(
          source: input['provider'] as String? ?? 'tencent',
        );
      case 'stock_list':
        return _eastmoney.stockList(source: input['provider'] as String?);
      case 'fund_list':
        return _eastmoney.fundList();
      case 'fund_nav':
        return _eastmoney.fundNav(_fundNavCode(symbols, input));
      case 'fund_money_yield':
        return _eastmoney.fundMoneyYield(_fundMoneyYieldCode(symbols, input));
      case 'fund_dividend_factor':
        return _fundDividendFactor(
          _firstSymbol(symbols, _fundDividendFactorError),
          input,
          context,
        );
      case 'fund_manager':
        return _eastmoney.fundManager();
      case 'fund_holding':
        return _eastmoney.fundHolding(_fundCode(symbols, input));
      case 'fund_performance':
        return _eastmoney.fundPerformance();
      case 'finance_news':
        return _financeNews.fetch(context, input);
      case 'trade_calendar':
        return _tradeCalendar(input, context);
      case 'index_constituents':
        _requireProviderOverride(
          input['provider'] as String?,
          allowed: const {'tushare'},
          action: 'index_constituents',
        );
        return _tushare.fetchIndexConstituents(
          context,
          _firstSymbol(symbols, _indexConstituentsError),
          asOfDate:
              input['asOfDate'] as String? ??
              input['tradeDate'] as String? ??
              _reportDate(input),
        );
      case 'stock_company_info':
        return _eastmoney.stockCompanyInfo(
          _firstSymbol(symbols, _stockCompanyInfoError),
        );
      case 'stock_shareholders':
        return _eastmoney.stockShareholders(
          _firstSymbol(symbols, _stockShareholdersError),
          reportDate: _reportDate(input),
        );
      case 'stock_risk_metrics':
      case 'fund_company_info':
      case 'fund_investor_holders':
      case 'index_profile':
      case 'bond_profile':
      case 'bond_market_data':
        return _windStructured.run(
          action,
          _firstSymbol(
            symbols,
            'stock_risk_metrics/fund_company_info/fund_investor_holders/index_profile/bond_profile/bond_market_data requires symbols: ["600519"], ["110011"], ["000300"], or ["019521.SH"]',
          ),
          input,
          context,
        );
      case 'fund_financials':
      case 'index_fundamentals':
      case 'bond_issuer_financials':
        return _windStructured.run(
          action,
          _firstSymbol(
            symbols,
            'fund_financials/index_fundamentals/bond_issuer_financials requires symbols: ["110011"], ["000300"], or ["019521.SH"]',
          ),
          input,
          context,
        );
      case 'margin_trading':
        return _marginTrading.fetch(
          _firstSymbol(symbols, _marginTradingError),
          date: (input['date'] as String?) ?? (input['tradeDate'] as String?),
          provider: input['provider'] as String?,
        );
      case 'earnings':
        return _earnings.fetch(_firstSymbol(symbols, _earningsError), context);
      case 'scan':
        return _tradingview.scan(
          _firstSymbols(symbols, _scanError),
          input,
          context,
        );
      case 'price':
        return _yahoo.price(_firstSymbols(symbols, _priceError), context);
      case 'yahoo_history':
        return _yahoo.history(
          _firstSymbol(symbols, _yahooHistoryError),
          input,
          context,
        );
      case 'option_daily_kline':
        return _yahoo.optionDailyKline(
          _firstSymbol(symbols, _optionDailyKlineError),
          input,
          context,
        );
      case 'yahoo_earnings':
        return _yahoo.earnings(
          _firstSymbol(symbols, _yahooEarningsError),
          input,
          context,
        );
      case 'global_income_statement':
        return _yahoo.earningsSlice(
          _firstSymbol(symbols, _yahooEarningsError),
          input,
          context,
          interfaceId: 'global.income_statement',
          readbackDataset: 'income_statement',
          readbackAction: 'query_global_income_statement',
        );
      case 'global_balance_sheet':
        return _yahoo.earningsSlice(
          _firstSymbol(symbols, _yahooEarningsError),
          input,
          context,
          interfaceId: 'global.balance_sheet',
          readbackDataset: 'balance_sheet',
          readbackAction: 'query_global_balance_sheet',
        );
      case 'global_cash_flow':
        return _yahoo.earningsSlice(
          _firstSymbol(symbols, _yahooEarningsError),
          input,
          context,
          interfaceId: 'global.cash_flow',
          readbackDataset: 'cash_flow',
          readbackAction: 'query_global_cash_flow',
        );
      case 'global_quarterly_income_statement':
        return _yahoo.earningsSlice(
          _firstSymbol(symbols, _yahooEarningsError),
          input,
          context,
          interfaceId: 'global.quarterly_income_statement',
          readbackDataset: 'quarterly_income_statement',
          readbackAction: 'query_global_quarterly_income_statement',
        );
      case 'global_quarterly_balance_sheet':
        return _yahoo.earningsSlice(
          _firstSymbol(symbols, _yahooEarningsError),
          input,
          context,
          interfaceId: 'global.quarterly_balance_sheet',
          readbackDataset: 'quarterly_balance_sheet',
          readbackAction: 'query_global_quarterly_balance_sheet',
        );
      case 'global_quarterly_cash_flow':
        return _yahoo.earningsSlice(
          _firstSymbol(symbols, _yahooEarningsError),
          input,
          context,
          interfaceId: 'global.quarterly_cash_flow',
          readbackDataset: 'quarterly_cash_flow',
          readbackAction: 'query_global_quarterly_cash_flow',
        );
      case 'global_major_holders':
        return _yahoo.earningsSlice(
          _firstSymbol(symbols, _yahooEarningsError),
          input,
          context,
          interfaceId: 'global.major_holders',
          readbackDataset: 'major_holders',
          readbackAction: 'query_global_major_holders',
        );
      case 'yahoo_news':
        return _yahoo.news(
          _firstSymbols(symbols, _yahooNewsError),
          input,
          context,
        );
      case 'yahoo_options':
        return _yahoo.options(
          _firstSymbol(symbols, _yahooOptionsError),
          input,
          context,
        );
      case 'yahoo_actions':
        return _yahoo.actions(
          _firstSymbol(symbols, _yahooActionsError),
          input,
          context,
        );
      case 'global_capital_gains':
        return _yahoo.actionsSlice(
          _firstSymbol(symbols, _yahooActionsError),
          input,
          context,
          interfaceId: 'global.capital_gains',
          readbackDataset: 'capital_gains',
          readbackAction: 'query_global_capital_gains',
        );
      case 'limit_up':
        return _eastmoneyAdvanced.limitUp(input);
      case 'limit_down':
        return _eastmoneyAdvanced.limitDown(input);
      case 'hot_rank':
        return _eastmoneyAdvanced.hotRank(input);
      case 'dragon_tiger':
        return _eastmoneyAdvanced.dragonTiger(input);
      case 'northbound':
        return _eastmoneyAdvanced.northbound(input);
      case 'unusual':
        return _eastmoneyAdvanced.unusual(input);
      default:
        throw ArgumentError('Unsupported MarketData market action: $action');
    }
  }

  Future<Map<String, dynamic>> _quote(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    _rejectGlobalSymbolsForQuote(symbols);
    final interfaceId = _quoteInterfaceId(symbols);
    final policy = interfaceId == 'index.quote'
        ? const CachePolicy(mode: CachePolicyMode.liveOnly)
        : CachePolicy.fromInput(input, task: FinanceDataTask.quote);
    final result = await _resolveService.resolveQuotes(
      symbols,
      context: context,
      source: (input['source'] as String?) ?? (input['provider'] as String?),
      policy: policy,
    );
    return {
      'action': 'quote',
      'interfaceId': interfaceId,
      'canonicalSchema': 'quote_snapshot',
      'canonicalTable': 'quote_snapshot',
      'readbackAction': interfaceId == 'bond.convertible_quote'
          ? 'query_bond_quote'
          : interfaceId == 'index.quote'
          ? 'query_index_quote'
          : 'query_quote',
      'cacheStatus': result.source.startsWith('local ')
          ? 'local-hit'
          : 'provider-hit',
      'count': result.data.length,
      'source': result.source,
      'data': result.data.map((row) => row.toJson()).toList(),
    };
  }

  String _quoteInterfaceId(List<String> symbols) {
    if (symbols.isNotEmpty &&
        symbols.every((symbol) {
          final clean = _cleanCode(symbol);
          return RegExp(r'^(11|12)\d{4}$').hasMatch(clean);
        })) {
      return 'bond.convertible_quote';
    }
    if (symbols.isNotEmpty &&
        (symbols.every(
              (symbol) => symbol.trim().toUpperCase().startsWith('INDEX:'),
            ) ||
            (symbols.length > 1 &&
                symbols.every(
                  (symbol) =>
                      coreCnMarketIndexCodeSet.contains(_cleanCode(symbol)),
                )) ||
            symbols.every(
              (symbol) => unambiguousCoreCnMarketIndexCodes.contains(
                _cleanCode(symbol),
              ),
            ))) {
      return 'index.quote';
    }
    return 'stock.quote';
  }

  void _rejectGlobalSymbolsForQuote(List<String> symbols) {
    final globalSymbols = symbols.where(_isGlobalMarketSymbol).toList();
    if (globalSymbols.isEmpty) return;
    throw ArgumentError(
      'MarketData(action:"quote") is for A-share/index/local quote providers and cannot fetch global symbols: ${globalSymbols.join(", ")}. Use MarketData(action:"price", symbols:[...]) for Yahoo/global indices, US/HK stocks, ETFs, FX, and crypto, then reuse MarketData(action:"query_quote", symbols:[...]) for persisted global quote_snapshot rows.',
    );
  }

  bool _isGlobalMarketSymbol(String symbol) {
    final value = symbol.trim().toUpperCase();
    if (value.isEmpty) return false;
    if (RegExp(r'^\d{6}$').hasMatch(_cleanCode(value))) return false;
    if (value.startsWith('INDEX:')) return false;
    if (value.startsWith('^')) return true;
    if (value.contains('-USD') || value.endsWith('=X')) return true;
    if (value.endsWith('.HK') || value.endsWith('.US')) return true;
    if (RegExp(r'^[A-Z]{1,6}$').hasMatch(value)) return true;
    return false;
  }

  String _cleanCode(String value) {
    return value
        .replaceAll(RegExp(r'^(SH|SZ|BJ|CSI)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\.(SH|SZ|BJ|CSI)$', caseSensitive: false), '')
        .trim();
  }

  Future<Map<String, dynamic>> _kline(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    _rejectAmbiguousKlineSymbol(symbol);
    final period = input['period'] as String? ?? 'daily';
    if (period != 'daily') {
      throw ArgumentError(
        'MarketData(action:"kline") currently supports only governed daily K-line in FinAgent/shared-mobile; requested period "$period" is not registered with a canonical interface/readback path. Use period:"daily", yahoo_history for global daily ranges, or an explicit provider diagnostic action when validating a provider contract.',
      );
    }
    final result = await _resolveService.resolveKline(
      symbol,
      context: context,
      source: (input['source'] as String?) ?? (input['provider'] as String?),
      period: period,
      startDate: input['startDate'] as String? ?? '',
      endDate: input['endDate'] as String? ?? '',
      adjust: input['adjust'] as String? ?? 'qfq',
      policy: CachePolicy.fromInput(input, task: FinanceDataTask.kline),
    );
    final interfaceId = _klineInterfaceId(
      symbol,
      adjust: input['adjust'] as String? ?? 'qfq',
      source: (input['source'] as String?) ?? (input['provider'] as String?),
    );
    final provenance = {
      'interfaceId': interfaceId,
      'canonicalSchema': 'kline_daily',
      'canonicalTable': 'kline_daily',
      'readbackAction': interfaceId == 'bond.convertible_daily_kline'
          ? 'query_bond_kline'
          : 'query_kline',
      'cacheStatus': result.source.startsWith('local ')
          ? 'local-hit'
          : 'provider-hit',
    };
    if (result.bars.length > 60) {
      final preview = result.bars.sublist(result.bars.length - 5);
      return {
        'action': 'kline',
        'symbol': symbol,
        ...provenance,
        'source': result.source,
        'bars': result.bars.length,
        'range': '${result.bars.first.date} ~ ${result.bars.last.date}',
        'latest5': preview.map((row) => row.toJson()).toList(),
        'note':
            '${result.bars.length} bars total. Use narrower query limits or code-owned summary/optimizer actions for analysis instead of reading saved raw tool output.',
      };
    }
    return {
      'action': 'kline',
      'symbol': symbol,
      ...provenance,
      'source': result.source,
      'bars': result.bars.length,
      'data': result.bars.map((row) => row.toJson()).toList(),
    };
  }

  String _klineInterfaceId(String symbol, {String? adjust, String? source}) {
    final clean = _cleanCode(symbol);
    if (RegExp(r'^(11|12)\d{4}$').hasMatch(clean)) {
      return 'bond.convertible_daily_kline';
    }
    if (RegExp(
          r'^(510|512|513|515|516|518|588|589|159)\d{3}$',
        ).hasMatch(clean) &&
        (source != null || adjust == 'none')) {
      return 'fund.etf_daily_ohlcv_bars';
    }
    if (symbol.trim().toUpperCase().startsWith('INDEX:')) {
      return 'index.daily_kline';
    }
    return 'stock.daily_kline';
  }

  void _rejectAmbiguousKlineSymbol(String symbol) {
    final text = symbol.trim().toUpperCase();
    if (_cleanCode(text) != '000001') return;
    if (text.startsWith('INDEX:') ||
        text.startsWith('SH') ||
        text.startsWith('SZ') ||
        text.endsWith('.SH') ||
        text.endsWith('.SZ')) {
      return;
    }
    throw ArgumentError(
      'MarketData(action:"kline") received ambiguous symbol "000001". Use "INDEX:000001" for the Shanghai Composite index daily K-line, or "SZ000001" / "000001.SZ" for Ping An Bank stock K-line.',
    );
  }

  Future<Map<String, dynamic>> _fundDividendFactor(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final limit = _intValue(input['limit']) ?? 240;
    final result = await _router.runCapability<Map<String, dynamic>>(
      interfaceId: 'fund.dividend_factor',
      constraint: _constraintFromInput(input),
      cachePolicy: CachePolicy.fromInput(input, task: FinanceDataTask.fund),
      readCache: () async {
        final rows = _dataManager.queryFundDividendFactor(
          symbol,
          startDate: input['startDate'] as String? ?? '',
          endDate: input['endDate'] as String? ?? '',
          limit: limit,
        );
        if (rows.isEmpty) return null;
        return DataApiLocalCacheResult(
          data: {
            'action': 'query_fund_dividend_factor',
            'symbol': symbol,
            'count': rows.length,
            'data': rows,
          },
        );
      },
      call: (capability) async {
        if (capability.provider != FinanceProvider.sina) return null;
        final rows = await _sinaFetcher.getFundDividendFactors(
          symbol,
          limit: limit,
        );
        _dataManager.saveFundDividendFactors(
          symbol,
          rows,
          source: '新浪财经:fund_dividend_factor',
        );
        final readbackRows = _dataManager.queryFundDividendFactor(
          symbol,
          startDate: input['startDate'] as String? ?? '',
          endDate: input['endDate'] as String? ?? '',
          limit: limit,
        );
        return DataApiProviderExecution(
          data: {
            'action': 'fund_dividend_factor',
            'source': '新浪财经:fund_dividend_factor',
            'symbol': symbol,
            'count': readbackRows.length,
            'data': readbackRows,
          },
          source: '新浪财经:fund_dividend_factor',
          providerName: '新浪财经',
        );
      },
      isUsable: (value) {
        final count = value['count'];
        if (count is num) return count > 0;
        final data = value['data'];
        return data is List && data.isNotEmpty;
      },
      emptyMessage: 'returned no reusable fund_dividend_factor rows',
      failureMessage: 'All fund.dividend_factor providers failed',
    );
    return {
      ...result.data,
      'action': 'fund_dividend_factor',
      'source': result.source,
      'interfaceId': result.provenance.interfaceId,
      'capabilityId': result.provenance.capabilityId,
      'provider': result.provenance.provider,
      'canonicalSchema': result.provenance.canonicalSchema,
      'canonicalTable': result.provenance.canonicalTable,
      'readbackAction': 'query_fund_dividend_factor',
      'cacheStatus': result.provenance.cacheStatus,
      'cachePolicyMode': result.provenance.cachePolicyMode,
      'cacheDecision': result.provenance.cacheDecision,
      ...result.provenance.routePolicyJson(),
      'provenance': result.provenance.toJson(),
    };
  }

  Future<Map<String, dynamic>> _tradeCalendar(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final service = _tradeCalendarServiceFactory(context.basePath);
    final constraint = _constraintFromInput(input);
    final policy = CachePolicy.fromInput(input, task: FinanceDataTask.fund);
    final year = _intValue(input['year']);
    final result = await service.fetchRange(
      year: year,
      startDate: input['startDate'] as String? ?? input['start'] as String?,
      endDate: input['endDate'] as String? ?? input['end'] as String?,
      market: (input['market'] as String?)?.trim().toUpperCase() ?? 'CN',
      policy: policy,
      constraint: constraint,
    );
    final rows = result.rows;
    final sourceDataTime = rows.isEmpty ? null : '${rows.last['date'] ?? ''}';
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    return {
      'action': 'trade_calendar',
      if (year != null) 'year': year,
      if (input['startDate'] != null || input['start'] != null)
        'startDate': input['startDate'] ?? input['start'],
      if (input['endDate'] != null || input['end'] != null)
        'endDate': input['endDate'] ?? input['end'],
      'market': (input['market'] as String?)?.trim().toUpperCase() ?? 'CN',
      ...result.provenance.toJson(),
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      'fetchedAt': fetchedAt,
      'count': rows.length,
      'source': result.provenance.providerName,
      'data': rows.take(120).toList(growable: false),
      if (rows.length > 120)
        'note':
            'Showing first 120 of ${rows.length} trade calendar rows. Use query_trade_calendar for reusable readback.',
    };
  }
}

String _firstSymbol(List<String> symbols, String error) {
  if (symbols.isEmpty) throw ArgumentError(error);
  return symbols.first;
}

List<String> _firstSymbols(List<String> symbols, String error) {
  if (symbols.isEmpty) throw ArgumentError(error);
  return symbols;
}

const _quoteError =
    'symbols required for quote. Example: MarketData(action: "quote", symbols: ["600519", "000001"])';
const _klineError =
    'symbols required for kline. Example: MarketData(action: "kline", symbols: ["600519"], period: "daily", startDate: "2024-01-01")';
const _flowError =
    'symbols required for flow. Example: MarketData(action: "flow", symbols: ["600519"])';
const _chipError =
    'symbols required for chip. Example: MarketData(action: "chip", symbols: ["600519"])';
const _fundNavError =
    'fundCode required for fund_nav. Example: MarketData(action:"fund_nav", symbols:["110011.OF"]) or MarketData(action:"fund_nav", fundCode:"110011.OF")';
const _fundMoneyYieldError =
    'fundCode required for fund_money_yield. Example: MarketData(action:"fund_money_yield", symbols:["000009"]) or MarketData(action:"fund_money_yield", fundCode:"000009")';
const _fundDividendFactorError =
    'fund code required for fund_dividend_factor. Example: MarketData(action:"fund_dividend_factor", symbols:["510050"])';
const _fundHoldingError =
    'fundCode required for fund_holding. Example: MarketData(action:"fund_holding", symbols:["110011"]) or MarketData(action:"fund_holding", fundCode:"110011")';
const _indexConstituentsError =
    'symbols required for index_constituents. Example: MarketData(action:"index_constituents", symbols:["000300"], asOfDate:"2026-06-18")';
const _stockCompanyInfoError =
    'symbol required for stock_company_info. Example: MarketData(action:"stock_company_info", symbols:["600519"])';
const _stockShareholdersError =
    'symbol required for stock_shareholders. Example: MarketData(action:"stock_shareholders", symbols:["600519"], reportDate:"2026-03-31")';

String? _reportDate(Map<String, dynamic> input) {
  final value = input['reportDate'] ?? input['date'];
  if (value == null) return null;
  final text = '$value'.trim().replaceAll('/', '-');
  if (text.length == 8 && !text.contains('-')) {
    return '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6, 8)}';
  }
  return text.isEmpty ? null : text;
}

const _marginTradingError =
    'symbols required for margin_trading. Example: MarketData(action:"margin_trading", symbols:["600519"], date:"2024-04-11")';
const _earningsError =
    'symbols required. Example: MarketData(action:"earnings", symbols:["000858"])';
const _scanError =
    'symbols required for scan. Example: MarketData(action: "scan", symbols: ["NASDAQ:AAPL"])';
const _priceError =
    'symbols required for price. Example: MarketData(action: "price", symbols: ["AAPL", "BTC-USD"])';
const _yahooHistoryError =
    'symbols required for yahoo_history. Example: MarketData(action:"yahoo_history", symbols:["AAPL"], period:"6mo")';
const _optionDailyKlineError =
    'symbols required for option_daily_kline. Example: MarketData(action:"option_daily_kline", symbols:["AAPL260619C00100000"], period:"6mo")';
const _yahooEarningsError =
    'symbols required for yahoo_earnings. Example: MarketData(action:"yahoo_earnings", symbols:["AAPL"])';
const _yahooNewsError =
    'symbols required for yahoo_news. Example: MarketData(action:"yahoo_news", symbols:["AAPL"], limit:10)';
const _yahooOptionsError =
    'symbols required for yahoo_options. Example: MarketData(action:"yahoo_options", symbols:["AAPL"], expiry:"2026-06-19")';
const _yahooActionsError =
    'symbols required for yahoo_actions. Example: MarketData(action:"yahoo_actions", symbols:["AAPL"], period:"5y")';

String _fundCode(List<String> symbols, Map<String, dynamic> input) {
  final explicit =
      (input['fundCode'] as String?) ??
      (input['code'] as String?) ??
      (input['symbol'] as String?);
  final resolved = (explicit != null && explicit.trim().isNotEmpty)
      ? explicit.trim()
      : (symbols.isNotEmpty ? symbols.first : '');
  if (resolved.isEmpty) {
    throw ArgumentError(_fundHoldingError);
  }
  return resolved;
}

String _fundNavCode(List<String> symbols, Map<String, dynamic> input) {
  final explicit =
      (input['fundCode'] as String?) ??
      (input['code'] as String?) ??
      (input['symbol'] as String?);
  final resolved = (explicit != null && explicit.trim().isNotEmpty)
      ? explicit.trim()
      : (symbols.isNotEmpty ? symbols.first : '');
  if (resolved.isEmpty) {
    throw ArgumentError(_fundNavError);
  }
  return resolved.toUpperCase().endsWith('.OF') ? resolved : '$resolved.OF';
}

String _fundMoneyYieldCode(List<String> symbols, Map<String, dynamic> input) {
  final explicit =
      (input['fundCode'] as String?) ??
      (input['code'] as String?) ??
      (input['symbol'] as String?);
  final resolved = (explicit != null && explicit.trim().isNotEmpty)
      ? explicit.trim()
      : (symbols.isNotEmpty ? symbols.first : '');
  if (resolved.isEmpty) {
    throw ArgumentError(_fundMoneyYieldError);
  }
  return resolved;
}

DataApiProviderConstraint _constraintFromInput(Map<String, dynamic> input) {
  final rawProvider = input['provider'] ?? input['source'];
  final providers = rawProvider == null
      ? const <FinanceProvider>[]
      : const ProviderPolicy().normalizeProviders(rawProvider);
  final provider = providers.isEmpty ? null : providers.first;
  final providerMode = switch ('${input['providerMode'] ?? ''}') {
    'strict' => DataApiProviderMode.strict,
    'preferred' => DataApiProviderMode.preferred,
    _ =>
      provider == null ? DataApiProviderMode.auto : DataApiProviderMode.strict,
  };
  return DataApiProviderConstraint(
    provider: provider,
    providerMode: providerMode,
    allowFallback: input['allowFallback'] is bool
        ? input['allowFallback'] as bool
        : true,
    allowDegraded: input['allowDegraded'] is bool
        ? input['allowDegraded'] as bool
        : false,
  );
}

int? _intValue(Object? value) {
  if (value is int) return value;
  return int.tryParse('${value ?? ''}'.trim());
}

void _requireProviderOverride(
  String? provider, {
  required Set<String> allowed,
  required String action,
}) {
  if (provider == null || provider.trim().isEmpty) return;
  final normalized = provider.trim().toLowerCase();
  if (allowed.contains(normalized)) return;
  throw ArgumentError(
    '$action only supports provider overrides: ${allowed.join(", ")}. Received: $provider',
  );
}
