part of 'reusable_data_store.dart';

extension ReusableDataStoreMarketScreening on ReusableDataStore {
  void saveMarketScreeningSnapshots({
    required String provider,
    required String capabilityId,
    required String sourceAction,
    required List<String> universe,
    required Map<String, dynamic> filters,
    required Map<String, dynamic> sort,
    required List<Map<String, dynamic>> rows,
    String? screenedAt,
    String? fetchedAt,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final screenTime = screenedAt ?? DateTime.now().toUtc().toIso8601String();
    final fetchTime = fetchedAt ?? screenTime;
    final universeJson = jsonEncode(universe);
    final filtersJson = jsonEncode(filters);
    final sortJson = jsonEncode(sort);
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO market_screening_snapshot
      (provider,capability_id,source_action,symbol,name,market,rank,score,screened_at,fetched_at,universe_json,filters_json,sort_json,fields_json,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final symbol = '${row['symbol'] ?? row['ticker'] ?? row['code'] ?? ''}';
        if (symbol.isEmpty) continue;
        stmt.execute([
          provider,
          capabilityId,
          sourceAction,
          symbol,
          row['name']?.toString(),
          row['market']?.toString(),
          _int(row['rank']) ?? i + 1,
          _nullableNum(
            row['score'] ?? row['composite_score'] ?? row['Recommend.All'],
          ),
          screenTime,
          fetchTime,
          universeJson,
          filtersJson,
          sortJson,
          jsonEncode(row),
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryMarketScreeningSnapshots({
    String? provider,
    String? symbol,
    String? sourceAction,
    String? since,
    int limit = 50,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['1=1'];
    final args = <Object>[];
    if (provider != null && provider.isNotEmpty) {
      where.add('provider = ?');
      args.add(provider);
    }
    if (symbol != null && symbol.isNotEmpty) {
      where.add('symbol = ?');
      args.add(symbol);
    }
    if (sourceAction != null && sourceAction.isNotEmpty) {
      where.add('source_action = ?');
      args.add(sourceAction);
    }
    if (since != null && since.isNotEmpty) {
      where.add('screened_at >= ?');
      args.add(since);
    }
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM market_screening_snapshot WHERE ${where.join(' AND ')} '
      'ORDER BY screened_at DESC, rank IS NULL, rank ASC, score DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList(growable: false);
  }
}
