part of 'reusable_data_store.dart';

extension ReusableDataStoreCoverageSummarySources on ReusableDataStore {
  List<Map<String, dynamic>> _reusableSummarySources(Database db) {
    final sources = db.select('''
      SELECT source, COUNT(*) AS rows, MAX(seen_at) AS latest FROM (
        SELECT source, timestamp AS seen_at FROM quote_snapshot
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM kline_daily
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM tick_chart_intraday
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM transactions
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM volume_profile
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM auction_snapshot
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM xdxr_event
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM stock_company_info
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM hot_rank
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM dragon_tiger
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM limit_pool
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM northbound_flow
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM northbound_holding
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM unusual_activity
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM flow_rank
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM fundamental
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM money_flow
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM fund_nav
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM fund_holding
        UNION ALL
        SELECT source, updated_at AS seen_at FROM fund_manager
        UNION ALL
        SELECT source, fetched_at AS seen_at FROM finance_news
        UNION ALL
        SELECT provider AS source, fetched_at AS seen_at FROM fund_performance_metrics
        UNION ALL
        SELECT provider AS source, fetched_at AS seen_at FROM index_constituent
        UNION ALL
        SELECT source, updated_at AS seen_at FROM ex_category
        UNION ALL
        SELECT source, updated_at AS seen_at FROM yfinance_profile_fields
        UNION ALL
        SELECT source, updated_at AS seen_at FROM yfinance_statement_items
        UNION ALL
        SELECT source, updated_at AS seen_at FROM yfinance_recommendations
        UNION ALL
        SELECT source, updated_at AS seen_at FROM yfinance_news
        UNION ALL
        SELECT source, updated_at AS seen_at FROM yfinance_option_expiries
        UNION ALL
        SELECT source, updated_at AS seen_at FROM yfinance_option_contracts
        UNION ALL
        SELECT source, updated_at AS seen_at FROM yfinance_corporate_actions
        UNION ALL
        SELECT source, updated_at AS seen_at FROM yfinance_holders
        UNION ALL
        SELECT source, updated_at AS seen_at FROM yfinance_insider_transactions
        UNION ALL
        SELECT source, updated_at AS seen_at FROM wind_document
        UNION ALL
        SELECT source, updated_at AS seen_at FROM wind_economic_series
        UNION ALL
        SELECT source, updated_at AS seen_at FROM wind_analytics_result
        UNION ALL
        SELECT provider AS source, fetched_at AS seen_at FROM technical_indicator_series
        UNION ALL
        SELECT provider AS source, fetched_at AS seen_at FROM alpha_factor
      )
      GROUP BY source
      ORDER BY rows DESC
    ''');
    return sources.map(_rowMap).toList();
  }

  void cleanup({int quoteDays = 30, int cacheDays = 7}) {
    final db = _db;
    if (db == null) return;
    final quoteBefore = DateTime.now()
        .toUtc()
        .subtract(Duration(days: quoteDays))
        .toIso8601String();
    final cacheBefore = DateTime.now()
        .toUtc()
        .subtract(Duration(days: cacheDays))
        .toIso8601String();
    db.execute('DELETE FROM quote_snapshot WHERE timestamp < ?', [quoteBefore]);
    db.execute(
      'DELETE FROM api_result_cache WHERE COALESCE(expires_at, fetched_at) < ?',
      [cacheBefore],
    );
    db.execute(
      'DELETE FROM raw_api_payload WHERE expires_at IS NOT NULL AND expires_at < ?',
      [DateTime.now().toUtc().toIso8601String()],
    );
  }
}
