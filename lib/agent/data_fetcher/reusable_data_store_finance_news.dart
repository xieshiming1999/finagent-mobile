part of 'reusable_data_store.dart';

extension ReusableDataStoreFinanceNews on ReusableDataStore {
  Map<String, dynamic> saveFinanceNews(List<Map<String, dynamic>> rows) {
    final db = _db;
    if (db == null) return _ingestion('finance_news', 'finance_news', 0);
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO finance_news
      (news_id,title,summary,content,publisher,published_at,url,source,fetched_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final title = _first(row, ['title', 'headline', 'name']);
        if (title == null || title.isEmpty) continue;
        final publishedAt = _first(row, [
          'published_at',
          'publish_time',
          'date',
          'time',
        ]);
        final url = _first(row, ['url', 'link']);
        final source = _first(row, ['source', 'publisher', 'media']) ?? 'news';
        final rawJson = jsonEncode(row);
        stmt.execute([
          _first(row, ['news_id', 'id']) ??
              _financeNewsId(source, publishedAt, title, url),
          title,
          _first(row, ['summary', 'abstract', 'description']),
          _first(row, ['content', 'body']),
          _first(row, ['publisher', 'media', 'media_name']) ?? source,
          publishedAt,
          url,
          source,
          _first(row, ['fetched_at']) ?? fetchedAt,
          row['raw_json']?.toString() ?? rawJson,
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion('finance_news', 'finance_news', count, provider: 'news');
  }

  List<Map<String, dynamic>> queryFinanceNews({
    String? keyword,
    String? source,
    int limit = 50,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['1=1'];
    final args = <Object>[];
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    if (keyword != null && keyword.isNotEmpty) {
      where.add('(title LIKE ? OR summary LIKE ? OR content LIKE ?)');
      final pattern = '%$keyword%';
      args.addAll([pattern, pattern, pattern]);
    }
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM finance_news WHERE ${where.join(' AND ')} ORDER BY published_at DESC, fetched_at DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }

  String _financeNewsId(
    String source,
    String? publishedAt,
    String title,
    String? url,
  ) {
    final seed = jsonEncode({
      'source': source,
      'published_at': publishedAt,
      'title': title,
      'url': url,
    });
    return sha256.convert(utf8.encode(seed)).toString();
  }
}
