part of 'reusable_data_store.dart';

extension ReusableDataStoreYfinanceOwnershipDatasets on ReusableDataStore {
  void saveYfinanceRecommendations(List<Map<String, dynamic>> rows) {
    _saveYfinanceRows(
      this,
      'yfinance_recommendations',
      [
        'symbol',
        'period',
        'strong_buy',
        'buy',
        'hold',
        'sell',
        'strong_sell',
        'source',
        'updated_at',
        'raw_json',
      ],
      rows,
      numericColumns: const {
        'strong_buy',
        'buy',
        'hold',
        'sell',
        'strong_sell',
      },
    );
  }

  void saveYfinanceHolders(List<Map<String, dynamic>> rows) {
    _saveYfinanceRows(
      this,
      'yfinance_holders',
      [
        'symbol',
        'holder_type',
        'holder_name',
        'reported_date',
        'pct_held',
        'shares',
        'value',
        'pct_change',
        'source',
        'updated_at',
        'raw_json',
      ],
      rows,
      numericColumns: const {'pct_held', 'shares', 'value', 'pct_change'},
    );
  }

  void saveYfinanceInsiderTransactions(List<Map<String, dynamic>> rows) {
    _saveYfinanceRows(
      this,
      'yfinance_insider_transactions',
      [
        'symbol',
        'transaction_id',
        'insider',
        'position',
        'transaction_text',
        'start_date',
        'ownership',
        'shares',
        'value',
        'source',
        'updated_at',
        'raw_json',
      ],
      rows,
      numericColumns: const {'shares', 'value'},
    );
  }
}

void _saveYfinanceRows(
  ReusableDataStore store,
  String table,
  List<String> columns,
  List<Map<String, dynamic>> rows, {
  Set<String> numericColumns = const {},
  Set<String> intColumns = const {},
}) {
  final db = store._db;
  if (db == null || rows.isEmpty) return;
  final placeholders = List.filled(columns.length, '?').join(',');
  final stmt = db.prepare('''
    INSERT OR REPLACE INTO $table
    (${columns.join(',')})
    VALUES ($placeholders)
  ''');
  final updatedAt = DateTime.now().toUtc().toIso8601String();
  try {
    for (final row in rows) {
      final symbol = '${row['symbol'] ?? ''}'.trim().toUpperCase();
      if (symbol.isEmpty) continue;
      stmt.execute(
        columns.map((column) {
          if (column == 'symbol') return symbol;
          if (column == 'updated_at') return row[column] ?? updatedAt;
          if (column == 'source') return row[column] ?? 'yfinance';
          if (column == 'raw_json') return row[column] ?? jsonEncode(row);
          final value = row[column];
          if (numericColumns.contains(column)) return store._nullableNum(value);
          if (intColumns.contains(column)) {
            if (value is bool) return value ? 1 : 0;
            return store._int(value);
          }
          return value;
        }).toList(),
      );
    }
  } finally {
    stmt.close();
  }
}
