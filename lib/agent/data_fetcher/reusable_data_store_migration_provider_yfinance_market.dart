part of 'reusable_data_store.dart';

void _migrateReusableDataStoreProviderYfinanceMarket(Database db) {
  db.execute('''
      CREATE TABLE IF NOT EXISTS yfinance_recommendations (
        symbol TEXT NOT NULL,
        period TEXT NOT NULL,
        strong_buy REAL,
        buy REAL,
        hold REAL,
        sell REAL,
        strong_sell REAL,
        source TEXT,
        updated_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (symbol, period)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS yfinance_news (
        symbol TEXT NOT NULL,
        news_id TEXT NOT NULL,
        title TEXT,
        publisher TEXT,
        published_at TEXT,
        link TEXT,
        summary TEXT,
        source TEXT,
        updated_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (symbol, news_id)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS yfinance_option_expiries (
        symbol TEXT NOT NULL,
        expiry_date TEXT NOT NULL,
        source TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (symbol, expiry_date)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS yfinance_option_contracts (
        symbol TEXT NOT NULL,
        expiry_date TEXT NOT NULL,
        option_type TEXT NOT NULL,
        contract_symbol TEXT NOT NULL,
        strike REAL,
        last_price REAL,
        bid REAL,
        ask REAL,
        change REAL,
        percent_change REAL,
        volume REAL,
        open_interest REAL,
        implied_volatility REAL,
        in_the_money INTEGER,
        currency TEXT,
        last_trade_date TEXT,
        source TEXT,
        updated_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (symbol, expiry_date, option_type, contract_symbol)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS yfinance_corporate_actions (
        symbol TEXT NOT NULL,
        action_type TEXT NOT NULL,
        action_date TEXT NOT NULL,
        value REAL,
        source TEXT,
        updated_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (symbol, action_type, action_date)
      )
    ''');
}
