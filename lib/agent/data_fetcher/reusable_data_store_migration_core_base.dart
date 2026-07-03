part of 'reusable_data_store.dart';

void _migrateReusableDataStoreCoreBase(ReusableDataStore store, Database db) {
  db.execute('''
      CREATE TABLE IF NOT EXISTS quote_snapshot (
        code TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        fetched_at TEXT,
        source TEXT NOT NULL,
        name TEXT,
        price REAL,
        change REAL,
        change_pct REAL,
        open REAL,
        high REAL,
        low REAL,
        prev_close REAL,
        volume REAL,
        amount REAL,
        pe REAL,
        pb REAL,
        market_cap REAL,
        turnover_rate REAL,
        raw_json TEXT,
        PRIMARY KEY (code, timestamp, source)
      )
    ''');
  store._ensureColumn('quote_snapshot', 'fetched_at', 'TEXT');
  db.execute(
    'UPDATE quote_snapshot SET fetched_at = timestamp WHERE fetched_at IS NULL',
  );
  db.execute('''
      CREATE TABLE IF NOT EXISTS kline_daily (
        code TEXT NOT NULL,
        date TEXT NOT NULL,
        adjust TEXT NOT NULL DEFAULT 'qfq',
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        open REAL NOT NULL,
        high REAL NOT NULL,
        low REAL NOT NULL,
        close REAL NOT NULL,
        volume REAL,
        amount REAL,
        change_pct REAL,
        turnover_rate REAL,
        raw_json TEXT,
        PRIMARY KEY (code, date, adjust)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS api_result_cache (
        source TEXT NOT NULL,
        tool TEXT NOT NULL,
        action TEXT NOT NULL,
        request_key TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        expires_at TEXT,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (source, tool, action, request_key)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS raw_api_payload (
        source TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        request_hash TEXT NOT NULL,
        request_json TEXT NOT NULL,
        response_json TEXT,
        is_error INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        expires_at TEXT,
        PRIMARY KEY (source, endpoint, request_hash)
      )
    ''');
}
