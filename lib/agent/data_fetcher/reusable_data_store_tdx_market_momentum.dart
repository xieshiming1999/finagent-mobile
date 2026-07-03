part of 'reusable_data_store.dart';

extension ReusableDataStoreTdxMarketMomentum on ReusableDataStore {
  void saveIndexMomentum(
    String code,
    Map<String, dynamic> payload, {
    required String source,
    String? tradeDate,
  }) {
    final db = _db;
    final values = payload['momentum'] as List?;
    if (db == null || values == null || values.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final date = tradeDate ?? _today();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO tdx_index_momentum
      (code,trade_date,sequence,source,fetched_at,value,raw_json)
      VALUES (?,?,?,?,?,?,?)
    ''');
    try {
      for (var i = 0; i < values.length; i++) {
        final row = {'value': values[i], 'sequence': i, 'payload': payload};
        stmt.execute([
          _cleanCode(code),
          date,
          i,
          source,
          fetchedAt,
          _nullableNum(values[i]),
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryIndexMomentum(
    String code, {
    String? tradeDate,
    int limit = 200,
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
      'SELECT * FROM tdx_index_momentum WHERE ${where.join(' AND ')} ORDER BY trade_date DESC, sequence ASC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
