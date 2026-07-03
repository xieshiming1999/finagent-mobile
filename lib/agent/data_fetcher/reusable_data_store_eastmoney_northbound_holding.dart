part of 'reusable_data_store.dart';

extension ReusableDataStoreEastmoneyNorthboundHolding on ReusableDataStore {
  void saveNorthboundHolding(
    List<Map<String, dynamic>> rows, {
    required String source,
    String? code,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO northbound_holding
      (trade_date,code,source,fetched_at,name,hold_shares,hold_market_cap,hold_ratio,change_shares,change_market_cap,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final rowCode = _first(row, ['SECURITY_CODE', 'code']) ?? code;
        if (rowCode == null || rowCode.isEmpty) continue;
        final tradeDate =
            _dateOnly(
              _first(row, ['HOLD_DATE', 'TRADE_DATE', 'tradeDate', 'date']),
            ) ??
            _today();
        stmt.execute([
          tradeDate,
          _cleanCode(rowCode),
          source,
          fetchedAt,
          _first(row, ['SECURITY_NAME_ABBR', 'SECURITY_NAME', 'name']),
          _nullableNum(_firstValue(row, ['HOLD_SHARES', 'holdShares'])),
          _nullableNum(
            _firstValue(row, [
              'HOLD_MARKETCAP',
              'HOLD_MARKET_CAP',
              'holdMarketCap',
            ]),
          ),
          _nullableNum(_firstValue(row, ['HOLD_RATIO', 'holdRatio'])),
          _nullableNum(_firstValue(row, ['CHANGE_SHARES', 'changeShares'])),
          _nullableNum(
            _firstValue(row, [
              'CHANGE_MARKETCAP',
              'CHANGE_MARKET_CAP',
              'changeMarketCap',
            ]),
          ),
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryNorthboundHolding({
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
      'SELECT * FROM northbound_holding $whereSql ORDER BY trade_date DESC, hold_market_cap DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
