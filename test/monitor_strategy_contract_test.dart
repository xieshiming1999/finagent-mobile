import 'dart:io';

import 'package:finagent/agent/data_fetcher/reusable_data_store.dart';
import 'package:finagent/agent/monitor.dart';
import 'package:finagent/agent/monitor_scheduler.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/monitor_create_tool/monitor_create_tool.dart';
import 'package:finagent/agent/tools/monitor_list_tool/monitor_list_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'MonitorList exposes strategy id and structured strategy rules',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'finagent-monitor-strategy-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = MonitorStore(memoryDir: dir.path)..load();
      store.add(
        Monitor(
          id: 'mon-strategy',
          name: 'Strategy monitor',
          script: 'return {"value": 1};',
          strategyId: 'custom_rsi_volume_rebound_v1',
          strategyRules: {
            'entry': {
              'all': [
                {'left': 'rsi5', 'op': '<', 'right': 65},
              ],
            },
          },
        ),
      );

      final result = await MonitorListTool(store: store).call(
        'list-1',
        const {},
        ToolContext(basePath: dir.path, serviceBaseUrl: ''),
      );

      expect(result.isError, isFalse);
      expect(result.content, contains('custom_rsi_volume_rebound_v1'));
      expect(result.content, contains('strategyRules'));
      expect(result.content, contains('rsi5'));
      expect(result.content, contains('monitorList:'));
      expect(result.content, contains('"contract":"monitor-list-v1"'));
      expect(
        result.content,
        contains('"strategyId":"custom_rsi_volume_rebound_v1"'),
      );
    },
  );

  test(
    'MonitorCreate folds fund monitor draft evidence into strategy rules',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'finagent-monitor-strategy-create-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = MonitorStore(memoryDir: dir.path)..load();
      final scheduler = MonitorScheduler(
        store: store,
        serviceBaseUrl: '',
        basePath: dir.path,
      );

      final result = await MonitorCreateTool(store: store, scheduler: scheduler)
          .call('create-1', {
            'name': 'Fund strategy monitor',
            'script': 'return {"value": 1};',
            'strategyId': 'fund_dca_nav_guard_v1',
            'monitorDraft': {
              'mode': 'fund_rule_monitor',
              'entryRules': [
                {'left': 'nav_trend_20', 'op': '>', 'right': 0},
              ],
            },
            'dcaObservation': {
              'mode': 'fund_observation_only',
              'cadenceDays': 30,
            },
            'user_prompt': 'fund strategy monitor',
            'description': 'Monitor validated fund strategy rules',
          }, ToolContext(basePath: dir.path, serviceBaseUrl: ''));

      expect(result.isError, isFalse);
      expect(store.monitors, hasLength(1));
      final rules = store.monitors.single.strategyRules;
      expect(rules, isNotNull);
      expect((rules!['monitorDraft'] as Map)['mode'], 'fund_rule_monitor');
      expect((rules['dcaObservation'] as Map)['mode'], 'fund_observation_only');

      final listed = await MonitorListTool(store: store).call(
        'list-1',
        const {},
        ToolContext(basePath: dir.path, serviceBaseUrl: ''),
      );
      expect(listed.content, contains('fund_rule_monitor'));
      expect(listed.content, contains('fund_observation_only'));
    },
  );

  test(
    'MonitorCreate supports strategy_signal template without raw script',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'finagent-monitor-strategy-template-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final templateDir = Directory(
        '${dir.path}/bundle/skills/monitor-templates',
      )..createSync(recursive: true);
      File('${templateDir.path}/strategy_signal.js').writeAsStringSync('''
var strategyId = '{{strategy_id}}';
var kline = callService('/api/finance/kline', {ts_code: '{{ts_code}}', limit: 120, adjust: 'qfq'});
var rows = (kline && kline.data) || [];
if (rows.length < 120) return {state:'data_missing', signal:'wait', reason:'not enough rows'};
Bridge.sendToAgent('策略信号已触发：{{name}} {{ts_code}}。请先计算可以买多少和风险，不要直接下单；需要用户确认后才允许进入雪球模拟盘或 Portfolio 写入。', {template:'strategy_signal', strategyId: strategyId, code:'{{ts_code}}', confirmationRequired:true});
return {value: rows[rows.length - 1].close, signal:'wait', state:'ok'};
''');
      final store = MonitorStore(memoryDir: dir.path)..load();
      final scheduler = MonitorScheduler(
        store: store,
        serviceBaseUrl: '',
        basePath: dir.path,
      );

      final result = await MonitorCreateTool(store: store, scheduler: scheduler)
          .call(
            'create-strategy-template',
            {
              'name': 'Strategy signal monitor',
              'template': 'strategy_signal',
              'params': {'ts_code': '600519.SH', 'name': '贵州茅台'},
              'strategyId': 'custom_20_v1',
              'strategyRules': {
                'id': 'custom_20_v1',
                'entry': {'all': []},
              },
              'user_prompt': 'strategy signal monitor',
              'description': 'Monitor saved custom strategy signal',
            },
            ToolContext(basePath: dir.path, serviceBaseUrl: ''),
          );

      expect(result.isError, isFalse);
      expect(result.content, contains('Template: strategy_signal'));
      expect(result.content, contains('data_missing'));
      expect(store.monitors.single.strategyId, 'custom_20_v1');
      expect(store.monitors.single.script, contains('Bridge.sendToAgent'));
      expect(store.monitors.single.script, contains('custom_20_v1'));
      expect(
        store.monitors.single.script,
        contains('confirmationRequired:true'),
      );
      expect(
        store.monitors.single.strategyRules,
        containsPair('id', 'custom_20_v1'),
      );
    },
  );

  test(
    'MonitorCreate supports fund_rule_monitor template with fund provenance',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'finagent-monitor-fund-rule-template-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final templateDir = Directory(
        '${dir.path}/bundle/skills/monitor-templates',
      )..createSync(recursive: true);
      File('${templateDir.path}/fund_rule_monitor.js').writeAsStringSync('''
var fundCode = '{{fund_code}}';
var strategyId = '{{strategy_id}}';
var monitorDraft = {{monitor_draft}};
var dcaObservation = {{dca_observation}};
var nav = callService('/api/finance/fund/nav', {code: '{{fund_code}}', limit: 30});
var allRows = ((nav && nav.data) || []).slice();
var minRows = 30;
var rows = allRows.slice(-minRows);
if (rows.length < 30) return {template:'fund_rule_monitor', state:'data_missing', signal:'wait', strategyId:strategyId, monitorDraft:monitorDraft, dcaObservation:dcaObservation, confirmationRequired:true};
Bridge.sendToAgent('基金观察策略已触发：{{name}} {{fund_code}}。请先复核基金净值、回撤、波动和定投边界，不要直接申购、赎回或写入模拟交易。', {template:'fund_rule_monitor', strategyId:strategyId, code:fundCode, value:rows[rows.length - 1].nav, rows:rows.length, sourceDataTime:rows[rows.length - 1].date, fetchedAt:rows[rows.length - 1].fetched_at, cacheStatus:nav.cacheStatus, monitorDraft:monitorDraft, dcaObservation:dcaObservation, confirmationRequired:true});
return {template:'fund_rule_monitor', value: rows[rows.length - 1].nav, signal:'wait', state:'ok', sourceDataTime:rows[rows.length - 1].date, fetchedAt:rows[rows.length - 1].fetched_at, cacheStatus:nav.cacheStatus};
''');
      final store = MonitorStore(memoryDir: dir.path)..load();
      final scheduler = MonitorScheduler(
        store: store,
        serviceBaseUrl: '',
        basePath: dir.path,
      );

      final result = await MonitorCreateTool(store: store, scheduler: scheduler)
          .call(
            'create-fund-rule-template',
            {
              'name': 'Fund rule monitor',
              'template': 'fund_rule_monitor',
              'params': {'name': '易方达基金'},
              'strategyId': 'fund_dca_nav_guard_v1',
              'monitorDraft': {
                'mode': 'fund_rule_monitor',
                'symbol': '110011.OF',
                'entryRules': [
                  {'left': 'nav_trend_20', 'op': '>', 'right': 0},
                ],
              },
              'dcaObservation': {'mode': 'fund_observation_only'},
              'user_prompt': 'fund observation monitor',
              'description': 'Monitor saved fund observation rules',
            },
            ToolContext(basePath: dir.path, serviceBaseUrl: ''),
          );

      expect(result.isError, isFalse);
      expect(result.content, contains('Template: fund_rule_monitor'));
      expect(store.monitors.single.strategyId, 'fund_dca_nav_guard_v1');
      expect(store.monitors.single.script, contains('110011.OF'));
      expect(store.monitors.single.script, contains('/api/finance/fund/nav'));
      expect(store.monitors.single.script, contains('allRows.slice(-minRows)'));
      expect(store.monitors.single.script, contains('fund_rule_monitor'));
      expect(store.monitors.single.script, contains('sourceDataTime'));
      expect(store.monitors.single.script, contains('fetchedAt'));
      expect(store.monitors.single.script, contains('cacheStatus'));
      expect(
        store.monitors.single.script,
        contains('confirmationRequired:true'),
      );
      expect(store.monitors.single.script, contains('不要直接申购、赎回或写入模拟交易'));
      expect(
        store.monitors.single.strategyRules,
        containsPair('monitorDraft', isA<Map>()),
      );
      expect(
        store.monitors.single.strategyRules,
        containsPair('dcaObservation', isA<Map>()),
      );
    },
  );

  test(
    'MonitorCreate supports portfolio_rebalance_monitor template with portfolio evidence',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'monitor-portfolio-rebalance-template-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final templateDir = Directory(
        '${dir.path}/bundle/skills/monitor-templates',
      )..createSync(recursive: true);
      File(
        '${templateDir.path}/portfolio_rebalance_monitor.js',
      ).writeAsStringSync('''
var strategyId = '{{strategy_id}}';
var portfolioEvidence = {{portfolio_evidence}};
var rebalanceDraft = {{rebalance_draft}};
Bridge.sendToAgent('组合策略复核触发：strategyId=' + strategyId + '。请复核 portfolioEvidence、rebalanceDraft 和再平衡边界，不要自动调仓或下单。', {template:'portfolio_rebalance_monitor', strategyId:strategyId, portfolioEvidence:portfolioEvidence, rebalanceDraft:rebalanceDraft, confirmationRequired:true});
return {template:'portfolio_rebalance_monitor', signal:'review_rebalance', selectedCount:rebalanceDraft.positions.length, rebalanceInterval:rebalanceDraft.rebalanceInterval, confirmationRequired:true};
''');
      final store = MonitorStore(memoryDir: dir.path)..load();
      final scheduler = MonitorScheduler(
        store: store,
        serviceBaseUrl: '',
        basePath: dir.path,
      );

      final result = await MonitorCreateTool(store: store, scheduler: scheduler)
          .call(
            'create-portfolio-rebalance-template',
            {
              'name': 'Portfolio rebalance review',
              'template': 'portfolio_rebalance_monitor',
              'strategyId': 'ranked_portfolio_v1',
              'interval': '1d',
              'portfolioEvidence': {
                'mode': 'equal_weight_selected_metrics',
                'selectedCount': 2,
                'portfolioBacktestEvidence': {
                  'portfolioReturnPct': 6.2,
                  'portfolioMaxDrawdownPct': -4.1,
                },
              },
              'rebalanceDraft': {
                'mode': 'equal_weight_top_n',
                'rebalanceInterval': 'monthly',
                'positions': [
                  {'symbol': '300059', 'targetWeight': 0.4},
                  {'symbol': '600519', 'targetWeight': 0.4},
                ],
              },
              'user_prompt': 'portfolio rebalance monitor',
              'description': 'Review saved portfolio ranking evidence',
            },
            ToolContext(basePath: dir.path, serviceBaseUrl: ''),
          );

      expect(result.isError, isFalse);
      expect(result.content, contains('Template: portfolio_rebalance_monitor'));
      expect(result.content, contains('Interval: 1440m'));
      expect(store.monitors.single.strategyId, 'ranked_portfolio_v1');
      expect(store.monitors.single.interval, const Duration(days: 1));
      expect(store.monitors.single.script, contains('portfolioEvidence'));
      expect(store.monitors.single.script, contains('rebalanceDraft'));
      expect(
        store.monitors.single.script,
        contains('portfolio_rebalance_monitor'),
      );
      expect(
        store.monitors.single.strategyRules,
        containsPair('portfolioEvidence', isA<Map>()),
      );
      expect(
        store.monitors.single.strategyRules,
        containsPair('rebalanceDraft', isA<Map>()),
      );
    },
  );

  test(
    'MonitorCreate rejects portfolio_rebalance_monitor without ranked portfolio evidence modes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'monitor-portfolio-rebalance-weak-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final templateDir = Directory(
        '${dir.path}/bundle/skills/monitor-templates',
      )..createSync(recursive: true);
      File(
        '${templateDir.path}/portfolio_rebalance_monitor.js',
      ).writeAsStringSync('''
var strategyId = '{{strategy_id}}';
var portfolioEvidence = {{portfolio_evidence}};
var rebalanceDraft = {{rebalance_draft}};
return {template:'portfolio_rebalance_monitor', strategyId:strategyId, selectedCount:rebalanceDraft.positions.length};
''');
      final store = MonitorStore(memoryDir: dir.path)..load();
      final scheduler = MonitorScheduler(
        store: store,
        serviceBaseUrl: '',
        basePath: dir.path,
      );

      final result = await MonitorCreateTool(store: store, scheduler: scheduler)
          .call(
            'create-weak-portfolio-rebalance-template',
            {
              'name': 'Weak portfolio rebalance review',
              'template': 'portfolio_rebalance_monitor',
              'strategyId': 'ranked_portfolio_v1',
              'portfolioEvidence': {
                'selectedCount': 2,
                'tradeBoundary': 'review_only',
              },
              'rebalanceDraft': {
                'rebalanceInterval': 'monthly',
                'positions': [
                  {'symbol': '300059', 'targetWeight': 0.4},
                  {'symbol': '600519', 'targetWeight': 0.4},
                ],
              },
              'user_prompt': 'portfolio rebalance monitor',
              'description': 'Weak evidence should be rejected',
            },
            ToolContext(basePath: dir.path, serviceBaseUrl: ''),
          );

      expect(result.isError, isTrue);
      expect(result.content, contains('custom_strategy_list/read'));
      expect(result.content, contains('custom_strategy_rank'));
      expect(store.monitors, isEmpty);
    },
  );

  test('MonitorScheduler reads fund NAV with .OF code variants', () async {
    final dir = await Directory.systemTemp.createTemp(
      'finagent-monitor-fund-nav-code-variant-',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final storeData = ReusableDataStore(dir.path);
    storeData.saveFundNav([
      for (var i = 0; i < 30; i++)
        {
          'code': '161725.OF',
          'date': '2026-06-${(i + 1).toString().padLeft(2, '0')}',
          'nav': 1.0 + i / 100,
          'source': 'fixture',
        },
    ]);

    final store = MonitorStore(memoryDir: dir.path)..load();
    final scheduler = MonitorScheduler(
      store: store,
      serviceBaseUrl: '',
      basePath: dir.path,
    );
    final monitor = Monitor(
      id: 'fund-nav-variant',
      name: 'Fund NAV variant monitor',
      script: '''
var nav = callService('/api/finance/fund/nav', {code: '161725', limit: 30});
var rows = (nav && nav.data) || [];
return {state: rows.length >= 30 ? 'ok' : 'data_missing', count: rows.length, lastCode: rows.length ? rows[rows.length - 1].code : null, lastNav: rows.length ? rows[rows.length - 1].nav : null, cacheStatus: nav.cacheStatus};
''',
    );

    final result = await scheduler.executeOnce(monitor);

    expect(result['state'], 'ok');
    expect(result['count'], 30);
    expect(result['lastCode'], '161725.OF');
    expect(result['cacheStatus'], 'cache-hit');
  });

  test(
    'MonitorScheduler forwards strategy signal preflight to agent',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'finagent-monitor-strategy-agent-message-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = MonitorStore(memoryDir: dir.path)..load();
      final scheduler = MonitorScheduler(
        store: store,
        serviceBaseUrl: '',
        basePath: dir.path,
      );
      final messages = <Map<String, dynamic>>[];
      scheduler.onAgentMessage = (monitorName, message, data) {
        messages.add({
          'monitorName': monitorName,
          'message': message,
          'data': data,
        });
      };
      final monitor = Monitor(
        id: 'm-agent-message',
        name: 'Strategy signal monitor',
        script: '''
Bridge.sendToAgent('策略信号已触发：贵州茅台 600519。请先计算可以买多少和风险，不要直接下单；需要用户确认后才允许进入雪球模拟盘或 Portfolio 写入。', {
  template: 'strategy_signal',
  strategyId: 'custom_20_v1',
  code: '600519',
  price: 1200,
  confirmationRequired: true,
  tradeBoundary: 'No Portfolio or XueqiuTrade action before explicit user confirmation.'
});
return {signal:'entry', value:1200};
''',
      );

      final result = await scheduler.executeOnce(monitor);

      expect(result, containsPair('signal', 'entry'));
      expect(messages, hasLength(1));
      expect(messages.single['monitorName'], 'Strategy signal monitor');
      expect(messages.single['message'] as String, contains('请先计算可以买多少和风险'));
      expect(
        messages.single['data'],
        containsPair('strategyId', 'custom_20_v1'),
      );
      expect(
        messages.single['data'],
        containsPair('confirmationRequired', true),
      );
    },
  );
}
