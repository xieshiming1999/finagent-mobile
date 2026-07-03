part of 'reusable_data_store.dart';

extension ReusableDataStoreEastmoneyMarketFlowRank on ReusableDataStore {
  void saveFlowRank(
    String period,
    List<Map<String, dynamic>> rows, {
    required String source,
    String? tradeDate,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final date = tradeDate ?? _today();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO flow_rank
      (trade_date,period,code,source,fetched_at,name,main_net,main_pct,super_large_net,super_large_pct,large_net,large_pct,medium_net,medium_pct,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final code = _first(row, ['code', 'f12']);
        if (code == null || code.isEmpty) continue;
        final values = _flowRankValues(period, row);
        stmt.execute([
          date,
          period,
          _cleanCode(code),
          source,
          fetchedAt,
          _first(row, ['name', 'f14']),
          values['main_net'],
          values['main_pct'],
          values['super_large_net'],
          values['super_large_pct'],
          values['large_net'],
          values['large_pct'],
          values['medium_net'],
          values['medium_pct'],
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryFlowRank({
    String? period,
    String? code,
    String? tradeDate,
    int limit = 50,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (period != null && period.isNotEmpty) {
      where.add('period = ?');
      args.add(period);
    }
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
      'SELECT * FROM flow_rank $whereSql ORDER BY trade_date DESC, main_net DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
