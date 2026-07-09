import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/api_stats.dart';
import '../../../agent/data_fetcher/models.dart';
import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../../../agent/tool_context.dart';
import '../analysis/analysis_evidence_contract.dart';
import '../market_index_universe.dart';
import 'eastmoney_advanced_service.dart';
import 'eastmoney_market_data_service.dart';
import 'market_data_read_service.dart';
import 'macro_research_extraction.dart';
import 'macro_numeric_series_catalog.dart';
import 'macro_research_source_catalog.dart';
import 'raw_payload_query_service.dart';
import 'tdx_market_data_query_service.dart';
import 'tushare_market_data_service.dart';
import 'wind_market_data_service.dart';
import 'yahoo_market_data_service.dart';

part 'market_data_query_action_local_readbacks.dart';
part 'market_data_query_action_provenance_readbacks.dart';
part 'market_data_query_action_yahoo_readbacks.dart';

class MarketDataQueryActionService {
  final MarketDataReadService _readService;
  final DataManager? _dataManager;
  TushareMarketDataService? _tushare;
  final WindMarketDataService _wind;
  final YahooMarketDataService _yahoo;
  final EastmoneyMarketDataService _eastmoney;
  final EastmoneyAdvancedService _eastmoneyAdvanced;
  final TdxMarketDataQueryService _tdx;
  final RawPayloadQueryService _rawPayload;

  MarketDataQueryActionService({
    DataManager? dataManager,
    MarketDataReadService? readService,
    TushareMarketDataService? tushare,
    WindMarketDataService? wind,
    YahooMarketDataService? yahoo,
    EastmoneyMarketDataService? eastmoney,
    EastmoneyAdvancedService? eastmoneyAdvanced,
    TdxMarketDataQueryService? tdx,
    RawPayloadQueryService? rawPayload,
  }) : _dataManager = dataManager,
       _readService =
           readService ?? MarketDataReadService(dataManager: dataManager),
       _tushare = tushare,
       _wind = wind ?? WindMarketDataService(dataManager: dataManager),
       _yahoo = yahoo ?? YahooMarketDataService(dataManager: dataManager),
       _eastmoney =
           eastmoney ?? EastmoneyMarketDataService(dataManager: dataManager),
       _eastmoneyAdvanced =
           eastmoneyAdvanced ??
           EastmoneyAdvancedService(dataManager: dataManager),
       _tdx = tdx ?? TdxMarketDataQueryService(dataManager: dataManager),
       _rawPayload =
           rawPayload ?? RawPayloadQueryService(dataManager: dataManager);

  Map<String, dynamic> query(
    String action,
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    switch (action) {
      case 'market_activity_summary':
        return _marketActivitySummary(input, context);
      case 'query_quote':
        if (symbols.length > 1) {
          if (_isCommonMarketIndexQuoteBasket(symbols)) {
            return _queryIndexQuoteBasket(symbols, input, context);
          }
          return _queryQuoteBatch(action, symbols, input, context);
        }
        return _queryQuote(
          action,
          _firstSymbol(symbols, _quoteError),
          input,
          context,
        );
      case 'query_etf_quote':
      case 'query_listed_fund_quote':
      case 'query_bond_quote':
        return _queryQuote(
          action,
          _firstSymbol(symbols, _quoteError),
          input,
          context,
        );
      case 'query_index_quote':
        if (symbols.isEmpty) {
          return _queryIndexQuoteOverview(input, context);
        }
        return _queryIndexQuoteRows(
          symbols.map(_cleanQuoteCode).toList(),
          input,
          context,
          action: action,
          emptyDecision:
              'cacheFirst strict index quote read found no reusable quote_snapshot rows for the requested index symbols',
        );
      case 'query_kline':
        return _queryKline(_firstSymbol(symbols, _klineError), input, context);
      case 'query_bond_kline':
        return _queryKline(_firstSymbol(symbols, _klineError), {
          ...input,
          '_queryAction': action,
          'adjust': input['adjust'] ?? 'none',
        }, context);
      case 'query_fundamental':
        return _requireTushare().queryFundamental(
          context,
          _firstSymbol(symbols, _fundamentalError),
          input: input,
          limit: _inputLimit(input, 8),
        );
      case 'query_stock_daily_valuation':
        if (symbols.isEmpty) {
          return _requireTushare().queryFundamentalSample(
            context,
            input: input,
            limit: _inputLimit(input, 50),
          );
        }
        return _requireTushare().queryFundamental(
          context,
          _firstSymbol(symbols, _stockDailyValuationError),
          input: input,
          limit: _inputLimit(input, 8),
          action: 'query_stock_daily_valuation',
        );
      case 'query_fund_financials':
        return _queryWindFundamentalReadback(
          symbols,
          input,
          context,
          action: 'query_fund_financials',
          interfaceId: 'fund.financials',
        );
      case 'query_index_fundamentals':
        return _queryWindFundamentalReadback(
          symbols,
          input,
          context,
          action: 'query_index_fundamentals',
          interfaceId: 'index.fundamentals',
        );
      case 'query_bond_issuer_financials':
        return _queryWindFundamentalReadback(
          symbols,
          input,
          context,
          action: 'query_bond_issuer_financials',
          interfaceId: 'bond.issuer_financials',
        );
      case 'query_money_flow':
        return _requireTushare().queryMoneyFlow(
          context,
          _firstSymbol(symbols, _moneyFlowError),
          input: input,
          limit: _inputLimit(input, 30),
        );
      case 'query_fund_nav':
        return _queryFundNav(symbols, input, context);
      case 'query_fund_money_yield':
        return _requireTushare().queryFundMoneyYield(
          context,
          _firstSymbol(symbols, _fundMoneyYieldError),
          input: input,
          startDate: input['startDate'] as String? ?? '',
          endDate: input['endDate'] as String? ?? '',
          limit: (input['limit'] as num?)?.toInt(),
        );
      case 'query_fund_dividend_factor':
        return _requireTushare().queryFundDividendFactor(
          context,
          _firstSymbol(symbols, _fundDividendFactorError),
          input: input,
          startDate: input['startDate'] as String? ?? '',
          endDate: input['endDate'] as String? ?? '',
          limit: (input['limit'] as num?)?.toInt(),
        );
      case 'query_intraday_ohlcv_bars':
        return _requireTushare().queryIntradayOhlcvBars(
          context,
          _firstSymbol(symbols, _intradayOhlcvError),
          input: input,
          startDate: input['startDate'] as String? ?? '',
          endDate: input['endDate'] as String? ?? '',
          intervalMinutes:
              (input['intervalMinutes'] as num?)?.toInt() ??
              (input['scale'] as num?)?.toInt() ??
              5,
          limit: (input['limit'] as num?)?.toInt(),
        );
      case 'query_fund_list':
        return _queryFundList(symbols, input, context);
      case 'query_fund_manager':
        return _queryFundManager(symbols, input, context);
      case 'query_finance_news':
        return _queryFinanceNews(input, context);
      case 'query_fund_holding':
        return _queryFundHolding(symbols, input, context);
      case 'query_index_constituents':
        return _queryIndexConstituents(symbols, input, context);
      case 'query_fund_performance':
        return _queryFundPerformance(symbols, input, context);
      case 'query_trade_calendar':
        return _requireTushare().queryTradeCalendar(
          context,
          market: input['market'] as String?,
          start: input['start'] as String? ?? input['startDate'] as String?,
          end: input['end'] as String? ?? input['endDate'] as String?,
          limit: _inputLimit(input, 100),
        );
      case 'query_stock_list':
        return _requireTushare().queryStockList(
          context,
          market: input['market'] as String?,
          industry: input['industry'] as String?,
          stockType: input['stockType'] as String? ?? input['type'] as String?,
          keyword: input['keyword'] as String? ?? input['query'] as String?,
          limit: _inputLimit(input, 50),
        );
      case 'query_board_members':
      case 'query_sector_constituents':
      case 'query_industry_map':
      case 'query_board_ranking':
      case 'query_sector_ranking':
      case 'query_sector':
        return _eastmoney.queryAction(action, symbols, input, context);
      case 'query_chip':
        _firstSymbol(symbols, _chipError);
        return _eastmoney.queryAction(action, symbols, input, context);
      case 'query_market_screening':
        return _queryMarketScreening(symbols, input, context);
      case 'query_margin_trading':
        return _queryMarginTrading(symbols, input, context);
      case 'query_alpha_factors':
        return _queryAlphaFactors(symbols, input, context);
      case 'query_technical_indicator':
        return _queryTechnicalIndicator(symbols, input, context);
      case 'query_ex_categories':
      case 'query_tdx_count':
      case 'query_tdx_sampling':
      case 'query_ex_table':
      case 'query_tick_chart':
      case 'query_transactions':
      case 'query_volume_profile':
      case 'query_xdxr':
      case 'query_auction':
      case 'query_momentum':
      case 'query_top_board':
      case 'query_tdx_block_member':
      case 'query_stock_company_info':
      case 'query_company_info':
      case 'query_fund_company_info':
      case 'query_fund_investor_holders':
      case 'query_index_profile':
        _requireTdxQuerySymbol(action, symbols);
        return _tdx.queryAction(action, symbols, {
          ...input,
          '_queryAction': action,
        }, context);
      case 'query_bond_profile':
      case 'query_bond_market_data':
        return _queryWindCompanyInfoReadback(
          symbols,
          input,
          context,
          action: action,
          interfaceId: action == 'query_bond_profile'
              ? 'bond.profile'
              : 'bond.market_data',
          defaultInfoType: action == 'query_bond_profile'
              ? 'get_bond_basicinfo'
              : 'get_bond_market_data',
        );
      case 'query_stock_risk_metrics':
        return _queryWindCompanyInfoReadback(
          symbols,
          input,
          context,
          action: 'query_stock_risk_metrics',
          interfaceId: 'stock.risk_metrics',
          defaultInfoType: 'get_risk_metrics',
        );
      case 'query_stock_shareholders':
        return _queryStockShareholders(symbols, input, context);
      case 'query_hot_rank':
      case 'query_dragon_tiger':
      case 'query_limit_pool':
      case 'query_northbound':
      case 'query_northbound_flow':
      case 'query_northbound_holding':
      case 'query_unusual':
      case 'query_flow_rank':
        return _eastmoneyAdvanced.queryAction(action, symbols, input, context);
      case 'query_wind_document':
        return _wind.queryDocuments(
          context,
          input,
          limit: _inputLimit(input, 50),
        );
      case 'query_wind_economic':
        return _wind.queryEconomic(
          context,
          input,
          limit: _inputLimit(input, 100),
        );
      case 'query_wind_analytics':
        return _wind.queryAnalytics(
          context,
          input,
          limit: _inputLimit(input, 100),
        );
      case 'query_yfinance':
        return _yahoo.queryDataset(
          context,
          _firstSymbol(symbols, _yfinanceError),
          input,
        );
      case 'query_global_company_profile':
      case 'query_global_financial_statements':
      case 'query_global_income_statement':
      case 'query_global_balance_sheet':
      case 'query_global_cash_flow':
      case 'query_global_earnings_calendar':
      case 'query_global_earnings_history':
      case 'query_global_earnings_estimates':
      case 'query_global_eps_revisions':
      case 'query_global_eps_trend':
      case 'query_global_quarterly_financial_statements':
      case 'query_global_quarterly_income_statement':
      case 'query_global_quarterly_balance_sheet':
      case 'query_global_quarterly_cash_flow':
      case 'query_global_recommendations':
      case 'query_global_upgrade_downgrade_events':
      case 'query_global_holders':
      case 'query_global_major_holders':
      case 'query_global_institutional_holders':
      case 'query_global_mutual_fund_holders':
      case 'query_global_insider_transactions':
      case 'query_global_finance_news':
      case 'query_global_corporate_actions':
      case 'query_global_dividends':
      case 'query_global_capital_gains':
      case 'query_global_stock_splits':
      case 'query_option_expiry_calendar':
      case 'query_option_contract_list':
      case 'query_option_quote':
      case 'query_option_open_interest':
      case 'query_option_volume':
      case 'query_option_implied_volatility':
      case 'query_option_moneyness':
      case 'query_option_bid_ask_spread':
      case 'query_option_price_change':
      case 'query_option_trade_recency':
      case 'query_option_chain_snapshot':
      case 'query_global_options_chain':
        return _queryYahooReadbackAction(action, symbols, input, context);
      case 'query_option_daily_kline':
        return _queryKline(_firstSymbol(symbols, _quoteError), {
          ...input,
          '_queryAction': action,
          'adjust': 'none',
        }, context);
      case 'query_macro_factors':
        return _queryMacroFactors(input, context);
      case 'query_macro_attribution':
        return queryMacroAttribution(_storeForContext(context), input);
      case 'query_macro_numeric_series':
        return _queryMacroNumericSeries(input, context);
      case 'macro_numeric_series_catalog':
        return macroNumericSeriesCatalog(input);
      case 'macro_research_sources':
        return macroResearchSources(input);
      case 'macro_research_provenance':
        return macroResearchProvenance(_storeForContext(context), input);
      case 'macro_research_extraction_status':
        return macroResearchExtractionStatus(input);
      case 'query_macro_research_content':
        return queryMacroResearchContent(_storeForContext(context), input);
      case 'query_macro_research_evidence':
        return queryMacroResearchEvidence(_storeForContext(context), input);
      case 'query_raw_payload':
        return _rawPayload.query(context, input, limit: _inputLimit(input, 20));
      case 'query_api_calls':
      case 'query_api_errors':
        return _queryApiCalls(action, input);
      default:
        throw ArgumentError('Unsupported MarketData query action: $action');
    }
  }

  Map<String, dynamic> _queryMacroFactors(
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final store = _storeForContext(context);
    final families = macroFactorFamilies(input);
    final rows =
        store?.queryMarketMovingFactors(
          family: families == null ? _clean(input['family']) : null,
          families: families,
          status: _clean(input['status']),
          source: _clean(input['source']),
          target: _clean(
            input['target'] ??
                input['symbol'] ??
                input['code'] ??
                input['query'],
          ),
          assets: _list(input['assets']),
          regions: _list(input['regions'] ?? input['market']),
          sectors: _list(input['sectors'] ?? input['industry']),
          limit: _inputLimit(input, 20),
        ) ??
        const <Map<String, dynamic>>[];
    return {
      'action': 'query_macro_factors',
      'count': rows.length,
      'status': rows.isEmpty ? 'missing' : 'ok',
      if (rows.isEmpty)
        'missingReason':
            'No market_moving_factor rows matched the requested structured target/family/status filters. Treat this as an explicit macro-evidence gap, not as proof that macro factors are irrelevant.',
      'provenance': {
        'interfaceId': 'macro.factor_radar',
        'providerId': 'local',
        'provider': 'local',
        'capabilityId': 'local.query_macro_factors',
        'providerMode': 'local-evidence',
        'cacheStatus': 'local-readback',
        'cacheDecision':
            'read governed market_moving_factor rows before using macro context in analysis',
        'canonicalSchema': 'market_moving_factor_v1',
        'canonicalTable': 'market_moving_factor',
        'readbackAction': 'query_macro_factors',
        'source': 'local market_moving_factor',
        'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      },
      'rows': rows,
    };
  }

  Map<String, dynamic> _queryMacroNumericSeries(
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final store = _storeForContext(context);
    final rows =
        store
            ?.queryMarketMovingFactors(
              families: const [
                'macro_calendar',
                'macro_series',
                'rates_liquidity',
                'macro_official_series',
              ],
              status: _clean(input['status']),
              source: _numericSourceFilter(input),
              target: _clean(
                input['target'] ??
                    input['seriesId'] ??
                    input['metric'] ??
                    input['query'],
              ),
              assets: _list(input['assets']),
              regions: _list(input['regions'] ?? input['market']),
              sectors: _list(input['sectors'] ?? input['industry']),
              limit: _inputLimit(input, 40),
            )
            .where(_isNumericMacroRow)
            .map(_numericSeriesRow)
            .toList() ??
        const <Map<String, dynamic>>[];
    return {
      'action': 'query_macro_numeric_series',
      'count': rows.length,
      'status': rows.isEmpty ? 'missing' : 'ok',
      if (rows.isEmpty)
        'missingReason':
            'No official numeric macro series rows matched the requested filters. Run the macro factor refresh for configured providers or inspect macro_research_sources for credential/access limits.',
      'provenance': {
        'interfaceId': 'macro.official_series',
        'providerId': 'local',
        'provider': 'local',
        'capabilityId': 'local.query_macro_numeric_series',
        'providerMode': 'official-series-readback',
        'cacheStatus': 'local-readback',
        'cacheDecision':
            'read official numeric macro series separately from research narratives and policy/index events',
        'canonicalSchema': 'market_moving_factor_v1',
        'canonicalTable': 'market_moving_factor',
        'readbackAction': 'query_macro_numeric_series',
        'source': 'local official macro series rows',
        'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      },
      'series': rows,
    };
  }

  String? _numericSourceFilter(Map<String, dynamic> input) {
    final raw = _clean(input['source'] ?? input['provider']);
    if (raw == null) return null;
    const known = {
      'fred': 'FRED',
      'bls': 'BLS',
      'bea': 'BEA',
      'eia': 'EIA',
      'wind': 'Wind',
      'imf': 'IMF',
      'world_bank': 'World Bank',
      'worldbank': 'World Bank',
      'oecd': 'OECD',
      'nbs': 'NBS China',
      'nbs_china': 'NBS China',
      'stats_china': 'NBS China',
    };
    return known[raw.toLowerCase()] ?? raw;
  }

  bool _isNumericMacroRow(Map<String, dynamic> row) {
    final values = row['macro_values'];
    final retrieval = row['retrieval_test'];
    final sourceType = '${row['source_type'] ?? ''}';
    final family = '${row['family'] ?? ''}';
    final provider =
        '${retrieval is Map ? retrieval['provider'] : row['source_name'] ?? ''}'
            .toLowerCase();
    final hasValue =
        values is Map &&
        (values.containsKey('actual') || values.containsKey('text'));
    final knownProvider = [
      'fred',
      'bls',
      'bea',
      'eia',
      'oecd',
      'imf',
      'world bank',
      'wind',
      'nbs china',
    ].any(provider.contains);
    return sourceType == 'official_api' ||
        family == 'macro_official_series' ||
        family == 'macro_series' ||
        (knownProvider && hasValue);
  }

  Map<String, dynamic> _numericSeriesRow(Map<String, dynamic> row) {
    final values = row['macro_values'] is Map
        ? Map<String, dynamic>.from(row['macro_values'] as Map)
        : <String, dynamic>{};
    final retrieval = row['retrieval_test'] is Map
        ? Map<String, dynamic>.from(row['retrieval_test'] as Map)
        : <String, dynamic>{};
    final raw = row['raw_json'] is Map
        ? Map<String, dynamic>.from(row['raw_json'] as Map)
        : <String, dynamic>{};
    return {
      'seriesId': _seriesIdForRow(row, values, retrieval, raw),
      'metricName':
          row['title'] ?? raw['metric_name'] ?? raw['LineDescription'],
      'provider': retrieval['provider'] ?? row['source_name'],
      'sourceName': row['source_name'],
      'value': values['actual'] ?? values['text'],
      'unit': values['unit'] ?? raw['CL_UNIT'] ?? raw['unit'],
      'frequency': raw['Frequency'] ?? raw['frequency'],
      'sourceDataTime':
          values['period'] ?? row['source_published_at'] ?? row['event_at'],
      'releaseDate': row['source_published_at'] ?? row['event_at'],
      'fetchedAt': row['fetched_at'] ?? values['retrievedAt'],
      'status': row['status'],
      'failureClass': row['failure_class'],
      'sourceUrl': row['source_url'],
      'family': row['family'],
      'provenance': {
        'interfaceId': 'macro.official_series',
        'provider': retrieval['provider'] ?? row['source_name'],
        'capabilityId': retrieval['capability_id'],
        'canonicalSchema': 'market_moving_factor_v1',
        'canonicalTable': 'market_moving_factor',
        'sourceType': row['source_type'],
        'retrievalStatus': retrieval['status'],
      },
    };
  }

  String _seriesIdForRow(
    Map<String, dynamic> row,
    Map<String, dynamic> values,
    Map<String, dynamic> retrieval,
    Map<String, dynamic> raw,
  ) {
    final capability = '${retrieval['capability_id'] ?? ''}';
    if (capability.contains('fred')) return 'DGS10';
    if (capability.contains('bls')) return 'CUUR0000SA0';
    if (capability.contains('bea')) return 'NIPA:T10101';
    if (capability.contains('world_bank')) return 'NY.GDP.MKTP.CD';
    if (capability.contains('imf')) return 'NGDP_RPCH';
    if (capability.contains('oecd')) {
      return 'DF_QNA_EXPENDITURE_GROWTH_OECD:B1GQ:OECD:GCM';
    }
    if (capability.contains('eia')) return 'WCESTUS1';
    final sourceName = '${row['source_name'] ?? ''}'.toLowerCase();
    final factorId = '${row['factor_id'] ?? ''}'.toLowerCase();
    if (capability.contains('nbs china') ||
        capability.contains('nbs_china') ||
        sourceName.contains('nbs china') ||
        factorId.contains('nbs_china')) {
      return 'NBS_EASYQUERY_PENDING';
    }
    return '${raw['series_key'] ?? raw['metric_code'] ?? values['seriesId'] ?? row['factor_id'] ?? 'macro.series'}';
  }

  String? _clean(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  List<String>? _list(Object? value) {
    if (value is Iterable) {
      final items = value
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      return items.isEmpty ? null : items;
    }
    final text = _clean(value);
    if (text == null) return null;
    final items = text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return items.isEmpty ? null : items;
  }

  Map<String, dynamic> _marketActivitySummary(
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final limit = _inputLimit(input, 12);
    final hotRank = _eastmoneyAdvanced.queryAction('query_hot_rank', const [], {
      'limit': limit,
    }, context);
    final flowRank = _eastmoneyAdvanced.queryAction(
      'query_flow_rank',
      const [],
      {'limit': limit},
      context,
    );
    final limitPool = _eastmoneyAdvanced.queryAction(
      'query_limit_pool',
      const [],
      {'limit': limit},
      context,
    );
    final unusual = _eastmoneyAdvanced.queryAction('query_unusual', const [], {
      'limit': limit,
    }, context);
    final dragonTiger = _eastmoneyAdvanced.queryAction(
      'query_dragon_tiger',
      const [],
      {'limit': limit},
      context,
    );
    final parts = [hotRank, flowRank, limitPool, unusual, dragonTiger];
    final sourceTimes = parts
        .map((part) => part['sourceDataTime'])
        .whereType<Object>()
        .map((value) => '$value')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final fetchedTimes = parts
        .map((part) => part['fetchedAt'])
        .whereType<Object>()
        .map((value) => '$value')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return {
      'action': 'market_activity_summary',
      'interfaceId': 'market.activity_summary',
      'provider': 'local',
      'capabilityId': 'local.market.activity_summary',
      'cacheStatus': parts.any((part) => part['cacheStatus'] == 'cache-hit')
          ? 'cache-hit'
          : 'cache-miss',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'canonicalSchema':
          'hot_rank|flow_rank|limit_pool|unusual_activity|dragon_tiger',
      'readbackActions': const [
        'query_hot_rank',
        'query_flow_rank',
        'query_limit_pool',
        'query_unusual',
        'query_dragon_tiger',
      ],
      if (sourceTimes.isNotEmpty) 'sourceDataTimes': sourceTimes,
      if (fetchedTimes.isNotEmpty) 'fetchedAtTimes': fetchedTimes,
      'limit': limit,
      'workflowHint':
          'This bounded summary is the first-pass evidence for broad market activity. Answer from it before live refresh; disclose empty sections as limitations.',
      'sections': {
        'hotRank': hotRank,
        'flowRank': flowRank,
        'limitPool': limitPool,
        'unusual': unusual,
        'dragonTiger': dragonTiger,
      },
    };
  }

  TushareMarketDataService _requireTushare() {
    return _tushare ??= TushareMarketDataService(dataManager: _dataManager);
  }

  Map<String, dynamic> _queryKline(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final adjust = input['adjust'] as String? ?? 'qfq';
    final providerConstraint = _providerCacheConstraint(input);
    final requestedLimit = (input['limit'] as num?)?.toInt();
    final effectiveLimit = _boundedKlineReadbackLimit(requestedLimit);
    final rows = _queryPersistedKlineWithConstraint(
      this,
      context,
      symbol,
      startDate: input['startDate'] as String? ?? '',
      endDate: input['endDate'] as String? ?? '',
      adjust: adjust,
      limit: effectiveLimit,
      constraint: providerConstraint,
    );
    return {
      'action': input['_queryAction'] ?? 'query_kline',
      'symbol': symbol,
      'adjust': adjust,
      'interfaceId': _resolveKlineReadback(
        input['_queryAction'] as String? ?? 'query_kline',
        symbol: symbol,
      ),
      'provider': 'local',
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no kline_daily rows matched the requirement'
                : 'cacheFirst read reusable local data; no kline_daily rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable kline_daily rows',
      'canonicalSchema': 'kline_daily',
      'canonicalTable': 'kline_daily',
      'count': rows.length,
      'requestedLimit': ?requestedLimit,
      if (effectiveLimit != requestedLimit) 'effectiveLimit': effectiveLimit,
      if (effectiveLimit != requestedLimit)
        'truncated':
            'query_kline returns at most $effectiveLimit rows in normal agent workflow. Use MarketData(action:"backtest") or MarketData(action:"optimize_params") for full-window computation instead of reading raw tool-output files.',
      'source': 'local kline_daily',
      'data': rows.map((row) => row.toJson()).toList(),
    };
  }

  void _requireTdxQuerySymbol(String action, List<String> symbols) {
    switch (action) {
      case 'query_ex_categories':
      case 'query_tdx_count':
      case 'query_ex_table':
      case 'query_top_board':
      case 'query_tdx_block_member':
        return;
      case 'query_tdx_sampling':
        if (symbols.isEmpty) return;
        return;
      case 'query_tick_chart':
        _firstSymbol(symbols, _tickChartError);
        return;
      case 'query_transactions':
        _firstSymbol(symbols, _transactionsError);
        return;
      case 'query_volume_profile':
        _firstSymbol(symbols, _volumeProfileError);
        return;
      case 'query_xdxr':
        _firstSymbol(symbols, _xdxrError);
        return;
      case 'query_auction':
        _firstSymbol(symbols, _auctionError);
        return;
      case 'query_momentum':
        _firstSymbol(symbols, _momentumError);
        return;
      case 'query_stock_company_info':
      case 'query_company_info':
      case 'query_fund_company_info':
      case 'query_fund_investor_holders':
      case 'query_index_profile':
        _firstSymbol(symbols, _companyInfoError);
        return;
    }
  }
}

String _firstSymbol(List<String> symbols, String error) {
  if (symbols.isEmpty) throw ArgumentError(error);
  return symbols.first;
}

int _inputLimit(Map<String, dynamic> input, int fallback) {
  final value = input['limit'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return fallback;
}

int? _boundedKlineReadbackLimit(int? requestedLimit) {
  const maxRows = 120;
  if (requestedLimit == null) return maxRows;
  if (requestedLimit <= 0) return maxRows;
  return requestedLimit > maxRows ? maxRows : requestedLimit;
}

_ProviderCacheConstraint _providerCacheConstraint(Map<String, dynamic> input) {
  final rawProvider = input['provider'] ?? input['source'];
  final requestedProvider = rawProvider?.toString().trim();
  final providerMode = input['providerMode']?.toString().trim();
  final strict =
      requestedProvider != null &&
      requestedProvider.isNotEmpty &&
      providerMode?.toLowerCase() == 'strict';
  final sources = strict
      ? _providerSourceAliases(requestedProvider)
      : const <String>[];
  return _ProviderCacheConstraint(
    requestedProvider: requestedProvider == null || requestedProvider.isEmpty
        ? null
        : requestedProvider,
    providerMode: providerMode == null || providerMode.isEmpty
        ? null
        : providerMode,
    sourceAliases: sources,
  );
}

_ProviderCacheConstraint _indexQuoteCacheConstraint(
  Map<String, dynamic> input,
) {
  final explicit = _providerCacheConstraint(input);
  if (explicit.requestedProvider != null) {
    return _ProviderCacheConstraint(
      requestedProvider: explicit.requestedProvider,
      providerMode: explicit.providerMode ?? 'strict',
      sourceAliases: _indexQuoteSourceAliases(explicit.requestedProvider!),
    );
  }
  return _ProviderCacheConstraint(
    requestedProvider: 'index.quote',
    providerMode: 'strict',
    sourceAliases: const [
      'tdx:index_quote',
      'gotdx:index_quote',
      '通达信:index_quote',
      'sina:index_quote',
      '新浪:index_quote',
      '新浪财经:index_quote',
      'eastmoney:index_quote',
      'eastmoneyDirect:index_quote',
      '东方财富:index_quote',
      'tencent:index_quote',
      'qq:index_quote',
      '腾讯:index_quote',
      '腾讯财经:index_quote',
      'wind:index_quote',
      'Wind:index_quote',
    ],
  );
}

List<String> _indexQuoteSourceAliases(String provider) {
  final normalized = provider.trim().toLowerCase();
  switch (normalized) {
    case 'tdx':
    case 'gotdx':
    case 'tongdaxin':
    case '通达信':
      return const ['tdx:index_quote', 'gotdx:index_quote', '通达信:index_quote'];
    case 'eastmoney':
    case 'em':
    case '东方财富':
      return const [
        'eastmoney:index_quote',
        'eastmoneyDirect:index_quote',
        '东方财富:index_quote',
      ];
    case 'sina':
    case '新浪':
    case '新浪财经':
      return const ['sina:index_quote', '新浪:index_quote', '新浪财经:index_quote'];
    case 'tencent':
    case 'qq':
    case '腾讯':
    case '腾讯财经':
      return const [
        'tencent:index_quote',
        'qq:index_quote',
        '腾讯:index_quote',
        '腾讯财经:index_quote',
      ];
    case 'wind':
      return const ['wind:index_quote', 'Wind:index_quote'];
    default:
      return ['$provider:index_quote'];
  }
}

List<StockQuote> _queryPersistedQuotesWithConstraint(
  MarketDataQueryActionService service,
  ToolContext context,
  String symbol, {
  required int limit,
  required _ProviderCacheConstraint constraint,
}) {
  if (!constraint.isStrict) {
    return service._readService.queryPersistedQuotes(
      context,
      symbol,
      limit: limit,
    );
  }
  for (final source in constraint.sourceAliases) {
    final rows = service._readService.queryPersistedQuotes(
      context,
      symbol,
      limit: limit,
      source: source,
    );
    if (rows.isNotEmpty) {
      constraint.effectiveSource = source;
      return rows;
    }
  }
  return const [];
}

List<String> _quoteSourceProviders(List<StockQuote> rows) {
  final values = <String>{};
  for (final row in rows) {
    final source = row.source.trim();
    if (source.isNotEmpty) values.add(source);
  }
  return values.toList();
}

List<Map<String, dynamic>> _queryMapsWithProviderConstraint({
  required _ProviderCacheConstraint constraint,
  required List<Map<String, dynamic>> Function(String? provider) query,
  String? fallbackProvider,
}) {
  if (!constraint.isStrict) {
    return query(fallbackProvider ?? constraint.requestedProvider);
  }
  for (final source in constraint.sourceAliases) {
    final rows = query(source);
    if (rows.isNotEmpty) {
      constraint.effectiveSource = source;
      return rows;
    }
  }
  return const [];
}

List<KlineBar> _queryPersistedKlineWithConstraint(
  MarketDataQueryActionService service,
  ToolContext context,
  String symbol, {
  required String startDate,
  required String endDate,
  required String adjust,
  required int? limit,
  required _ProviderCacheConstraint constraint,
}) {
  if (!constraint.isStrict) {
    return service._readService.queryPersistedKline(
      context,
      symbol,
      startDate: startDate,
      endDate: endDate,
      adjust: adjust,
      limit: limit,
    );
  }
  for (final source in constraint.sourceAliases) {
    final rows = service._readService.queryPersistedKline(
      context,
      symbol,
      startDate: startDate,
      endDate: endDate,
      adjust: adjust,
      source: source,
      limit: limit,
    );
    if (rows.isNotEmpty) {
      constraint.effectiveSource = source;
      return rows;
    }
  }
  return const [];
}

List<String> _providerSourceAliases(String provider) {
  final normalized = provider.trim().toLowerCase();
  switch (normalized) {
    case 'tdx':
    case 'gotdx':
    case 'tongdaxin':
    case '通达信':
      return const ['tdx', 'gotdx', '通达信', '通达信:index_quote'];
    case 'eastmoney':
    case 'em':
    case '东方财富':
      return const ['eastmoney', 'EastMoney', 'eastmoneyDirect', '东方财富'];
    case 'akshare':
      return const ['akshare', 'AkShare'];
    case 'tushare':
      return const ['tushare', 'Tushare'];
    case 'wind':
      return const ['wind', 'Wind'];
    case 'yahoo':
    case 'yfinance':
      return const ['yahoo', 'yfinance'];
    case 'sina':
    case '新浪':
    case '新浪财经':
      return const ['sina', '新浪', '新浪财经'];
    case 'tencent':
    case 'qq':
    case '腾讯':
    case '腾讯财经':
      return const ['tencent', 'qq', '腾讯', '腾讯财经'];
    default:
      return [provider];
  }
}

class _ProviderCacheConstraint {
  final String? requestedProvider;
  final String? providerMode;
  final List<String> sourceAliases;
  String? effectiveSource;

  _ProviderCacheConstraint({
    required this.requestedProvider,
    required this.providerMode,
    required this.sourceAliases,
  });

  bool get isStrict =>
      requestedProvider != null &&
      providerMode?.toLowerCase() == 'strict' &&
      sourceAliases.isNotEmpty;

  String? get strictSource => isStrict ? sourceAliases.first : null;
}

const _quoteError =
    'symbols required for query_quote. Example: MarketData(action:"query_quote", symbols:["600519"])';
const _klineError =
    'symbols required for query_kline. Example: MarketData(action:"query_kline", symbols:["600519"], startDate:"2024-01-01")';
const _fundamentalError =
    'symbols required for query_fundamental. Example: MarketData(action:"query_fundamental", symbols:["600519"])';
const _stockDailyValuationError =
    'symbols required for query_stock_daily_valuation. Example: MarketData(action:"query_stock_daily_valuation", symbols:["600519"])';
const _moneyFlowError =
    'symbols required for query_money_flow. Example: MarketData(action:"query_money_flow", symbols:["600519"])';
const _fundNavError =
    'symbols required for query_fund_nav. Example: MarketData(action:"query_fund_nav", symbols:["110011.OF"])';
const _fundMoneyYieldError =
    'symbols required for query_fund_money_yield. Example: MarketData(action:"query_fund_money_yield", symbols:["000009"])';
const _fundDividendFactorError =
    'symbols required for query_fund_dividend_factor. Example: MarketData(action:"query_fund_dividend_factor", symbols:["510050"])';
const _intradayOhlcvError =
    'symbols required for query_intraday_ohlcv_bars. Example: MarketData(action:"query_intraday_ohlcv_bars", symbols:["600519"], intervalMinutes:5)';
const _yfinanceError =
    'symbols required for query_yfinance. Example: MarketData(action:"query_yfinance", symbols:["AAPL"], dataset:"profile")';
const _tickChartError =
    'symbols required for query_tick_chart. Example: MarketData(action:"query_tick_chart", symbols:["600519"])';
const _transactionsError =
    'symbols required for query_transactions. Example: MarketData(action:"query_transactions", symbols:["600519"], limit:50)';
const _volumeProfileError =
    'symbols required for query_volume_profile. Example: MarketData(action:"query_volume_profile", symbols:["600519"])';
const _xdxrError =
    'symbols required for query_xdxr. Example: MarketData(action:"query_xdxr", symbols:["600519"])';
const _auctionError =
    'symbols required for query_auction. Example: MarketData(action:"query_auction", symbols:["600519"])';
const _momentumError =
    'symbols required for query_momentum. Example: MarketData(action:"query_momentum", symbols:["000001"])';
const _companyInfoError =
    'symbols required for query_company_info. Example: MarketData(action:"query_company_info", symbols:["600519"])';
const _chipError =
    'symbols required for query_chip. Example: MarketData(action:"query_chip", symbols:["600519"])';

bool _isCommonMarketIndexQuoteBasket(List<String> symbols) {
  return symbols.length > 1 &&
      symbols.every(
        (symbol) => coreCnMarketIndexCodeSet.contains(_cleanQuoteCode(symbol)),
      );
}

String _cleanQuoteCode(String symbol) {
  var value = symbol.trim();
  value = value.replaceFirst(RegExp(r'^INDEX:', caseSensitive: false), '');
  value = value.replaceFirst(
    RegExp(r'^(SH|SZ|BJ|CSI)', caseSensitive: false),
    '',
  );
  return value;
}

String _cleanFundCode(String value) {
  return value.trim().toUpperCase().replaceFirst(RegExp(r'\.OF$'), '');
}

List<String> _inputFundCodes(
  List<String> symbols,
  Map<String, dynamic> input, {
  bool requireCode = false,
}) {
  final values = <String>[];
  void addValue(Object? value) {
    if (value == null) return;
    if (value is Iterable) {
      for (final item in value) {
        addValue(item);
      }
      return;
    }
    final text = value.toString().trim();
    if (text.isEmpty) return;
    for (final part in text.split(RegExp(r'[\s,，;；]+'))) {
      final clean = _cleanFundCode(part);
      if (clean.isNotEmpty && !values.contains(clean)) values.add(clean);
    }
  }

  addValue(input['fundCodes']);
  addValue(input['fundCode']);
  addValue(input['codes']);
  addValue(input['code']);
  addValue(input['symbols']);
  addValue(input['symbol']);
  addValue(symbols);
  if (requireCode && values.isEmpty) throw ArgumentError(_fundNavError);
  return values;
}

List<Map<String, dynamic>> _dedupeMapRows(
  Iterable<Map<String, dynamic>> rows,
  List<String> keys,
) {
  final seen = <String>{};
  final result = <Map<String, dynamic>>[];
  for (final row in rows) {
    final key = keys.map((key) => '${row[key] ?? ''}').join('|');
    if (seen.add(key)) result.add(row);
  }
  return result;
}

bool _hasIndexQuoteIdentity(StockQuote quote) {
  final expectedName = coreCnMarketIndexNameByCode[quote.code];
  if (expectedName == null) return true;
  final name = quote.name.trim();
  return name == expectedName || name.contains('指数') || name.contains('指');
}
