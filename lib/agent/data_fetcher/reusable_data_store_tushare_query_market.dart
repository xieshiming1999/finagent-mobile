part of 'reusable_data_store.dart';

extension ReusableDataStoreTushareQueryMarket on ReusableDataStore {
  void saveFundDividendFactors(
    String code,
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO fund_dividend_factor
      (code,event_date,dividend,factor,source,fetched_at,raw_json)
      VALUES (?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final eventDate =
            '${row['event_date'] ?? row['date'] ?? row['d'] ?? ''}';
        if (eventDate.isEmpty) continue;
        stmt.execute([
          _cleanCode('${row['code'] ?? code}'),
          eventDate,
          _nullableNum(row['dividend']),
          _nullableNum(row['factor']),
          '${row['source'] ?? source}',
          '${row['fetched_at'] ?? fetchedAt}',
          jsonEncode(row['raw_json'] ?? row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  void saveIntradayOhlcvBars(
    String code,
    List<Map<String, dynamic>> rows, {
    required String source,
    int intervalMinutes = 5,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO intraday_ohlcv_bars
      (code,bar_time,interval_minutes,trade_date,source,fetched_at,open,high,low,close,volume,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final barTime = '${row['bar_time'] ?? row['day'] ?? row['time'] ?? ''}';
        if (barTime.isEmpty) continue;
        stmt.execute([
          _cleanCode('${row['code'] ?? code}'),
          barTime,
          _int(row['interval_minutes']) ?? intervalMinutes,
          '${row['trade_date'] ?? barTime.split(' ').first}',
          '${row['source'] ?? source}',
          '${row['fetched_at'] ?? fetchedAt}',
          _nullableNum(row['open']),
          _nullableNum(row['high']),
          _nullableNum(row['low']),
          _nullableNum(row['close']),
          _nullableNum(row['volume']),
          jsonEncode(row['raw_json'] ?? row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryFundamental(
    String code, {
    String? reportDate,
    String? source,
    int limit = 8,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['code = ?'];
    final args = <Object>[_cleanCode(code)];
    if (reportDate != null && reportDate.isNotEmpty) {
      where.add('report_date = ?');
      args.add(reportDate);
    }
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM fundamental WHERE ${where.join(' AND ')} '
      'ORDER BY report_date DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }

  List<Map<String, dynamic>> queryFundamentalSample({
    String? source,
    int limit = 50,
    double? peLte,
    double? peGte,
    double? roeGte,
    bool latestOnly = true,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object?>[];
    if (source != null && source.isNotEmpty) {
      where.add('f.source = ?');
      args.add(source);
    }
    if (peLte != null) {
      where.add('f.pe_ttm IS NOT NULL AND f.pe_ttm <= ?');
      args.add(peLte);
    }
    if (peGte != null) {
      where.add('f.pe_ttm IS NOT NULL AND f.pe_ttm >= ?');
      args.add(peGte);
    }
    if (roeGte != null) {
      where.add('f.roe IS NOT NULL AND f.roe >= ?');
      args.add(roeGte);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = latestOnly
        ? db.select('''
            SELECT f.* FROM fundamental f
            JOIN (
              SELECT code, MAX(report_date) AS latest_report_date
              FROM fundamental
              GROUP BY code
            ) latest
              ON latest.code = f.code
             AND latest.latest_report_date = f.report_date
            $whereSql
            ORDER BY f.report_date DESC, f.fetched_at DESC
            LIMIT ?
            ''', args)
        : db.select('''
            SELECT f.* FROM fundamental f
            $whereSql
            ORDER BY f.report_date DESC, f.fetched_at DESC
            LIMIT ?
            ''', args);
    return rows.map(_rowMap).toList();
  }

  List<Map<String, dynamic>> queryMoneyFlow(
    String code, {
    String? source,
    int limit = 30,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['code = ?'];
    final args = <Object?>[_cleanCode(code)];
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM money_flow WHERE ${where.join(' AND ')} ORDER BY date DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }

  List<Map<String, dynamic>> queryFundNav(
    String code, {
    String startDate = '',
    String endDate = '',
    String? source,
    int? limit,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['code = ?'];
    final args = <Object>[code];
    if (startDate.isNotEmpty) {
      where.add('date >= ?');
      args.add(startDate);
    }
    if (endDate.isNotEmpty) {
      where.add('date <= ?');
      args.add(endDate);
    }
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    final limitSql = limit == null ? '' : ' LIMIT ?';
    if (limit != null) args.add(limit);
    final rows = db.select(
      'SELECT * FROM fund_nav WHERE ${where.join(' AND ')} ORDER BY date DESC$limitSql',
      args,
    );
    return rows.map(_rowMap).toList().reversed.toList();
  }

  List<Map<String, dynamic>> queryFundNavRows({
    String startDate = '',
    String endDate = '',
    String? source,
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['1=1'];
    final args = <Object>[];
    if (startDate.isNotEmpty) {
      where.add('date >= ?');
      args.add(startDate);
    }
    if (endDate.isNotEmpty) {
      where.add('date <= ?');
      args.add(endDate);
    }
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM fund_nav WHERE ${where.join(' AND ')} ORDER BY date DESC, code LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList(growable: false);
  }

  List<Map<String, dynamic>> queryFundMoneyYield(
    String code, {
    String startDate = '',
    String endDate = '',
    String? source,
    int? limit,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['code = ?'];
    final args = <Object>[code];
    if (startDate.isNotEmpty) {
      where.add('date >= ?');
      args.add(startDate);
    }
    if (endDate.isNotEmpty) {
      where.add('date <= ?');
      args.add(endDate);
    }
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    final limitSql = limit == null ? '' : ' LIMIT ?';
    if (limit != null) args.add(limit);
    final rows = db.select(
      'SELECT * FROM fund_money_yield WHERE ${where.join(' AND ')} ORDER BY date DESC$limitSql',
      args,
    );
    return rows.map(_rowMap).toList().reversed.toList();
  }

  List<Map<String, dynamic>> queryFundDividendFactor(
    String code, {
    String startDate = '',
    String endDate = '',
    String? source,
    int? limit,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['code = ?'];
    final args = <Object>[code];
    if (startDate.isNotEmpty) {
      where.add('event_date >= ?');
      args.add(startDate);
    }
    if (endDate.isNotEmpty) {
      where.add('event_date <= ?');
      args.add(endDate);
    }
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    final limitSql = limit == null ? '' : ' LIMIT ?';
    if (limit != null) args.add(limit);
    final rows = db.select(
      'SELECT * FROM fund_dividend_factor WHERE ${where.join(' AND ')} ORDER BY event_date DESC$limitSql',
      args,
    );
    return rows.map(_rowMap).toList().reversed.toList();
  }

  List<Map<String, dynamic>> queryIntradayOhlcvBars(
    String code, {
    String startDate = '',
    String endDate = '',
    int intervalMinutes = 5,
    String? source,
    int? limit,
  }) {
    final db = _db;
    if (db == null) return const [];
    final clean = _cleanCode(code);
    final codeAliases = <String>{clean};
    if (RegExp(r'^\d{6}$').hasMatch(clean)) {
      codeAliases.add(clean.startsWith('6') ? 'sh$clean' : 'sz$clean');
    }
    final placeholders = List.filled(codeAliases.length, '?').join(',');
    final where = <String>['code IN ($placeholders)'];
    final args = <Object>[...codeAliases];
    if (startDate.isNotEmpty) {
      where.add('bar_time >= ?');
      args.add(startDate);
    }
    if (endDate.isNotEmpty) {
      where.add('bar_time <= ?');
      args.add(endDate);
    }
    where.add('interval_minutes = ?');
    args.add(intervalMinutes);
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    final limitSql = limit == null ? '' : ' LIMIT ?';
    if (limit != null) args.add(limit);
    final rows = db.select(
      'SELECT * FROM intraday_ohlcv_bars WHERE ${where.join(' AND ')} ORDER BY bar_time DESC$limitSql',
      args,
    );
    return rows.map(_rowMap).toList().reversed.toList();
  }
}
