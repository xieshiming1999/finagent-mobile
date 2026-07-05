part of 'market_data_query_action_service.dart';

extension _MarketDataQueryActionYahooReadbacks on MarketDataQueryActionService {
  Map<String, dynamic> _queryYahooReadbackAction(
    String action,
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final symbol = _firstSymbol(symbols, _yfinanceError);
    final dataset = switch (action) {
      'query_global_company_profile' => 'profile',
      'query_global_financial_statements' => 'statements',
      'query_global_income_statement' => 'income_statement',
      'query_global_balance_sheet' => 'balance_sheet',
      'query_global_cash_flow' => 'cash_flow',
      'query_global_earnings_calendar' => 'earnings_calendar',
      'query_global_earnings_history' => 'earnings_history',
      'query_global_earnings_estimates' => 'earnings_estimates',
      'query_global_eps_revisions' => 'eps_revisions',
      'query_global_eps_trend' => 'eps_trend',
      'query_global_quarterly_financial_statements' =>
        'quarterly_financial_statements',
      'query_global_quarterly_income_statement' => 'quarterly_income_statement',
      'query_global_quarterly_balance_sheet' => 'quarterly_balance_sheet',
      'query_global_quarterly_cash_flow' => 'quarterly_cash_flow',
      'query_global_recommendations' => 'recommendations',
      'query_global_upgrade_downgrade_events' => 'upgrade_downgrade_events',
      'query_global_holders' => 'holders',
      'query_global_major_holders' => 'major_holders',
      'query_global_institutional_holders' => 'institutional_holders',
      'query_global_mutual_fund_holders' => 'mutual_fund_holders',
      'query_global_insider_transactions' => 'insiders',
      'query_global_finance_news' => 'news',
      'query_global_corporate_actions' => 'actions',
      'query_global_dividends' => 'dividends',
      'query_global_capital_gains' => 'capital_gains',
      'query_global_stock_splits' => 'splits',
      'query_option_expiry_calendar' => 'option_expiries',
      'query_option_contract_list' => 'options',
      'query_option_quote' => 'options',
      'query_option_daily_kline' => 'option_daily_kline',
      'query_option_open_interest' => 'option_open_interest',
      'query_option_volume' => 'option_volume',
      'query_option_implied_volatility' => 'option_implied_volatility',
      'query_option_moneyness' => 'option_moneyness',
      'query_option_bid_ask_spread' => 'option_bid_ask_spread',
      'query_option_price_change' => 'option_price_change',
      'query_option_trade_recency' => 'option_trade_recency',
      'query_option_chain_snapshot' => 'options',
      'query_global_options_chain' => 'options',
      _ => throw ArgumentError('Unsupported Yahoo readback action: $action'),
    };
    return _yahoo.queryDataset(context, symbol, {
      ...input,
      'dataset': dataset,
      '_queryAction': action,
    });
  }

  String _resolveKlineReadback(String action, {required String symbol}) {
    if (action == 'query_option_daily_kline') return 'option.daily_kline';
    if (action == 'query_bond_kline') return 'bond.convertible_daily_kline';
    final upper = symbol.trim().toUpperCase();
    if (RegExp(r'^[A-Z]+[0-9]{6}[CP][0-9]{8}$').hasMatch(upper)) {
      return 'option.daily_kline';
    }
    if (RegExp(r'^(11|12)\d{4}$').hasMatch(upper)) {
      return 'bond.convertible_daily_kline';
    }
    return 'stock.daily_kline';
  }
}
