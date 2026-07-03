part of 'reusable_data_store.dart';

extension ReusableDataStoreFundPerformance on ReusableDataStore {
  Map<String, dynamic> saveFundPerformanceMetrics(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) {
      return _ingestion(
        'fund_performance_metrics',
        'fund_performance_metrics',
        0,
        provider: source,
      );
    }
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO fund_performance_metrics
      (code,metric_date,provider,capability_id,source_action,nav,return_ytd,return_1w,return_1m,return_3m,return_6m,return_1y,return_2y,return_3y,return_since_inception,fetched_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final code = _cleanCode(
          _first(row, ['code', 'fund_code', '基金代码', '基金Wind代码', 'Wind代码']) ??
              '',
        );
        final metricDate = _normalizeDate(
          _first(row, ['metric_date', 'date', '净值日期', '交易日期', '日期', '报告期']),
        );
        final provider = '${row['provider'] ?? source}'.trim();
        if (code.isEmpty || metricDate == null || provider.isEmpty) continue;
        stmt.execute([
          code,
          metricDate,
          provider,
          row['capability_id'] ?? '$provider.fund.performance_metrics',
          row['source_action'] ?? 'fund_performance',
          _nullableNum(row['nav'] ?? row['单位净值'] ?? row['最新净值']),
          _nullableNum(row['return_ytd'] ?? row['今年以来'] ?? row['年初至今']),
          _nullableNum(row['return_1w'] ?? row['近1周'] ?? row['近一周']),
          _nullableNum(row['return_1m'] ?? row['近1月'] ?? row['近一月']),
          _nullableNum(row['return_3m'] ?? row['近3月'] ?? row['近三月']),
          _nullableNum(row['return_6m'] ?? row['近6月'] ?? row['近六月']),
          _nullableNum(row['return_1y'] ?? row['近1年'] ?? row['近一年']),
          _nullableNum(row['return_2y'] ?? row['近2年'] ?? row['近二年']),
          _nullableNum(row['return_3y'] ?? row['近3年'] ?? row['近三年']),
          _nullableNum(row['return_since_inception'] ?? row['成立以来']),
          row['fetched_at'] ?? fetchedAt,
          row['raw_json'] ?? jsonEncode(row),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion(
      'fund_performance_metrics',
      'fund_performance_metrics',
      count,
      provider: source,
    );
  }

  List<Map<String, dynamic>> queryFundPerformanceMetrics({
    String? code,
    String? provider,
    String? metricDate,
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (code != null && code.isNotEmpty) {
      where.add('code = ?');
      args.add(_cleanCode(code));
    }
    if (provider != null && provider.isNotEmpty) {
      where.add('provider = ?');
      args.add(provider);
    }
    if (metricDate != null && metricDate.isNotEmpty) {
      where.add('metric_date = ?');
      args.add(metricDate);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM fund_performance_metrics $whereSql ORDER BY metric_date DESC, fetched_at DESC, return_1y DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList(growable: false);
  }
}
