part of 'reusable_data_store.dart';

extension ReusableDataStoreAlphaFactor on ReusableDataStore {
  Map<String, dynamic> saveAlphaFactors(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) {
      return _ingestion('alpha_factor', 'alpha_factor', 0, provider: source);
    }
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO alpha_factor
      (provider,capability_id,source_action,symbol,factor_name,params_hash,source_date,value,bars,fetched_at,params_json,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final provider = '${row['provider'] ?? row['source'] ?? source}'.trim();
        final symbol = _cleanCode(
          _first(row, ['symbol', 'code', 'ts_code', '证券代码', '股票代码']) ?? '',
        );
        final factorName =
            _first(row, ['factor_name', 'factorName', 'factor', 'name']) ?? '';
        final sourceDate = _normalizeDate(
          _first(row, ['source_date', 'sourceDate', 'date', 'timestamp', '日期']),
        );
        if (provider.isEmpty ||
            symbol.isEmpty ||
            factorName.isEmpty ||
            sourceDate == null) {
          continue;
        }
        final paramsJson =
            row['params_json'] ?? jsonEncode(row['params'] ?? {});
        stmt.execute([
          provider,
          row['capability_id'] ?? '$provider.stock.alpha_factors',
          row['source_action'] ?? row['action'] ?? 'alpha_factors',
          symbol,
          factorName,
          row['params_hash'] ??
              sha1.convert(utf8.encode('$paramsJson')).toString(),
          sourceDate,
          _nullableNum(row['value'] ?? row['数值']),
          _int(row['bars']),
          row['fetched_at'] ?? fetchedAt,
          paramsJson,
          row['raw_json'] ?? jsonEncode(row),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion('alpha_factor', 'alpha_factor', count, provider: source);
  }

  List<Map<String, dynamic>> queryAlphaFactors({
    String? symbol,
    String? factorName,
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
    if (factorName != null && factorName.isNotEmpty) {
      where.add('factor_name = ?');
      args.add(factorName);
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
      'SELECT * FROM alpha_factor $whereSql ORDER BY source_date DESC, fetched_at DESC, factor_name LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList(growable: false);
  }
}
