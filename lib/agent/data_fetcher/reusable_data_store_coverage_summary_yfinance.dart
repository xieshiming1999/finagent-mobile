part of 'reusable_data_store.dart';

extension ReusableDataStoreCoverageSummaryYfinance on ReusableDataStore {
  Map<String, dynamic> reusableSummaryYfinanceTables(Database db) {
    final yfinanceProfile = db.select(
      'SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols, MAX(updated_at) AS latest FROM yfinance_profile_fields',
    ).first;
    final yfinanceStatements = db.select(
      'SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols, MAX(updated_at) AS latest FROM yfinance_statement_items',
    ).first;
    final yfinanceRecommendations = db.select(
      'SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols, MAX(updated_at) AS latest FROM yfinance_recommendations',
    ).first;
    final yfinanceNews = db.select(
      'SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols, MAX(updated_at) AS latest FROM yfinance_news',
    ).first;
    final yfinanceOptionExpiries = db.select(
      'SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols, MAX(updated_at) AS latest FROM yfinance_option_expiries',
    ).first;
    final yfinanceOptionContracts = db.select(
      'SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols, MAX(updated_at) AS latest FROM yfinance_option_contracts',
    ).first;
    final yfinanceActions = db.select(
      'SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols, MAX(updated_at) AS latest FROM yfinance_corporate_actions',
    ).first;
    final yfinanceHolders = db.select(
      'SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols, MAX(updated_at) AS latest FROM yfinance_holders',
    ).first;
    final yfinanceInsiders = db.select(
      'SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols, MAX(updated_at) AS latest FROM yfinance_insider_transactions',
    ).first;
    return {
      'yfinance_profile_fields': _rowMap(yfinanceProfile),
      'yfinance_statement_items': _rowMap(yfinanceStatements),
      'yfinance_recommendations': _rowMap(yfinanceRecommendations),
      'yfinance_news': _rowMap(yfinanceNews),
      'yfinance_option_expiries': _rowMap(yfinanceOptionExpiries),
      'yfinance_option_contracts': _rowMap(yfinanceOptionContracts),
      'yfinance_corporate_actions': _rowMap(yfinanceActions),
      'yfinance_holders': _rowMap(yfinanceHolders),
      'yfinance_insider_transactions': _rowMap(yfinanceInsiders),
    };
  }
}
