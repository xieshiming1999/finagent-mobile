part of 'reusable_data_store.dart';

extension ReusableDataStoreIndexConstituent on ReusableDataStore {
  Map<String, dynamic> saveIndexConstituents(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) {
      return _ingestion(
        'index_constituent',
        'index_constituent',
        0,
        provider: source,
      );
    }
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO index_constituent
      (index_code,stock_code,stock_name,weight,as_of_date,provider,capability_id,source_action,fetched_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final indexCode = _cleanCode(
          _first(row, [
                'index_code',
                'indexCode',
                '指数代码',
                '指数Wind代码',
                'index',
              ]) ??
              '',
        );
        final stockCode = _cleanCode(
          _first(row, [
                'stock_code',
                'stockCode',
                '成分券代码',
                '成分股代码',
                '股票代码',
                '证券代码',
                'code',
              ]) ??
              '',
        );
        final asOfDate =
            _normalizeDate(
              _first(row, [
                'as_of_date',
                'asOfDate',
                'trade_date',
                'date',
                '生效日期',
                '日期',
              ]),
            ) ??
            _today();
        final provider = '${row['provider'] ?? row['source'] ?? source}'.trim();
        if (indexCode.isEmpty || stockCode.isEmpty || provider.isEmpty) {
          continue;
        }
        stmt.execute([
          indexCode,
          stockCode,
          _first(row, [
            'stock_name',
            'stockName',
            '成分券名称',
            '成分股名称',
            '股票名称',
            '证券简称',
            '中文简称',
            'name',
          ]),
          _nullableNum(row['weight'] ?? row['权重'] ?? row['权重(%)']),
          asOfDate,
          provider,
          row['capability_id'] ?? '$provider.index.constituents',
          row['source_action'] ?? row['action'] ?? 'index_constituents',
          row['fetched_at'] ?? fetchedAt,
          row['raw_json'] ?? jsonEncode(row),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion(
      'index_constituent',
      'index_constituent',
      count,
      provider: source,
    );
  }

  List<Map<String, dynamic>> queryIndexConstituents({
    String? indexCode,
    String? stockCode,
    String? asOfDate,
    String? provider,
    int limit = 300,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (indexCode != null && indexCode.isNotEmpty) {
      where.add('index_code = ?');
      args.add(_cleanCode(indexCode));
    }
    if (stockCode != null && stockCode.isNotEmpty) {
      where.add('stock_code = ?');
      args.add(_cleanCode(stockCode));
    }
    final normalizedDate = _normalizeDate(asOfDate);
    if (normalizedDate != null) {
      where.add('as_of_date = ?');
      args.add(normalizedDate);
    }
    if (provider != null && provider.isNotEmpty) {
      where.add('provider = ?');
      args.add(provider);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM index_constituent $whereSql ORDER BY as_of_date DESC, weight DESC, stock_code LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList(growable: false);
  }
}
