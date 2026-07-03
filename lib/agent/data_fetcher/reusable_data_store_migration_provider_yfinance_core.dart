part of 'reusable_data_store.dart';

void _migrateReusableDataStoreProviderYfinanceCore(Database db) {
  db.execute('''
      CREATE TABLE IF NOT EXISTS yfinance_profile_fields (
        symbol TEXT NOT NULL,
        field_key TEXT NOT NULL,
        field_value TEXT,
        field_type TEXT,
        source TEXT,
        updated_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (symbol, field_key)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS yfinance_statement_items (
        symbol TEXT NOT NULL,
        statement_type TEXT NOT NULL,
        period TEXT NOT NULL,
        item TEXT NOT NULL,
        value REAL,
        source TEXT,
        updated_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (symbol, statement_type, period, item)
      )
    ''');
}
