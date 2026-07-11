import 'dart:io';

import 'package:finagent/agent/data_fetcher/data_manager.dart';
import 'package:finagent/agent/data_fetcher/reusable_data_store.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/domain/market/services/market_data_query_action_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'query_fund_nav excludes known money funds from ordinary NAV rows',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'finagent-query-fund-nav-money-filter-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = ReusableDataStore(dir.path)..cleanup();
      store.saveFundList([
        {
          'code': '110011',
          'name': '易方达优质精选混合',
          'fund_type': '混合型',
          'fund_category': 'ordinary',
        },
        {
          'code': '000009',
          'name': '易方达天天理财货币A',
          'fund_type': '货币型',
          'fund_category': 'money',
        },
      ]);
      store.saveFundNav([
        {
          'code': '110011',
          'date': '2026-06-24',
          'nav': 3.91,
          'source': 'eastmoney',
          'raw_json': '{"provider":"eastmoney","nav":3.91}',
        },
        {
          'code': '000009',
          'date': '2026-06-24',
          'nav': 1.0,
          'source': 'eastmoney',
          'raw_json': '{"provider":"eastmoney","money":true}',
        },
      ]);

      final service = MarketDataQueryActionService(dataManager: DataManager());
      final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

      final payload = service.query(
        'query_fund_nav',
        ['110011', '000009'],
        {'limit': 20},
        context,
      );

      expect(payload['action'], 'query_fund_nav');
      expect(payload['cacheStatus'], 'cache-hit');
      expect(payload['knownMoneyFundCodes'], contains('000009'));
      expect(payload['cacheDecision'], contains('query_fund_money_yield'));
      final rows = (payload['data'] as List).cast<Map>();
      expect(rows.map((row) => row['code']), contains('110011'));
      expect(rows.map((row) => row['code']), isNot(contains('000009')));
      expect(rows.any((row) => row.containsKey('raw_json')), isFalse);
    },
  );

  test(
    'calendar readback separates full coverage from limited page rows',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'finagent-query-calendar-coverage-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = ReusableDataStore(dir.path)..cleanup();
      final rows = <Map<String, dynamic>>[];
      var date = DateTime.utc(2026, 1, 5);
      final end = DateTime.utc(2026, 12, 31);
      while (!date.isAfter(end)) {
        rows.add({
          'date':
              '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          'market': 'CN',
          'is_trading_day':
              date.weekday == DateTime.saturday ||
                  date.weekday == DateTime.sunday
              ? 0
              : 1,
        });
        date = date.add(const Duration(days: 1));
      }
      store.saveTradeCalendarRows(rows, market: 'CN', source: 'fixture');

      final service = MarketDataQueryActionService(dataManager: DataManager());
      final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

      final summary = service.query('query_trade_calendar', const [], {
        'market': 'CN',
        'limit': 100,
      }, context);
      expect(summary['cacheStatus'], 'cache-hit');
      expect(summary['coverageStart'], '2026-01-05');
      expect(summary['coverageEnd'], '2026-12-31');
      expect(summary['coverageRows'], rows.length);
      expect(summary['pageRows'], 100);
      expect((summary['data'] as List).last['date'], '2026-12-31');

      final exact = service.query('query_trade_calendar', const [], {
        'market': 'CN',
        'date': '2026-07-10',
      }, context);
      expect(exact['count'], 1);
      expect((exact['data'] as List).first['date'], '2026-07-10');
    },
  );
}
