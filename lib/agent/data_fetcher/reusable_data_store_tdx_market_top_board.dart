part of 'reusable_data_store.dart';

extension ReusableDataStoreTdxMarketTopBoard on ReusableDataStore {
  void saveTopBoard(
    Map<String, dynamic> payload, {
    required String source,
    String category = '0',
    String? boardDate,
  }) {
    final db = _db;
    if (db == null) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final date = boardDate ?? _today();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO tdx_top_board
      (board_date,category,side,rank,code,source,fetched_at,market,price,value,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)
    ''');
    void insertRows(String side, Object? rawRows) {
      final rows = rawRows is List ? rawRows : const [];
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (row is! Map) continue;
        final code = _first(row.cast<String, dynamic>(), ['code']);
        if (code == null || code.isEmpty) continue;
        stmt.execute([
          date,
          category,
          side,
          i + 1,
          _cleanCode(code),
          source,
          fetchedAt,
          _int(row['market']),
          _nullableNum(row['price']),
          _nullableNum(row['value']),
          jsonEncode(row),
        ]);
      }
    }

    try {
      insertRows('increase', payload['increase']);
      insertRows('decrease', payload['decrease']);
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryTopBoard({
    String? code,
    String? category,
    String? side,
    String? boardDate,
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (code != null && code.isNotEmpty) {
      where.add('code = ?');
      args.add(_cleanCode(code));
    }
    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    if (side != null && side.isNotEmpty) {
      where.add('side = ?');
      args.add(side);
    }
    if (boardDate != null && boardDate.isNotEmpty) {
      where.add('board_date = ?');
      args.add(boardDate);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM tdx_top_board $whereSql ORDER BY board_date DESC, category, side, rank LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
