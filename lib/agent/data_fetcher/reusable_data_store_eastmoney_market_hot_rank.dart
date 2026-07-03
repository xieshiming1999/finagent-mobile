part of 'reusable_data_store.dart';

extension ReusableDataStoreEastmoneyMarketHotRank on ReusableDataStore {
  void saveHotRank(
    List<Map<String, dynamic>> rows, {
    required String source,
    String? tradeDate,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final date = tradeDate ?? _today();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO hot_rank
      (trade_date,code,source,fetched_at,name,rank,rank_change,hot_value,market_code,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final code = '${row['code'] ?? ''}';
        if (code.isEmpty) continue;
        stmt.execute([
          date,
          _cleanCode(code),
          source,
          fetchedAt,
          '${row['name'] ?? ''}',
          _int(row['rank']),
          _nullableNum(row['rankChange'] ?? row['rank_change']),
          _nullableNum(row['hotValue'] ?? row['hot_value']),
          '${row['marketCode'] ?? row['market_code'] ?? ''}',
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryHotRank({
    String? code,
    String? tradeDate,
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
    if (tradeDate != null && tradeDate.isNotEmpty) {
      where.add('trade_date = ?');
      args.add(tradeDate);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM hot_rank $whereSql ORDER BY trade_date DESC, rank ASC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
