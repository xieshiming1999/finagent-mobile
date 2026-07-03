part of 'reusable_data_store.dart';

extension ReusableDataStoreTdxReferenceSampling on ReusableDataStore {
  void saveTdxSecurityCounts(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO tdx_security_count
      (scope,market,source,fetched_at,count,raw_json)
      VALUES (?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        stmt.execute([
          '${row['scope'] ?? 'main'}',
          '${row['market'] ?? 'all'}',
          source,
          '${row['fetched_at'] ?? fetchedAt}',
          _int(row['count']) ?? 0,
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryTdxSecurityCounts({
    String? scope,
    String? market,
    int limit = 20,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (scope != null && scope.isNotEmpty) {
      where.add('scope = ?');
      args.add(scope);
    }
    if (market != null && market.isNotEmpty) {
      where.add('market = ?');
      args.add(market);
    }
    args.add(limit);
    final sql =
        'SELECT * FROM tdx_security_count'
        '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}'
        ' ORDER BY fetched_at DESC LIMIT ?';
    final rows = db.select(sql, args);
    return rows.map(_rowMap).toList();
  }

  void saveTdxChartSampling(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO tdx_chart_sampling
      (scope,code,sequence,source,fetched_at,market,category,pre_close,price,change,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final scope = '${row['scope'] ?? 'main'}';
        final code = _cleanCode('${row['code'] ?? ''}');
        final sequence = _int(row['sequence']);
        if (code.isEmpty || sequence == null) continue;
        stmt.execute([
          scope,
          code,
          sequence,
          source,
          '${row['fetched_at'] ?? fetchedAt}',
          row['market']?.toString(),
          row['category']?.toString(),
          _nullableNum(row['pre_close']),
          _nullableNum(row['price']),
          _nullableNum(row['change']),
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryTdxChartSampling({
    String? scope,
    String? code,
    String? market,
    String? category,
    int limit = 120,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (scope != null && scope.isNotEmpty) {
      where.add('scope = ?');
      args.add(scope);
    }
    if (code != null && code.isNotEmpty) {
      where.add('code = ?');
      args.add(_cleanCode(code));
    }
    if (market != null && market.isNotEmpty) {
      where.add('market = ?');
      args.add(market);
    }
    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    args.add(limit);
    final sql =
        'SELECT * FROM tdx_chart_sampling'
        '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}'
        ' ORDER BY fetched_at DESC, sequence ASC LIMIT ?';
    final rows = db.select(sql, args);
    return rows.map(_rowMap).toList();
  }
}
