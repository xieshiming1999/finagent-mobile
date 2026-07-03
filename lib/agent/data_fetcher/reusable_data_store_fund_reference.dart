part of 'reusable_data_store.dart';

extension ReusableDataStoreFundReference on ReusableDataStore {
  Map<String, dynamic> saveFundList(List<Map<String, dynamic>> rows) {
    final db = _db;
    if (db == null || rows.isEmpty) {
      return _ingestion('fund_list', 'fund_list', 0, provider: 'local');
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO fund_list
      (code,name,fund_type,fund_category,company,manager,setup_date,total_size,nav,nav_date,return_1y,return_3y,return_ytd,updated_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    final managerStmt = db.prepare('''
      INSERT OR REPLACE INTO fund_manager
      (manager_name,company,fund_code,fund_name,fund_type,total_size,updated_at,source,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?)
    ''');
    var count = 0;
    var managerCount = 0;
    try {
      for (final row in rows) {
        final code = _first(row, ['code', 'fund_code', 'ts_code']);
        if (code == null || code.isEmpty) continue;
        final name = _first(row, ['name', 'fund_name']) ?? code;
        final fundType = _first(row, ['fund_type', 'type']);
        final fundCategory = normalizeFundCategory({
          ...row,
          'fund_type': fundType,
          'name': name,
        });
        final company = _first(row, ['company', 'management', 'custodian']);
        final manager = _first(row, ['manager']);
        final totalSize = _nullableNum(
          row['total_size'] ?? row['issue_amount'] ?? row['m_fee'],
        );
        final rowUpdatedAt = _first(row, ['updated_at']) ?? updatedAt;
        final rawJson = jsonEncode(row);
        stmt.execute([
          code,
          name,
          fundType,
          fundCategory,
          company,
          manager,
          _normalizeDate(_first(row, ['setup_date', 'found_date'])),
          totalSize,
          _nullableNum(row['nav']),
          _normalizeDate(_first(row, ['nav_date'])),
          _nullableNum(row['return_1y']),
          _nullableNum(row['return_3y']),
          _nullableNum(row['return_ytd']),
          rowUpdatedAt,
          rawJson,
        ]);
        count++;
        if (manager != null && manager.isNotEmpty) {
          managerStmt.execute([
            manager,
            company,
            code,
            name,
            fundType,
            totalSize,
            rowUpdatedAt,
            _first(row, ['source']) ?? 'local',
            rawJson,
          ]);
          managerCount++;
        }
      }
    } finally {
      stmt.close();
      managerStmt.close();
    }
    return {
      ..._ingestion('fund_list', 'fund_list', count, provider: 'local'),
      'derived': {
        'schema': 'fund_manager',
        'table': 'fund_manager',
        'rows': managerCount,
        'persisted': managerCount > 0,
      },
    };
  }

  Map<String, dynamic> saveFundManagerRows(
    List<Map<String, dynamic>> rows, {
    String source = 'local',
  }) {
    final db = _db;
    if (db == null || rows.isEmpty) {
      return _ingestion('fund_manager', 'fund_manager', 0, provider: source);
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO fund_manager
      (manager_name,company,fund_code,fund_name,fund_type,total_size,updated_at,source,raw_json)
      VALUES (?,?,?,?,?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final managerName =
            _first(row, ['manager_name', 'manager', 'name'])?.trim();
        if (managerName == null || managerName.isEmpty) continue;
        stmt.execute([
          managerName,
          _first(row, ['company']),
          _first(row, ['fund_code', 'code']),
          _first(row, ['fund_name', 'name']),
          _first(row, ['fund_type', 'type']),
          _nullableNum(row['total_size']),
          _first(row, ['updated_at']) ?? updatedAt,
          _first(row, ['source']) ?? source,
          row['raw_json'] ?? jsonEncode(row),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion('fund_manager', 'fund_manager', count, provider: source);
  }

  Map<String, dynamic> saveFundNav(List<Map<String, dynamic>> rows) {
    final db = _db;
    if (db == null || rows.isEmpty) {
      return _ingestion('fund_nav', 'fund_nav', 0, provider: 'local');
    }
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO fund_nav
      (code,date,nav,acc_nav,daily_return,source,fetched_at,raw_json)
      VALUES (?,?,?,?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final code = _first(row, ['code', 'fund_code', 'ts_code']);
        final date = _normalizeDate(
          _first(row, ['date', 'nav_date', 'end_date']),
        );
        if (code == null || code.isEmpty || date == null) continue;
        stmt.execute([
          code,
          date,
          _nullableNum(row['nav'] ?? row['unit_nav'] ?? row['adj_nav']),
          _nullableNum(row['acc_nav'] ?? row['accum_nav']),
          _nullableNum(row['daily_return']),
          _first(row, ['source']) ?? 'local',
          _first(row, ['fetched_at']) ?? fetchedAt,
          jsonEncode(row),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion('fund_nav', 'fund_nav', count, provider: 'local');
  }

  Map<String, dynamic> saveFundMoneyYield(List<Map<String, dynamic>> rows) {
    final db = _db;
    if (db == null || rows.isEmpty) {
      return _ingestion(
        'fund_money_yield',
        'fund_money_yield',
        0,
        provider: 'local',
      );
    }
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO fund_money_yield
      (code,date,million_copies_income,seven_day_annualized_yield,source,fetched_at,raw_json)
      VALUES (?,?,?,?,?,?,?)
    ''');
    var count = 0;
    try {
      for (final row in rows) {
        final code = _first(row, ['code', 'fund_code', 'ts_code']);
        final date = _normalizeDate(_first(row, ['date', 'yield_date']));
        if (code == null || code.isEmpty || date == null) continue;
        stmt.execute([
          code,
          date,
          _nullableNum(row['million_copies_income']),
          _nullableNum(row['seven_day_annualized_yield']),
          _first(row, ['source']) ?? 'local',
          _first(row, ['fetched_at']) ?? fetchedAt,
          jsonEncode(row),
        ]);
        count++;
      }
    } finally {
      stmt.close();
    }
    return _ingestion(
      'fund_money_yield',
      'fund_money_yield',
      count,
      provider: 'local',
    );
  }

  List<Map<String, dynamic>> queryFundManager({
    String? company,
    String? manager,
    String? fundCode,
    int limit = 100,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['1=1'];
    final args = <Object>[];
    if (company != null && company.isNotEmpty) {
      where.add('company LIKE ?');
      args.add('%$company%');
    }
    if (manager != null && manager.isNotEmpty) {
      where.add('manager_name LIKE ?');
      args.add('%$manager%');
    }
    if (fundCode != null && fundCode.isNotEmpty) {
      where.add('fund_code = ?');
      args.add(fundCode);
    }
    args.add(limit);
    final rows = db.select(
      'SELECT * FROM fund_manager WHERE ${where.join(' AND ')} ORDER BY updated_at DESC, company, manager_name, fund_code LIMIT ?',
      args,
    );
    return rows.map(_rowMap).toList();
  }
}
