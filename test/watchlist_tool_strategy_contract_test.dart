import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/watchlist_tool/watchlist_tool.dart';
import 'package:finagent/agent/watchlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Watchlist preserves strategy id and structured strategy rules',
    () async {
      final dir = await Directory.systemTemp.createTemp('finagent-watchlist-strategy-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = WatchlistStore()..load(dir.path);
      final tool = WatchlistTool(store: store);
      final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

      final add = await tool.call('add-1', {
        'action': 'add',
        'symbol': '600519',
        'name': '贵州茅台',
        'type': 'stock',
        'entryCondition': 'StrategySpec entry rules',
        'strategyId': 'custom_rsi_volume_rebound_v1',
        'strategyRules': {
          'entry': {
            'all': [
              {'left': 'rsi5', 'op': '<', 'right': 65},
            ],
          },
          'exit': {
            'any': [
              {'type': 'stop_loss_pct', 'value': 8},
            ],
          },
        },
        'portfolioEvidence': {
          'mode': 'equal_weight_selected_metrics',
          'selectedCount': 2,
          'aggregateMetrics': {
            'selectedSymbols': ['600519', '000858'],
            'expectedReturnPct': 8.4,
          },
          'tradeBoundary': 'Evidence only. Do not place orders.',
        },
        'rebalanceDraft': {
          'rebalanceInterval': 'monthly',
          'positions': [
            {'symbol': '600519', 'targetWeight': 0.4},
            {'symbol': '000858', 'targetWeight': 0.4},
          ],
          'tradeBoundary': 'Requires confirmation before any order.',
        },
      }, context);
      expect(add.isError, isFalse);

      final list = await tool.call('list-1', {
        'action': 'list',
        'symbol': '600519',
        'status': 'watching',
      }, context);
      final payload = jsonDecode(list.content) as Map<String, dynamic>;
      final item = (payload['items'] as List).single as Map<String, dynamic>;
      expect(item['strategyId'], 'custom_rsi_volume_rebound_v1');
      expect((item['strategyRules'] as Map)['entry'], isA<Map>());
      expect((item['strategyRules'] as Map)['exit'], isA<Map>());
      expect(item['portfolioEvidence'], isA<Map>());
      expect(item['rebalanceDraft'], isA<Map>());
      final rules = item['strategyRules'] as Map;
      expect((rules['portfolioEvidence'] as Map)['selectedCount'], 2);
      expect((rules['rebalanceDraft'] as Map)['rebalanceInterval'], 'monthly');
    },
  );

  test(
    'Watchlist filters strategy-derived rows by strategy id for exact readback',
    () async {
      final dir = await Directory.systemTemp.createTemp('finagent-watchlist-strategy-filter-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = WatchlistStore()..load(dir.path);
      final tool = WatchlistTool(store: store);
      final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

      await tool.call('add-other', {
        'action': 'add',
        'symbol': '000858',
        'name': '五粮液',
        'type': 'stock',
        'strategyId': 'older_strategy_v1',
        'strategyRules': {'id': 'older_strategy_v1', 'symbol': '000858'},
      }, context);
      await tool.call('add-new', {
        'action': 'add',
        'symbol': '600519',
        'name': '贵州茅台',
        'type': 'stock',
        'strategyId': 'custom_20_v1',
        'strategyRules': {'id': 'custom_20_v1', 'symbol': '600519'},
      }, context);

      final bySymbol = await tool.call('list-symbol', {
        'action': 'list',
        'symbol': '600519',
        'status': 'watching',
      }, context);
      final symbolPayload = jsonDecode(bySymbol.content) as Map<String, dynamic>;
      expect(symbolPayload['count'], 1);
      expect((symbolPayload['items'] as List).first['strategyId'], 'custom_20_v1');
      expect((symbolPayload['items'] as List).first['addedAt'], isA<String>());

      final byStrategy = await tool.call('list-strategy', {
        'action': 'list',
        'symbol': '600519',
        'strategyId': 'custom_20_v1',
        'status': 'watching',
      }, context);
      final strategyPayload = jsonDecode(byStrategy.content) as Map<String, dynamic>;
      final item = (strategyPayload['items'] as List).single as Map<String, dynamic>;
      expect(item['symbol'], '600519');
      expect(item['strategyId'], 'custom_20_v1');
      expect((item['strategyRules'] as Map)['id'], 'custom_20_v1');

      final mismatch = await tool.call('list-mismatch', {
        'action': 'list',
        'symbol': '600519',
        'strategyId': 'older_strategy_v1',
        'status': 'watching',
      }, context);
      expect((jsonDecode(mismatch.content) as Map<String, dynamic>)['count'], 0);
    },
  );

  test(
    'Watchlist supports macro-condition rows without fund or ETF placeholders',
    () async {
      final dir = await Directory.systemTemp.createTemp('finagent-watchlist-macro-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = WatchlistStore()..load(dir.path);
      final tool = WatchlistTool(store: store);
      final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

      final add = await tool.call('add-macro', {
        'action': 'add',
        'type': 'macro-condition',
        'name': '利率上行风险观察',
        'entryCondition': '10Y收益率继续上行且信用利差扩大',
        'source': 'macro-reliability',
        'tags': ['macro', 'risk'],
        'strategyRules': {
          'evidenceTier': 'official numeric fact + research view',
          'invalidation': '利率回落且信用利差收窄',
        },
      }, context);
      expect(add.isError, isFalse);

      final list = await tool.call('list-macro', {
        'action': 'list',
        'type': 'macro-condition',
        'status': 'watching',
      }, context);
      final payload = jsonDecode(list.content) as Map<String, dynamic>;
      final item = (payload['items'] as List).single as Map<String, dynamic>;
      expect(item['type'], 'macro-condition');
      expect(item['name'], '利率上行风险观察');
      expect(item['entryCondition'], '10Y收益率继续上行且信用利差扩大');
      expect('${item['symbol']}', startsWith('macro:'));
    },
  );

  test('Watchlist rejects fund placeholders without identity name', () async {
    final dir = await Directory.systemTemp.createTemp('finagent-watchlist-fund-validation-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = WatchlistStore()..load(dir.path);
    final tool = WatchlistTool(store: store);
    final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

    final add = await tool.call('add-invalid-fund', {
      'action': 'add',
      'symbol': '110022',
      'type': 'fund',
      'tag': 'macro',
    }, context);

    expect(add.isError, isTrue);
    expect(add.content, contains('name required for fund/etf watchlist items'));
  });
}
