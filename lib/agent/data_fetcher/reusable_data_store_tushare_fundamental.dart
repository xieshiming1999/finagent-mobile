part of 'reusable_data_store.dart';

extension ReusableDataStoreTushareFundamental on ReusableDataStore {
  Map<String, dynamic> saveFundamentalRows(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) {
      return _ingestion('fundamental', 'fundamental', 0, provider: source);
    }
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT INTO fundamental
      (code,report_date,pe_ttm,pb,ps_ttm,roe,gross_margin,net_margin,revenue,revenue_yoy,net_profit,profit_yoy,total_assets,total_liabilities,debt_ratio,dividend_yield,market_cap,circ_cap,source,fetched_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(code,report_date) DO UPDATE SET
        pe_ttm=COALESCE(excluded.pe_ttm, fundamental.pe_ttm),
        pb=COALESCE(excluded.pb, fundamental.pb),
        ps_ttm=COALESCE(excluded.ps_ttm, fundamental.ps_ttm),
        roe=COALESCE(excluded.roe, fundamental.roe),
        gross_margin=COALESCE(excluded.gross_margin, fundamental.gross_margin),
        net_margin=COALESCE(excluded.net_margin, fundamental.net_margin),
        revenue=COALESCE(excluded.revenue, fundamental.revenue),
        revenue_yoy=COALESCE(excluded.revenue_yoy, fundamental.revenue_yoy),
        net_profit=COALESCE(excluded.net_profit, fundamental.net_profit),
        profit_yoy=COALESCE(excluded.profit_yoy, fundamental.profit_yoy),
        total_assets=COALESCE(excluded.total_assets, fundamental.total_assets),
        total_liabilities=COALESCE(excluded.total_liabilities, fundamental.total_liabilities),
        debt_ratio=COALESCE(excluded.debt_ratio, fundamental.debt_ratio),
        dividend_yield=COALESCE(excluded.dividend_yield, fundamental.dividend_yield),
        market_cap=COALESCE(excluded.market_cap, fundamental.market_cap),
        circ_cap=COALESCE(excluded.circ_cap, fundamental.circ_cap),
        source=excluded.source,
        fetched_at=excluded.fetched_at,
        raw_json=excluded.raw_json
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final code = _stripTsCode(_first(row, ['ts_code', 'code']));
        final reportDate = _normalizeDate(
          _first(row, [
            'trade_date',
            'end_date',
            'ann_date',
            'period',
            'report_date',
          ]),
        );
        if (code == null || code.isEmpty || reportDate == null) continue;
        stmt.execute([
          _cleanCode(code),
          reportDate,
          _nullableNum(row['pe_ttm'] ?? row['pe']),
          _nullableNum(row['pb']),
          _nullableNum(row['ps_ttm'] ?? row['ps']),
          _nullableNum(row['roe'] ?? row['roe_dt']),
          _nullableNum(row['gross_margin'] ?? row['grossprofit_margin']),
          _nullableNum(row['net_margin'] ?? row['netprofit_margin']),
          _nullableNum(row['revenue'] ?? row['total_revenue']),
          _nullableNum(row['revenue_yoy'] ?? row['or_yoy'] ?? row['tr_yoy']),
          _nullableNum(row['net_profit'] ?? row['n_income_attr_p']),
          _nullableNum(row['profit_yoy'] ?? row['netprofit_yoy']),
          _nullableNum(row['total_assets']),
          _nullableNum(row['total_liabilities'] ?? row['total_liab']),
          _nullableNum(row['debt_ratio'] ?? row['debt_to_assets']),
          _nullableNum(row['dividend_yield'] ?? row['dv_ttm']),
          _nullableNum(row['market_cap']),
          _nullableNum(row['circ_cap']),
          row['source']?.toString() ?? source,
          row['fetched_at']?.toString() ?? fetchedAt,
          row['raw_json']?.toString() ?? jsonEncode(row),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion('fundamental', 'fundamental', count, provider: source);
  }
}
