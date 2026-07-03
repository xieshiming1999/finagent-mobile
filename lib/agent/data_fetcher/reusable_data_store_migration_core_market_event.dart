part of 'reusable_data_store.dart';

void _migrateReusableDataStoreCoreMarketEvent(Database db) {
  db.execute('''
      CREATE TABLE IF NOT EXISTS hot_rank (
        trade_date TEXT NOT NULL,
        code TEXT NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        name TEXT,
        rank INTEGER,
        rank_change REAL,
        hot_value REAL,
        market_code TEXT,
        raw_json TEXT,
        PRIMARY KEY (trade_date, code, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS dragon_tiger (
        trade_date TEXT NOT NULL,
        code TEXT NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        name TEXT,
        close REAL,
        change_pct REAL,
        net_buy REAL,
        buy_amount REAL,
        sell_amount REAL,
        turnover REAL,
        reason TEXT,
        raw_json TEXT,
        PRIMARY KEY (trade_date, code, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS limit_pool (
        trade_date TEXT NOT NULL,
        pool_type TEXT NOT NULL,
        code TEXT NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        name TEXT,
        price REAL,
        change_pct REAL,
        amount REAL,
        turnover_rate REAL,
        first_limit_time TEXT,
        last_limit_time TEXT,
        limit_count INTEGER,
        days INTEGER,
        industry TEXT,
        raw_json TEXT,
        PRIMARY KEY (trade_date, pool_type, code, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS unusual_activity (
        event_date TEXT NOT NULL,
        code TEXT NOT NULL,
        event_time TEXT NOT NULL,
        event_type TEXT NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        name TEXT,
        info TEXT,
        raw_json TEXT,
        PRIMARY KEY (event_date, code, event_time, event_type, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS flow_rank (
        trade_date TEXT NOT NULL,
        period TEXT NOT NULL,
        code TEXT NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        name TEXT,
        main_net REAL,
        main_pct REAL,
        super_large_net REAL,
        super_large_pct REAL,
        large_net REAL,
        large_pct REAL,
        medium_net REAL,
        medium_pct REAL,
        raw_json TEXT,
        PRIMARY KEY (trade_date, period, code, source)
      )
    ''');
}
