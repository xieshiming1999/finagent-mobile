part of 'reusable_data_store.dart';

void _migrateReusableDataStoreCoreTdxReference(Database db) {
  db.execute('''
      CREATE TABLE IF NOT EXISTS xdxr_event (
        code TEXT NOT NULL,
        event_date TEXT NOT NULL,
        category INTEGER NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        category_name TEXT,
        a REAL,
        b REAL,
        c REAL,
        d REAL,
        raw_json TEXT,
        PRIMARY KEY (code, event_date, category, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS tdx_index_momentum (
        code TEXT NOT NULL,
        trade_date TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        value REAL,
        raw_json TEXT,
        PRIMARY KEY (code, trade_date, sequence, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS tdx_top_board (
        board_date TEXT NOT NULL,
        category TEXT NOT NULL,
        side TEXT NOT NULL,
        rank INTEGER NOT NULL,
        code TEXT NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        market INTEGER,
        price REAL,
        value REAL,
        raw_json TEXT,
        PRIMARY KEY (board_date, category, side, rank, code, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS tdx_security_count (
        scope TEXT NOT NULL,
        market TEXT NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        count INTEGER NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (scope, market, source, fetched_at)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS tdx_chart_sampling (
        scope TEXT NOT NULL,
        code TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        market TEXT,
        category TEXT,
        pre_close REAL,
        price REAL,
        change REAL,
        raw_json TEXT,
        PRIMARY KEY (scope, code, sequence, source, fetched_at)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS tdx_block_member (
        block_code TEXT NOT NULL,
        block_name TEXT,
        code TEXT NOT NULL,
        name TEXT,
        block_type TEXT,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (block_code, code, source)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS ex_table_entry (
        entry_key TEXT NOT NULL,
        category TEXT,
        code TEXT,
        name TEXT,
        source TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (entry_key, source)
      )
    ''');
}
