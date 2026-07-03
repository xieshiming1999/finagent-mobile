part of 'reusable_data_store.dart';

extension ReusableDataStoreEastmoneySectorIdentity on ReusableDataStore {
  Map<String, dynamic> saveIndustryMap(
    List<Map<String, dynamic>> rows, {
    required String industry,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty || industry.isEmpty) {
      return _ingestion(
        'industry_map',
        'industry_map',
        0,
        provider: '东方财富',
      );
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO industry_map
      (code,industry_l1,industry_l2,industry_l3,updated_at)
      VALUES (?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final code = _first(row, ['code', 'symbol']);
        if (code == null || code.isEmpty) continue;
        stmt.execute([
          _cleanCode(code),
          industry,
          _first(row, ['industry_l2']),
          _first(row, ['industry_l3']),
          updatedAt,
        ]);
        count += 1;
      }
    } finally {
      stmt.close();
    }
    return _ingestion(
      'industry_map',
      'industry_map',
      count,
      provider: '东方财富',
    );
  }

  List<Map<String, dynamic>> queryIndustryMap({
    String? code,
    String? industry,
    int limit = 50,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (code != null && code.isNotEmpty) {
      where.add('code = ?');
      args.add(_cleanCode(code));
    }
    if (industry != null && industry.isNotEmpty) {
      where.add(
        '(industry_l1 LIKE ? OR industry_l2 LIKE ? OR industry_l3 LIKE ?)',
      );
      args.add('%$industry%');
      args.add('%$industry%');
      args.add('%$industry%');
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM industry_map $whereSql ORDER BY updated_at DESC, code LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
