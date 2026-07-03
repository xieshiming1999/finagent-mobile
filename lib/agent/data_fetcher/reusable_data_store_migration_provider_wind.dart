part of 'reusable_data_store.dart';

void _migrateReusableDataStoreProviderWind(Database db) {
  db.execute('''
      CREATE TABLE IF NOT EXISTS wind_document (
        doc_id TEXT NOT NULL PRIMARY KEY,
        tool TEXT NOT NULL,
        query TEXT,
        title TEXT,
        publisher TEXT,
        published_at TEXT,
        url TEXT,
        summary TEXT,
        entity_code TEXT,
        entity_name TEXT,
        source TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        raw_json TEXT
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS wind_economic_series (
        series_key TEXT NOT NULL,
        metric_query TEXT NOT NULL,
        metric_name TEXT NOT NULL,
        metric_code TEXT,
        date TEXT NOT NULL,
        value_num REAL,
        value_text TEXT,
        unit TEXT,
        frequency TEXT,
        currency TEXT,
        source TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (series_key, date, metric_name)
      )
    ''');
  db.execute('''
      CREATE TABLE IF NOT EXISTS wind_analytics_result (
        result_id TEXT NOT NULL PRIMARY KEY,
        question TEXT NOT NULL,
        entity_code TEXT,
        entity_name TEXT,
        value_date TEXT,
        title TEXT,
        content TEXT,
        value_num REAL,
        value_text TEXT,
        unit TEXT,
        source TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        raw_json TEXT
      )
    ''');
}
