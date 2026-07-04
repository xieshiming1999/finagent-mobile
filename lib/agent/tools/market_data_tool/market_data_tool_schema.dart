part of 'market_data_tool.dart';

mixin _MarketDataToolSchema on _MarketDataToolBase {
  String get _customStrategyIndicatorSummary => strategyIndicatorRegistry
      .where((definition) => definition.executable)
      .map((definition) => definition.type)
      .join('/');

  @override
  String get prompt =>
      '''Fetch market data. Use action="help" to discover all available actions.

Broad market discipline:
- For broad market activity, money-flow, hot-rank, or unusual-stock discovery
  intents, call `market_activity_summary` first. It returns bounded local
  hot-rank, flow-rank, limit-pool, unusual-activity, dragon-tiger, and cached
  quote evidence in one governed readback.
- For narrower broad market money-flow intents, use bounded local readbacks:
  `query_flow_rank`, optionally `query_sector_ranking`, and local
  `query_northbound_flow`. Stop and answer when those rows provide usable
  evidence.
- For broad unusual-stock discovery intents, use bounded local readbacks first:
  `query_unusual`, then `query_limit_pool` if empty, then at most one of
  `query_hot_rank` or `query_flow_rank` as proxy evidence. Stop and answer from
  those rows when they provide usable evidence.
- Do not escalate into multiple broad live refresh actions such as `limit_up`,
  `limit_down`, `unusual`, `hot_rank`, `flow_rank`, `sector`, or
  `dragon_tiger` in the same first-pass answer unless the user explicitly asks
  for a live refresh or deeper follow-up. If local evidence is missing, stale,
  or partial, state that gap with source/data time/retrieval time instead of
  probing unrelated broad providers.

Key actions:
- **quote** — A-share real-time quotes (TDX→EastMoney→Sina→Tencent fallback). symbols: ["600519", "000001"]. Convertible-bond quote symbols such as ["110059"] route through `bond.convertible_quote`; read back with `query_bond_quote`.
- **kline** — Governed daily A-share K-line (TDX→EastMoney fallback). symbols: ["600519"], period: daily, startDate, endDate. ETF symbols such as ["510300"] route through `fund.etf_daily_ohlcv_bars` on mobile only with adjust:"none"; convertible-bond symbols such as ["110059"] route through `bond.convertible_daily_kline` only with adjust:"none"; read back with `query_kline` / `query_bond_kline`.
- **flow** — A-share money flow (EastMoney; TDX does not provide this action). symbols: ["600519"]
- **flow_rank** — Market-wide money flow ranking (资金流入排名). period: today/3day/5day/10day
- **sector** — Sector/board rankings (板块排名). boardType: industry/concept/area. When sectorCode is provided, returns sector constituent stocks and persists industry_map + quote snapshots + stock_list rows.
- **chip** — Chip distribution (筹码分布). symbols: ["600519"]
- **etf** — ETF quotes. No symbols needed (returns all).
- **listed_fund_quote** — Bounded exchange-listed fund and money-market fund quotes through governed fund.listed_fund_quote. provider: tencent.
- **stock_list** — Stock identity list. No symbols needed; persists `stock_list`.
- **fund_list** — Fund identity list. No symbols needed; persists `fund_list`.
- **fund_nav** — Fund NAV history. symbols: ["110011.OF"] or fundCode/code; persists `fund_nav`.
- **fund_money_yield** — Money-fund per-10k income and seven-day annualized yield. symbols: ["000009"] or fundCode/code; persists `fund_money_yield`. Use for money funds instead of ordinary `fund_nav`.
- **query_fund_money_yield** — Read persisted money-fund yield rows. symbols: ["000009"]; separate from ordinary `fund_nav`.
- **fund_dividend_factor** — Refresh governed Sina ETF dividend/factor rows through `fund.dividend_factor`; persists `fund_dividend_factor`, then read back with `query_fund_dividend_factor`.
- **query_fund_dividend_factor** — Read persisted fund dividend/factor rows. symbols: ["510050"].
- **intraday_ohlcv_bars** — Refresh governed Sina 5-minute intraday OHLCV bars through `market.intraday_ohlcv_bars`; persists `intraday_ohlcv_bars`, then read back with `query_intraday_ohlcv_bars`.
- **query_intraday_ohlcv_bars** — Read persisted intraday OHLCV bars. symbols: ["600519"], intervalMinutes: 5.
- **fund_manager** — Fund manager list and profiles. No symbols needed; persists `fund_manager`.
- **fund_holding** — Fund holdings. symbols: ["110011"] or fundCode/code; persists `fund_holding` and related `stock_list` rows.
- **stock_risk_metrics/fund_company_info/fund_investor_holders/fund_financials/index_fundamentals/index_profile/bond_profile/bond_market_data/bond_issuer_financials** — Governed Wind structured workflows. symbols: ["600519"], ["110011"], ["000300"], or ["019521.SH"]; refreshes Wind canonical rows and returns interface/provider/cache provenance.
- **stock_company_info** — Stock company profile/F10 summary. symbols: ["600519"]; persists `stock_company_info`.
- **stock_shareholders** — Top stock shareholders. symbols: ["600519"], reportDate/date optional; persists `stock_shareholder`.
- **margin_trading** — Margin trading detail. symbols: ["600519"] or ["000001"], date/tradeDate optional; persists `margin_trading`.
- **fund_performance** — Fund performance metrics. No symbols needed; persists `fund_performance_metrics`.
- **finance_news** — Broad governed finance news feed. query/keyword required; provider/cache policy optional; persists `finance_news`.
- **trade_calendar** — Trade calendar snapshots. year or startDate/endDate optional; market: CN by default; persists `trade_calendar` through governed calendar routing.
- **index_constituents** — Index constituent membership and weights. symbols: ["000300"], asOfDate/date optional; persists `index_constituent` through governed Tushare routing.
- **limit_up** — Limit-up stock pool (涨停股池). date: "20260507" (optional)
- **limit_down** — Limit-down stock pool (跌停股池). date: "20260507" (optional)
- **hot_rank** — Hot stock ranking (人气榜). pageSize: 50
- **dragon_tiger** — Dragon tiger board (龙虎榜). date: "2026-05-07" (optional)
- **northbound** — Northbound capital flow (北向资金). symbols: ["600519"] for holding, omit for flow history
- **unusual** — Unusual market activity (盘口异动/火箭发射/大笔买入)
- **transactions** — Stock or ETF transaction ticks through `stock.transactions` / `fund.etf_transactions`. symbols: ["600519"] or ["510300"], provider optional (`tdx`/`sina`/`tencent`), instrumentType optional (`etf`), date optional
- **scan** — TradingView Scanner: global real-time indicators. symbols: ["BINANCE:BTCUSDT", "NASDAQ:AAPL"]
- **price** — Yahoo Finance: real-time price. symbols: ["AAPL", "BTC-USD"]
- **yahoo_history/option_daily_kline/yahoo_earnings/global_income_statement/global_balance_sheet/global_cash_flow/global_quarterly_income_statement/global_quarterly_balance_sheet/global_quarterly_cash_flow/global_major_holders/yahoo_news/yahoo_options/yahoo_actions/global_capital_gains** — Yahoo Finance typed datasets for non-A-share symbols. Query persisted `query_yfinance` / `query_global_*` / `query_option_*` rows first. Live `yahoo_earnings` and `yahoo_options` refreshes are governed by `interface_availability` and current runtime probe evidence; if Yahoo returns 401/403 credential-or-permission evidence, keep the provider blocked and reuse cache/readback instead of retrying.
- **backtest** — Strategy backtest (A-share + global). symbols: ["600519"] or ["AAPL"], strategy: rsi/rsi_conservative/macd/bollinger/boll_tight/ema_cross/supertrend/donchian/kdj/ma_golden_cross/volume_breakout/dual_thrust/adx_emerging/mean_reversion/turtle_breakout/compare
- **custom_strategy_help/custom_strategy_validate/custom_strategy_backtest/custom_strategy_observe/custom_strategy_fund_backtest/custom_strategy_rank/custom_strategy_save/custom_strategy_list/custom_strategy_compare/custom_strategy_run** — Governed agent-created StrategySpec workflow. Use custom_strategy_help as the code-owned discovery surface for the current executable indicator catalog ($_customStrategyIndicatorSummary), dataRequirements, lifecycle fields, and output contracts. Fund StrategySpec must set assetClass:"fund" or market:"fund" and accepts fund-only observation indicators such as nav_trend, rolling_return, fund_drawdown, fund_volatility, fund_momentum_acceleration, money_yield, seven_day_yield, and dca_interval; use custom_strategy_observe or custom_strategy_fund_backtest with fundRows from fund query results for fund evidence, not stock backtest. FundRows with multiple code/name groups produce comparisonEvidence. Use custom_strategy_rank for multi-symbol stock ranking/rebalance evidence including portfolioScoringEvidence; it does not place orders. Use custom_strategy_compare to compare already saved artifacts by structured lifecycle, metric, portfolio, and data coverage fields without rerunning or fetching. For stock custom_strategy_backtest, optional outOfSampleRatio adds chronological holdout evidence and optional walkForwardFolds adds chronological stability evidence when enough bars exist. custom_strategy_backtest returns lifecycleAdvice; lifecycleAdvice.saveable=true means status:"backtested" can be saved/rerun even when metrics.tradeCount is 0. Validate a structured spec first; validationSummary, validationIssues, unsupportedDetails, dataCoverage, lifecycleAdvice, lifecycleIssue, and readback_only are structured contract fields; do not parse prose when these fields are present. Unsupported source signals must stay as unsupported indicator types during validation; do not replace them with supported proxy indicators unless proxyFor, unsupportedOriginalSignals, and proxyApproval:{approved:true} are present. Unsupported arbitrary code/news/sentiment/broker execution is rejected before backtest.
- **help** — List all actions with detailed parameters
- **interfaces** — Discover governed Data API interfaces before fetch/query. Optional category/provider/health/limit filters
- **interface_describe** — Explain one governed or controlled output-only interface contract. interfaceId required
- **interface_availability** — Explain whether one interface is reusable now or needs provider refresh. interfaceId required; provider/providerMode optional
- **sources** — Data source health status
- **stats** — Local reusable data store stats
- **data_health** — Data API interface/provider/cache/API-error health. section: summary|interfaces|providers|gaps|failures|all
- **runtime_probe** — Inspect or run controlled runtime provider probes. Start with probeAction:status and inspect recommendedTargets/blockedTargets. probeMode failures/all auto-runs retryable transport/runtime/provider-error targets only; credential/quota/unsupported/schema/do-not-retry rows stay blocked unless an explicit bounded probeIds list is provided.
- **fetch_status** — Local durable fetch/data-task queue health. status: pending|running|failed|completed|cancelled|all
- **coverage** — Local reusable data coverage. Optional symbols: ["600519"]
- **market_activity_summary** — Bounded local first-pass evidence for broad market activity, hot-rank, flow-rank, limit-pool, unusual-activity, dragon-tiger, and cached quote context. Use before live broad refreshes.
- **query_quote** — Inspect persisted quote snapshots. symbols: ["600519"]
- **query_index_quote** — Inspect persisted governed index quote snapshots. symbols: ["000001"]
- **query_etf_quote** — Inspect persisted governed ETF quote snapshots. symbols: ["510300"]
- **query_listed_fund_quote** — Inspect persisted governed listed-fund and exchange money-market quote snapshots. symbols: ["511880"]
- **query_bond_quote** — Inspect persisted governed convertible-bond quote snapshots. symbols: ["110059"]
- **query_kline** — Inspect persisted daily K-line rows. symbols: ["600519"], startDate/endDate/adjust
- **query_bond_kline** — Inspect persisted governed convertible-bond daily K-line rows. symbols: ["110059"], startDate/endDate/adjust
- **query_stock_daily_valuation/query_fundamental/query_fund_financials/query_index_fundamentals/query_bond_issuer_financials/query_money_flow/query_fund_nav/query_fund_list/query_fund_manager/query_trade_calendar/query_stock_list** — Inspect persisted Tushare/local research rows
- **query_index_constituents** — Inspect persisted index constituent membership and weights. indexCode/code, stockCode, asOfDate, provider optional
- **query_board_members/query_industry_map** — Inspect persisted board-member and sector-constituent mappings. code/industry/boardCode/boardName/limit
- **query_market_screening** — Inspect persisted governed market screening snapshots. symbols/provider/sourceAction/limit optional; readback may contain TradingView, AkShare-sidecar, or Wind-backed screening rows depending on what has been persisted
- **query_technical_indicator** — Inspect persisted technical indicator series. symbols/code, indicator/func, fieldName, since optional
- **query_alpha_factors** — Inspect persisted Alpha factor snapshots. symbols/code, factorName/factor, since optional
- **query_finance_news** — Inspect persisted finance news rows from Research(news). keyword/source/limit optional
- **query_ex_categories** — Inspect persisted ExTDX market categories
- **query_tdx_count** — Inspect persisted TDX/ExTDX security-count snapshots. scope: main/ex, market optional
- **query_tdx_sampling** — Inspect persisted TDX/ExTDX chart-sampling rows. symbols optional for main; code/category filters optional
- **query_ex_table** — Inspect persisted ExTDX table entries. code/category/limit optional
- **query_yfinance** — Inspect persisted Yahoo/yfinance rows through the generic dataset bucket. symbols: ["AAPL"], dataset: profile/statements/income_statement/balance_sheet/cash_flow/earnings_calendar/earnings_history/earnings_estimates/eps_revisions/eps_trend/quarterly_financial_statements/quarterly_income_statement/quarterly_balance_sheet/quarterly_cash_flow/recommendations/upgrade_downgrade_events/news/options/option_expiries/option_open_interest/option_volume/option_implied_volatility/option_moneyness/option_bid_ask_spread/option_price_change/option_trade_recency/actions/dividends/capital_gains/splits/holders/major_holders/institutional_holders/mutual_fund_holders/insiders
- **query_global_company_profile/query_global_financial_statements/query_global_income_statement/query_global_balance_sheet/query_global_cash_flow/query_global_earnings_calendar/query_global_earnings_history/query_global_earnings_estimates/query_global_eps_revisions/query_global_eps_trend/query_global_quarterly_financial_statements/query_global_quarterly_income_statement/query_global_quarterly_balance_sheet/query_global_quarterly_cash_flow/query_global_recommendations/query_global_upgrade_downgrade_events/query_global_holders/query_global_major_holders/query_global_institutional_holders/query_global_mutual_fund_holders/query_global_insider_transactions** — Requirement-level Yahoo/global research readbacks over persisted yfinance tables. symbols: ["AAPL"]
- **query_global_finance_news/query_global_corporate_actions/query_global_dividends/query_global_capital_gains/query_global_stock_splits/query_option_expiry_calendar/query_option_contract_list/query_option_quote/query_option_daily_kline/query_option_open_interest/query_option_volume/query_option_implied_volatility/query_option_moneyness/query_option_bid_ask_spread/query_option_price_change/query_option_trade_recency/query_option_chain_snapshot/query_global_options_chain** — Requirement-level Yahoo/global readbacks over persisted yfinance tables. symbols: ["AAPL"]
- **query_tick_chart/query_transactions/query_volume_profile** — Inspect persisted intraday rows. `query_transactions` reads the canonical `transactions` table for `stock.transactions` and ETF `fund.etf_transactions` rows. symbols: ["600519"] or ["510300"]
- **query_stock_company_info/query_company_info/query_stock_risk_metrics/query_fund_company_info/query_fund_investor_holders/query_index_profile/query_bond_profile/query_bond_market_data/query_stock_shareholders/query_hot_rank/query_dragon_tiger/query_limit_pool/query_northbound/query_northbound_flow/query_northbound_holding/query_unusual/query_flow_rank/query_sector/query_sector_ranking/query_board_ranking/query_chip** — Inspect persisted TDX/EastMoney/shareholder structured rows
- **query_xdxr/query_auction/query_momentum/query_top_board** — Inspect persisted TDX ex-rights/dividend, auction, momentum, and ranking rows. symbols: ["600519"]
- **tdx_count/tdx_sampling** — TDX market count and chart-sampling. tdx_sampling symbols: ["000001"]
- **ex_count/ex_sampling/ex_table** — ExTDX market count, chart-sampling, and protocol table. ex_sampling params:{category:30, code:"RBL8"}
- **query_raw_payload** — Inspect legacy/explicit raw audit payloads for diagnostics; normal unknown provider schemas are output-only
- **query_api_calls** — Inspect recent failed provider/API calls before retrying. source optional, minutes optional
- **query_api_errors** — Compatibility alias for `query_api_calls`

Market routing: 6-digit codes → A-share (TDX first for quote/kline, EastMoney for advanced REST-only datasets), EXCHANGE:SYMBOL → TradingView, other → Yahoo. Query local reusable data and recent API errors before repeating failed provider calls.''';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': [
          'quote',
          'kline',
          'flow',
          'flow_rank',
          'sector',
          'chip',
          'etf',
          'listed_fund_quote',
          'stock_list',
          'fund_list',
          'fund_nav',
          'fund_money_yield',
          'fund_dividend_factor',
          'fund_manager',
          'fund_holding',
          'fund_performance',
          'finance_news',
          'stock_risk_metrics',
          'fund_company_info',
          'fund_investor_holders',
          'fund_financials',
          'index_fundamentals',
          'index_profile',
          'bond_profile',
          'bond_market_data',
          'bond_issuer_financials',
          'trade_calendar',
          'index_constituents',
          'stock_company_info',
          'stock_shareholders',
          'margin_trading',
          'earnings',
          'tushare',
          'scan',
          'price',
          'yahoo_history',
          'option_daily_kline',
          'yahoo_earnings',
          'global_income_statement',
          'global_balance_sheet',
          'global_cash_flow',
          'global_quarterly_income_statement',
          'global_quarterly_balance_sheet',
          'global_quarterly_cash_flow',
          'global_major_holders',
          'yahoo_news',
          'yahoo_options',
          'yahoo_actions',
          'global_capital_gains',
          'backtest',
          'backtest_enhanced',
          'backtest_composite',
          'custom_strategy_help',
          'custom_strategy_validate',
          'custom_strategy_backtest',
          'custom_strategy_observe',
          'custom_strategy_fund_backtest',
          'custom_strategy_rank',
          'custom_strategy_save',
          'custom_strategy_list',
          'custom_strategy_compare',
          'custom_strategy_run',
          'backtest_batch',
          'optimize_params',
          'limit_up',
          'limit_down',
          'hot_rank',
          'dragon_tiger',
          'northbound',
          'unusual',
          'transactions',
          'tdx_tick_chart',
          'tdx_transactions',
          'tdx_finance',
          'tdx_xdxr',
          'tdx_unusual',
          'tdx_index_info',
          'tdx_count',
          'tdx_sampling',
          'tdx_stock_list',
          'tdx_volume_profile',
          'tdx_auction',
          'tdx_history_tick',
          'tdx_momentum',
          'tdx_history_trans',
          'tdx_top_board',
          'tdx_quotes_list',
          'tdx_index_bars',
          'tdx_company_info',
          'tdx_block',
          'ex_categories',
          'ex_count',
          'ex_sampling',
          'ex_table',
          'ex_kline',
          'ex_quote',
          'ex_list',
          'help',
          'interfaces',
          'interface_describe',
          'interface_availability',
          'sources',
          'stats',
          'data_health',
          'finance_doctor',
          'runtime_probe',
          'fetch_status',
          'coverage',
          'reusable_summary',
          'query_quote',
          'query_index_quote',
          'query_etf_quote',
          'query_listed_fund_quote',
          'query_bond_quote',
          'query_kline',
          'query_bond_kline',
          'query_fundamental',
          'query_stock_daily_valuation',
          'query_fund_financials',
          'query_index_fundamentals',
          'query_bond_issuer_financials',
          'query_money_flow',
          'query_fund_nav',
          'query_fund_money_yield',
          'query_fund_dividend_factor',
          'intraday_ohlcv_bars',
          'query_intraday_ohlcv_bars',
          'query_fund_list',
          'query_fund_manager',
          'query_finance_news',
          'query_fund_holding',
          'query_index_constituents',
          'query_fund_performance',
          'query_trade_calendar',
          'query_stock_list',
          'query_board_members',
          'query_sector_constituents',
          'query_industry_map',
          'query_board_ranking',
          'query_sector_ranking',
          'query_ex_categories',
          'query_tdx_count',
          'query_tdx_sampling',
          'query_ex_table',
          'query_wind_document',
          'query_wind_economic',
          'query_wind_analytics',
          'query_yfinance',
          'query_global_company_profile',
          'query_global_financial_statements',
          'query_global_income_statement',
          'query_global_balance_sheet',
          'query_global_cash_flow',
          'query_global_earnings_calendar',
          'query_global_earnings_history',
          'query_global_earnings_estimates',
          'query_global_eps_revisions',
          'query_global_eps_trend',
          'query_global_quarterly_financial_statements',
          'query_global_quarterly_income_statement',
          'query_global_quarterly_balance_sheet',
          'query_global_quarterly_cash_flow',
          'query_global_recommendations',
          'query_global_upgrade_downgrade_events',
          'query_global_holders',
          'query_global_major_holders',
          'query_global_institutional_holders',
          'query_global_mutual_fund_holders',
          'query_global_insider_transactions',
          'query_global_finance_news',
          'query_global_corporate_actions',
          'query_global_dividends',
          'query_global_capital_gains',
          'query_global_stock_splits',
          'query_option_expiry_calendar',
          'query_option_contract_list',
          'query_option_quote',
          'query_option_daily_kline',
          'query_option_open_interest',
          'query_option_volume',
          'query_option_implied_volatility',
          'query_option_moneyness',
          'query_option_bid_ask_spread',
          'query_option_price_change',
          'query_option_trade_recency',
          'query_option_chain_snapshot',
          'query_global_options_chain',
          'query_tick_chart',
          'query_transactions',
          'query_volume_profile',
          'query_xdxr',
          'query_auction',
          'query_momentum',
          'query_top_board',
          'query_tdx_block_member',
          'query_stock_company_info',
          'query_company_info',
          'query_stock_risk_metrics',
          'query_fund_company_info',
          'query_fund_investor_holders',
          'query_index_profile',
          'query_bond_profile',
          'query_bond_market_data',
          'query_stock_shareholders',
          'query_hot_rank',
          'query_dragon_tiger',
          'query_limit_pool',
          'query_northbound',
          'query_northbound_flow',
          'query_northbound_holding',
          'query_unusual',
          'query_flow_rank',
          'market_activity_summary',
          'query_sector',
          'query_chip',
          'query_market_screening',
          'query_margin_trading',
          'query_technical_indicator',
          'query_alpha_factors',
          'query_raw_payload',
          'query_api_calls',
          'query_api_errors',
        ],
        'description': 'Action to perform. Use help for full list.',
      },
      'symbols': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Stock/crypto symbols',
      },
      'period': {
        'type': 'string',
        'description':
            'Kline period. Governed MarketData(action:"kline") supports daily only; backtest/Yahoo range actions may use 1mo/3mo/6mo/1y/2y.',
      },
      'startDate': {
        'type': 'string',
        'description': 'Start date YYYY-MM-DD (kline)',
      },
      'endDate': {
        'type': 'string',
        'description': 'End date YYYY-MM-DD (kline)',
      },
      'adjust': {
        'type': 'string',
        'description': 'Price adjust: qfq(前复权)/hfq(后复权)/none',
      },
      'boardType': {
        'type': 'string',
        'description': '(sector) Board type: industry/concept/area',
      },
      'sectorCode': {
        'type': 'string',
        'description':
            '(sector) EastMoney board code, e.g. BK0475. When provided, returns constituent stocks instead of ranking rows.',
      },
      'sectorName': {
        'type': 'string',
        'description':
            '(sector) Optional industry label to persist into industry_map alongside sector constituents.',
      },
      'industry': {
        'type': 'string',
        'description':
            '(query_industry_map/query_stock_list) Industry filter or label.',
      },
      'code': {
        'type': 'string',
        'description':
            '(query_industry_map/query_northbound/query_northbound_holding/query_index_constituents) Single security or index code filter.',
      },
      'indexCode': {
        'type': 'string',
        'description':
            '(query_index_constituents) Index code filter, e.g. 000300.',
      },
      'stockCode': {
        'type': 'string',
        'description':
            '(query_index_constituents/query_fund_holding) Constituent stock code filter.',
      },
      'asOfDate': {
        'type': 'string',
        'description':
            '(query_index_constituents) Source membership snapshot date filter.',
      },
      'api_name': {
        'type': 'string',
        'description':
            '(tushare) Tushare API name, e.g. stock_basic, daily, weekly, monthly, index_daily, index_weight, daily_basic, trade_cal. Statement, moneyflow, fund_basic, and fund_nav Tushare APIs are disabled in this app.',
      },
      'fields': {
        'type': 'string',
        'description': '(tushare) Return fields, comma-separated',
      },
      'params': {
        'type': 'object',
        'description': '(tushare) API params as key-value',
      },
      'persist': {
        'type': 'boolean',
        'description':
            '(tushare) Persist registered schemas to local reusable SQLite rows. Defaults to true.',
      },
      'source': {
        'type': 'string',
        'description':
            'Force specific data source: eastmoney/tdx/sina/tencent/tushare/yahoo/tradingview',
      },
      'endpoint': {
        'type': 'string',
        'description': '(query_raw_payload) Endpoint/action filter',
      },
      'indicators': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': '(scan) Indicator columns',
      },
      'indicator': {
        'type': 'string',
        'description':
            '(query_technical_indicator) Indicator name, e.g. rsi or macd.',
      },
      'func': {
        'type': 'string',
        'description':
            '(query_technical_indicator) Alias for indicator, matching desktop DataStore technical_indicator calls.',
      },
      'fieldName': {
        'type': 'string',
        'description':
            '(query_technical_indicator) Indicator output field such as RSI_14 or value.',
      },
      'factorName': {
        'type': 'string',
        'description':
            '(query_alpha_factors) Alpha factor name such as momentum_5d or kmid.',
      },
      'since': {
        'type': 'string',
        'description':
            '(query_technical_indicator/query_market_screening/query_alpha_factors) Earliest source date/time filter.',
      },
      'timeframe': {
        'type': 'string',
        'description': '(scan) Timeframe: 5m/15m/1h/4h/1d',
      },
      'limit': {
        'type': 'number',
        'description': 'Max rows for local query or ranking actions',
      },
      'interfaceId': {
        'type': 'string',
        'description':
            '(interface_describe/interface_availability) Governed or controlled output-only Data API interface id such as stock.quote, market.hot_rank, or provider.diagnostic.',
      },
      'provider': {
        'type': 'string',
        'description':
            '(interfaces/interface_availability and governed workflows) Provider routing constraint such as tdx/eastmoney/wind/tushare/yahoo/tradingview.',
      },
      'providerMode': {
        'type': 'string',
        'description':
            '(interface_availability and governed workflows) auto|preferred|strict. Defaults to auto.',
      },
      'category': {
        'type': 'string',
        'description':
            '(interfaces) Optional category filter such as stock/index/market/fund_etf/news/technical/provider_diagnostic.',
      },
      'health': {
        'type': 'string',
        'description':
            '(interfaces) Optional health filter: ready|attention|gap.',
      },
      'section': {
        'type': 'string',
        'description':
            '(data_health) summary|interfaces|providers|gaps|failures|all. Defaults to summary.',
      },
      'probeAction': {
        'type': 'string',
        'enum': ['status', 'run'],
        'description':
            '(runtime_probe) status to inspect durable runtime-probe state, run to execute mobile-native controlled probes.',
      },
      'probeMode': {
        'type': 'string',
        'enum': ['credential', 'unstable', 'failures', 'all'],
        'description':
            '(runtime_probe) credential|unstable|failures|all. Defaults to all.',
      },
      'probeIds': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            '(runtime_probe) Optional explicit bounded probe IDs from status.recommendedTargets/providerProbePacks.',
      },
      'status': {
        'type': 'string',
        'description':
            '(fetch_status) pending|running|failed|completed|cancelled|all. Defaults to all.',
      },
      'strategy': {
        'type': 'string',
        'description':
            '(backtest) Strategy name: rsi, rsi_conservative, macd, bollinger/boll, boll_tight, ema_cross, supertrend, donchian, kdj, ma_golden_cross, volume_breakout, dual_thrust, adx_emerging, mean_reversion, turtle_breakout, or compare',
      },
      'stopLoss': {
        'type': 'number',
        'description': '(backtest_enhanced) Stop loss % (e.g. 8)',
      },
      'takeProfit': {
        'type': 'number',
        'description': '(backtest_enhanced) Take profit %',
      },
      'trailingStop': {
        'type': 'number',
        'description': '(backtest_enhanced) Trailing stop %',
      },
      'positionSizing': {
        'type': 'string',
        'description':
            '(backtest_enhanced) fullCapital/fixedFraction/kelly/atrBased',
      },
      'paramGrid': {
        'type': 'object',
        'description':
            '(optimize_params) Parameter ranges, e.g. {"period":[10,14,20], "oversold":[30,40]}. Returns best params plus parameterStability evidence over top grid results.',
      },
      'strategySpec': {
        'type': 'object',
        'description':
            '(custom_strategy_*) Structured StrategySpec. Use custom_strategy_help as the code-owned discovery surface for the current executable indicator catalog ($_customStrategyIndicatorSummary), dataRequirements, lifecycle fields, and output contracts. custom_strategy_backtest returns lifecycleAdvice; lifecycleAdvice.saveable=true means status:"backtested" can be saved/rerun even when metrics.tradeCount is 0. Fund specs must set assetClass:"fund" or market:"fund" and use fund-only observation indicators with custom_strategy_observe/custom_strategy_fund_backtest plus fundRows. Use custom_strategy_rank with symbols[] for stock portfolio ranking evidence. Unsupported source signals must stay as unsupported indicator types during validation; proxy redesign requires proxyFor, unsupportedOriginalSignals, and proxyApproval:{approved:true}.',
      },
      'outOfSampleRatio': {
        'type': 'number',
        'description':
            '(custom_strategy_backtest) Optional chronological holdout ratio such as 0.3. Returns outOfSample train/test evidence when enough bars exist.',
      },
      'walkForwardFolds': {
        'type': 'number',
        'description':
            '(custom_strategy_backtest) Optional chronological walk-forward fold count, such as 3. Returns fold metrics and stability evidence when each fold has enough bars.',
      },
      'fundRows': {
        'type': 'array',
        'description':
            '(custom_strategy_observe/custom_strategy_fund_backtest) Structured fund NAV/yield rows from query_fund_nav or query_fund_money_yield. Fields may include code, name, date, nav, moneyYield, sevenDayYield. Multiple code groups return comparisonEvidence or fund period evidence.',
      },
      'topN': {
        'type': 'number',
        'description':
            '(custom_strategy_rank) Number of ranked symbols to include in the rebalance draft and portfolioScoringEvidence.',
      },
      'rankingMetric': {
        'type': 'string',
        'description':
            '(custom_strategy_rank) score, total_return_pct, sharpe_ratio, max_drawdown_pct, trade_count, relative_strength_pct, or rps.',
      },
      'rebalanceInterval': {
        'type': 'string',
        'description':
            '(custom_strategy_rank) Evidence-only rebalance cadence: weekly, monthly, or quarterly.',
      },
      'maxPositionWeight': {
        'type': 'number',
        'description':
            '(custom_strategy_rank) Evidence-only max per-symbol target weight, clamped to 0.01..1.0.',
      },
      'minScore': {
        'type': 'number',
        'description':
            '(custom_strategy_rank) Optional minimum rank score required before a candidate can enter the rebalance draft. Ranked rows below the threshold remain visible with selectionEvidence exclusionReason.',
      },
      'strategyId': {
        'type': 'string',
        'description': '(custom_strategy_run) Saved custom StrategySpec id',
      },
      'strategyIds': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            '(custom_strategy_compare) Optional saved StrategySpec ids to compare; omit to compare all saved artifacts.',
      },
      'evidence': {
        'type': 'object',
        'description':
            '(custom_strategy_save) Optional latest validation/backtest evidence',
      },
    },
    'required': ['action'],
  };

  ToolResult _help(String toolUseId) {
    return ToolResult(
      toolUseId: toolUseId,
      content:
          '''MarketData actions:

A-SHARE DATA:
  quote   — Real-time quotes (TDX→EastMoney→Sina→Tencent fallback). symbols: ["600519"]. Convertible-bond quote symbols such as ["110059"] use bond.convertible_quote. Returns: price/change/volume/PE/PB/marketCap
  kline   — Governed daily historical K-line (TDX→EastMoney fallback). symbols: ["600519"], period: daily, startDate: "2024-01-01", endDate: "2025-01-01", adjust: qfq|hfq|none. Mobile Tencent ETF daily OHLCV and convertible-bond daily K-line are governed only for adjust:none.
  flow    — Money flow (EastMoney; TDX does not provide this action). symbols: ["600519"]. Returns: main/small/medium/large net inflow
  flow_rank — Market-wide money flow ranking (全市场资金流入排名). period: today|3day|5day|10day
  sector  — Sector/board rankings (板块排名). boardType: industry|concept|area. Returns: top sectors with leading stocks
  chip    — Chip distribution (筹码分布). symbols: ["600519"]. Returns: avg cost, profit ratio, concentration
  earnings — Financial report (财务指标). symbols: ["600519"]. Returns: revenue, profit, YoY growth, margins, ROE, cash flow (last 4 quarters)
  etf     — All ETF quotes. No symbols needed.
  listed_fund_quote — Bounded exchange-listed fund and money-market fund quotes. provider: tencent. Persists quote_snapshot and listed_fund stock_list identities; read back with query_listed_fund_quote.
  limit_up  — Limit-up stock pool (涨停股池). startDate: "2026-05-07" or "20260507" (optional, defaults to today)
  limit_down — Limit-down stock pool (跌停股池). Same params as limit_up
  hot_rank — Hot stock ranking (人气榜/东方财富). limit: 50 (default)
  dragon_tiger — Dragon tiger board (龙虎榜). startDate: "2026-05-07" (optional)
  northbound — Northbound capital (北向资金). symbols: ["600519"] for individual holding, omit for daily flow history. limit: 20
  unusual — Unusual market activity (盘口异动: 火箭发射/大笔买入/涨停打开等). Real-time
  tushare — Tushare Pro API (需要TUSHARE_TOKEN). Registered schemas persist to local reusable SQLite by default; use persist:false only for inspection.
    Persisted schemas: stock_basic, daily/weekly/monthly/index_daily, daily_basic, trade_cal
    Disabled in this app: fina_indicator, income, balancesheet, cashflow, moneyflow, fund_basic, fund_nav
    api_name: "daily", params: {ts_code:"600519.SH"}

GLOBAL DATA:
  scan    — TradingView Scanner. symbols: ["NASDAQ:AAPL"]. indicators: [RSI, MACD.macd, ...], timeframe: 1d
  price   — Yahoo Finance prices. symbols: ["AAPL", "BTC-USD", "^GSPC"]
  yahoo_history — Yahoo historical daily bars. symbols: ["AAPL"], period/range: 1mo|3mo|6mo|1y|2y|3y. Persists kline_daily with adjust:none and source yahoo.
  option_daily_kline — Yahoo option-contract daily bars. symbols: ["AAPL260619C00100000"], period/range: 1mo|3mo|6mo|1y|2y|3y. Persists kline_daily with interface option.daily_kline and source yahoo.
  yahoo_earnings — Yahoo company/profile + financial statement summaries. symbols: ["AAPL"]. Check interface_availability for global.company_profile first; if current Yahoo/yfinance evidence is credential-gated (401/403), reuse query_global_company_profile/query_yfinance cache instead of live refresh. Persists yfinance_profile_fields, yfinance_statement_items, yfinance_recommendations, yfinance_holders, yfinance_insider_transactions when live refresh is allowed.
  global_income_statement/global_balance_sheet/global_cash_flow — Fetch and reread governed Yahoo annual statement slices. symbols: ["AAPL"].
  global_quarterly_income_statement/global_quarterly_balance_sheet/global_quarterly_cash_flow — Fetch and reread governed Yahoo quarterly statement slices. symbols: ["AAPL"].
  global_major_holders — Fetch and reread governed Yahoo major-holders rows. symbols: ["AAPL"].
  yahoo_news — Yahoo Finance news search. symbols: ["AAPL"], limit: 10. Persists yfinance_news.
  yahoo_options — Yahoo option chain. symbols: ["AAPL"], expiry: "2026-06-19" optional. Check interface_availability for option.chain_snapshot first; if current Yahoo/yfinance evidence is credential-gated (401/403), reuse query_option_chain_snapshot/query_yfinance cache instead of live refresh. Persists yfinance_option_expiries and yfinance_option_contracts when live refresh is allowed.
  yahoo_actions — Yahoo dividends/splits/capital gains. symbols: ["AAPL"], period: "5y". Persists yfinance_corporate_actions.
  global_capital_gains — Fetch and reread governed Yahoo capital-gains rows. symbols: ["AAPL"], period: "5y".
  backtest — Strategy backtest. symbols: ["AAPL"], strategy: rsi|rsi_conservative|macd|bollinger|boll|boll_tight|ema_cross|supertrend|donchian|kdj|ma_golden_cross|volume_breakout|dual_thrust|adx_emerging|mean_reversion|turtle_breakout|compare, period: 1y
  custom_strategy_help/custom_strategy_validate/custom_strategy_backtest/custom_strategy_observe/custom_strategy_fund_backtest/custom_strategy_rank/custom_strategy_save/custom_strategy_list/custom_strategy_compare/custom_strategy_run — Governed custom StrategySpec path for agent-created strategies. Use custom_strategy_help as the code-owned discovery surface for the current executable indicator catalog ($_customStrategyIndicatorSummary), dataRequirements, lifecycle fields, and output contracts. Fund StrategySpec must set assetClass:"fund" or market:"fund" and accepts nav_trend/rolling_return/fund_drawdown/fund_volatility/fund_momentum_acceleration/money_yield/seven_day_yield/dca_interval as fund observation rules; use custom_strategy_observe for current signal evidence and custom_strategy_fund_backtest for NAV/yield period evidence with fundRows from query_fund_nav/query_fund_money_yield/query_fund_performance. Multiple fund code groups return comparisonEvidence for fund comparison. Use custom_strategy_rank for stock multi-symbol ranking/rebalance evidence, including portfolioScoringEvidence. Use custom_strategy_compare for saved artifact comparison; it reads existing lifecycle/metric/portfolio/data coverage evidence and does not rerun or fetch. Use outOfSampleRatio for holdout validation and walkForwardFolds for chronological walk-forward stability evidence. Do not send fund specs to custom_strategy_backtest. Validate first; only supported stock indicators/rules compile into sandboxed stock backtests. custom_strategy_backtest returns lifecycleAdvice; lifecycleAdvice.saveable=true means status:"backtested" can be saved/rerun even when metrics.tradeCount is 0. Unsupported source signals must stay as unsupported indicator types during validation; proxy redesign requires proxyFor, unsupportedOriginalSignals, and proxyApproval:{approved:true}. Prefer structured fields such as validationSummary, validationIssues, unsupportedDetails, dataCoverage, lifecycleAdvice, lifecycleIssue, and readback_only over prose.
  custom_strategy_rank — Validate a stock StrategySpec, run it across symbols[], rank candidates, and return equal-weight top-N rebalance evidence plus portfolioScoringEvidence. This is the governed strategy-candidate scoring surface; do not add legacy DataProcess technical scoring after using it. rankingMetric may be score, total_return_pct, sharpe_ratio, max_drawdown_pct, trade_count, relative_strength_pct, or rps. Optional rebalanceInterval, maxPositionWeight, and minScore are evidence-only draft assumptions; minScore excludes weak ranked rows from the rebalance draft but keeps them visible with selectionEvidence. This is not a trade/order action.

SYSTEM:
  help    — This help text
  interfaces — List governed Data API interfaces before picking a fetch/query path. category/provider/health/limit optional.
  interface_describe — Explain one governed or controlled output-only interface contract. interfaceId required. Returns schema, query actions, freshness policy, provider capabilities, and current health. Output-only boundaries such as provider.diagnostic are known but not normal reusable mobile data workflows.
  interface_availability — Explain whether one interface is reusable now or needs provider refresh. interfaceId required; provider/providerMode optional.
  sources — Data source health/circuit breaker status + available sources
  data_health — Interface/provider/cache/API-error health. section: summary|interfaces|providers|gaps|failures|all. Returns providerGapQueue, credentialActivationQueue, policyDisabledQueue, and failureActionQueue. It also returns credentialValidatedQueue for credential-gated capabilities with valid live evidence.
  finance_doctor — Local runtime/session/DataStore/provider readiness report. Use before continuing a workflow when session/history, runtime path, cache, API failure, or feed health may explain failures.
  runtime_probe — Agent-visible controlled runtime probe entry. probeAction: status|run; probeMode: credential|unstable|failures|all; optional probeIds for explicit bounded selections. Start with status and inspect recommendedTargets, blockedTargets, providerProbePacks, and guidance before running a bounded probe. Automatic failures/all runs only select retryable transport, timeout, provider-error, runtime-unavailable, or transport-unstable targets. Credential/permission, quota/rate-limit, unsupported-route, runtime-blocked, schema-contract, schema-mismatch, and explicit do-not-retry rows stay in blockedTargets until the root cause changes or the user explicitly chooses bounded probeIds. Runs only mobile-native governed probes and persists durable evidence under data/runtime-probes.
  fetch_status — Local durable fetch/data-task queue. status: pending|running|failed|completed|cancelled|all. Returns provenance with interfaceId, capabilityId, cacheStatus, canonicalSchema, canonicalTable, and readbackAction. Failed rows are split into actionableFailures and nonActionableEvidence with nextAction guidance before retry.
  coverage — Local reusable data coverage. Optional symbols: ["600519"]
  reusable_summary — Summary of persisted reusable finance data
  query_quote — Read persisted quote snapshots. symbols: ["600519"]
  query_index_quote — Read persisted governed index.quote snapshots. symbols: ["000001"]
  query_etf_quote — Read persisted governed fund.etf_quote snapshots. symbols: ["510300"]
  query_listed_fund_quote — Read persisted governed fund.listed_fund_quote snapshots. symbols: ["511880"]
  query_bond_quote — Read persisted governed bond.convertible_quote snapshots. symbols: ["110059"]
  query_kline — Read persisted daily K-line rows. symbols: ["600519"], startDate/endDate/adjust
  query_bond_kline — Read persisted governed bond.convertible_daily_kline rows. symbols: ["110059"], startDate/endDate/adjust. Tencent mobile support is unadjusted adjust:none only. ETF daily OHLCV rows reuse query_kline.
  query_option_daily_kline — Read persisted Yahoo option-contract daily K-line rows. symbols: ["AAPL260619C00100000"], startDate/endDate
  query_stock_daily_valuation — Read persisted stock daily valuation/fundamental rows. symbols: ["600519"]
  query_fundamental — Compatibility readback over the same persisted stock daily valuation rows. symbols: ["600519"]
  query_fund_financials — Read persisted Wind fund.financials rows. symbols: ["110011"] or ["110011.OF"], reportDate optional.
  query_index_fundamentals — Read persisted Wind index.fundamentals rows. symbols: ["000300"], reportDate optional.
  query_bond_issuer_financials — Read persisted Wind bond.issuer_financials rows. symbols: ["019521.SH"] or issuer code, reportDate optional.
  query_money_flow — Read persisted money-flow rows. symbols: ["600519"]
  query_fund_nav — Read persisted fund NAV rows. symbols: ["110011.OF"], startDate/endDate
  query_fund_money_yield — Read persisted money-fund per-10k income and seven-day annualized yield rows. symbols: ["000009"], startDate/endDate
  fund_dividend_factor — Refresh governed Sina ETF dividend/factor rows. symbols: ["510050"], limit optional; persists fund_dividend_factor.
  query_fund_dividend_factor — Read persisted fund dividend/factor rows. symbols: ["510050"], startDate/endDate
  intraday_ohlcv_bars — Refresh governed Sina intraday OHLCV bars. symbols: ["600519"], intervalMinutes:5, limit optional; persists intraday_ohlcv_bars.
  query_intraday_ohlcv_bars — Read persisted intraday OHLCV bars. symbols: ["600519"], intervalMinutes:5, startDate/endDate
  query_fund_list — Read persisted fund list rows. fundType/company/limit optional
  stock_list — Fetch and persist governed stock.identity_list rows from native EastMoney provider routing.
  fund_list — Fetch and persist governed fund_list rows from native EastMoney provider routing.
  fund_nav — Fetch and persist governed fund_nav rows from native EastMoney provider routing. symbols:["110011.OF"] or fundCode/code required.
  fund_money_yield — Fetch and persist governed fund_money_yield rows from native EastMoney provider routing. symbols:["000009"] or fundCode/code required. Use for money funds instead of ordinary fund_nav.
  fund_manager — Fetch and persist governed fund_manager rows from native EastMoney provider routing.
  query_fund_manager — Read persisted fund_manager rows. company/manager/fundCode/code/limit optional. Returns provenance with interfaceId and cacheStatus.
  fund_holding — Fetch and persist governed fund_holding rows from native EastMoney provider routing. symbols:["110011"] or fundCode/code required.
  stock_risk_metrics — Fetch and persist governed Wind stock.risk_metrics rows. symbols:["600519"] required; provider override only supports wind.
  fund_company_info — Fetch and persist governed Wind fund.company_info rows. symbols:["110011"] or ["110011.OF"] required; provider override only supports wind.
  fund_investor_holders — Fetch and persist governed Wind fund.investor_holders rows. symbols:["110011"] or ["110011.OF"] required; provider override only supports wind.
  fund_financials — Fetch and persist governed Wind fund.financials rows. symbols:["110011"] or ["110011.OF"] required; reportDate optional; provider override only supports wind.
  index_fundamentals — Fetch and persist governed Wind index.fundamentals rows. symbols:["000300"] required; reportDate optional; provider override only supports wind.
  index_profile — Fetch and persist governed Wind index.profile rows. symbols:["000300"] required; provider override only supports wind.
  bond_profile — Fetch and persist governed Wind bond.profile rows. symbols:["019521.SH"] or issuer code required; provider override only supports wind.
  bond_market_data — Fetch and persist governed Wind bond.market_data rows. symbols:["019521.SH"] required; provider override only supports wind.
  bond_issuer_financials — Fetch and persist governed Wind bond.issuer_financials rows. symbols:["019521.SH"] or issuer code required; reportDate optional; provider override only supports wind.
  trade_calendar — Fetch and persist governed trade_calendar rows through calendar.trade_days routing. year or startDate/endDate optional; market defaults to CN; provider override supports szse or tushare.
  index_constituents — Fetch and persist governed index_constituent rows through the credential-gated Tushare index_weight route. symbols:["000300"] required; asOfDate/date optional.
  stock_company_info — Fetch and persist governed stock.company_info rows from native EastMoney company survey routing. symbols:["600519"] required.
  finance_news — Fetch and persist governed finance_news rows through the news.finance_feed interface. query/keyword required; provider/providerMode/cacheMode/allowFallback/source/limit optional.
  query_finance_news — Read persisted finance_news rows from Research(news). keyword/query/source/limit optional. Returns provenance with interfaceId, cacheStatus, sourceDataTime, fetchedAt.
  query_fund_holding — Read persisted fund_holding rows. fundCode/code/symbols optional, stockCode/reportDate/limit optional. Returns provenance with interfaceId, cacheStatus, sourceDataTime, fetchedAt.
  query_index_constituents — Read persisted index_constituent rows. indexCode/code/symbols optional, stockCode/asOfDate/provider/limit optional. Returns provenance with interfaceId, cacheStatus, sourceDataTime, fetchedAt.
  fund_performance — Fetch and persist governed fund_performance_metrics rows from native EastMoney provider routing.
  query_fund_performance — Read persisted fund_performance_metrics rows. symbols/code/fundCode optional, provider/metricDate/date/limit optional. Returns provenance with interfaceId, cacheStatus, sourceDataTime, fetchedAt.
  stock_shareholders — Fetch and persist governed stock_shareholder rows from native EastMoney shareholder routing. symbols:["600519"], reportDate/date optional.
  query_trade_calendar — Read persisted Tushare trade calendar rows. market/startDate/endDate optional
  query_stock_list — Read persisted stock_list rows. market/industry/stockType(type)/limit optional
  query_board_members — Read persisted governed market.board_members rows. boardCode/boardName/code/industry/limit optional
  query_sector_constituents — Read persisted governed market.sector_constituents rows. sectorCode/sectorName/code/industry/limit optional
  query_industry_map — Compatibility readback over persisted market.sector_constituents rows. code/industry/limit optional
  query_ex_categories — Read persisted ExTDX market categories. limit optional
  query_tdx_count — Read persisted TDX / ExTDX security-count snapshots. scope: main|ex, market/limit optional
  query_tdx_sampling — Read persisted TDX / ExTDX chart-sampling rows. symbols optional, scope/category/market/limit optional
  query_ex_table — Read persisted ExTDX table entries. code/category/limit optional
  query_tdx_block_member — Read persisted TDX block-file members. symbols/code optional, blockCode/filename/blockName optional
  query_wind_document — Read persisted Wind document/news rows before another Wind call. query/tool/code/limit optional. Returns provenance with interfaceId, provider, cacheStatus, sourceDataTime, fetchedAt.
  query_wind_economic — Read persisted Wind economic series rows before another Wind call. metricQuery/limit optional. Returns provenance with interfaceId, provider, cacheStatus, sourceDataTime, fetchedAt.
  query_wind_analytics — Read persisted Wind analytics rows before another Wind call. question/limit optional. Returns provenance with interfaceId, provider, cacheStatus, sourceDataTime, fetchedAt.
  query_tick_chart — Read persisted TDX intraday minute rows. symbols: ["600519"], date: "2026-06-04"
  query_transactions — Read persisted stock or ETF transactions from the canonical transactions table. symbols: ["600519"] or ["510300"], instrumentType optional, date/limit
  query_volume_profile — Read persisted TDX volume profile rows. symbols: ["600519"], date/limit
  query_xdxr — Read persisted TDX ex-rights/dividend events. symbols: ["600519"]
  query_auction — Read persisted TDX auction snapshots. symbols: ["600519"], date/limit
  query_momentum — Read persisted TDX index momentum rows. symbols: ["000001"], date/limit
  query_top_board — Read persisted TDX top board rankings. symbols optional, category/side/date/limit
  query_tdx_block_member — Read persisted TDX block-file members. symbols optional, blockCode/filename/blockName/limit
  query_tdx_count — Read persisted TDX / ExTDX security counts. scope: main|ex, market optional
  query_tdx_sampling — Read persisted TDX / ExTDX chart-sampling rows. symbols/code/category/limit optional
  query_ex_table — Read persisted ExTDX table entries. code/category/limit optional
  query_stock_company_info — Read persisted stock company/F10 payloads. symbols: ["600519"]
  query_company_info — Compatibility readback over persisted stock/fund/index/bond company-info style rows. symbols: ["600519"]
  query_stock_risk_metrics — Read persisted Wind stock.risk_metrics rows. symbols: ["600519"], infoType optional.
  query_fund_company_info — Read persisted Wind fund.company_info rows. symbols: ["110011.OF"] or ["110011"], infoType optional.
  query_fund_investor_holders — Read persisted Wind fund.investor_holders rows. symbols: ["110011.OF"] or ["110011"], infoType optional.
  query_index_profile — Read persisted Wind index.profile rows. symbols: ["000300"], infoType optional.
  query_bond_profile — Read persisted Wind bond.profile rows. symbols: ["019521.SH"], infoType optional.
  query_bond_market_data — Read persisted Wind bond.market_data rows. symbols: ["019521.SH"], infoType optional.
  query_stock_shareholders — Read persisted stock shareholder rows. code/symbol optional, holderName/name/query optional, reportDate/date optional
  query_hot_rank — Read persisted EastMoney hot rank rows. symbols optional, date/limit
  query_dragon_tiger — Read persisted EastMoney dragon tiger rows. symbols optional, date/limit
  query_limit_pool — Read persisted EastMoney limit-up/down pools. poolType: limit_up|limit_down
  query_northbound — Read persisted EastMoney northbound flow/holding. symbols optional; kind: flow|holding
  query_northbound_flow — Read persisted EastMoney northbound flow. date/limit optional
  query_northbound_holding — Read persisted EastMoney northbound holdings. symbols optional; date/limit optional
  query_unusual — Read persisted EastMoney unusual activity. symbols optional
  query_flow_rank — Read persisted EastMoney money-flow ranking. period: today|3day|5day|10day
  market_activity_summary — Bounded first-pass market activity summary over local hot-rank, flow-rank, limit-pool, unusual, dragon-tiger, and cached quote context
  query_sector_ranking — Read persisted governed market.sector_ranking rows. boardType: industry|concept|area
  query_sector — Compatibility readback for governed market.sector_ranking rows. boardType: industry|concept|area
  query_board_ranking — Read persisted governed market.board_ranking rows. boardType: industry|concept|area
  query_chip — Read persisted EastMoney chip distribution. symbols: ["600519"], date/limit
  query_market_screening — Read persisted market screening snapshots. symbols optional; provider/sourceAction/since/limit optional
  query_margin_trading — Read persisted margin_trading rows. symbols/code optional; date/tradeDate/provider/limit optional.
  margin_trading — Fetch and persist governed margin_trading rows through the mobile official exchange route. symbols:["600519"] or ["000001"], date/tradeDate optional, provider optional: sse|szse.
  query_technical_indicator — Read persisted technical_indicator_series rows. symbols/code optional; indicator/func/fieldName/since/provider/limit optional
  query_alpha_factors — Read persisted alpha_factor rows. symbols/code optional; factorName/factor/since/provider/limit optional
  query_yfinance — Read persisted Yahoo/yfinance rows. dataset: profile|statements|income_statement|balance_sheet|cash_flow|earnings_calendar|earnings_history|earnings_estimates|eps_revisions|eps_trend|quarterly_financial_statements|quarterly_income_statement|quarterly_balance_sheet|quarterly_cash_flow|recommendations|upgrade_downgrade_events|news|options|option_expiries|option_open_interest|option_volume|option_implied_volatility|option_moneyness|option_bid_ask_spread|option_price_change|option_trade_recency|actions|dividends|splits|holders|institutional_holders|mutual_fund_holders|insiders
  query_raw_payload — Read legacy/explicit raw audit payloads for diagnostics. Unknown schemas from normal provider calls are returned only, not persisted.
  query_api_calls — Read recent failed provider/API calls from API stats. source optional, minutes optional, limit optional. Use before retrying EastMoney/Tushare/Wind/Yahoo failures.
  query_api_errors — Compatibility alias for query_api_calls.''',
    );
  }

  ToolResult _interfaces(String toolUseId, Map<String, dynamic> input) {
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(
        _supportService.interfaceCatalog(
          category: input['category'] as String?,
          provider: input['provider'] as String?,
          health: input['health'] as String?,
          limit: (input['limit'] as num?)?.toInt() ?? 30,
        ),
      ),
    );
  }

  ToolResult _interfaceDescribe(String toolUseId, Map<String, dynamic> input) {
    final interfaceId = '${input['interfaceId'] ?? ''}'.trim();
    if (interfaceId.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'interfaceId is required for interface_describe.',
        isError: true,
      );
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent(
        '  ',
      ).convert(_supportService.interfaceDescribe(interfaceId)),
    );
  }

  ToolResult _interfaceAvailability(
    String toolUseId,
    Map<String, dynamic> input,
  ) {
    final interfaceId = '${input['interfaceId'] ?? ''}'.trim();
    if (interfaceId.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'interfaceId is required for interface_availability.',
        isError: true,
      );
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(
        _supportService.interfaceAvailability(
          interfaceId,
          provider: input['provider'] as String?,
          providerMode: input['providerMode'] as String?,
        ),
      ),
    );
  }

  ToolResult _sources(String toolUseId) {
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent(
        '  ',
      ).convert(_supportService.sources()),
    );
  }

  ToolResult _stats(String toolUseId) {
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent(
        '  ',
      ).convert(_supportService.stats()),
    );
  }

  ToolResult _dataHealth(String toolUseId, Map<String, dynamic> input) {
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(
        _supportService.dataHealth(
          section: input['section'] as String? ?? 'summary',
          limit: (input['limit'] as num?)?.toInt() ?? 20,
        ),
      ),
    );
  }

  ToolResult _financeDoctor(String toolUseId, ToolContext context) {
    final report = buildFinanceDoctorReport(basePath: context.basePath);
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'action': 'finance_doctor',
        'provenance': {
          'interfaceId': 'data.health',
          'providerId': 'local',
          'provider': 'local',
          'capabilityId': 'local.finance_doctor',
          'providerMode': 'local-evidence',
          'cacheStatus': 'local-evidence',
          'canonicalSchema': 'finance_doctor_report',
          'canonicalTable': 'finance_doctor_report',
          'readbackAction': 'finance_doctor',
          'failureClass': null,
          'source':
              'FinAgent/shared-mobile local runtime, session, API, task, and reusable-store checks',
          'fetchedAt': DateTime.now().toUtc().toIso8601String(),
        },
        'report': report.toJson(),
      }),
    );
  }

  Future<ToolResult> _runtimeProbe(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final probeAction = '${input['probeAction'] ?? 'status'}'
        .trim()
        .toLowerCase();
    final probeMode = '${input['probeMode'] ?? 'all'}'.trim().toLowerCase();
    final probeIds = (input['probeIds'] as List?)
        ?.map((value) => '$value'.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final payload = probeAction == 'run'
        ? await _runtimeProbeService.run(
            context.basePath,
            context,
            mode: probeMode,
            probeIds: probeIds ?? const [],
          )
        : _runtimeProbeService.status(context.basePath);
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  ToolResult _coverage(String toolUseId, List<String> symbols) {
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(
        _supportService.coverage(
          code: symbols.isNotEmpty ? symbols.first : null,
        ),
      ),
    );
  }

  ToolResult _fetchStatus(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(
        _supportService.fetchTaskQueue(
          basePath: context.basePath,
          status: input['status'] as String?,
          limit: (input['limit'] as num?)?.toInt() ?? 20,
        ),
      ),
    );
  }
}
