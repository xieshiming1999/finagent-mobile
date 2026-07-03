part of 'reusable_data_store.dart';

extension ReusableDataStoreCoreReference on ReusableDataStore {
  Map<String, dynamic> saveStockListRows(
    List<Map<String, dynamic>> rows, {
    required String source,
    String? market,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) {
      return _ingestion('stock_list', 'stock_list', 0, provider: source);
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO stock_list
      (code,name,market,industry,list_date,delist_date,stock_type,updated_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final code = _first(row, ['code', 'ts_code', 'symbol']);
        final name = _first(row, ['name', 'symbolName', 'SECURITY_NAME_ABBR']);
        if (code == null || code.isEmpty || name == null || name.isEmpty) {
          continue;
        }
        stmt.execute([
          _stripTsCode(code) ?? _cleanCode(code),
          name,
          _first(row, ['market', 'exchange']) ?? market,
          _first(row, ['industry']),
          _normalizeDate(_first(row, ['list_date', 'listDate'])),
          _normalizeDate(_first(row, ['delist_date', 'delistDate'])),
          _first(row, ['stock_type', 'type']) ?? 'stock',
          updatedAt,
          jsonEncode(row),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion('stock_list', 'stock_list', count, provider: source);
  }

  Map<String, dynamic> saveExCategories(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) {
      return _ingestion('ex_category', 'ex_category', 0, provider: source);
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO ex_category
      (category,name,abbr,source,updated_at,raw_json)
      VALUES (?,?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final category = row['category'];
        final name = _first(row, ['name']);
        if (category == null || name == null || name.isEmpty) continue;
        stmt.execute([
          category,
          name,
          _first(row, ['abbr']),
          source,
          updatedAt,
          jsonEncode(row),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion('ex_category', 'ex_category', count, provider: source);
  }
}
