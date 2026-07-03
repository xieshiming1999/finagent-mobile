part of 'reusable_data_store.dart';

void _migrateReusableDataStore(ReusableDataStore store, Database db) {
  _migrateReusableDataStoreCoreBase(store, db);
  _migrateReusableDataStoreCoreTdxIntraday(db);
  _migrateReusableDataStoreCoreTdxReference(db);
  _migrateReusableDataStoreCoreIdentity(store, db);
  _migrateReusableDataStoreCoreMarketEvent(db);
  _migrateReusableDataStoreCoreMarketBoard(db);
  _migrateReusableDataStoreProviderResearch(db);
  _migrateReusableDataStoreProviderYfinanceCore(db);
  _migrateReusableDataStoreProviderYfinanceMarket(db);
  _migrateReusableDataStoreProviderYfinanceOwnership(db);
  _migrateReusableDataStoreProviderWind(db);
  _migrateReusableDataStoreMarketScreening(db);
  _migrateReusableDataStoreMarginTrading(db);
  _migrateReusableDataStoreIndexes(db);
}

void _migrateReusableDataStoreMarketScreening(Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS market_screening_snapshot (
      provider TEXT NOT NULL,
      capability_id TEXT NOT NULL,
      source_action TEXT NOT NULL,
      symbol TEXT NOT NULL,
      name TEXT,
      market TEXT,
      rank INTEGER,
      score REAL,
      screened_at TEXT NOT NULL,
      fetched_at TEXT NOT NULL,
      universe_json TEXT,
      filters_json TEXT,
      sort_json TEXT,
      fields_json TEXT,
      raw_json TEXT,
      PRIMARY KEY (provider, source_action, symbol, screened_at)
    )
  ''');
}

void _migrateReusableDataStoreMarginTrading(Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS margin_trading (
      trade_date TEXT NOT NULL,
      code TEXT NOT NULL,
      name TEXT,
      provider TEXT NOT NULL,
      capability_id TEXT,
      source_action TEXT,
      financing_buy REAL,
      financing_balance REAL,
      margin_sell_volume REAL,
      margin_balance_volume REAL,
      margin_balance REAL,
      total_balance REAL,
      fetched_at TEXT NOT NULL,
      raw_json TEXT,
      PRIMARY KEY (trade_date, code, provider)
    )
  ''');
  db.execute('''
    CREATE INDEX IF NOT EXISTS idx_margin_trading_code_date
    ON margin_trading(code, trade_date DESC)
  ''');
  db.execute('''
    CREATE INDEX IF NOT EXISTS idx_margin_trading_date_provider
    ON margin_trading(trade_date DESC, fetched_at DESC, provider)
  ''');
}
