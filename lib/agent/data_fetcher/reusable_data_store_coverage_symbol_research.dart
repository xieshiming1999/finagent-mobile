part of 'reusable_data_store.dart';

extension ReusableDataStoreCoverageSymbolResearch on ReusableDataStore {
  Map<String, dynamic> _coverageResearchRows(
    Database db,
    String clean,
    String symbol,
  ) {
    final windDocuments = db.select(
      'SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM wind_document WHERE entity_code = ?',
      [clean],
    ).first;
    final windAnalytics = db.select(
      'SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM wind_analytics_result WHERE entity_code = ?',
      [clean],
    ).first;
    final windRows = {
      'wind_document': _rowMap(windDocuments),
      'wind_analytics_result': _rowMap(windAnalytics),
    };
    if (_isAshareCoverageSymbol(symbol)) {
      return windRows;
    }
    final yfinanceProfile = db.select(
      'SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_profile_fields WHERE symbol = ?',
      [symbol],
    ).first;
    final yfinanceStatements = db.select(
      'SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_statement_items WHERE symbol = ?',
      [symbol],
    ).first;
    final yfinanceEarningsCalendar = db.select(
      "SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_statement_items WHERE symbol = ? AND statement_type IN ('earnings_dates', 'earnings_history')",
      [symbol],
    ).first;
    final yfinanceEarningsHistory = db.select(
      "SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_statement_items WHERE symbol = ? AND statement_type = 'earnings_history'",
      [symbol],
    ).first;
    final yfinanceEarningsEstimates = db.select(
      "SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_statement_items WHERE symbol = ? AND statement_type = 'earnings_estimate'",
      [symbol],
    ).first;
    final yfinanceEpsRevisions = db.select(
      "SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_statement_items WHERE symbol = ? AND statement_type = 'eps_revisions'",
      [symbol],
    ).first;
    final yfinanceEpsTrend = db.select(
      "SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_statement_items WHERE symbol = ? AND statement_type = 'eps_trend'",
      [symbol],
    ).first;
    final yfinanceQuarterlyStatements = db.select(
      "SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_statement_items WHERE symbol = ? AND statement_type IN ('quarterly_financials', 'quarterly_income_stmt', 'quarterly_balance_sheet', 'quarterly_balancesheet', 'quarterly_cash_flow', 'quarterly_cashflow')",
      [symbol],
    ).first;
    final yfinanceRecommendations = db.select(
      'SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_recommendations WHERE symbol = ?',
      [symbol],
    ).first;
    final yfinanceNews = db.select(
      'SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_news WHERE symbol = ?',
      [symbol],
    ).first;
    final yfinanceOptionExpiries = db.select(
      'SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_option_expiries WHERE symbol = ?',
      [symbol],
    ).first;
    final yfinanceOptionContracts = db.select(
      'SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_option_contracts WHERE symbol = ?',
      [symbol],
    ).first;
    final yfinanceActions = db.select(
      'SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_corporate_actions WHERE symbol = ?',
      [symbol],
    ).first;
    final yfinanceDividends = db.select(
      "SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_corporate_actions WHERE symbol = ? AND action_type IN ('dividend', 'dividends')",
      [symbol],
    ).first;
    final yfinanceSplits = db.select(
      "SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_corporate_actions WHERE symbol = ? AND action_type IN ('split', 'splits')",
      [symbol],
    ).first;
    final yfinanceHolders = db.select(
      'SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_holders WHERE symbol = ?',
      [symbol],
    ).first;
    final yfinanceInstitutionalHolders = db.select(
      "SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_holders WHERE symbol = ? AND holder_type IN ('institutional_holders', 'institutional')",
      [symbol],
    ).first;
    final yfinanceMutualFundHolders = db.select(
      "SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_holders WHERE symbol = ? AND holder_type IN ('mutualfund_holders', 'fund')",
      [symbol],
    ).first;
    final yfinanceInsiders = db.select(
      'SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM yfinance_insider_transactions WHERE symbol = ?',
      [symbol],
    ).first;
    return {
      'yfinance_profile_fields': _rowMap(yfinanceProfile),
      'yfinance_statement_items': _rowMap(yfinanceStatements),
      'yfinance_earnings_calendar': _rowMap(yfinanceEarningsCalendar),
      'yfinance_earnings_history': _rowMap(yfinanceEarningsHistory),
      'yfinance_earnings_estimates': _rowMap(yfinanceEarningsEstimates),
      'yfinance_eps_revisions': _rowMap(yfinanceEpsRevisions),
      'yfinance_eps_trend': _rowMap(yfinanceEpsTrend),
      'yfinance_quarterly_financial_statements': _rowMap(
        yfinanceQuarterlyStatements,
      ),
      'yfinance_recommendations': _rowMap(yfinanceRecommendations),
      'yfinance_upgrade_downgrade_events': _rowMap(yfinanceRecommendations),
      'yfinance_news': _rowMap(yfinanceNews),
      'yfinance_option_expiries': _rowMap(yfinanceOptionExpiries),
      'yfinance_option_contracts': _rowMap(yfinanceOptionContracts),
      'yfinance_corporate_actions': _rowMap(yfinanceActions),
      'yfinance_dividends': _rowMap(yfinanceDividends),
      'yfinance_splits': _rowMap(yfinanceSplits),
      'yfinance_holders': _rowMap(yfinanceHolders),
      'yfinance_institutional_holders': _rowMap(yfinanceInstitutionalHolders),
      'yfinance_mutual_fund_holders': _rowMap(yfinanceMutualFundHolders),
      'yfinance_insider_transactions': _rowMap(yfinanceInsiders),
      ...windRows,
    };
  }

  bool _isAshareCoverageSymbol(String symbol) {
    return RegExp(r'^\d{6}(\.(SH|SZ|BJ))?$').hasMatch(symbol.toUpperCase());
  }
}
