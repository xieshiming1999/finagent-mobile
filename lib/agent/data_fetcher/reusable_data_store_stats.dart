part of 'reusable_data_store.dart';

extension ReusableDataStoreStats on ReusableDataStore {
  Map<String, dynamic> stats() {
    final db = _db;
    if (db == null) {
      return {'available': false, 'message': 'Reusable data store unavailable'};
    }

    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final tableRows = tables.map((row) {
      final name = row['name'] as String;
      final countRow = db.select('SELECT COUNT(*) AS cnt FROM $name').first;
      return {
        'name': name,
        'count': (countRow['cnt'] as num?)?.toInt() ?? 0,
      };
    }).toList(growable: false);
    final totalRows = tableRows.fold<int>(
      0,
      (sum, row) => sum + ((row['count'] as int?) ?? 0),
    );
    final dbFile = File('$basePath/data/market_data.db');

    return {
      'available': true,
      'sizeBytes': dbFile.existsSync() ? dbFile.lengthSync() : 0,
      'tableCount': tableRows.length,
      'totalRows': totalRows,
      'tables': tableRows,
      'sources': _reusableSummarySources(db),
      'coverage': reusableSummary(),
    };
  }
}
