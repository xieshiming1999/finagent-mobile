part of 'reusable_data_store.dart';

extension ReusableDataStoreMarginTrading on ReusableDataStore {
  void saveMarginTradingRows(List<Map<String, dynamic>> rows) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO margin_trading
      (trade_date,code,name,provider,capability_id,source_action,financing_buy,financing_balance,margin_sell_volume,margin_balance_volume,margin_balance,total_balance,fetched_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final tradeDate =
            row['trade_date']?.toString() ?? row['date']?.toString();
        final code = row['code']?.toString() ?? row['symbol']?.toString();
        if (tradeDate == null ||
            tradeDate.isEmpty ||
            code == null ||
            code.isEmpty) {
          continue;
        }
        final provider = row['provider']?.toString() ?? 'unknown';
        final fetchedAt =
            row['fetched_at']?.toString() ??
            DateTime.now().toUtc().toIso8601String();
        stmt.execute([
          tradeDate,
          code,
          row['name']?.toString(),
          provider,
          row['capability_id']?.toString() ?? row['capabilityId']?.toString(),
          row['source_action']?.toString() ?? row['sourceAction']?.toString(),
          _nullableNum(row['financing_buy']),
          _nullableNum(row['financing_balance']),
          _nullableNum(row['margin_sell_volume']),
          _nullableNum(row['margin_balance_volume']),
          _nullableNum(row['margin_balance']),
          _nullableNum(row['total_balance']),
          fetchedAt,
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryMarginTradingRows({
    String? code,
    String? tradeDate,
    String? provider,
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['1=1'];
    final args = <Object>[];
    if (code != null && code.isNotEmpty) {
      where.add('code = ?');
      args.add(code);
    }
    if (tradeDate != null && tradeDate.isNotEmpty) {
      where.add('trade_date = ?');
      args.add(tradeDate);
    }
    if (provider != null && provider.isNotEmpty) {
      where.add('provider = ?');
      args.add(provider);
    }
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM margin_trading WHERE ${where.join(' AND ')} '
      'ORDER BY trade_date DESC, fetched_at DESC, code LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList(growable: false);
  }
}
