part of 'reusable_data_store.dart';

extension ReusableDataStoreTdxAuction on ReusableDataStore {
  void saveAuction(
    String code,
    List<Map<String, dynamic>> rows, {
    required String source,
    String? tradeDate,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final date = tradeDate ?? _today();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO auction_snapshot
      (code,trade_date,time,sequence,source,fetched_at,price,volume,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        stmt.execute([
          _cleanCode(code),
          date,
          '${row['time'] ?? ''}',
          _int(row['index']) ?? i,
          source,
          fetchedAt,
          _nullableNum(row['price']),
          _nullableNum(row['volume']),
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryAuction(
    String code, {
    String? tradeDate,
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['code = ?'];
    final args = <Object>[_cleanCode(code)];
    if (tradeDate != null && tradeDate.isNotEmpty) {
      where.add('trade_date = ?');
      args.add(tradeDate);
    }
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM auction_snapshot WHERE ${where.join(' AND ')} ORDER BY trade_date DESC, sequence DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList().reversed.toList();
  }
}
