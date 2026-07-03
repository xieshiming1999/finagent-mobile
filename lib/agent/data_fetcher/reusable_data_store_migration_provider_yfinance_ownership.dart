part of 'reusable_data_store.dart';

void _migrateReusableDataStoreProviderYfinanceOwnership(Database db) {
  db.execute('''
      CREATE TABLE IF NOT EXISTS yfinance_holders (
        symbol TEXT NOT NULL,
        holder_type TEXT NOT NULL,
        holder_name TEXT NOT NULL,
        reported_date TEXT NOT NULL,
        pct_held REAL,
        shares REAL,
        value REAL,
        pct_change REAL,
        source TEXT,
        updated_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (symbol, holder_type, holder_name, reported_date)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS yfinance_insider_transactions (
        symbol TEXT NOT NULL,
        transaction_id TEXT NOT NULL,
        insider TEXT,
        position TEXT,
        transaction_text TEXT,
        start_date TEXT,
        ownership TEXT,
        shares REAL,
        value REAL,
        source TEXT,
        updated_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (symbol, transaction_id)
      )
    ''');
}
