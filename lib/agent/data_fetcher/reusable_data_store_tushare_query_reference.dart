part of 'reusable_data_store.dart';

extension ReusableDataStoreTushareQueryReference on ReusableDataStore {
  List<Map<String, dynamic>> queryFundList({
    String? fundType,
    String? company,
    List<String> codes = const [],
    int limit = 50,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['1=1'];
    final args = <Object>[];
    final cleanCodes = codes
        .map(_cleanCode)
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList();
    if (cleanCodes.isNotEmpty) {
      where.add(
        'UPPER(REPLACE(code, \'.OF\', \'\')) IN (${List.filled(cleanCodes.length, '?').join(',')})',
      );
      args.addAll(cleanCodes);
    }
    if (fundType != null && fundType.isNotEmpty) {
      where.add('fund_type = ?');
      args.add(fundType);
    }
    if (company != null && company.isNotEmpty) {
      where.add('company LIKE ?');
      args.add('%$company%');
    }
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM fund_list WHERE ${where.join(' AND ')} ORDER BY total_size DESC, code LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }

  List<Map<String, dynamic>> queryStockList({
    String? market,
    String? industry,
    String? stockType,
    int limit = 50,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['delist_date IS NULL'];
    final args = <Object>[];
    if (market != null && market.isNotEmpty) {
      where.add('market = ?');
      args.add(market);
    }
    if (industry != null && industry.isNotEmpty) {
      where.add('industry LIKE ?');
      args.add('%$industry%');
    }
    if (stockType != null && stockType.isNotEmpty) {
      where.add('stock_type = ?');
      args.add(stockType);
    }
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM stock_list WHERE ${where.join(' AND ')} ORDER BY code LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }

  Map<String, dynamic>? queryStockIdentity(String code) {
    final db = _db;
    if (db == null) return null;
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    final rows = db.select(
      'SELECT * FROM stock_list WHERE code = ? ORDER BY updated_at DESC LIMIT 1',
      [trimmed],
    );
    if (rows.isEmpty) return null;
    return _rowMap(rows.first);
  }

  List<Map<String, dynamic>> queryExCategories({int limit = 100}) {
    final db = _db;
    if (db == null) return const [];
    final rows = db.select(
      'SELECT * FROM ex_category ORDER BY category LIMIT ?',
      [limit],
    );
    return rows.map(_rowMap).toList();
  }

  List<Map<String, dynamic>> queryTradeCalendar({
    String? market,
    String? start,
    String? end,
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    final clauses = <String>[];
    final args = <Object?>[];
    if (market != null && market.trim().isNotEmpty) {
      clauses.add('market = ?');
      args.add(market.trim().toUpperCase());
    }
    final startDate = _normalizeDate(start);
    if (startDate != null) {
      clauses.add('date >= ?');
      args.add(startDate);
    }
    final endDate = _normalizeDate(end);
    if (endDate != null) {
      clauses.add('date <= ?');
      args.add(endDate);
    }
    final whereSql = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = db.select(
      'SELECT * FROM trade_calendar $whereSql ORDER BY date ASC LIMIT ?',
      [...args, limit],
    );
    return rows
        .map(
          (row) => {
            'date': row['date'],
            'market': row['market'],
            'is_trading_day': row['is_trading_day'],
            'year': row['year'],
            'month': row['month'],
          },
        )
        .toList();
  }
}
