import 'dart:io';

import 'package:finagent/agent/data_fetcher/reusable_data_store.dart';

void main() {
  final dir = Directory.systemTemp.createTempSync('finagent_store_');
  try {
    final store = ReusableDataStore(dir.path);
    store.saveTickChart(
      '600519',
      [
        {
          'minute': 0,
          'time': '09:30',
          'price': 1280.5,
          'avg': 1280.5,
          'volume': 12,
        },
        {
          'minute': 1,
          'time': '09:31',
          'price': 1281.0,
          'avg': 1280.7,
          'volume': 8,
        },
      ],
      source: '通达信',
      tradeDate: '2026-06-04',
    );
    store.saveTransactions(
      '600519',
      [
        {
          'time': '09:30',
          'price': 1280.5,
          'volume': 2,
          'trades': 1,
          'direction': 'buy',
        },
      ],
      source: '通达信',
      tradeDate: '2026-06-04',
    );
    store.saveVolumeProfile(
      '600519',
      {
        'close': 1281.0,
        'open': 1280.0,
        'high': 1288.0,
        'low': 1279.0,
        'preClose': 1290.0,
        'vol': 100,
        'amount': 128100,
        'profiles': [
          {'price': 1280.0, 'vol': 10, 'buy': 6, 'sell': 4},
        ],
      },
      source: '通达信',
      tradeDate: '2026-06-04',
    );
    store.saveCompanyInfo('600519', 'tdx_finance', {
      'eps': 1.23,
      'netProfit': 100,
      'source': '通达信',
    }, source: '通达信');
    store.saveHotRank(
      [
        {
          'code': '600519',
          'name': '贵州茅台',
          'rank': 1,
          'rankChange': 0,
          'hotValue': 999,
        },
      ],
      source: '东方财富',
      tradeDate: '2026-06-04',
    );
    store.saveDragonTiger([
      {
        'SECURITY_CODE': '600519',
        'SECURITY_NAME_ABBR': '贵州茅台',
        'TRADE_DATE': '2026-06-04 00:00:00',
        'NET_BUY_AMT': 12345,
      },
    ], source: '东方财富');

    final checks = <String, bool>{
      'tick_chart_intraday': store.queryTickChart('600519').length == 2,
      'transactions': store.queryTransactions('600519').length == 1,
      'volume_profile': store.queryVolumeProfile('600519').length == 1,
      'stock_company_info': store.queryCompanyInfo('600519').length == 1,
      'hot_rank': store.queryHotRank(code: '600519').length == 1,
      'dragon_tiger': store.queryDragonTiger(code: '600519').length == 1,
    };
    final failed = checks.entries
        .where((e) => !e.value)
        .map((e) => e.key)
        .toList();
    if (failed.isNotEmpty) {
      throw StateError('structured store checks failed: ${failed.join(', ')}');
    }
    stdout.writeln('structured reusable store checks passed');
  } finally {
    dir.deleteSync(recursive: true);
  }
}
