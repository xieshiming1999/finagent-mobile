part of 'reusable_data_store.dart';

extension ReusableDataStoreWind on ReusableDataStore {
  void saveWindDocuments(List<Map<String, dynamic>> rows) {
    _saveGenericRows(
      'wind_document',
      [
        'doc_id',
        'tool',
        'query',
        'title',
        'publisher',
        'published_at',
        'url',
        'summary',
        'entity_code',
        'entity_name',
        'source',
        'updated_at',
        'raw_json',
      ],
      rows,
    );
  }

  void saveWindEconomicSeries(List<Map<String, dynamic>> rows) {
    _saveGenericRows(
      'wind_economic_series',
      [
        'series_key',
        'metric_query',
        'metric_name',
        'metric_code',
        'date',
        'value_num',
        'value_text',
        'unit',
        'frequency',
        'currency',
        'source',
        'updated_at',
        'raw_json',
      ],
      rows,
      numericColumns: const {'value_num'},
    );
  }

  void saveWindAnalyticsResults(List<Map<String, dynamic>> rows) {
    _saveGenericRows(
      'wind_analytics_result',
      [
        'result_id',
        'question',
        'entity_code',
        'entity_name',
        'value_date',
        'title',
        'content',
        'value_num',
        'value_text',
        'unit',
        'source',
        'updated_at',
        'raw_json',
      ],
      rows,
      numericColumns: const {'value_num'},
    );
  }

  void _saveGenericRows(
    String table,
    List<String> columns,
    List<Map<String, dynamic>> rows, {
    Set<String> numericColumns = const {},
    Set<String> intColumns = const {},
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final placeholders = List.filled(columns.length, '?').join(',');
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO $table
      (${columns.join(',')})
      VALUES ($placeholders)
    ''');
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    try {
      for (final row in rows) {
        stmt.execute(
          columns.map((column) {
            if (column == 'updated_at') return row[column] ?? updatedAt;
            if (column == 'source') return row[column] ?? 'Wind';
            if (column == 'raw_json') return row[column] ?? jsonEncode(row);
            final value = row[column];
            if (numericColumns.contains(column)) return _nullableNum(value);
            if (intColumns.contains(column)) return _int(value);
            return value;
          }).toList(),
        );
      }
    } finally {
      stmt.close();
    }
  }
}
