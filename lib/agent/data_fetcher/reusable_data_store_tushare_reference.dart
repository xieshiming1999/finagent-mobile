part of 'reusable_data_store.dart';

extension ReusableDataStoreTushareReference on ReusableDataStore {
  Map<String, dynamic>? saveTradeCalendarRows(
    List<Map<String, dynamic>> rows, {
    String market = 'CN',
    String source = 'calendar',
  }) {
    if (_db == null || rows.isEmpty) return null;
    final db = _db!;
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO trade_calendar
      (date,market,is_trading_day,year,month)
      VALUES (?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final date = _normalizeDate(_first(row, ['date', 'cal_date', 'jyrq']));
        if (date == null) continue;
        stmt.execute([
          date,
          _first(row, ['market', 'exchange', 'source_market']) ?? market,
          _int(row['is_trading_day'] ?? row['is_open'] ?? row['jybz']) ?? 0,
          int.tryParse(date.substring(0, 4)),
          int.tryParse(date.substring(5, 7)),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion(source, 'trade_calendar', count);
  }

  Map<String, dynamic> _saveTushareTradeCalendar(
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> params,
  ) {
    return saveTradeCalendarRows(
      rows,
      market: '${params['exchange'] ?? 'SSE'}',
      source: 'trade_calendar',
    )!;
  }
}
