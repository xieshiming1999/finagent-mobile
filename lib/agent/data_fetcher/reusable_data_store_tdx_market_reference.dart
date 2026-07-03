part of 'reusable_data_store.dart';

extension ReusableDataStoreTdxMarketReference on ReusableDataStore {
  void saveTdxBlockMembers(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO tdx_block_member
      (block_code,block_name,code,name,block_type,source,fetched_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final blockCode = '${row['block_code'] ?? row['blockCode'] ?? ''}'.trim();
        final code = _cleanCode('${row['code'] ?? ''}');
        if (blockCode.isEmpty || code.isEmpty) continue;
        stmt.execute([
          blockCode,
          row['block_name'] ?? row['blockName'],
          code,
          row['name'],
          '${row['block_type'] ?? row['blockType'] ?? ''}',
          source,
          fetchedAt,
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryTdxBlockMembers({
    String? code,
    String? blockCode,
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
    if (blockCode != null && blockCode.isNotEmpty) {
      where.add('block_code = ?');
      args.add(blockCode);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM tdx_block_member $whereSql ORDER BY fetched_at DESC, block_code ASC, code ASC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }

  void saveCompanyInfo(
    String code,
    String infoType,
    Map<String, dynamic> payload, {
    required String source,
  }) {
    final db = _db;
    if (db == null) return;
    final categories = payload['categories'] as List?;
    String? fallbackTitle;
    if (categories != null && categories.isNotEmpty) {
      final first = categories.first;
      if (first is Map) {
        fallbackTitle = first['title'] as String?;
      }
    }
    db.execute(
      '''
      INSERT OR REPLACE INTO stock_company_info
      (code,info_type,title,source,fetched_at,category_count,content,payload_json)
      VALUES (?,?,?,?,?,?,?,?)
      ''',
      [
        _cleanCode(code),
        infoType,
        payload['title'] as String? ?? fallbackTitle ?? infoType,
        source,
        DateTime.now().toUtc().toIso8601String(),
        categories?.length,
        payload['first_content'] as String?,
        jsonEncode(payload),
      ],
    );
  }

  List<Map<String, dynamic>> queryCompanyInfo(
    String code, {
    String? infoType,
    int limit = 20,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['code = ?'];
    final args = <Object>[_cleanCode(code)];
    if (infoType != null && infoType.isNotEmpty) {
      where.add('(info_type = ? OR info_type LIKE ?)');
      args.add(infoType);
      args.add('$infoType:%');
    }
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM stock_company_info WHERE ${where.join(' AND ')} ORDER BY fetched_at DESC, title ASC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }

  void saveStockShareholders(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) return;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO stock_shareholder
      (code,report_date,holder_name,holder_type,rank,hold_shares,hold_pct,share_nature,announcement_date,shareholder_note,shareholder_count,average_holding,source,fetched_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        final code = _cleanCode('${row['code'] ?? row['symbol'] ?? ''}');
        final reportDate =
            '${row['report_date'] ?? row['reportDate'] ?? ''}'.trim();
        final holderName =
            '${row['holder_name'] ?? row['holderName'] ?? row['name'] ?? ''}'
                .trim();
        if (code.isEmpty || reportDate.isEmpty || holderName.isEmpty) {
          continue;
        }
        stmt.execute([
          code,
          reportDate,
          holderName,
          '${row['holder_type'] ?? row['holderType'] ?? 'top_shareholder'}',
          _asInt(row['rank']),
          _asDouble(row['hold_shares'] ?? row['holdShares']),
          _asDouble(row['hold_pct'] ?? row['holdPct']),
          row['share_nature'] ?? row['shareNature'],
          row['announcement_date'] ?? row['announcementDate'],
          row['shareholder_note'] ?? row['shareholderNote'],
          _asInt(row['shareholder_count'] ?? row['shareholderCount']),
          _asDouble(row['average_holding'] ?? row['averageHolding']),
          source,
          fetchedAt,
          jsonEncode(row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryStockShareholders({
    String? code,
    String? holderName,
    String? reportDate,
    String? source,
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>[];
    final args = <Object>[];
    if (code != null && code.isNotEmpty) {
      where.add('code = ?');
      args.add(_cleanCode(code));
    }
    if (holderName != null && holderName.isNotEmpty) {
      where.add('holder_name LIKE ?');
      args.add('%$holderName%');
    }
    if (reportDate != null && reportDate.isNotEmpty) {
      where.add('report_date = ?');
      args.add(reportDate);
    }
    if (source != null && source.isNotEmpty) {
      where.add('source = ?');
      args.add(source);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM stock_shareholder $whereSql ORDER BY report_date DESC, rank IS NULL, rank ASC, hold_pct DESC LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  double? _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value'.replaceAll('%', ''));
  }
}
