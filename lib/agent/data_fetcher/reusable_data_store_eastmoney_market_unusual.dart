part of 'reusable_data_store.dart';

extension ReusableDataStoreEastmoneyMarketUnusual on ReusableDataStore {
  void saveUnusualActivity(
    List<Map<String, dynamic>> rows, {
    required String source,
    String? eventDate,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final date = eventDate ?? _today();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO unusual_activity
      (event_date,code,event_time,event_type,source,fetched_at,name,info,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final code = _first(row, ['code', 'SECURITY_CODE']);
        if (code == null || code.isEmpty) continue;
        stmt.execute([
          date,
          _cleanCode(code),
          _first(row, ['time', 'eventTime']) ?? '',
          _first(row, ['type', 'eventType']) ?? '',
          source,
          fetchedAt,
          _first(row, ['name', 'SECURITY_NAME_ABBR', 'SECURITY_NAME']),
          _first(row, ['info', 'eventInfo', 'eventName']),
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryUnusualActivity({
    String? code,
    String? eventDate,
    int limit = 50,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (code != null && code.isNotEmpty) {
      where.add('code = ?');
      args.add(_cleanCode(code));
    }
    if (eventDate != null && eventDate.isNotEmpty) {
      where.add('event_date = ?');
      args.add(eventDate);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM unusual_activity $whereSql ORDER BY event_date DESC, event_time DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
