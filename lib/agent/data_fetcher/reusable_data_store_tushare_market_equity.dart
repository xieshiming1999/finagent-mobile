part of 'reusable_data_store.dart';

extension ReusableDataStoreTushareMarketEquity on ReusableDataStore {
  Map<String, dynamic>? saveTushareRows(
    String apiName,
    List<Map<String, dynamic>> rows, {
    Map<String, dynamic> params = const {},
    String source = 'Tushare',
  }) {
    if (_db == null || rows.isEmpty) return null;
    return switch (apiName) {
      'stock_basic' => _saveTushareStockBasic(rows, source),
      'daily' ||
      'weekly' ||
      'monthly' ||
      'index_daily' => _saveTushareKline(rows, params, source),
      'index_weight' => _saveTushareIndexConstituents(rows, params, source),
      'daily_basic' => _saveTushareFundamental(apiName, rows, source),
      'trade_cal' => _saveTushareTradeCalendar(rows, params),
      _ => null,
    };
  }

  Map<String, dynamic> _saveTushareStockBasic(
    List<Map<String, dynamic>> rows,
    String source,
  ) {
    final db = _db!;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT INTO stock_list
      (code,name,market,industry,list_date,delist_date,stock_type,updated_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?)
      ON CONFLICT(code) DO UPDATE SET
        name=excluded.name,
        market=excluded.market,
        industry=excluded.industry,
        list_date=COALESCE(excluded.list_date, stock_list.list_date),
        delist_date=excluded.delist_date,
        stock_type=excluded.stock_type,
        updated_at=excluded.updated_at,
        raw_json=excluded.raw_json
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final tsCode = _first(row, ['ts_code', 'code']);
        final code = _first(row, ['symbol']) ?? _stripTsCode(tsCode);
        if (code == null || code.isEmpty) continue;
        stmt.execute([
          _cleanCode(code),
          _first(row, ['name']) ?? code,
          _first(row, ['market']) ?? _tsSuffix(tsCode) ?? source,
          _first(row, ['industry']),
          _normalizeDate(_first(row, ['list_date'])),
          _normalizeDate(_first(row, ['delist_date'])),
          _first(row, ['stock_type']) ?? 'stock',
          fetchedAt,
          jsonEncode(row),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion('stock_list', 'stock_list', count);
  }

  Map<String, dynamic> _saveTushareKline(
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> params,
    String source,
  ) {
    final grouped = <String, List<KlineBar>>{};
    for (final row in rows) {
      final code =
          _stripTsCode(_first(row, ['ts_code', 'code'])) ??
          _stripTsCode('${params['ts_code'] ?? params['code'] ?? ''}');
      final date = _normalizeDate(_first(row, ['trade_date', 'date']));
      final open = _nullableNum(row['open']);
      final high = _nullableNum(row['high']);
      final low = _nullableNum(row['low']);
      final close = _nullableNum(row['close']);
      if (code == null ||
          code.isEmpty ||
          date == null ||
          open == null ||
          high == null ||
          low == null ||
          close == null) {
        continue;
      }
      final volume = _nullableNum(row['vol'] ?? row['volume']);
      final amount = _nullableNum(row['amount']);
      (grouped[_cleanCode(code)] ??= []).add(
        KlineBar(
          date: date,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume == null ? 0 : volume * 100,
          amount: amount == null ? 0 : amount * 1000,
          changePct: _nullableNum(row['pct_chg'] ?? row['change_pct']),
          turnoverRate: _nullableNum(
            row['turnover_rate'] ?? row['turnover_rate_f'],
          ),
        ),
      );
    }
    final adjust = '${params['adjust'] ?? 'none'}';
    for (final entry in grouped.entries) {
      saveKline(entry.key, entry.value, source: source, adjust: adjust);
    }
    final count = grouped.values.fold<int>(0, (sum, rows) => sum + rows.length);
    return _ingestion('kline_daily', 'kline_daily', count);
  }

  Map<String, dynamic> _saveTushareIndexConstituents(
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> params,
    String source,
  ) {
    final indexCode =
        _stripTsCode(
          _first(params, ['index_code', 'ts_code', 'code']) ??
              _first(rows.isEmpty ? const {} : rows.first, [
                'index_code',
                'indexCode',
                'ts_code',
                'con_code',
              ]),
        ) ??
        _cleanCode('${params['index_code'] ?? params['code'] ?? ''}');
    if (indexCode.isEmpty) {
      return _ingestion('index_constituent', 'index_constituent', 0);
    }
    final normalizedRows = rows
        .map((row) {
          final stockCode =
              _stripTsCode(_first(row, ['con_code', 'ts_code', 'stock_code'])) ??
              _cleanCode('${row['stock_code'] ?? row['code'] ?? ''}');
          if (stockCode.isEmpty) return null;
          return <String, dynamic>{
            'index_code': indexCode,
            'stock_code': stockCode,
            'stock_name':
                _first(row, ['con_name', 'stock_name', 'name']) ?? stockCode,
            'weight': _nullableNum(row['weight'] ?? row['weight_pct']),
            'as_of_date':
                _normalizeDate(
                  _first(row, ['trade_date', 'end_date', 'date']),
                ) ??
                _today(),
            'provider': 'tushare',
            'capability_id': 'tushare.index.constituents',
            'source_action': 'index_weight',
            'raw_json': jsonEncode(row),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    return saveIndexConstituents(normalizedRows, source: source);
  }
}
