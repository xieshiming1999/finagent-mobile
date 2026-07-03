part of 'reusable_data_store.dart';

extension ReusableDataStoreEastmoneySectorMarket on ReusableDataStore {
  void saveSectorRanking(
    String boardType,
    List<Map<String, dynamic>> rows, {
    required String source,
    String? tradeDate,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final date = tradeDate ?? _today();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO sector_rank
      (trade_date,board_type,rank,code,source,fetched_at,name,change_pct,change_amount,turnover_rate,up_count,down_count,leading_stock,leading_change_pct,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final code = _first(row, ['code', 'f12']);
        if (code == null || code.isEmpty) continue;
        stmt.execute([
          date,
          boardType,
          i + 1,
          code,
          source,
          fetchedAt,
          _first(row, ['name', 'f14']),
          _nullableNum(row['changePct'] ?? row['f3']),
          _nullableNum(row['changeAmount'] ?? row['f4']),
          _nullableNum(row['turnoverRate'] ?? row['f8']),
          _int(row['upCount'] ?? row['f104']),
          _int(row['downCount'] ?? row['f105']),
          _first(row, ['leadingStock', 'f140']),
          _nullableNum(row['leadingChangePct'] ?? row['f141']),
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> querySectorRanking({
    String? boardType,
    String? tradeDate,
    String? source,
    int limit = 50,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (boardType != null && boardType.isNotEmpty) {
      where.add('board_type = ?');
      args.add(boardType);
    }
    if (tradeDate != null && tradeDate.isNotEmpty) {
      where.add('trade_date = ?');
      args.add(tradeDate);
    }
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM sector_rank $whereSql ORDER BY trade_date DESC, board_type, rank LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }

  void saveChipDistribution(
    String code,
    Map<String, dynamic> payload, {
    required String source,
    String? tradeDate,
  }) {
    final db = _db;
    if (db == null || payload.isEmpty || payload['error'] != null) return;
    final date =
        tradeDate ??
        _normalizeDate(_first(payload, ['date', 'TRADE_DATE'])) ??
        _today();
    db.execute(
      '''
      INSERT OR REPLACE INTO chip_distribution
      (code,trade_date,source,fetched_at,avg_cost,profit_ratio,concentration70,concentration90,current_price,method,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)
      ''',
      [
        _cleanCode(code),
        date,
        source,
        DateTime.now().toUtc().toIso8601String(),
        _nullableNum(payload['avgCost'] ?? payload['AVG_COST']),
        _nullableNum(payload['profitRatio'] ?? payload['PROFIT_RATIO']),
        _nullableNum(payload['concentration70'] ?? payload['CONCENTRATION_70']),
        _nullableNum(payload['concentration90'] ?? payload['CONCENTRATION_90']),
        _nullableNum(payload['currentPrice']),
        _first(payload, ['method']),
        jsonEncode(payload),
      ],
    );
  }

  List<Map<String, dynamic>> queryChipDistribution(
    String code, {
    String? tradeDate,
    String? source,
    int limit = 20,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['code = ?'];
    final args = <Object>[_cleanCode(code)];
    if (tradeDate != null && tradeDate.isNotEmpty) {
      where.add('trade_date = ?');
      args.add(tradeDate);
    }
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM chip_distribution WHERE ${where.join(' AND ')} ORDER BY trade_date DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
