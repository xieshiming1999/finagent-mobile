part of 'reusable_data_store.dart';

extension ReusableDataStoreYfinanceQuery on ReusableDataStore {
  List<Map<String, dynamic>> queryYfinanceDataset(
    String dataset,
    String symbol, {
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    final normalizedDataset = switch (dataset.trim().toLowerCase()) {
      'expiries' => 'option_expiries',
      'open_interest' => 'option_open_interest',
      'volume' => 'option_volume',
      'implied_volatility' => 'option_implied_volatility',
      'moneyness' || 'in_the_money' => 'option_moneyness',
      'spread' ||
      'option_spread' ||
      'bid_ask_spread' => 'option_bid_ask_spread',
      'price_change' || 'change' || 'percent_change' => 'option_price_change',
      'trade_recency' ||
      'last_trade' ||
      'last_trade_date' => 'option_trade_recency',
      'earnings_dates' => 'earnings_calendar',
      'earnings_estimate' => 'earnings_estimates',
      'income' || 'income_stmt' => 'income_statement',
      'balancesheet' => 'balance_sheet',
      'cashflow' => 'cash_flow',
      'quarterly_financials' ||
      'quarterly_statements' => 'quarterly_financial_statements',
      'quarterly_income' ||
      'quarterly_income_stmt' => 'quarterly_income_statement',
      'quarterly_balancesheet' => 'quarterly_balance_sheet',
      'quarterly_cashflow' => 'quarterly_cash_flow',
      'upgrades_downgrades' ||
      'upgrades' ||
      'downgrades' => 'upgrade_downgrade_events',
      'capitalgains' => 'capital_gains',
      final value => value,
    };
    final spec = switch (normalizedDataset) {
      'recommendations' => (
        table: 'yfinance_recommendations',
        order: 'period DESC',
        where: '',
      ),
      'earnings_calendar' => (
        table: 'yfinance_statement_items',
        order: 'period DESC, statement_type, item',
        where: "AND statement_type IN ('earnings_dates', 'earnings_history')",
      ),
      'earnings_history' => (
        table: 'yfinance_statement_items',
        order: 'period DESC, item',
        where: "AND statement_type = 'earnings_history'",
      ),
      'earnings_estimates' => (
        table: 'yfinance_statement_items',
        order: 'period DESC, item',
        where: "AND statement_type = 'earnings_estimate'",
      ),
      'income_statement' => (
        table: 'yfinance_statement_items',
        order: 'period DESC, item',
        where: "AND statement_type = 'income'",
      ),
      'balance_sheet' => (
        table: 'yfinance_statement_items',
        order: 'period DESC, item',
        where: "AND statement_type = 'balance_sheet'",
      ),
      'cash_flow' => (
        table: 'yfinance_statement_items',
        order: 'period DESC, item',
        where: "AND statement_type = 'cash_flow'",
      ),
      'eps_revisions' => (
        table: 'yfinance_statement_items',
        order: 'period DESC, item',
        where: "AND statement_type = 'eps_revisions'",
      ),
      'eps_trend' => (
        table: 'yfinance_statement_items',
        order: 'period DESC, item',
        where: "AND statement_type = 'eps_trend'",
      ),
      'quarterly_financial_statements' => (
        table: 'yfinance_statement_items',
        order: 'period DESC, statement_type, item',
        where:
            "AND statement_type IN ('quarterly_financials', 'quarterly_income_stmt', 'quarterly_balance_sheet', 'quarterly_balancesheet', 'quarterly_cash_flow', 'quarterly_cashflow')",
      ),
      'quarterly_income_statement' => (
        table: 'yfinance_statement_items',
        order: 'period DESC, item',
        where: "AND statement_type = 'quarterly_income_stmt'",
      ),
      'quarterly_balance_sheet' => (
        table: 'yfinance_statement_items',
        order: 'period DESC, item',
        where:
            "AND statement_type IN ('quarterly_balance_sheet', 'quarterly_balancesheet')",
      ),
      'quarterly_cash_flow' => (
        table: 'yfinance_statement_items',
        order: 'period DESC, item',
        where:
            "AND statement_type IN ('quarterly_cash_flow', 'quarterly_cashflow')",
      ),
      'upgrade_downgrade_events' => (
        table: 'yfinance_recommendations',
        order: 'period DESC',
        where: '',
      ),
      'news' => (table: 'yfinance_news', order: 'published_at DESC', where: ''),
      'options' => (
        table: 'yfinance_option_contracts',
        order: 'expiry_date DESC, option_type, strike',
        where: '',
      ),
      'option_open_interest' => (
        table: 'yfinance_option_contracts',
        order: 'expiry_date DESC, open_interest DESC, option_type, strike',
        where: 'AND open_interest IS NOT NULL',
      ),
      'option_volume' => (
        table: 'yfinance_option_contracts',
        order: 'expiry_date DESC, volume DESC, option_type, strike',
        where: 'AND volume IS NOT NULL',
      ),
      'option_implied_volatility' => (
        table: 'yfinance_option_contracts',
        order: 'expiry_date DESC, implied_volatility DESC, option_type, strike',
        where: 'AND implied_volatility IS NOT NULL',
      ),
      'option_moneyness' => (
        table: 'yfinance_option_contracts',
        order: 'expiry_date DESC, in_the_money DESC, option_type, strike',
        where: 'AND in_the_money IS NOT NULL',
      ),
      'option_bid_ask_spread' => (
        table: 'yfinance_option_contracts',
        order: 'expiry_date DESC, (ask - bid) ASC, option_type, strike',
        where: 'AND bid IS NOT NULL AND ask IS NOT NULL',
      ),
      'option_price_change' => (
        table: 'yfinance_option_contracts',
        order:
            'expiry_date DESC, ABS(percent_change) DESC, option_type, strike',
        where: 'AND (change IS NOT NULL OR percent_change IS NOT NULL)',
      ),
      'option_trade_recency' => (
        table: 'yfinance_option_contracts',
        order: 'last_trade_date DESC, expiry_date DESC, option_type, strike',
        where: 'AND last_trade_date IS NOT NULL',
      ),
      'option_expiries' => (
        table: 'yfinance_option_expiries',
        order: 'expiry_date DESC',
        where: '',
      ),
      'actions' => (
        table: 'yfinance_corporate_actions',
        order: 'action_date DESC, action_type',
        where: '',
      ),
      'dividends' => (
        table: 'yfinance_corporate_actions',
        order: 'action_date DESC',
        where: "AND action_type IN ('dividend', 'dividends')",
      ),
      'splits' || 'stock_splits' => (
        table: 'yfinance_corporate_actions',
        order: 'action_date DESC',
        where: "AND action_type IN ('split', 'splits')",
      ),
      'holders' => (
        table: 'yfinance_holders',
        order: 'holder_type, reported_date DESC, holder_name',
        where: '',
      ),
      'major_holders' => (
        table: 'yfinance_holders',
        order: 'reported_date DESC, holder_name',
        where: "AND holder_type = 'major_holders'",
      ),
      'institutional_holders' || 'institutions' => (
        table: 'yfinance_holders',
        order: 'reported_date DESC, holder_name',
        where: "AND holder_type IN ('institutional_holders', 'institutional')",
      ),
      'mutualfund_holders' || 'mutual_fund_holders' || 'fund_holders' => (
        table: 'yfinance_holders',
        order: 'reported_date DESC, holder_name',
        where: "AND holder_type IN ('mutualfund_holders', 'fund')",
      ),
      'insiders' => (
        table: 'yfinance_insider_transactions',
        order: 'start_date DESC, insider',
        where: '',
      ),
      'capital_gains' => (
        table: 'yfinance_corporate_actions',
        order: 'action_date DESC',
        where: "AND action_type = 'capital_gains'",
      ),
      _ => null,
    };
    if (spec == null) return const [];
    final rows = db.select(
      '''
      SELECT * FROM ${spec.table}
      WHERE symbol = ?
      ${spec.where}
      ORDER BY ${spec.order}
      LIMIT ?
      ''',
      [symbol.trim().toUpperCase(), limit],
    );
    return rows.map(_rowMap).toList();
  }
}
