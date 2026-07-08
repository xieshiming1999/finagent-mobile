import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/tool_context.dart';
import 'market_data_backtest_action_service.dart';
import 'market_data_market_action_service.dart';
import 'market_data_query_action_service.dart';
import 'market_data_tdx_action_service.dart';
import 'market_data_tushare_action_service.dart';

class MarketDataActionService {
  final MarketDataQueryActionService _query;
  final MarketDataMarketActionService _market;
  final MarketDataTdxActionService _tdx;
  final MarketDataBacktestActionService _backtest;
  final MarketDataTushareActionService _tushare;

  MarketDataActionService({
    DataManager? dataManager,
    MarketDataQueryActionService? query,
    MarketDataMarketActionService? market,
    MarketDataTdxActionService? tdx,
    MarketDataBacktestActionService? backtest,
    MarketDataTushareActionService? tushare,
  }) : _query = query ?? MarketDataQueryActionService(dataManager: dataManager),
       _market =
           market ?? MarketDataMarketActionService(dataManager: dataManager),
       _tdx = tdx ?? MarketDataTdxActionService(dataManager: dataManager),
       _backtest =
           backtest ??
           MarketDataBacktestActionService(dataManager: dataManager),
       _tushare =
           tushare ?? MarketDataTushareActionService(dataManager: dataManager);

  Future<Object> run(
    String action,
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    if (_queryActions.contains(action)) {
      return _query.query(action, symbols, input, context);
    }
    if (_marketActions.contains(action)) {
      return await _market.run(action, symbols, input, context);
    }
    if (_tdxActions.contains(action)) {
      return await _tdx.run(action, symbols, input, context);
    }
    if (_backtestActions.contains(action)) {
      return await _backtest.run(action, symbols, input, context);
    }
    if (_tushareActions.contains(action)) {
      return await _tushare.run(action, input);
    }
    throw ArgumentError('Unsupported MarketData action: $action');
  }
}

const _queryActions = {
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
  'query_intraday_ohlcv_bars',
  'query_fund_list',
  'query_fund_manager',
  'query_finance_news',
  'query_fund_holding',
  'query_fund_performance',
  'query_trade_calendar',
  'query_stock_list',
  'query_index_constituents',
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
  'query_macro_factors',
  'query_margin_trading',
  'query_technical_indicator',
  'query_alpha_factors',
  'query_raw_payload',
  'query_api_calls',
  'query_api_errors',
};

const _marketActions = {
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
  'trade_calendar',
  'index_constituents',
  'stock_company_info',
  'stock_shareholders',
  'stock_risk_metrics',
  'fund_company_info',
  'fund_investor_holders',
  'fund_financials',
  'index_fundamentals',
  'index_profile',
  'bond_profile',
  'bond_market_data',
  'bond_issuer_financials',
  'margin_trading',
  'earnings',
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
  'limit_up',
  'limit_down',
  'hot_rank',
  'dragon_tiger',
  'northbound',
  'unusual',
};

const _tdxActions = {
  'intraday_ohlcv_bars',
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
};

const _backtestActions = {
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
  'custom_strategy_read',
  'custom_strategy_compare',
  'custom_strategy_run',
  'backtest_batch',
  'optimize_params',
};

const _tushareActions = {'tushare'};
