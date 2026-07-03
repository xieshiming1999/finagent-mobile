part of 'reusable_data_store.dart';

extension ReusableDataStoreTdxDistribution on ReusableDataStore {
  void saveVolumeProfile(
    String code,
    Map<String, dynamic> payload, {
    required String source,
    String? tradeDate,
  }) {
    final db = _db;
    final profiles = payload['profiles'] as List? ?? const [];
    if (db == null || profiles.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final date = tradeDate ?? _today();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO volume_profile
      (code,trade_date,price,source,fetched_at,close,open,high,low,pre_close,total_volume,amount,profile_volume,buy_volume,sell_volume,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final item in profiles) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        stmt.execute([
          _cleanCode(code),
          date,
          _num(row['price']),
          source,
          fetchedAt,
          _nullableNum(payload['close']),
          _nullableNum(payload['open']),
          _nullableNum(payload['high']),
          _nullableNum(payload['low']),
          _nullableNum(payload['preClose'] ?? payload['pre_close']),
          _nullableNum(payload['vol'] ?? payload['volume']),
          _nullableNum(payload['amount']),
          _nullableNum(row['vol'] ?? row['volume']),
          _nullableNum(row['buy']),
          _nullableNum(row['sell']),
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryVolumeProfile(
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
      'SELECT * FROM volume_profile WHERE ${where.join(' AND ')} ORDER BY trade_date DESC, price ASC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
