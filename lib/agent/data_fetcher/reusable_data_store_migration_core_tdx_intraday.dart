part of 'reusable_data_store.dart';

void _migrateReusableDataStoreCoreTdxIntraday(Database db) {
  db.execute('''
      CREATE TABLE IF NOT EXISTS tick_chart_intraday (
        code TEXT NOT NULL,
        trade_date TEXT NOT NULL,
        minute INTEGER NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        time TEXT,
        price REAL,
        avg_price REAL,
        volume REAL,
        raw_json TEXT,
        PRIMARY KEY (code, trade_date, minute, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        code TEXT NOT NULL,
        trade_date TEXT NOT NULL,
        time TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        price REAL,
        volume REAL,
        trades REAL,
        direction TEXT,
        raw_json TEXT,
        PRIMARY KEY (code, trade_date, time, sequence, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS volume_profile (
        code TEXT NOT NULL,
        trade_date TEXT NOT NULL,
        price REAL NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        close REAL,
        open REAL,
        high REAL,
        low REAL,
        pre_close REAL,
        total_volume REAL,
        amount REAL,
        profile_volume REAL,
        buy_volume REAL,
        sell_volume REAL,
        raw_json TEXT,
        PRIMARY KEY (code, trade_date, price, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS auction_snapshot (
        code TEXT NOT NULL,
        trade_date TEXT NOT NULL,
        time TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        price REAL,
        volume REAL,
        raw_json TEXT,
        PRIMARY KEY (code, trade_date, time, sequence, source)
      )
    ''');
}
