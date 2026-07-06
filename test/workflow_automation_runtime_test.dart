import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/agent.dart';
import 'package:finagent/agent/llm_client.dart';
import 'package:finagent/agent/message.dart';
import 'package:finagent/agent/prompt_builder.dart';
import 'package:finagent/agent/session.dart';
import 'package:finagent/agent/tool.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/data_fetcher/data_manager.dart';
import 'package:finagent/agent/tools/market_data_tool/market_data_tool.dart';
import 'package:finagent/agent/tools/portfolio_tool/portfolio_tool.dart';
import 'package:finagent/agent/tools/ui_control_tool/ui_control_tool.dart';
import 'package:finagent/agent/tools/webview_tool/webview_tool.dart';
import 'package:finagent/agent/workflow_automation_control.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync(
      'finagent_workflow_automation_runtime_test_',
    );
    Directory('${tmpDir.path}/memory/pages').createSync(recursive: true);
    Directory('${tmpDir.path}/bundle').createSync(recursive: true);
    Directory('${tmpDir.path}/sessions').createSync(recursive: true);
  });

  tearDown(() {
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  test(
    'in-process bridge drives agent UIControl page workflow with report evidence',
    () async {
      final pageFile = File('${tmpDir.path}/memory/pages/workflow.html')
        ..writeAsStringSync(
          '<!doctype html><html><body><h1>FinAgent Workflow Page</h1></body></html>',
        );
      final uiState = <String, dynamic>{
        'runtime': 'finagent',
        'activePanel': 'chat',
        'dashboardReady': false,
        'activeDashboard': null,
      };
      final uiControlTool = UIControlTool()
        ..handler = (action, params) async {
          if (action != 'openPage' && action != 'fin:openPage') {
            return jsonEncode({'ok': false, 'action': action});
          }
          final file = params['file'] ?? params['path'];
          final path = file is String && file.startsWith('/')
              ? file
              : '${tmpDir.path}/$file';
          final exists = File(path).existsSync();
          uiState['activePanel'] = 'dashboard';
          uiState['dashboardReady'] = exists;
          uiState['activeDashboard'] = {
            'title': params['title'] ?? 'FinAgent Workflow Page',
            'filePath': path,
          };
          return jsonEncode({
            'ok': exists,
            'action': 'openPage',
            'observed': exists,
            'fileExists': exists,
            'filePath': path,
          });
        };
      final agent = _makeAgent(
        tmpDir.path,
        _MockLLMClient(
          _MockLLMResponse.toolThenText(
            id: 'open-finagent-page',
            name: 'UIControl',
            arguments: {
              'action': 'openPage',
              'params': {
                'file': pageFile.path,
                'title': 'FinAgent Workflow Page',
              },
            },
            text:
                'I opened the FinAgent Workflow Page and verified the dashboard evidence.',
          ),
        ),
        tools: [uiControlTool],
      );
      final control = WorkflowAutomationControl(
        agent: agent,
        enabled: true,
        uiStateProvider: () => Map<String, dynamic>.from(uiState),
      );
      final bridge = WorkflowAutomationInProcessBridge(control: control);

      final health = await bridge.health();
      expect(health['enabled'], isTrue);
      expect(health['transport'], 'in-process-bridge');
      expect(health['localOnly'], isTrue);

      final scenario = await bridge.scenario(
        id: 'mobile-ui-dashboard-open-smoke',
        prompt:
            'Open the local workflow page through the FinAgent UI before summarizing.',
        expectTools: ['UIControl'],
        expectToolResultContains: ['"observed":true', pageFile.path],
        expectFinalContains: ['FinAgent Workflow Page'],
        expectUiStateKeys: [
          'activePanel',
          'dashboardReady',
          'activeDashboard.filePath',
        ],
      );
      expect(scenario['ok'], isTrue);
      expect(
        scenario['run']['report']['finalAssistantText'],
        contains('FinAgent Workflow Page'),
      );
      expect(scenario['run']['report']['uiState']['activePanel'], 'dashboard');
      expect(scenario['run']['report']['uiState']['dashboardReady'], isTrue);
      expect(
        scenario['run']['report']['uiEvidence']['paths'],
        contains('activeDashboard.filePath'),
      );
      expect(scenario['assertions'], everyElement(containsPair('ok', true)));

      final session = await bridge.session();
      expect(session['messageCount'], agent.messages.length);
      expect(
        (session['messages'] as List).any(
          (message) =>
              '${message['content']}'.contains('UIControl') ||
              '${message['toolResult']}'.contains('openPage'),
        ),
        isTrue,
      );
      expect(
        (scenario['run']['report']['toolCalls'] as List).single['toolName'],
        'UIControl',
      );

      final idle = await bridge.idle(timeoutMs: 25);
      expect(idle['ok'], isTrue);
      expect(idle['idle'], isTrue);
      expect(idle['agentRunning'], isFalse);
      expect(idle['timedOut'], isFalse);

      final cancel = await bridge.cancel(reason: 'cleanup');
      expect(cancel['ok'], isTrue);
      expect(cancel['runningBeforeCancel'], isFalse);
      expect(cancel['cancelRequested'], isFalse);
      expect(cancel['agentRunning'], isFalse);

      final panels = await bridge.panels();
      expect(panels['uiState']['activePanel'], 'dashboard');
      expect(panels['uiState']['activeDashboard']['filePath'], pageFile.path);
      expect(
        panels['uiEvidence']['paths'],
        contains('activeDashboard.filePath'),
      );

      final reports = await bridge.reports();
      expect(reports['count'], greaterThanOrEqualTo(1));
      expect(
        (reports['reports'] as List).any(
          (entry) => '${entry['path']}'.endsWith('.json'),
        ),
        isTrue,
      );
      expect(
        (reports['reports'] as List).any(
          (entry) =>
              '${entry['uiEvidence']}'.contains('activeDashboard.filePath'),
        ),
        isTrue,
      );
      final scenarioSummary = (reports['reports'] as List)
          .whereType<Map<String, dynamic>>()
          .firstWhere(
            (entry) => entry['scenarioId'] == 'mobile-ui-dashboard-open-smoke',
          );
      expect(scenarioSummary['kind'], 'scenario');
      expect(scenarioSummary['assertionCount'], greaterThan(0));
      expect(scenarioSummary['assertionFailCount'], 0);
      expect(scenarioSummary['failedAssertions'], isEmpty);

      final toolResult = agent.messages
          .where((message) => message.toolResult != null)
          .map((message) => message.toolResult!.content)
          .single;
      expect(toolResult, contains('"observed":true'));
      expect(
        File(scenario['scenarioReportPath'] as String).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'in-process bridge drives FinAgent workflow without HTTP host',
    () async {
      final agent = _makeAgent(
        tmpDir.path,
        _MockLLMClient([
          _MockLLMResponse.text('FinAgent bridge workflow completed.'),
        ]),
      );
      final control = WorkflowAutomationControl(
        agent: agent,
        enabled: true,
        uiStateProvider: () => {'runtime': 'finagent', 'activePanel': 'chat'},
      );
      final bridge = WorkflowAutomationInProcessBridge(control: control);

      final health = await bridge.health();
      expect(health['enabled'], isTrue);
      expect(health['transport'], 'in-process-bridge');
      expect(health['localOnly'], isTrue);

      final scenario = await bridge.scenario(
        id: 'finagent-in-process-workflow-smoke',
        prompt: 'Run a FinAgent workflow automation bridge smoke.',
        expectFinalContains: ['bridge workflow completed'],
        expectUiStateKeys: ['runtime', 'activePanel'],
      );

      expect(scenario['ok'], isTrue);
      expect(
        scenario['run']['report']['finalAssistantText'],
        contains('bridge workflow completed'),
      );
      final session = await bridge.session();
      expect(session['rawSessionAvailable'], isTrue);
      expect(session['rawLineCount'], greaterThanOrEqualTo(2));
      expect(session['messageCount'], agent.messages.length);
      expect(
        File(scenario['scenarioReportPath'] as String).existsSync(),
        isTrue,
      );
      expect(agent.messages.map((m) => m.role), contains(Role.user));
    },
  );

  test('trigger monitor action returns agent-message evidence', () async {
    final agent = _makeAgent(tmpDir.path, _MockLLMClient([]));
    final control = WorkflowAutomationControl(
      agent: agent,
      enabled: true,
      monitorTriggerHandler: ({required monitorId, timeout}) async => {
        'ok': true,
        'monitorId': monitorId,
        'timeoutMs': timeout?.inMilliseconds,
        'agentMessageCount': 1,
        'agentMessages': [
          {
            'monitorName': 'Strategy signal monitor',
            'message': '策略信号已触发：请先计算可以买多少和风险',
            'data': {
              'strategyId': 'custom_20_v1',
              'confirmationRequired': true,
            },
          },
        ],
      },
    );
    final bridge = WorkflowAutomationInProcessBridge(control: control);

    final result = await bridge.triggerMonitor(
      monitorId: 'm-strategy',
      timeoutMs: 60000,
    );

    expect(result['ok'], isTrue);
    expect(result['monitorId'], 'm-strategy');
    expect(result['timeoutMs'], 60000);
    expect(result['agentMessageCount'], 1);
    expect(jsonEncode(result), contains('custom_20_v1'));
  });

  test(
    'trigger monitor bridge preserves portfolio rebalance evidence',
    () async {
      final agent = _makeAgent(tmpDir.path, _MockLLMClient([]));
      final control = WorkflowAutomationControl(
        agent: agent,
        enabled: true,
        monitorTriggerHandler: ({required monitorId, timeout}) async => {
          'ok': true,
          'monitorId': monitorId,
          'timeoutMs': timeout?.inMilliseconds,
          'agentMessageCount': 1,
          'agentMessages': [
            {
              'monitorName': 'Portfolio rebalance monitor',
              'message': '组合策略复核触发：strategyId=portfolio_rank_v1',
              'data': {
                'template': 'portfolio_rebalance_monitor',
                'strategyId': 'portfolio_rank_v1',
                'portfolioEvidence': {
                  'selectedCount': 2,
                  'aggregateMetrics': {
                    'selectedSymbols': ['600519', '000858'],
                  },
                },
                'rebalanceDraft': {
                  'rebalanceInterval': 'monthly',
                  'positions': [
                    {'symbol': '600519', 'targetWeight': 0.4},
                    {'symbol': '000858', 'targetWeight': 0.4},
                  ],
                },
                'confirmationRequired': true,
              },
            },
          ],
        },
      );
      final bridge = WorkflowAutomationInProcessBridge(control: control);

      final result = await bridge.triggerMonitor(
        monitorId: 'm-portfolio',
        timeoutMs: 60000,
      );

      expect(result['ok'], isTrue);
      expect(result['monitorId'], 'm-portfolio');
      final encoded = jsonEncode(result);
      expect(encoded, contains('portfolio_rebalance_monitor'));
      expect(encoded, contains('portfolio_rank_v1'));
      expect(encoded, contains('rebalanceDraft'));
      expect(encoded, contains('600519'));
    },
  );

  test(
    'HTTP host serves interactive state while a prompt request is running',
    () async {
      final promptCompleter = Completer<List<AgentEvent>>();
      final agent = _makeAgent(
        tmpDir.path,
        _MockLLMClient([_MockLLMResponse.text('unused')]),
      );
      final control = WorkflowAutomationControl(
        agent: agent,
        enabled: true,
        promptRunHandler: (_) => promptCompleter.future,
        interactiveStateProvider: () => {
          'hasPendingUserQuestion': true,
          'currentQuestionIndex': 0,
          'collectedAnswers': <String, String>{},
          'questions': [
            {
              'header': 'Confirm',
              'question': 'Proceed?',
              'options': [
                {'label': 'Wait', 'description': 'Do not proceed yet'},
              ],
            },
          ],
        },
      );
      final host = WorkflowAutomationHttpHost(control: control);
      final port = await host.start();
      addTearDown(host.close);
      expect(port, isNotNull);

      final sendFuture = _postJson(port!, '/workflow/send', {
        'prompt': 'Run a long FinAgent workflow.',
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final interactive = await _getJson(port, '/workflow/interactive');
      expect(interactive['hasPendingUserQuestion'], isTrue);
      expect((interactive['questions'] as List).single['question'], 'Proceed?');

      promptCompleter.complete(const <AgentEvent>[]);
      final send = await sendFuture;
      expect(send['ok'], isTrue);
    },
  );

  test(
    'in-process bridge drives FinAgent MarketData provenance without HTTP host',
    () async {
      final agent = _makeAgent(
        tmpDir.path,
        _MockLLMClient(
          _MockLLMResponse.toolThenText(
            id: 'finagent-bridge-interface-availability',
            name: 'MarketData',
            arguments: {
              'action': 'interface_availability',
              'interfaceId': 'stock.quote',
              'provider': 'tdx',
              'providerMode': 'preferred',
            },
            text:
                'FinAgent checked stock.quote availability through the in-process bridge before any provider refresh.',
          ),
        ),
        tools: [
          MarketDataTool(dataManager: DataManager(basePath: tmpDir.path)),
        ],
      );
      final control = WorkflowAutomationControl(
        agent: agent,
        enabled: true,
        uiStateProvider: () => {
          'runtime': 'finagent',
          'activePanel': 'api-health',
        },
      );
      final bridge = WorkflowAutomationInProcessBridge(control: control);

      final scenario = await bridge.scenario(
        id: 'finagent-in-process-interface-availability-smoke',
        prompt:
            'Check stock quote interface availability through the FinAgent in-process bridge.',
        expectTools: ['MarketData'],
        expectToolResultContains: [
          '"action": "interface_availability"',
          '"interfaceId": "stock.quote"',
          '"provider": "tdx"',
          '"providerMode": "preferred"',
          '"canonicalSchema": "data_interface_availability"',
          '"canonicalTable": "quote_snapshot"',
          '"capabilityId": "tdx.stock.quote"',
        ],
        expectFinalContains: ['in-process bridge'],
        expectUiStateKeys: ['runtime', 'activePanel'],
      );

      expect(
        scenario['ok'],
        isTrue,
        reason: jsonEncode(scenario['assertions']),
      );
      expect(
        scenario['run']['report']['toolCalls'].single['toolName'],
        'MarketData',
      );
      expect(
        File(scenario['scenarioReportPath'] as String).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'in-process bridge stops FinAgent blocked provider route without HTTP host',
    () async {
      File('${tmpDir.path}/data/runtime-probes/live-status/latest.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          JsonEncoder.withIndent('  ').convert({
            'generatedAt': DateTime.now().toUtc().toIso8601String(),
            'summary': {'total': 1, 'passed': 0, 'failed': 1, 'blocked': 0},
            'passedApis': const [],
            'failures': [
              {
                'id': 'mobile_yahoo_earnings',
                'provider': 'yfinance',
                'status': 'failed',
                'validationState': 'credential-gated',
                'failureClass': 'credential-or-permission',
              },
            ],
          }),
        );
      final agent = _makeAgent(
        tmpDir.path,
        _MockLLMClient(
          _MockLLMResponse.toolThenText(
            id: 'finagent-yahoo-earnings-runtime-blocked-fetch',
            name: 'MarketData',
            arguments: {
              'action': 'yahoo_earnings',
              'symbols': ['AAPL'],
              'provider': 'yfinance',
              'providerMode': 'strict',
              'allowFallback': false,
              'cachePolicy': 'liveOnly',
            },
            text:
                'FinAgent stopped the strict Yahoo earnings fetch because runtime probe evidence blocks that provider route.',
          ),
        ),
        tools: [
          MarketDataTool(dataManager: DataManager(basePath: tmpDir.path)),
        ],
      );
      final control = WorkflowAutomationControl(
        agent: agent,
        enabled: true,
        uiStateProvider: () => {
          'runtime': 'finagent',
          'activePanel': 'api-health',
        },
      );
      final bridge = WorkflowAutomationInProcessBridge(control: control);

      final scenario = await bridge.scenario(
        id: 'finagent-runtime-provider-block-fetch-smoke',
        prompt:
            'Try a strict Yahoo earnings live refresh for AAPL only if runtime evidence says the provider route is usable.',
        expectTools: ['MarketData'],
        expectToolErrors: [
          'no runtime-eligible providers after probe evidence gating',
          'yfinance:blocked-credential',
          'credentials or permissions change',
        ],
        expectFinalContains: ['runtime probe evidence blocks'],
        expectUiStateKeys: ['runtime', 'activePanel'],
      );

      expect(scenario['ok'], isTrue, reason: '${scenario['assertions']}');
      expect(scenario['assertions'], everyElement(containsPair('ok', true)));
      expect(
        File(scenario['scenarioReportPath'] as String).existsSync(),
        isTrue,
      );
      final toolError = agent.messages
          .where((message) => message.toolResult?.isError ?? false)
          .map((message) => message.toolResult!.content)
          .single;
      expect(toolError, contains('yfinance:blocked-credential'));
    },
  );

  test(
    'in-process bridge drives agent WebView refresh workflow with report evidence',
    () async {
      final uiState = <String, dynamic>{
        'runtime': 'finagent',
        'activePanel': 'dashboard',
        'activeDashboard': {
          'title': 'FinAgent Workflow Page',
          'filePath': '${tmpDir.path}/memory/pages/workflow.html',
        },
        'dashboardReady': true,
        'refreshCount': 0,
      };
      final webViewTool = WebViewTool()
        ..registerHandler('dashboard', (action, params) async {
          if (action != 'refresh') {
            return WebViewResult(
              content: jsonEncode({
                'ok': false,
                'action': action,
                'observed': false,
              }),
              isError: true,
            );
          }
          uiState['refreshCount'] = (uiState['refreshCount'] as int) + 1;
          return WebViewResult(
            content: jsonEncode({
              'ok': true,
              'action': 'refresh',
              'target': params['target'] ?? 'dashboard',
              'observed': true,
              'refreshCount': uiState['refreshCount'],
              'note': 'Refresh re-read the active file-backed dashboard.',
            }),
          );
        });
      final agent = _makeAgent(
        tmpDir.path,
        _MockLLMClient(
          _MockLLMResponse.toolThenText(
            id: 'refresh-finagent-page',
            name: 'WebView',
            arguments: {'action': 'refresh', 'target': 'dashboard'},
            text:
                'I refreshed the FinAgent workflow dashboard and verified the UI evidence.',
          ),
        ),
        tools: [webViewTool],
      );
      final control = WorkflowAutomationControl(
        agent: agent,
        enabled: true,
        uiStateProvider: () => Map<String, dynamic>.from(uiState),
      );
      final bridge = WorkflowAutomationInProcessBridge(control: control);

      final scenario = await bridge.scenario(
        id: 'mobile-ui-dashboard-refresh-smoke',
        prompt:
            'Refresh the already-open FinAgent workflow dashboard before summarizing.',
        expectTools: ['WebView'],
        expectToolResultContains: [
          '"action":"refresh"',
          '"observed":true',
          '"refreshCount":1',
        ],
        expectFinalContains: ['refreshed the FinAgent workflow dashboard'],
        expectUiStateKeys: [
          'activeDashboard',
          'dashboardReady',
          'refreshCount',
        ],
      );

      expect(scenario['ok'], isTrue);
      expect(scenario['assertions'], everyElement(containsPair('ok', true)));
      expect(scenario['run']['report']['uiState']['refreshCount'], 1);
      expect(
        (scenario['run']['report']['toolCalls'] as List).single['toolName'],
        'WebView',
      );
      expect(
        File(scenario['scenarioReportPath'] as String).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'in-process bridge drives Portfolio paper-trade workflow with report evidence',
    () async {
      final uiState = <String, dynamic>{
        'runtime': 'finagent',
        'activePanel': 'portfolio',
        'portfolioMode': 'paper',
        'brokerSideEffect': false,
      };
      final agent = _makeAgent(
        tmpDir.path,
        _MockLLMClient(
          _MockLLMResponse.toolThenText(
            id: 'portfolio-paper-buy',
            name: 'Portfolio',
            arguments: {
              'action': 'trade',
              'market': 'cn',
              'symbol': '600519',
              'side': 'buy',
              'shares': 100,
              'price': 1200,
            },
            text:
                'I recorded a local paper portfolio trade only; no Xueqiu or real broker order was sent.',
          ),
        ),
        tools: [PortfolioTool()],
      );
      final control = WorkflowAutomationControl(
        agent: agent,
        enabled: true,
        uiStateProvider: () => Map<String, dynamic>.from(uiState),
      );
      final bridge = WorkflowAutomationInProcessBridge(control: control);

      final scenario = await bridge.scenario(
        id: 'mobile-portfolio-paper-trade-smoke',
        prompt:
            'Record a local paper portfolio buy and confirm no real broker or Xueqiu order is sent.',
        expectTools: ['Portfolio'],
        expectToolResultContains: ['600519', '1200'],
        expectFinalContains: ['paper portfolio trade', 'no Xueqiu'],
        expectUiStateKeys: ['activePanel', 'portfolioMode', 'brokerSideEffect'],
      );

      expect(scenario['ok'], isTrue);
      expect(scenario['assertions'], everyElement(containsPair('ok', true)));
      expect(scenario['run']['report']['uiState']['activePanel'], 'portfolio');
      expect(scenario['run']['report']['uiState']['portfolioMode'], 'paper');
      expect(scenario['run']['report']['uiState']['brokerSideEffect'], isFalse);
      expect(
        (scenario['run']['report']['toolCalls'] as List).single['toolName'],
        'Portfolio',
      );
      final portfolioFile = File('${tmpDir.path}/memory/.portfolio_cn.json');
      expect(portfolioFile.existsSync(), isTrue);
      final portfolio = jsonDecode(portfolioFile.readAsStringSync()) as Map;
      expect((portfolio['positions'] as Map)['600519']['shares'], 100.0);
      expect(portfolio['trades'], hasLength(1));
      expect(
        File(scenario['scenarioReportPath'] as String).existsSync(),
        isTrue,
      );
    },
  );
}

Agent _makeAgent(
  String basePath,
  LLMClient client, {
  List<Tool> tools = const [],
}) {
  final sessionsDir = '$basePath/sessions';
  final sessionManager = SessionManager(sessionsDir: sessionsDir)
    ..loadOrCreate(feature: 'finagent-workflow-automation-test');
  final context = ToolContext(
    basePath: basePath,
    serviceBaseUrl: '',
    approvedTools: {},
    skipPermissions: true,
  );
  return Agent(
    client: client,
    tools: tools,
    promptBuilder: PromptBuilder(
      basePath: basePath,
      featurePrompt: 'FinAgent workflow automation runtime test.',
    ),
    toolContext: context,
    sessionManager: sessionManager,
  );
}

Future<Map<String, dynamic>> _getJson(int port, String path) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    expect(response.statusCode, 200, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _postJson(
  int port,
  String path,
  Map<String, dynamic> body,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    expect(response.statusCode, 200, reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
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
