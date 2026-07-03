part of 'reusable_data_store.dart';

extension ReusableDataStoreEastmoneyMarketDragonTiger on ReusableDataStore {
  void saveDragonTiger(
    List<Map<String, dynamic>> rows, {
    required String source,
    String? tradeDate,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO dragon_tiger
      (trade_date,code,source,fetched_at,name,close,change_pct,net_buy,buy_amount,sell_amount,turnover,reason,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final code = _first(row, ['SECURITY_CODE', 'code', 'Code']);
        if (code == null || code.isEmpty) continue;
        final rowDate =
            _first(row, ['TRADE_DATE', 'tradeDate', 'date']) ?? tradeDate;
        stmt.execute([
          _dateOnly(rowDate) ?? tradeDate ?? _today(),
          _cleanCode(code),
          source,
          fetchedAt,
          _first(row, ['SECURITY_NAME_ABBR', 'SECURITY_NAME', 'name']),
          _nullableNum(_firstValue(row, ['CLOSE_PRICE', 'close'])),
          _nullableNum(_firstValue(row, ['CHANGE_RATE', 'changePct'])),
          _nullableNum(_firstValue(row, ['NET_BUY_AMT', 'NET_BUY', 'netBuy'])),
          _nullableNum(
            _firstValue(row, ['BUY_AMT', 'BUY_AMOUNT', 'buyAmount']),
          ),
          _nullableNum(
            _firstValue(row, ['SELL_AMT', 'SELL_AMOUNT', 'sellAmount']),
          ),
          _nullableNum(
            _firstValue(row, ['TURNOVERRATE', 'TURNOVER_RATE', 'turnover']),
          ),
          _first(row, ['EXPLANATION', 'BILLBOARD_REASON', 'reason']),
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryDragonTiger({
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
      'SELECT * FROM dragon_tiger $whereSql ORDER BY trade_date DESC, net_buy DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
