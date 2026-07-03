part of 'reusable_data_store.dart';

extension ReusableDataStoreEastmoneyNorthboundFlow on ReusableDataStore {
  void saveNorthboundFlow(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO northbound_flow
      (trade_date,source,fetched_at,mutual_type,buy_amount,sell_amount,net_buy,hold_market_cap,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final tradeDate = _dateOnly(
          _first(row, ['TRADE_DATE', 'tradeDate', 'date']),
        );
        if (tradeDate == null) continue;
        stmt.execute([
          tradeDate,
          source,
          fetchedAt,
          _first(row, ['MUTUAL_TYPE', 'mutualType', 'type']) ?? 'northbound',
          _nullableNum(
            _firstValue(row, ['BUY_AMT', 'BUY_AMOUNT', 'buyAmount']),
          ),
          _nullableNum(
            _firstValue(row, ['SELL_AMT', 'SELL_AMOUNT', 'sellAmount']),
          ),
          _nullableNum(
            _firstValue(row, [
              'NET_BUY_AMT',
              'NET_BUY',
              'netBuy',
              'ADD_MARKET_CAP',
            ]),
          ),
          _nullableNum(
            _firstValue(row, [
              'HOLD_MARKETCAP',
              'HOLD_MARKET_CAP',
              'holdMarketCap',
            ]),
          ),
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryNorthboundFlow({
    String? tradeDate,
    int limit = 50,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (tradeDate != null && tradeDate.isNotEmpty) {
      where.add('trade_date = ?');
      args.add(tradeDate);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM northbound_flow $whereSql ORDER BY trade_date DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
