import 'dart:async';
import 'dart:io';

import 'package:finagent/agent/data_fetcher/data_manager.dart';
import 'package:finagent/agent/data_fetcher/models.dart';
import 'package:finagent/agent/llm_client.dart';
import 'package:finagent/agent/message.dart';
import 'package:finagent/agent/tool.dart';
import 'package:finagent/agent/workflow_automation_control.dart';
import 'package:finagent/features/finance/finagent_screen.dart';
import 'package:finagent/shared/agent_factory.dart';
import 'package:finagent/shared/feature_prompts.dart';
import 'package:finagent/shared/i18n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync(
      'finagent_p0_user_workflow_app_started_test_',
    );
    _installPathProviderMock(() => tmpDir.path);
    Directory('${tmpDir.path}/memory/pages').createSync(recursive: true);
    Directory('${tmpDir.path}/bundle').createSync(recursive: true);
    Directory('${tmpDir.path}/sessions').createSync(recursive: true);
    _seedReusableFinanceData(tmpDir.path);
  });

  tearDown(() {
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  testWidgets('started FinAgent screen runs mobile P0 user workflow batch', (
    tester,
  ) async {
    WebViewPlatform.instance = _FakeWebViewPlatform();
    final runtime = createAgentRuntime(
      basePath: tmpDir.path,
      serverUrl: '',
      featurePrompt: finagentPromptForLocale(const Locale('zh')),
      featureId: 'finance',
      skipPermissions: true,
      batchDrainQueue: true,
      enableWatchlistRefresher: false,
      llmClient: _MockLLMClient([
        ..._MockLLMResponse.toolThenText(
          id: 'mobile-p0-market-query-index',
          name: 'MarketData',
          arguments: {
            'action': 'query_quote',
            'symbols': ['000001'],
            'limit': 1,
          },
          text:
              '今天市场先复用本地 stock.quote 证据：上证指数有 source time 和 fetched time，本次不把缺失板块数据包装成确定结论。',
        ),
        ..._MockLLMResponse.toolCallsThenText(
          [
            _ToolCallSpec(
              id: 'mobile-p0-market-sector-ranking',
              name: 'MarketData',
              arguments: {
                'action': 'query_sector_ranking',
                'boardType': 'industry',
                'date': '2026-06-26',
                'limit': 3,
              },
            ),
            _ToolCallSpec(
              id: 'mobile-p0-market-flow-rank',
              name: 'MarketData',
              arguments: {
                'action': 'query_flow_rank',
                'period': 'today',
                'date': '2026-06-26',
                'limit': 3,
              },
            ),
          ],
          text:
              '热门方向基于本地 market.sector_ranking 和 market.flow_rank：半导体强于样本均值，贵州茅台资金流入；结论限定为缓存样本，不扩大成全市场判断。',
        ),
        ..._MockLLMResponse.toolCallsThenText(
          [
            _ToolCallSpec(
              id: 'mobile-p0-stock-query-quote',
              name: 'MarketData',
              arguments: {
                'action': 'query_quote',
                'symbols': ['600519'],
                'limit': 1,
              },
            ),
            _ToolCallSpec(
              id: 'mobile-p0-stock-indicators',
              name: 'DataProcess',
              arguments: {
                'action': 'indicators',
                'symbol': '600519',
                'period': 'daily',
                'startDate': '2026-03-01',
              },
            ),
          ],
          text:
              '茅台分析已基于本地 quote_snapshot 和 technical.indicator_series；结论只覆盖价格、K线和技术指标，基本面缺口单独披露。',
        ),
        ..._MockLLMResponse.toolCallsThenText(
          [
            _ToolCallSpec(
              id: 'mobile-p0-wuliangye-query-quote',
              name: 'MarketData',
              arguments: {
                'action': 'query_quote',
                'symbols': ['000858'],
                'limit': 1,
              },
            ),
            _ToolCallSpec(
              id: 'mobile-p0-wuliangye-query-kline',
              name: 'MarketData',
              arguments: {
                'action': 'query_kline',
                'symbols': ['000858'],
                'startDate': '2026-03-01',
                'limit': 5,
              },
            ),
            _ToolCallSpec(
              id: 'mobile-p0-wuliangye-fundamental',
              name: 'MarketData',
              arguments: {
                'action': 'query_fundamental',
                'symbols': ['000858'],
                'limit': 3,
              },
            ),
            _ToolCallSpec(
              id: 'mobile-p0-wuliangye-money-flow',
              name: 'MarketData',
              arguments: {
                'action': 'query_money_flow',
                'symbols': ['000858'],
                'limit': 3,
              },
            ),
          ],
          text:
              '五粮液深度分析复用了 stock.quote、stock.daily_kline、stock.daily_valuation 和 stock.money_flow；资金流为负，估值和基本面只按本地样本披露。',
        ),
        ..._MockLLMResponse.toolThenText(
          id: 'mobile-p0-selection-screen',
          name: 'DataProcess',
          arguments: {
            'action': 'screen',
            'codes': ['600519', '000001'],
            'conditions': [
              {'field': 'pe', 'op': '<', 'value': 20},
            ],
            'limit': 2,
          },
          text: '候选筛选只在已给定代码池内完成，未声称全市场覆盖；结果带有筛选口径和数据覆盖限制。',
        ),
        ..._MockLLMResponse.toolCallsThenText(
          [
            _ToolCallSpec(
              id: 'mobile-p0-selection-valuation',
              name: 'MarketData',
              arguments: {
                'action': 'query_fundamental',
                'symbols': ['600519', '000858'],
                'limit': 5,
              },
            ),
            _ToolCallSpec(
              id: 'mobile-p0-selection-pe-roe-screen',
              name: 'DataProcess',
              arguments: {
                'action': 'screen',
                'codes': ['600519', '000858'],
                'conditions': [
                  {'field': 'pe', 'op': '<', 'value': 20},
                  {'field': 'roe', 'op': '>', 'value': 15},
                ],
                'limit': 5,
              },
            ),
          ],
          text:
              'PE<20 ROE>15 仅在已缓存估值样本内筛选；DataProcess 返回 0 个匹配，不能下全市场结论，需补齐移动端筛选字段映射后再扩展。',
        ),
        ..._MockLLMResponse.toolThenText(
          id: 'mobile-p0-fund-nav',
          name: 'MarketData',
          arguments: {
            'action': 'query_fund_nav',
            'symbols': ['110011.OF'],
            'startDate': '2026-06-24',
            'limit': 1,
          },
          text: '基金判断复用本地 fund.nav_history；普通基金净值路径和货币基金收益路径保持区分。',
        ),
        ..._MockLLMResponse.toolCallsThenText(
          [
            _ToolCallSpec(
              id: 'mobile-p0-fund-list',
              name: 'MarketData',
              arguments: {'action': 'query_fund_list', 'limit': 5},
            ),
            _ToolCallSpec(
              id: 'mobile-p0-fund-holding',
              name: 'MarketData',
              arguments: {
                'action': 'query_fund_holding',
                'fundCode': '110011.OF',
                'reportDate': '2026-03-31',
                'limit': 3,
              },
            ),
            _ToolCallSpec(
              id: 'mobile-p0-fund-performance',
              name: 'MarketData',
              arguments: {
                'action': 'query_fund_performance',
                'symbols': ['110011.OF'],
                'limit': 3,
              },
            ),
          ],
          text:
              '基金选择基于 fund.identity_list、fund.holding 和 fund.performance_metrics；持仓集中度和回撤是风险，非买入建议。',
        ),
        ..._MockLLMResponse.toolCallsThenText([
          _ToolCallSpec(
            id: 'mobile-p0-quant-rsi-backtest',
            name: 'MarketData',
            arguments: {
              'action': 'backtest',
              'symbols': ['600519'],
              'strategy': 'rsi',
              'period': '1y',
            },
          ),
          _ToolCallSpec(
            id: 'mobile-p0-quant-kline-window',
            name: 'MarketData',
            arguments: {
              'action': 'query_kline',
              'symbols': ['600519'],
              'startDate': '2026-03-01',
              'limit': 5,
            },
          ),
        ], text: 'RSI 回测已用本地 K 线窗口执行并读取样本窗口；这不是收益承诺，仍需说明窗口、滑点和过拟合限制。'),
        ..._MockLLMResponse.toolCallsThenText([
          _ToolCallSpec(
            id: 'mobile-p0-quant-rsi-compare',
            name: 'MarketData',
            arguments: {
              'action': 'backtest',
              'symbols': ['600519'],
              'strategy': 'rsi',
              'period': '1y',
            },
          ),
          _ToolCallSpec(
            id: 'mobile-p0-quant-macd-compare',
            name: 'MarketData',
            arguments: {
              'action': 'backtest',
              'symbols': ['600519'],
              'strategy': 'macd',
              'period': '1y',
            },
          ),
        ], text: '策略比较只比较 RSI 和 MACD 的本地回测结果；如果交易次数不足，应拒绝给“最好策略”的确定结论。'),
        ..._MockLLMResponse.toolCallsThenText(
          [
            _ToolCallSpec(
              id: 'mobile-p0-buy-decision-quote',
              name: 'MarketData',
              arguments: {
                'action': 'query_quote',
                'symbols': ['600519'],
                'limit': 1,
              },
            ),
            _ToolCallSpec(
              id: 'mobile-p0-buy-decision-indicators',
              name: 'DataProcess',
              arguments: {
                'action': 'indicators',
                'symbol': '600519',
                'period': 'daily',
                'startDate': '2026-03-01',
              },
            ),
          ],
          text:
              '现在是否可以买只能给条件化决策：等待放量确认、控制仓位、设置止损；本轮没有调用 Watchlist、Portfolio、XueqiuTrade 或真实交易工具。',
        ),
        ..._MockLLMResponse.toolCallsThenText(
          [
            _ToolCallSpec(
              id: 'mobile-p0-decision-quote',
              name: 'MarketData',
              arguments: {
                'action': 'query_quote',
                'symbols': ['600519'],
                'limit': 1,
              },
            ),
            _ToolCallSpec(
              id: 'mobile-p0-decision-watchlist-add',
              name: 'Watchlist',
              arguments: {
                'action': 'add',
                'symbol': '600519',
                'name': '贵州茅台',
                'type': 'stock',
                'entryCondition': '等待放量站回 20 日均线再评估',
                'stopLoss': 1130,
                'source': 'mobile-p0-workflow',
              },
            ),
            _ToolCallSpec(
              id: 'mobile-p0-decision-watchlist-list',
              name: 'Watchlist',
              arguments: {'action': 'list', 'symbol': '600519'},
            ),
          ],
          text:
              '已按用户“加入观察池”意图执行 Watchlist 写入并回读；未触发 Portfolio、XueqiuTrade 或真实券商动作。',
        ),
        ..._MockLLMResponse.toolCallsThenText([
          _ToolCallSpec(
            id: 'mobile-p0-monitor-cron-create',
            name: 'CronCreate',
            arguments: {
              'schedule': '0 9 * * 1-5',
              'prompt': '每天开盘前分析自选股并说明数据来源、缺口和风险。',
              'recurring': true,
              'durable': true,
            },
          ),
          _ToolCallSpec(
            id: 'mobile-p0-monitor-cron-list',
            name: 'CronList',
            arguments: {},
          ),
        ], text: '已创建并回读移动端 durable Cron 自选股分析任务；这是监控/学习计划，不会自动交易。'),
        ..._MockLLMResponse.toolCallsThenText([
          _ToolCallSpec(
            id: 'mobile-p0-monitor-create',
            name: 'MonitorCreate',
            arguments: {
              'name': '茅台 RSI 观察',
              'script':
                  'return { text: "RSI monitor seeded from backtest evidence", value: 1 };',
              'interval': '5m',
              'display': 'text',
              'user_prompt': '回测结果不错，帮我设置监控',
              'description': '根据 RSI 回测证据创建移动端观察监控',
            },
          ),
          _ToolCallSpec(
            id: 'mobile-p0-monitor-list',
            name: 'MonitorList',
            arguments: {},
          ),
        ], text: '已创建并回读茅台 RSI 观察监控；监控只提示风险状态，不自动交易。'),
      ]),
    );
    addTearDown(() {
      runtime.agent.stopAutoProcessing();
      runtime.monitorScheduler.stop();
      runtime.cronScheduler.stop();
    });

    final bridgeCompleter = Completer<WorkflowAutomationInProcessBridge>();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: FinAgentScreen(
          agent: runtime.agent,
          uiQueryTool: runtime.uiQueryTool,
          uiControlTool: runtime.uiControlTool,
          askUserQuestionTool: runtime.askUserQuestionTool,
          webViewTool: runtime.webViewTool,
          environmentTool: runtime.environmentTool,
          dataTaskEngine: runtime.dataTaskEngine,
          monitorStore: runtime.monitorStore,
          watchlistStore: runtime.watchlistStore,
          monitorScheduler: runtime.monitorScheduler,
          notificationStore: runtime.notificationStore,
          workflowAutomationEnabledOverride: true,
          onWorkflowAutomationBridgeCreated: (bridge) {
            if (!bridgeCompleter.isCompleted) {
              bridgeCompleter.complete(bridge);
            }
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final bridge = await bridgeCompleter.future;
    final health = await tester.runAsync(bridge.health);
    expect(health?['transport'], 'in-process-bridge');
    expect(health?['providerEndpointBypass'], isFalse);

    final market = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-mkt-001-market-understanding',
      prompt: '今天市场怎么样？请先复用本地证据并说明数据时间。',
      expectTools: ['MarketData'],
      expectToolResultContains: [
        '"action": "query_quote"',
        '"interfaceId": "index.quote"',
        '"canonicalTable": "quote_snapshot"',
        '"cacheStatus": "cache-hit"',
        '000001',
      ],
      expectFinalContains: ['source time', 'fetched time', '缺失板块数据'],
    );
    expect(market['ok'], isTrue, reason: '${market['assertions']}');

    final hotSector = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-mkt-002-hot-sector',
      prompt: '最近什么板块热门？请复用板块和资金流本地证据。',
      expectTools: ['MarketData'],
      expectToolResultContains: [
        '"interfaceId": "market.sector_ranking"',
        '"interfaceId": "market.flow_rank"',
        '"canonicalTable": "sector_rank"',
        '"canonicalTable": "flow_rank"',
        '半导体',
      ],
      expectFinalContains: [
        'market.sector_ranking',
        'market.flow_rank',
        '缓存样本',
      ],
    );
    expect(hotSector['ok'], isTrue, reason: '${hotSector['assertions']}');

    final stock = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-stk-001-stock-research',
      prompt: '帮我看看茅台，给出证据和数据缺口。',
      expectTools: ['MarketData', 'DataProcess'],
      expectToolResultContains: [
        '"interfaceId": "stock.quote"',
        '"interfaceId": "technical.indicator_series"',
        '"canonicalTable": "technical_indicator_series"',
      ],
      expectFinalContains: ['technical.indicator_series', '基本面缺口'],
    );
    expect(stock['ok'], isTrue, reason: '${stock['assertions']}');

    final deepStock = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-stk-002-wuliangye-deep-research',
      prompt: '深度分析五粮液，包含行情、K线、估值和资金流。',
      expectTools: ['MarketData'],
      expectToolResultContains: [
        '"interfaceId": "stock.quote"',
        '"interfaceId": "stock.daily_kline"',
        '"interfaceId": "stock.daily_valuation"',
        '"interfaceId": "stock.money_flow"',
        '000858',
      ],
      expectFinalContains: [
        'stock.daily_valuation',
        'stock.money_flow',
        '本地样本',
      ],
    );
    expect(deepStock['ok'], isTrue, reason: '${deepStock['assertions']}');

    final selection = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-sel-001-stock-selection',
      prompt: '有什么好股票？先用小候选池筛选并说明覆盖范围。',
      expectTools: ['DataProcess'],
      expectToolResultContains: ['Screened 1 from 2 stocks', '600519'],
      expectFinalContains: ['筛选口径', '未声称全市场覆盖'],
    );
    expect(selection['ok'], isTrue, reason: '${selection['assertions']}');

    final peRoeSelection = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-sel-002-pe-roe-screen',
      prompt: '全市场筛选 PE<20 ROE>15；如果只是样本筛选必须说明。',
      expectTools: ['MarketData', 'DataProcess'],
      expectToolResultContains: [
        '"interfaceId": "stock.daily_valuation"',
        'No stocks match the given conditions',
      ],
      expectFinalContains: ['PE<20 ROE>15', '0 个匹配', '不能下全市场结论'],
    );
    expect(
      peRoeSelection['ok'],
      isTrue,
      reason: '${peRoeSelection['assertions']}',
    );

    final fund = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-fnd-001-fund-research',
      prompt: '这个基金适合长期持有吗？先复用净值数据。',
      expectTools: ['MarketData'],
      expectToolResultContains: [
        '"action": "query_fund_nav"',
        '"interfaceId": "fund.nav_history"',
        '"canonicalTable": "fund_nav"',
        '"cacheStatus": "cache-hit"',
        '110011.OF',
      ],
      expectFinalContains: ['fund.nav_history', '货币基金收益路径'],
    );
    expect(fund['ok'], isTrue, reason: '${fund['assertions']}');

    final fundSelection = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-fnd-001-002-fund-selection-depth',
      prompt: '帮我选基金，并说明这个基金适不适合长期持有。',
      expectTools: ['MarketData'],
      expectToolResultContains: [
        '"interfaceId": "fund.identity_list"',
        '"interfaceId": "fund.holding"',
        '"interfaceId": "fund.performance_metrics"',
        '110011.OF',
      ],
      expectFinalContains: [
        'fund.identity_list',
        'fund.performance_metrics',
        '非买入建议',
      ],
    );
    expect(
      fundSelection['ok'],
      isTrue,
      reason: '${fundSelection['assertions']}',
    );

    final quant = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-qnt-001-rsi-backtest',
      prompt: '回测 RSI 策略在茅台上最近 1 年表现。',
      expectTools: ['MarketData'],
      expectToolResultContains: [
        '"action": "backtest"',
        '"strategy": "rsi"',
        '"action": "query_kline"',
        '"canonicalTable": "kline_daily"',
      ],
      expectFinalContains: ['RSI 回测', '过拟合限制'],
    );
    expect(quant['ok'], isTrue, reason: '${quant['assertions']}');

    final quantCompare = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-qnt-002-strategy-compare',
      prompt: '茅台用什么策略最好？只比较支持的本地回测策略。',
      expectTools: ['MarketData'],
      expectToolResultContains: ['"strategy": "rsi"', '"strategy": "macd"'],
      expectFinalContains: ['RSI', 'MACD', '拒绝给“最好策略”的确定结论'],
    );
    expect(quantCompare['ok'], isTrue, reason: '${quantCompare['assertions']}');

    final noMutationDecision = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-dec-001-buy-decision-no-mutation',
      prompt: '现在可以买吗？只给条件化决策，不要加入观察池或交易。',
      expectTools: ['MarketData', 'DataProcess'],
      expectToolResultContains: [
        '"interfaceId": "stock.quote"',
        '"interfaceId": "technical.indicator_series"',
      ],
      expectFinalContains: ['条件化决策', '没有调用 Watchlist'],
    );
    expect(
      noMutationDecision['ok'],
      isTrue,
      reason: '${noMutationDecision['assertions']}',
    );

    final decision = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-dec-004-watchlist-observation',
      prompt: '把茅台加入观察池，但不要交易。',
      expectTools: ['MarketData', 'Watchlist'],
      expectToolResultContains: ['Added 贵州茅台', '"symbol": "600519"'],
      expectFinalContains: ['Watchlist', '未触发 Portfolio'],
    );
    expect(decision['ok'], isTrue, reason: '${decision['assertions']}');

    final monitoring = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-mon-001-cron-monitoring',
      prompt: '每天分析自选股，创建后回读确认。',
      expectTools: ['CronCreate', 'CronList'],
      expectToolResultContains: ['"durable":true', '"jobs":'],
      expectFinalContains: ['durable Cron', '不会自动交易'],
    );
    expect(monitoring['ok'], isTrue, reason: '${monitoring['assertions']}');

    final monitorCreate = await _runScenario(
      tester,
      bridge,
      id: 'mobile-p0-mon-002-monitor-create-readback',
      prompt: '回测结果不错，帮我设置监控并回读确认。',
      expectTools: ['MonitorCreate', 'MonitorList'],
      expectToolResultContains: ['Monitor "茅台 RSI 观察" created', '茅台 RSI 观察'],
      expectFinalContains: ['创建并回读', '不自动交易'],
    );
    expect(
      monitorCreate['ok'],
      isTrue,
      reason: '${monitorCreate['assertions']}',
    );

    final panels = await tester.runAsync(bridge.panels);
    expect(panels?['uiEvidence']['semanticsAvailable'], isTrue);
    expect(
      (panels?['uiArtifacts'] as List<dynamic>).any(
        (artifact) => artifact['kind'] == 'mobile-semantic-snapshot',
      ),
      isTrue,
    );
    expect(runtime.watchlistStore.items.any((i) => i.symbol == '600519'), true);
    expect(runtime.cronScheduler.listTasks().any((t) => t.durable), true);

    final reports = await tester.runAsync(() => bridge.reports(limit: 20));
    final summaries = (reports?['reports'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .where((report) => '${report['scenarioId']}'.startsWith('mobile-p0-'))
        .toList();
    expect(summaries.length, greaterThanOrEqualTo(10));
    for (final summary in summaries) {
      expect(summary['kind'], 'scenario');
      expect(summary['assertionFailCount'], 0);
      expect(summary['failedAssertions'], isEmpty);
      expect(summary['uiArtifactCount'], greaterThanOrEqualTo(1));
      expect(summary['uiEvidence']['semanticsAvailable'], isTrue);
    }

    runtime.agent.stopAutoProcessing();
    runtime.cronScheduler.stop();
    runtime.monitorScheduler.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

void _installPathProviderMock(String Function() path) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getApplicationSupportDirectory':
        case 'getTemporaryDirectory':
          return path();
        default:
          return null;
      }
    },
  );
}

Future<Map<String, dynamic>> _runScenario(
  WidgetTester tester,
  WorkflowAutomationInProcessBridge bridge, {
  required String id,
  required String prompt,
  required List<String> expectTools,
  required List<String> expectToolResultContains,
  required List<String> expectFinalContains,
}) async {
  final result = await tester.runAsync(
    () => bridge.scenario(
      id: id,
      prompt: prompt,
      expectTools: expectTools,
      expectToolResultContains: expectToolResultContains,
      expectFinalContains: expectFinalContains,
      expectUiStateKeys: ['runtime', 'sessionId', 'messages'],
      expectUiArtifactKinds: ['mobile-semantic-snapshot'],
    ),
  );
  expect(result, isNotNull);
  expect(File(result?['scenarioReportPath'] as String).existsSync(), isTrue);
  return result!;
}

void _seedReusableFinanceData(String basePath) {
  final dataManager = DataManager(basePath: basePath);
  final now = DateTime.now().toUtc().toIso8601String();
  dataManager.saveQuoteSnapshots([
    StockQuote(
      code: '000001',
      timestamp: now,
      fetchedAt: now,
      name: '上证指数',
      price: 3025.18,
      change: -8.21,
      changePct: -0.27,
      open: 3030,
      high: 3042,
      low: 3018,
      prevClose: 3033.39,
      volume: 10000000,
      amount: 260000000000,
      source: 'tdx',
    ),
    StockQuote(
      code: '600519',
      timestamp: now,
      fetchedAt: now,
      name: '贵州茅台',
      price: 1215,
      change: 14.75,
      changePct: 1.23,
      open: 1200,
      high: 1220,
      low: 1198,
      prevClose: 1200.25,
      volume: 1000,
      amount: 1215000,
      pe: 13.4,
      pb: 6.2,
      source: 'tdx',
    ),
    StockQuote(
      code: '000858',
      timestamp: now,
      fetchedAt: now,
      name: '五粮液',
      price: 128.6,
      change: -1.2,
      changePct: -0.92,
      open: 130,
      high: 131.2,
      low: 127.8,
      prevClose: 129.8,
      volume: 220000,
      amount: 28292000,
      pe: 8.9,
      pb: 2.3,
      source: 'tdx',
    ),
  ], source: 'tdx');
  dataManager.saveKlineRows(
    '600519',
    _buildBars(),
    source: 'tdx',
    adjust: 'qfq',
  );
  dataManager.saveKlineRows(
    '000858',
    _buildBars(base: 112, step: 0.08),
    source: 'tdx',
    adjust: 'qfq',
  );
  dataManager.saveSectorRanking(
    'industry',
    [
      {
        'code': 'BK1036',
        'name': '半导体',
        'changePct': 3.2,
        'upCount': 28,
        'downCount': 4,
      },
      {
        'code': 'BK0475',
        'name': '白酒',
        'changePct': 1.1,
        'upCount': 12,
        'downCount': 6,
      },
    ],
    source: 'eastmoney',
    tradeDate: '2026-06-26',
  );
  dataManager.saveFlowRank(
    'today',
    [
      {
        'code': '600519',
        'name': '贵州茅台',
        'f62': 123456789,
        'f184': 3.21,
        'f66': 67456789,
        'f72': 45000000,
        'f78': 23000000,
      },
      {
        'code': '000858',
        'name': '五粮液',
        'f62': -24000000,
        'f184': -0.83,
        'f66': -12000000,
        'f72': -8000000,
        'f78': -4000000,
      },
    ],
    source: 'eastmoney',
    tradeDate: '2026-06-26',
  );
  dataManager.saveFundamentalRows([
    {
      'code': '600519',
      'report_date': '2025-12-31',
      'source': 'eastmoney',
      'pe_ttm': 13.4,
      'pb': 6.2,
      'roe': 31.5,
      'revenue_yoy': 12.3,
      'profit_yoy': 14.1,
      'fetched_at': '2026-06-26T09:36:00.000Z',
    },
    {
      'code': '000858',
      'report_date': '2025-12-31',
      'source': 'eastmoney',
      'pe_ttm': 8.9,
      'pb': 2.3,
      'roe': 22.4,
      'revenue_yoy': 7.2,
      'profit_yoy': 8.4,
      'fetched_at': '2026-06-26T09:36:00.000Z',
    },
  ], source: 'eastmoney');
  dataManager.saveMoneyFlowRows('000858', [
    MoneyFlow(
      date: '2026-06-26',
      mainNetInflow: -24000000,
      smallNetInflow: 3000000,
      mediumNetInflow: -5000000,
      largeNetInflow: -10000000,
      superLargeNetInflow: -12000000,
      closePrice: 128.6,
      changePct: -0.92,
    ),
  ], source: 'eastmoney');
  dataManager.saveFundList([
    {
      'code': '110011.OF',
      'name': '易方达中小盘混合',
      'fund_type': '混合型',
      'manager': '张坤',
      'source': 'eastmoney',
      'fetched_at': '2026-06-24T15:05:00.000Z',
    },
  ], source: 'eastmoney');
  dataManager.saveFundNav([
    {
      'code': '110011.OF',
      'date': '2026-06-24',
      'nav': 1.234,
      'accum_nav': 2.345,
      'daily_return': 0.42,
      'source': 'eastmoney',
      'fetched_at': '2026-06-24T15:05:00.000Z',
    },
  ], source: 'eastmoney');
  dataManager.saveFundHolding([
    {
      'fund_code': '110011.OF',
      'report_date': '2026-03-31',
      'stock_code': '600519',
      'stock_name': '贵州茅台',
      'hold_shares': 1200,
      'hold_value': 1458000,
      'hold_pct': 8.91,
      'rank': 1,
      'source': 'eastmoney',
      'fetched_at': '2026-06-24T15:05:00.000Z',
    },
  ], source: 'eastmoney');
  dataManager.saveFundPerformanceMetrics([
    {
      'code': '110011.OF',
      'period': '1y',
      'return': 8.2,
      'max_drawdown': -12.4,
      'volatility': 18.3,
      'sharpe': 0.62,
      'source': 'eastmoney',
      'fetched_at': '2026-06-24T15:05:00.000Z',
    },
  ], source: 'eastmoney');
}

List<KlineBar> _buildBars({double base = 1100, double step = 1.5}) {
  return List<KlineBar>.generate(420, (index) {
    final close = base + index * step;
    final date = DateTime(2025, 5, 1).add(Duration(days: index));
    return KlineBar(
      date:
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      open: close - 2,
      high: close + 5,
      low: close - 4,
      close: close,
      volume: 100000 + index * 1000,
      amount: close * (100000 + index * 1000),
    );
  });
}

class _ToolCallSpec {
  const _ToolCallSpec({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class _FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _FakePlatformWebViewController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _FakePlatformNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakePlatformWebViewWidget(params);

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => _FakePlatformCookieManager(params);
}

class _FakePlatformWebViewController extends PlatformWebViewController {
  _FakePlatformWebViewController(super.params) : super.implementation();

  @override
  Future<void> loadFile(String absoluteFilePath) async {}

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<String?> currentUrl() async => 'about:blank';

  @override
  Future<String?> getTitle() async => 'test';

  @override
  Future<bool> canGoBack() async => false;

  @override
  Future<bool> canGoForward() async => false;

  @override
  Future<void> goBack() async {}

  @override
  Future<void> goForward() async {}

  @override
  Future<void> reload() async {}

  @override
  Future<void> clearCache() async {}

  @override
  Future<void> clearLocalStorage() async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> runJavaScript(String javaScript) async {}

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async => '';

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {}

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {}

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> enableZoom(bool enabled) async {}
}

class _FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  _FakePlatformNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}
}

class _FakePlatformWebViewWidget extends PlatformWebViewWidget {
  _FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _FakePlatformCookieManager extends PlatformWebViewCookieManager {
  _FakePlatformCookieManager(super.params) : super.implementation();
}

class _MockLLMResponse {
  _MockLLMResponse(this.events);

  final List<SSEEvent> events;

  factory _MockLLMResponse.text(String text) => _MockLLMResponse([
    SSETextDelta(text),
    SSEUsage(promptTokens: 500, completionTokens: 50),
    SSEDone(finishReason: 'stop'),
  ]);

  factory _MockLLMResponse.toolCall({
    required String id,
    required String name,
    required Map<String, dynamic> arguments,
  }) => _MockLLMResponse([
    SSEToolCall(id: id, name: name, arguments: arguments),
    SSEUsage(promptTokens: 500, completionTokens: 100),
    SSEDone(finishReason: 'tool_calls'),
  ]);

  static List<_MockLLMResponse> toolThenText({
    required String id,
    required String name,
    required Map<String, dynamic> arguments,
    required String text,
  }) => [
    _MockLLMResponse.toolCall(id: id, name: name, arguments: arguments),
    _MockLLMResponse.text(text),
  ];

  static List<_MockLLMResponse> toolCallsThenText(
    List<_ToolCallSpec> calls, {
    required String text,
  }) => [
    for (final call in calls)
      _MockLLMResponse.toolCall(
        id: call.id,
        name: call.name,
        arguments: call.arguments,
      ),
    _MockLLMResponse.text(text),
  ];
}

class _MockLLMClient extends LLMClient {
  _MockLLMClient(this.script) : super(baseUrl: 'mock://localhost');

  final List<_MockLLMResponse> script;
  int _callIndex = 0;

  @override
  LLMClient clone() => _MockLLMClient(script);

  @override
  Stream<SSEEvent> sendMessage({
    required List<Message> messages,
    required List<Tool> tools,
    String? systemPrompt,
    int? maxOutputTokens,
    String? model,
  }) {
    final response = _callIndex < script.length
        ? script[_callIndex]
        : _MockLLMResponse([SSEDone(finishReason: 'stop')]);
    _callIndex++;

    final controller = StreamController<SSEEvent>();
    Future.microtask(() async {
      for (final event in response.events) {
        controller.add(event);
      }
      await controller.close();
    });
    return controller.stream;
  }

  @override
  void cancel() {}
}
