import 'dart:io';

import 'package:finagent/agent/watchlist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'searchCachedAssets reads stock and fund identities from local store',
    () async {
      final dir = await Directory.systemTemp.createTemp('finagent-watchlist-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dataDir = Directory('${dir.path}/data')
        ..createSync(recursive: true);
      final db = sqlite3.open('${dataDir.path}/market_data.db');
      addTearDown(db.close);
      db.execute('''
      CREATE TABLE stock_list (
        code TEXT,
        name TEXT,
        market TEXT,
        stock_type TEXT,
        delist_date TEXT
      )
    ''');
      db.execute('''
      CREATE TABLE fund_list (
        code TEXT,
        name TEXT,
        fund_type TEXT,
        company TEXT,
        total_size REAL
      )
    ''');
      db.execute(
        'INSERT INTO stock_list (code,name,market,stock_type,delist_date) VALUES (?,?,?,?,?)',
        ['600519', '贵州茅台', 'SH', 'stock', null],
      );
      db.execute(
        'INSERT INTO fund_list (code,name,fund_type,company,total_size) VALUES (?,?,?,?,?)',
        ['110011', '易方达中小盘', 'mixed', '易方达', 120.0],
      );

      final store = WatchlistStore()..load(dir.path);

      final stocks = store.searchCachedAssets('茅台', type: 'stock');
      expect(stocks, hasLength(1));
      expect(stocks.first.code, '600519');
      expect(stocks.first.name, '贵州茅台');

      final funds = store.searchCachedAssets('110', type: 'fund');
      expect(funds, hasLength(1));
      expect(funds.first.code, '110011');
      expect(funds.first.company, '易方达');
    },
  );
}
