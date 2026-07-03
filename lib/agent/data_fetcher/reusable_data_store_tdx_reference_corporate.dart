part of 'reusable_data_store.dart';

extension ReusableDataStoreTdxReferenceCorporate on ReusableDataStore {
  void saveXdxrEvents(
    String code,
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO xdxr_event
      (code,event_date,category,source,fetched_at,category_name,a,b,c,d,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final date = _normalizeDate(row['date']);
        final category = _int(row['category']);
        if (date == null || category == null) continue;
        stmt.execute([
          _cleanCode(code),
          date,
          category,
          source,
          fetchedAt,
          _first(row, ['categoryName', 'category_name']),
          _nullableNum(row['a']),
          _nullableNum(row['b']),
          _nullableNum(row['c']),
          _nullableNum(row['d']),
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryXdxrEvents(String code, {int limit = 50}) {
    final db = _db;
    if (db == null) return const [];
    final rows = db.select(
      'SELECT * FROM xdxr_event WHERE code = ? ORDER BY event_date DESC, category LIMIT ?',
      [_cleanCode(code), limit],
    );
    return rows.map(_rowMap).toList();
  }

  void saveExTableEntries(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO ex_table_entry
      (entry_key,category,code,name,source,updated_at,raw_json)
      VALUES (?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final entryKey = '${row['entry_key'] ?? ''}';
        if (entryKey.isEmpty) continue;
        stmt.execute([
          entryKey,
          row['category']?.toString(),
          row['code']?.toString(),
          row['name']?.toString(),
          source,
          '${row['updated_at'] ?? updatedAt}',
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryExTableEntries({
    String? code,
    String? category,
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (code != null && code.isNotEmpty) {
      where.add('code = ?');
      args.add(code);
    }
    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    args.add(limit);
    final sql =
        'SELECT * FROM ex_table_entry'
        '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}'
        ' ORDER BY updated_at DESC, entry_key ASC LIMIT ?';
    final rows = db.select(sql, args);
    return rows.map(_rowMap).toList();
  }
}
