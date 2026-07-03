part of 'reusable_data_store.dart';

void _migrateReusableDataStoreCoreMarketBoard(Database db) {
  db.execute('''
      CREATE TABLE IF NOT EXISTS northbound_flow (
        trade_date TEXT NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        mutual_type TEXT,
        buy_amount REAL,
        sell_amount REAL,
        net_buy REAL,
        hold_market_cap REAL,
        raw_json TEXT,
        PRIMARY KEY (trade_date, source, mutual_type)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS northbound_holding (
        trade_date TEXT NOT NULL,
        code TEXT NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        name TEXT,
        hold_shares REAL,
        hold_market_cap REAL,
        hold_ratio REAL,
        change_shares REAL,
        change_market_cap REAL,
        raw_json TEXT,
        PRIMARY KEY (trade_date, code, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS sector_rank (
        trade_date TEXT NOT NULL,
        board_type TEXT NOT NULL,
        rank INTEGER NOT NULL,
        code TEXT NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        name TEXT,
        change_pct REAL,
        change_amount REAL,
        turnover_rate REAL,
        up_count INTEGER,
        down_count INTEGER,
        leading_stock TEXT,
        leading_change_pct REAL,
        raw_json TEXT,
        PRIMARY KEY (trade_date, board_type, code, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS chip_distribution (
        code TEXT NOT NULL,
        trade_date TEXT NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        avg_cost REAL,
        profit_ratio REAL,
        concentration70 REAL,
        concentration90 REAL,
        current_price REAL,
        method TEXT,
        raw_json TEXT,
        PRIMARY KEY (code, trade_date, source)
      )
    ''');
}
