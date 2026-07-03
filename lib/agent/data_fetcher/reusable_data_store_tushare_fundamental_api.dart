part of 'reusable_data_store.dart';

extension ReusableDataStoreTushareFundamentalApi on ReusableDataStore {
  Map<String, dynamic> _saveTushareFundamental(
    String apiName,
    List<Map<String, dynamic>> rows,
    String source,
  ) {
    final db = _db!;
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
        final totalMv = _nullableNum(row['total_mv']);
        final circMv = _nullableNum(row['circ_mv']);
        stmt.execute([
          _cleanCode(code),
          reportDate,
          _nullableNum(row['pe_ttm'] ?? row['pe']),
          _nullableNum(row['pb']),
          _nullableNum(row['ps_ttm'] ?? row['ps']),
          _nullableNum(row['roe'] ?? row['roe_dt']),
          _nullableNum(row['grossprofit_margin']),
          _nullableNum(row['netprofit_margin']),
          _nullableNum(row['revenue'] ?? row['total_revenue']),
          _nullableNum(row['or_yoy'] ?? row['tr_yoy'] ?? row['revenue_yoy']),
          _nullableNum(row['n_income_attr_p'] ?? row['net_profit']),
          _nullableNum(row['netprofit_yoy'] ?? row['dt_netprofit_yoy']),
          _nullableNum(row['total_assets']),
          _nullableNum(row['total_liab'] ?? row['total_liabilities']),
          _nullableNum(row['debt_to_assets']),
          _nullableNum(row['dv_ttm'] ?? row['dv_ratio']),
          totalMv == null ? null : totalMv * 10000,
          circMv == null ? null : circMv * 10000,
          '$source:$apiName',
          fetchedAt,
          jsonEncode(row),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion('fundamental', 'fundamental', count);
  }
}
