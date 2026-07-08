part of 'reusable_data_store.dart';

void _migrateReusableDataStoreProviderResearch(Database db) {
  db.execute('''
      CREATE TABLE IF NOT EXISTS fundamental (
        code TEXT NOT NULL,
        report_date TEXT NOT NULL,
        pe_ttm REAL,
        pb REAL,
        ps_ttm REAL,
        roe REAL,
        gross_margin REAL,
        net_margin REAL,
        revenue REAL,
        revenue_yoy REAL,
        net_profit REAL,
        profit_yoy REAL,
        total_assets REAL,
        total_liabilities REAL,
        debt_ratio REAL,
        dividend_yield REAL,
        market_cap REAL,
        circ_cap REAL,
        source TEXT,
        fetched_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (code, report_date)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS money_flow (
        code TEXT NOT NULL,
        date TEXT NOT NULL,
        main_net REAL,
        small_net REAL,
        medium_net REAL,
        large_net REAL,
        super_large_net REAL,
        close_price REAL,
        change_pct REAL,
        source TEXT,
        fetched_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (code, date)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS fund_nav (
        code TEXT NOT NULL,
        date TEXT NOT NULL,
        nav REAL,
        acc_nav REAL,
        daily_return REAL,
        source TEXT,
        fetched_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (code, date)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS fund_money_yield (
        code TEXT NOT NULL,
        date TEXT NOT NULL,
        million_copies_income REAL,
        seven_day_annualized_yield REAL,
        source TEXT,
        fetched_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (code, date)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS fund_dividend_factor (
        code TEXT NOT NULL,
        event_date TEXT NOT NULL,
        dividend REAL,
        factor REAL,
        source TEXT,
        fetched_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (code, event_date)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS intraday_ohlcv_bars (
        code TEXT NOT NULL,
        bar_time TEXT NOT NULL,
        trade_date TEXT,
        interval_minutes INTEGER NOT NULL,
        open REAL,
        high REAL,
        low REAL,
        close REAL,
        volume REAL,
        source TEXT,
        fetched_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (code, bar_time, interval_minutes, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS fund_holding (
        fund_code TEXT NOT NULL,
        report_date TEXT NOT NULL,
        stock_code TEXT NOT NULL,
        stock_name TEXT,
        hold_shares REAL,
        hold_value REAL,
        hold_pct REAL,
        rank INTEGER,
        source TEXT,
        fetched_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (fund_code, report_date, stock_code)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS fund_performance_metrics (
        code TEXT NOT NULL,
        metric_date TEXT NOT NULL,
        provider TEXT NOT NULL,
        capability_id TEXT,
        source_action TEXT,
        nav REAL,
        return_ytd REAL,
        return_1w REAL,
        return_1m REAL,
        return_3m REAL,
        return_6m REAL,
        return_1y REAL,
        return_2y REAL,
        return_3y REAL,
        return_since_inception REAL,
        fetched_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (code, metric_date, provider)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS index_constituent (
        index_code TEXT NOT NULL,
        stock_code TEXT NOT NULL,
        stock_name TEXT,
        weight REAL,
        as_of_date TEXT NOT NULL,
        provider TEXT NOT NULL,
        capability_id TEXT,
        source_action TEXT,
        fetched_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (index_code, stock_code, as_of_date, provider)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS technical_indicator_series (
        provider TEXT NOT NULL,
        capability_id TEXT,
        source_action TEXT NOT NULL,
        symbol TEXT NOT NULL,
        indicator TEXT NOT NULL,
        field_name TEXT NOT NULL,
        params_hash TEXT NOT NULL,
        source_date TEXT NOT NULL,
        value REAL,
        fetched_at TEXT NOT NULL,
        params_json TEXT,
        raw_json TEXT,
        PRIMARY KEY (provider, symbol, indicator, field_name, params_hash, source_date)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS alpha_factor (
        provider TEXT NOT NULL,
        capability_id TEXT NOT NULL,
        source_action TEXT NOT NULL,
        symbol TEXT NOT NULL,
        factor_name TEXT NOT NULL,
        params_hash TEXT NOT NULL,
        source_date TEXT NOT NULL,
        value REAL,
        bars INTEGER,
        fetched_at TEXT NOT NULL,
        params_json TEXT,
        raw_json TEXT,
        PRIMARY KEY (provider, capability_id, symbol, factor_name, params_hash, source_date)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS fund_list (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        fund_type TEXT,
        fund_category TEXT,
        company TEXT,
        manager TEXT,
        setup_date TEXT,
        total_size REAL,
        nav REAL,
        nav_date TEXT,
        return_1y REAL,
        return_3y REAL,
        return_ytd REAL,
        updated_at TEXT NOT NULL,
        raw_json TEXT
      )
    ''');
  _ensureProviderResearchColumn(db, 'fund_list', 'fund_category', 'TEXT');
  db.execute('''
      UPDATE fund_list
      SET fund_category = CASE
        WHEN lower(COALESCE(fund_category, '')) IN ('money','backend','bond','etf','index','fof','qdii','reits','ordinary','unknown') THEN lower(fund_category)
        WHEN COALESCE(name, '') LIKE '%后端%' OR lower(COALESCE(name, '')) LIKE '%backend%' THEN 'backend'
        WHEN COALESCE(fund_type, '') LIKE '%货币%' OR COALESCE(name, '') LIKE '%货币%' OR lower(COALESCE(fund_type, '')) LIKE '%money%' OR lower(COALESCE(name, '')) LIKE '%money%' OR COALESCE(name, '') LIKE '%现金%' THEN 'money'
        WHEN COALESCE(fund_type, '') LIKE '%债%' OR lower(COALESCE(fund_type, '')) LIKE '%bond%' THEN 'bond'
        WHEN lower(COALESCE(fund_type, '')) LIKE '%etf%' OR lower(COALESCE(name, '')) LIKE '%etf%' THEN 'etf'
        WHEN COALESCE(fund_type, '') LIKE '%指数%' OR lower(COALESCE(fund_type, '')) LIKE '%index%' THEN 'index'
        WHEN lower(COALESCE(fund_type, '')) LIKE '%fof%' THEN 'fof'
        WHEN lower(COALESCE(fund_type, '')) LIKE '%qdii%' THEN 'qdii'
        WHEN lower(COALESCE(fund_type, '')) LIKE '%reit%' THEN 'reits'
        WHEN COALESCE(fund_type, '') = '' AND COALESCE(name, '') = '' THEN 'unknown'
        ELSE 'ordinary'
      END
      WHERE fund_category IS NULL OR fund_category = ''
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS fund_manager (
        manager_name TEXT NOT NULL,
        company TEXT,
        fund_code TEXT NOT NULL,
        fund_name TEXT,
        fund_type TEXT,
        total_size REAL,
        updated_at TEXT NOT NULL,
        source TEXT,
        raw_json TEXT,
        PRIMARY KEY (manager_name, fund_code)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS finance_news (
        news_id TEXT PRIMARY KEY,
        title TEXT,
        summary TEXT,
        content TEXT,
        publisher TEXT,
        published_at TEXT,
        url TEXT,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        raw_json TEXT
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS market_moving_factor (
        factor_id TEXT PRIMARY KEY,
        family TEXT NOT NULL,
        title TEXT NOT NULL,
        summary TEXT,
        source_name TEXT NOT NULL,
        source_url TEXT,
        source_type TEXT NOT NULL,
        source_published_at TEXT,
        fetched_at TEXT NOT NULL,
        event_at TEXT,
        next_catalyst_at TEXT,
        affected_assets_json TEXT,
        affected_regions_json TEXT,
        affected_sectors_json TEXT,
        transmission_channels_json TEXT,
        expected_direction TEXT,
        severity TEXT,
        confidence TEXT,
        status TEXT NOT NULL,
        failure_class TEXT,
        evidence_items_json TEXT,
        macro_values_json TEXT,
        retrieval_test_json TEXT,
        raw_json TEXT
      )
    ''');
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_market_moving_factor_family ON market_moving_factor(family, fetched_at DESC)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_market_moving_factor_status ON market_moving_factor(status, fetched_at DESC)',
  );
  db.execute('''
      CREATE TABLE IF NOT EXISTS trade_calendar (
        date TEXT NOT NULL,
        market TEXT NOT NULL,
        is_trading_day INTEGER NOT NULL,
        year INTEGER,
        month INTEGER,
        PRIMARY KEY (date, market)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS industry_map (
        code TEXT PRIMARY KEY,
        industry_l1 TEXT,
        industry_l2 TEXT,
        industry_l3 TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
}

void _ensureProviderResearchColumn(
  Database db,
  String table,
  String column,
  String definition,
) {
  final rows = db.select('PRAGMA table_info($table)');
  final hasColumn = rows.any((row) => row['name'] == column);
  if (!hasColumn) {
    db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}
