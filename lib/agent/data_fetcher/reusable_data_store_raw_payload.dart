part of 'reusable_data_store.dart';

extension ReusableDataStoreRawPayload on ReusableDataStore {
  void saveRawApiPayload({
    required String source,
    required String endpoint,
    required Map<String, dynamic> request,
    required Object? response,
    bool isError = false,
    Duration ttl = const Duration(days: 30),
  }) {
    final db = _db;
    if (db == null) return;
    final createdAt = DateTime.now().toUtc();
    final requestJson = jsonEncode(request);
    final hash = sha256.convert(utf8.encode(requestJson)).toString();
    db.execute(
      '''
      INSERT OR REPLACE INTO raw_api_payload
      (source,endpoint,request_hash,request_json,response_json,is_error,created_at,expires_at)
      VALUES (?,?,?,?,?,?,?,?)
      ''',
      [
        source,
        endpoint,
        hash,
        requestJson,
        _safeJson(response),
        isError ? 1 : 0,
        createdAt.toIso8601String(),
        createdAt.add(ttl).toIso8601String(),
      ],
    );
  }

  List<Map<String, dynamic>> queryRawApiPayload({
    String? source,
    String? endpoint,
    int limit = 20,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    if (endpoint != null && endpoint.isNotEmpty) {
      where.add('endpoint = ?');
      args.add(endpoint);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = db.select('''
      SELECT source,endpoint,request_hash,is_error,created_at,expires_at,request_json,
             substr(response_json, 1, 500) AS response_preview
      FROM raw_api_payload
      $whereSql
      ORDER BY created_at DESC
      LIMIT ?
      ''', args);
    return rows.map(_rowMap).toList();
  }
}
