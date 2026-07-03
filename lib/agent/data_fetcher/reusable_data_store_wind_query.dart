part of 'reusable_data_store.dart';

extension ReusableDataStoreWindQuery on ReusableDataStore {
  List<Map<String, dynamic>> queryWindDocuments({
    String? query,
    String? tool,
    String? entityCode,
    String? source,
    int limit = 50,
  }) {
    final db = _db;
    if (db == null) return const [];
    var sql = 'SELECT * FROM wind_document WHERE 1=1';
    final params = <Object?>[];
    if (query != null && query.isNotEmpty) {
      sql += ' AND query = ?';
      params.add(query);
    }
    if (tool != null && tool.isNotEmpty) {
      sql += ' AND tool = ?';
      params.add(tool);
    }
    if (entityCode != null && entityCode.isNotEmpty) {
      sql += ' AND entity_code = ?';
      params.add(_cleanCode(entityCode));
    }
    if (source != null && source.isNotEmpty) {
      sql += ' AND source = ?';
      params.add(source);
    }
    sql += ' ORDER BY published_at DESC, updated_at DESC LIMIT ?';
    params.add(limit);
    return db.select(sql, params).map(_rowMap).toList();
  }

  List<Map<String, dynamic>> queryWindEconomicSeries({
    String? metricQuery,
    String? source,
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    var sql = 'SELECT * FROM wind_economic_series WHERE 1=1';
    final params = <Object?>[];
    if (metricQuery != null && metricQuery.isNotEmpty) {
      sql += ' AND metric_query = ?';
      params.add(metricQuery);
    }
    if (source != null && source.isNotEmpty) {
      sql += ' AND source = ?';
      params.add(source);
    }
    sql += ' ORDER BY date DESC, metric_name LIMIT ?';
    params.add(limit);
    return db.select(sql, params).map(_rowMap).toList();
  }

  List<Map<String, dynamic>> queryWindAnalyticsResults({
    String? question,
    String? source,
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    var sql = 'SELECT * FROM wind_analytics_result WHERE 1=1';
    final params = <Object?>[];
    if (question != null && question.isNotEmpty) {
      sql += ' AND question = ?';
      params.add(question);
    }
    if (source != null && source.isNotEmpty) {
      sql += ' AND source = ?';
      params.add(source);
    }
    sql += ' ORDER BY value_date DESC, updated_at DESC LIMIT ?';
    params.add(limit);
    return db.select(sql, params).map(_rowMap).toList();
  }
}
