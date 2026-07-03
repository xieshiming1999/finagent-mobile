part of 'reusable_data_store.dart';

extension ReusableDataStoreTdxIntraday on ReusableDataStore {
  void saveTickChart(
    String code,
    List<Map<String, dynamic>> rows, {
    required String source,
    String? tradeDate,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final date = tradeDate ?? _today();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO tick_chart_intraday
      (code,trade_date,minute,source,fetched_at,time,price,avg_price,volume,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        stmt.execute([
          _cleanCode(code),
          date,
          _int(row['minute']) ?? i,
          source,
          fetchedAt,
          '${row['time'] ?? ''}',
          _nullableNum(row['price']),
          _nullableNum(row['avg'] ?? row['avg_price']),
          _nullableNum(row['volume']),
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryTickChart(
    String code, {
    String? tradeDate,
    int limit = 240,
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
      'SELECT * FROM tick_chart_intraday WHERE ${where.join(' AND ')} ORDER BY trade_date DESC, minute DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList().reversed.toList();
  }

  void saveTransactions(
    String code,
    List<Map<String, dynamic>> rows, {
    required String source,
    String? tradeDate,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final date = tradeDate ?? _today();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO transactions
      (code,trade_date,time,sequence,source,fetched_at,price,volume,trades,direction,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        stmt.execute([
          _cleanCode(code),
          date,
          '${row['time'] ?? ''}',
          i,
          source,
          fetchedAt,
          _nullableNum(row['price']),
          _nullableNum(row['volume']),
          _nullableNum(row['trades']),
          '${row['direction'] ?? ''}',
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryTransactions(
    String code, {
    String? tradeDate,
    int limit = 100,
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
      'SELECT * FROM transactions WHERE ${where.join(' AND ')} ORDER BY trade_date DESC, time DESC, sequence DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
