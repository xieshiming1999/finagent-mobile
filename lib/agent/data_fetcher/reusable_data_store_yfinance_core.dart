part of 'reusable_data_store.dart';

extension ReusableDataStoreYfinanceCore on ReusableDataStore {
  void saveYfinanceProfileFields(List<Map<String, dynamic>> rows) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO yfinance_profile_fields
      (symbol,field_key,field_value,field_type,source,updated_at,raw_json)
      VALUES (?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final symbol = '${row['symbol'] ?? ''}'.trim().toUpperCase();
        final fieldKey = '${row['field_key'] ?? row['key'] ?? ''}'.trim();
        if (symbol.isEmpty || fieldKey.isEmpty) continue;
        final value = row['field_value'] ?? row['value'];
        stmt.execute([
          symbol,
          fieldKey,
          value == null ? null : '$value',
          row['field_type'] ?? value.runtimeType.toString(),
          row['source'] ?? 'yfinance',
          row['updated_at'] ?? updatedAt,
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  void saveYfinanceStatementItems(List<Map<String, dynamic>> rows) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO yfinance_statement_items
      (symbol,statement_type,period,item,value,source,updated_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final symbol = '${row['symbol'] ?? ''}'.trim().toUpperCase();
        final statementType = '${row['statement_type'] ?? row['type'] ?? ''}'
            .trim();
        final period = '${row['period'] ?? row['date'] ?? ''}'.trim();
        final item = '${row['item'] ?? row['field_key'] ?? ''}'.trim();
        if (symbol.isEmpty ||
            statementType.isEmpty ||
            period.isEmpty ||
            item.isEmpty) {
          continue;
        }
        stmt.execute([
          symbol,
          statementType,
          period,
          item,
          _nullableNum(row['value']),
          row['source'] ?? 'yfinance',
          row['updated_at'] ?? updatedAt,
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryYfinanceProfile(
    String symbol, {
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    final rows = db.select(
      '''
      SELECT * FROM yfinance_profile_fields
      WHERE symbol = ?
      ORDER BY field_key
      LIMIT ?
      ''',
      [symbol.trim().toUpperCase(), limit],
    );
    return rows.map(_rowMap).toList();
  }

  List<Map<String, dynamic>> queryYfinanceStatements(
    String symbol, {
    String? statementType,
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['symbol = ?'];
    final args = <Object>[symbol.trim().toUpperCase()];
    if (statementType != null && statementType.isNotEmpty) {
      where.add('statement_type = ?');
      args.add(statementType);
    }
    args.add(limit);
    final rows = db.select('''
      SELECT * FROM yfinance_statement_items
      WHERE ${where.join(' AND ')}
      ORDER BY period DESC, statement_type, item
      LIMIT ?
      ''', args);
    return rows.map(_rowMap).toList();
  }
}
