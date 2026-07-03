part of 'reusable_data_store.dart';

void _migrateReusableDataStoreCoreIdentity(
  ReusableDataStore store,
  Database db,
) {
  db.execute('''
      CREATE TABLE IF NOT EXISTS stock_company_info (
        code TEXT NOT NULL,
        info_type TEXT NOT NULL,
        title TEXT,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        category_count INTEGER,
        content TEXT,
        payload_json TEXT,
        PRIMARY KEY (code, info_type, source)
      )
    ''');
  store._ensureColumn('stock_company_info', 'title', 'TEXT');
  db.execute('''
      CREATE TABLE IF NOT EXISTS stock_shareholder (
        code TEXT NOT NULL,
        report_date TEXT NOT NULL,
        holder_name TEXT NOT NULL,
        holder_type TEXT NOT NULL DEFAULT 'top_shareholder',
        rank INTEGER,
        hold_shares REAL,
        hold_pct REAL,
        share_nature TEXT,
        announcement_date TEXT,
        shareholder_note TEXT,
        shareholder_count INTEGER,
        average_holding REAL,
        source TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (code, report_date, holder_name, holder_type, source)
      )
    ''');
  db.execute('''
      CREATE INDEX IF NOT EXISTS idx_stock_shareholder_code_date
      ON stock_shareholder(code, report_date DESC)
    ''');
  db.execute('''
      CREATE INDEX IF NOT EXISTS idx_stock_shareholder_holder
      ON stock_shareholder(holder_name, report_date DESC)
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS stock_list (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        market TEXT,
        industry TEXT,
        list_date TEXT,
        delist_date TEXT,
        stock_type TEXT DEFAULT 'stock',
        updated_at TEXT NOT NULL,
        raw_json TEXT
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS ex_category (
        category INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        abbr TEXT,
        source TEXT,
        updated_at TEXT NOT NULL,
        raw_json TEXT
      )
    ''');
}
