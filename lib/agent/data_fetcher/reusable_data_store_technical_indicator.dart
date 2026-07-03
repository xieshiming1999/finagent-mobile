part of 'reusable_data_store.dart';

extension ReusableDataStoreTechnicalIndicator on ReusableDataStore {
  Map<String, dynamic> saveTechnicalIndicatorSeries(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) {
      return _ingestion(
        'technical_indicator_series',
        'technical_indicator_series',
        0,
        provider: source,
      );
    }
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO technical_indicator_series
      (provider,capability_id,source_action,symbol,indicator,field_name,params_hash,source_date,value,fetched_at,params_json,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final provider = '${row['provider'] ?? row['source'] ?? source}'.trim();
        final symbol = _cleanCode(
          _first(row, ['symbol', 'code', 'ts_code', '证券代码', '股票代码']) ?? '',
        );
        final indicator =
            _first(row, ['indicator', 'func', '指标', 'indicator_name']) ?? '';
        final fieldName =
            _first(row, ['field_name', 'fieldName', '字段', 'name']) ?? 'value';
        final sourceDate = _normalizeDate(
          _first(row, ['source_date', 'sourceDate', 'date', 'timestamp', '日期']),
        );
        if (provider.isEmpty ||
            symbol.isEmpty ||
            indicator.isEmpty ||
            sourceDate == null) {
          continue;
        }
        final paramsJson =
            row['params_json'] ?? jsonEncode(row['params'] ?? {});
        stmt.execute([
          provider,
          row['capability_id'] ?? '$provider.technical.indicator_series',
          row['source_action'] ?? row['action'] ?? 'technical_indicator',
          symbol,
          indicator,
          fieldName,
          row['params_hash'] ??
              sha1.convert(utf8.encode('$paramsJson')).toString(),
          sourceDate,
          _nullableNum(row['value'] ?? row['数值']),
          row['fetched_at'] ?? fetchedAt,
          paramsJson,
          row['raw_json'] ?? jsonEncode(row),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion(
      'technical_indicator_series',
      'technical_indicator_series',
      count,
      provider: source,
    );
  }

  List<Map<String, dynamic>> queryTechnicalIndicatorSeries({
    String? symbol,
    String? indicator,
    String? fieldName,
    String? since,
    String? provider,
    int limit = 200,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (symbol != null && symbol.isNotEmpty) {
      where.add('symbol = ?');
      args.add(_cleanCode(symbol));
    }
    if (indicator != null && indicator.isNotEmpty) {
      where.add('indicator = ?');
      args.add(indicator);
    }
    if (fieldName != null && fieldName.isNotEmpty) {
      where.add('field_name = ?');
      args.add(fieldName);
    }
    final normalizedSince = _normalizeDate(since);
    if (normalizedSince != null) {
      where.add('source_date >= ?');
      args.add(normalizedSince);
    }
    if (provider != null && provider.isNotEmpty) {
      where.add('provider = ?');
      args.add(provider);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM technical_indicator_series $whereSql ORDER BY source_date DESC, fetched_at DESC, field_name LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList(growable: false);
  }
}
