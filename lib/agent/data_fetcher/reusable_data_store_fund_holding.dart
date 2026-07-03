part of 'reusable_data_store.dart';

extension ReusableDataStoreFundHolding on ReusableDataStore {
  Map<String, dynamic> saveFundHolding(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) {
      return _ingestion('fund_holding', 'fund_holding', 0, provider: source);
    }
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO fund_holding
      (fund_code,report_date,stock_code,stock_name,hold_shares,hold_value,hold_pct,rank,source,fetched_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final fundCode = _cleanCode(
          _first(row, ['fund_code', '基金代码', '基金Wind代码', 'Wind代码']) ?? '',
        );
        final stockCode = _cleanCode(
          _first(row, ['stock_code', '股票代码', '持仓证券代码', '证券代码', 'code']) ?? '',
        );
        final reportDate = _normalizeDate(
          _first(row, ['report_date', '报告期', '截止日期', '持仓日期', '日期']),
        );
        if (fundCode.isEmpty || stockCode.isEmpty || reportDate == null) {
          continue;
        }
        stmt.execute([
          fundCode,
          reportDate,
          stockCode,
          _first(row, ['stock_name', '股票名称', '持仓证券简称', '证券简称', '中文简称']),
          _nullableNum(row['hold_shares'] ?? row['持股数'] ?? row['持仓数量']),
          _nullableNum(row['hold_value'] ?? row['持仓市值'] ?? row['持有市值']),
          _nullableNum(row['hold_pct'] ?? row['占净值比例'] ?? row['持仓占比']),
          _int(row['rank'] ?? row['排名'] ?? row['序号']),
          _first(row, ['source']) ?? source,
          _first(row, ['fetched_at']) ?? fetchedAt,
          jsonEncode(row),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion('fund_holding', 'fund_holding', count, provider: source);
  }

  List<Map<String, dynamic>> queryFundHolding({
    String? fundCode,
    String? stockCode,
    String? reportDate,
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    final cleanFundCode = fundCode == null || fundCode.isEmpty
        ? null
        : _cleanCode(fundCode);
    String? effectiveReportDate = reportDate;
    String? effectiveFetchedAt;
    if (cleanFundCode != null && stockCode == null) {
      effectiveReportDate ??= db
          .select(
            'SELECT MAX(report_date) AS report_date FROM fund_holding WHERE fund_code = ?',
            [cleanFundCode],
          )
          .firstOrNull?['report_date']
          ?.toString();
      if (effectiveReportDate != null && effectiveReportDate.isNotEmpty) {
        effectiveFetchedAt = db
            .select(
              'SELECT MAX(fetched_at) AS fetched_at FROM fund_holding WHERE fund_code = ? AND report_date = ?',
              [cleanFundCode, effectiveReportDate],
            )
            .firstOrNull?['fetched_at']
            ?.toString();
      }
    }
    if (cleanFundCode != null && cleanFundCode.isNotEmpty) {
      where.add('fund_code = ?');
      args.add(cleanFundCode);
    }
    if (stockCode != null && stockCode.isNotEmpty) {
      where.add('stock_code = ?');
      args.add(_cleanCode(stockCode));
    }
    if (effectiveReportDate != null && effectiveReportDate.isNotEmpty) {
      where.add('report_date = ?');
      args.add(effectiveReportDate);
    }
    if (effectiveFetchedAt != null && effectiveFetchedAt.isNotEmpty) {
      where.add('fetched_at = ?');
      args.add(effectiveFetchedAt);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM fund_holding $whereSql ORDER BY report_date DESC, rank ASC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList(growable: false);
  }
}
