part of 'reusable_data_store.dart';

extension ReusableDataStoreCoreMarket on ReusableDataStore {
  void saveQuoteSnapshots(List<StockQuote> quotes, String source) {
    final db = _db;
    if (db == null || quotes.isEmpty) return;
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO quote_snapshot
      (code,timestamp,fetched_at,source,name,price,change,change_pct,open,high,low,prev_close,volume,amount,pe,pb,market_cap,turnover_rate,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final q in quotes) {
        final fetchedAt =
            q.fetchedAt ?? DateTime.now().toUtc().toIso8601String();
        stmt.execute([
          _cleanCode(q.code),
          q.timestamp ?? fetchedAt,
          fetchedAt,
          source,
          q.name,
          q.price,
          q.change,
          q.changePct,
          q.open,
          q.high,
          q.low,
          q.prevClose,
          q.volume,
          q.amount,
          q.pe,
          q.pb,
          q.marketCap,
          q.turnoverRate,
          jsonEncode(q.toJson()),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  StockQuote? getRecentQuote(String code, Duration maxAge, {String? source}) {
    final db = _db;
    if (db == null) return null;
    final since = DateTime.now().toUtc().subtract(maxAge).toIso8601String();
    final where = <String>['code = ?', 'timestamp >= ?'];
    final args = <Object>[_cleanCode(code), since];
    if (source != null && source.isNotEmpty) {
      where.add('lower(source) = lower(?)');
      args.add(source);
    }
    final rows = db.select(
      'SELECT * FROM quote_snapshot WHERE ${where.join(' AND ')} ORDER BY timestamp DESC LIMIT 1',
      args,
    );
    if (rows.isEmpty) return null;
    return _quoteFromRow(rows.first);
  }

  List<StockQuote> queryQuotes(String code, {int limit = 20, String? source}) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['code = ?'];
    final args = <Object>[_cleanCode(code)];
    if (source != null && source.isNotEmpty) {
      where.add('lower(source) = lower(?)');
      args.add(source);
    }
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM quote_snapshot WHERE ${where.join(' AND ')} ORDER BY timestamp DESC LIMIT ?',
      args,
    );
    return rows.map(_quoteFromRow).toList();
  }

  void saveKline(
    String code,
    List<KlineBar> bars, {
    required String source,
    String adjust = 'qfq',
  }) {
    final db = _db;
    if (db == null || bars.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO kline_daily
      (code,date,adjust,source,fetched_at,open,high,low,close,volume,amount,change_pct,turnover_rate,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final b in bars) {
        stmt.execute([
          _cleanCode(code),
          b.date,
          adjust,
          source,
          fetchedAt,
          b.open,
          b.high,
          b.low,
          b.close,
          b.volume,
          b.amount,
          b.changePct,
          b.turnoverRate,
          jsonEncode(b.toJson()),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<KlineBar> queryKline(
    String code, {
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
    String? source,
    int? limit,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['code = ?', 'adjust = ?'];
    final args = <Object>[_cleanCode(code), adjust];
    if (source != null && source.isNotEmpty) {
      where.add('lower(source) = lower(?)');
      args.add(source);
    }
    if (startDate.isNotEmpty) {
      where.add('date >= ?');
      args.add(startDate);
    }
    if (endDate.isNotEmpty) {
      where.add('date <= ?');
      args.add(endDate);
    }
    final limitSql = limit == null ? '' : ' LIMIT ?';
    if (limit != null) args.add(limit);
    final rows = db.select(
      'SELECT * FROM kline_daily WHERE ${where.join(' AND ')} ORDER BY date DESC$limitSql',
      args,
    );
    return rows.map(_klineFromRow).toList().reversed.toList();
  }
}
