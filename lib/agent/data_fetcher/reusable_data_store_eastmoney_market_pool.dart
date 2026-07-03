part of 'reusable_data_store.dart';

extension ReusableDataStoreEastmoneyMarketPool on ReusableDataStore {
  void saveLimitPool(
    String poolType,
    List<Map<String, dynamic>> rows, {
    required String source,
    String? tradeDate,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final date = tradeDate ?? _today();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO limit_pool
      (trade_date,pool_type,code,source,fetched_at,name,price,change_pct,amount,turnover_rate,first_limit_time,last_limit_time,limit_count,days,industry,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final code = _first(row, ['code', 'SECURITY_CODE']);
        if (code == null || code.isEmpty) continue;
        stmt.execute([
          date,
          poolType,
          _cleanCode(code),
          source,
          fetchedAt,
          _first(row, ['name', 'SECURITY_NAME_ABBR', 'SECURITY_NAME']),
          _nullableNum(
            _firstValue(row, ['price', 'latestPrice', 'CLOSE_PRICE']),
          ),
          _nullableNum(_firstValue(row, ['changePct', 'CHANGE_RATE'])),
          _nullableNum(_firstValue(row, ['amount', 'AMOUNT'])),
          _nullableNum(_firstValue(row, ['turnoverRate', 'TURNOVERRATE'])),
          _first(row, ['firstLimitTime', 'FIRST_LIMIT_TIME']),
          _first(row, ['lastLimitTime', 'LAST_LIMIT_TIME']),
          _int(_firstValue(row, ['limitCount', 'LIMIT_COUNT'])),
          _int(_firstValue(row, ['days', 'DAYS'])),
          _first(row, ['industry', 'INDUSTRY', 'BOARD_NAME']),
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryLimitPool({
    String? poolType,
    String? code,
    String? tradeDate,
    int limit = 50,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (poolType != null && poolType.isNotEmpty) {
      where.add('pool_type = ?');
      args.add(poolType);
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
      'SELECT * FROM limit_pool $whereSql ORDER BY trade_date DESC, change_pct DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
