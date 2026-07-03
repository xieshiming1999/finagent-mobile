part of 'reusable_data_store.dart';

extension ReusableDataStoreTushareMarketMoneyFlow on ReusableDataStore {
  Map<String, dynamic> saveMoneyFlowRows(
    String code,
    List<MoneyFlow> rows, {
    required String source,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) {
      return _ingestion('money_flow', 'money_flow', 0, provider: source);
    }
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final clean = _cleanCode(code);
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO money_flow
      (code,date,main_net,small_net,medium_net,large_net,super_large_net,close_price,change_pct,source,fetched_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final date = _normalizeDate(row.date);
        if (date == null) continue;
        stmt.execute([
          clean,
          date,
          row.mainNetInflow,
          row.smallNetInflow,
          row.mediumNetInflow,
          row.largeNetInflow,
          row.superLargeNetInflow,
          row.closePrice,
          row.changePct,
          source,
          fetchedAt,
          jsonEncode(row.toJson()),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion('money_flow', 'money_flow', count, provider: source);
  }
}
