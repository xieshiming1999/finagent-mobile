import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/llm_client.dart';
import 'package:finagent/agent/data_fetcher/data_manager.dart';
import 'package:finagent/agent/data_fetcher/models.dart';
import 'package:finagent/agent/message.dart';
import 'package:finagent/agent/tool.dart';
import 'package:finagent/agent/workflow_automation_control.dart';
import 'package:finagent/domain/market/services/market_data_runtime_probe_service.dart';
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
      'finagent_workflow_automation_app_started_test_',
    );
    _installPathProviderMock(() => tmpDir.path);
    Directory('${tmpDir.path}/memory/pages').createSync(recursive: true);
    Directory('${tmpDir.path}/bundle').createSync(recursive: true);
    Directory('${tmpDir.path}/sessions').createSync(recursive: true);
  });

  tearDown(() {
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  testWidgets('started FinAgent screen exposes in-process dashboard UI evidence', (
    tester,
  ) async {
    WebViewPlatform.instance = _FakeWebViewPlatform();
    final pageFile = File('${tmpDir.path}/memory/pages/app_started.html')
      ..writeAsStringSync(
        '<!doctype html><html><body><h1>App Started Workflow</h1></body></html>',
      );
    final runtime = createAgentRuntime(
      basePath: tmpDir.path,
      serverUrl: '',
      featurePrompt: finagentPromptForLocale(const Locale('en')),
      featureId: 'finance',
      skipPermissions: true,
      batchDrainQueue: true,
      enableWatchlistRefresher: false,
      llmClient: _MockLLMClient([
        ..._MockLLMResponse.toolThenText(
          id: 'open-app-started-page',
          name: 'UIControl',
          arguments: {
            'action': 'openPage',
            'params': {'file': pageFile.path, 'title': 'App Started Workflow'},
          },
          text:
              'I opened the App Started Workflow dashboard and verified visible UI evidence.',
        ),
        ..._MockLLMResponse.toolThenText(
          id: 'inspect-app-started-data-health',
          name: 'MarketData',
          arguments: {'action': 'data_health', 'section': 'summary'},
          text:
              'I inspected FinAgent data health through the governed data.health interface before choosing any provider refresh.',
        ),
        ..._MockLLMResponse.toolThenText(
          id: 'refresh-app-started-page',
          name: 'WebView',
          arguments: {'action': 'refresh', 'target': 'fin'},
          text:
              'I refreshed the App Started Workflow dashboard and verified the visible mobile UI state.',
        ),
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
        locale: const Locale('en'),
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

    expect(bridgeCompleter.isCompleted, isTrue);
    final bridge = await bridgeCompleter.future;
    final health = await tester.runAsync(bridge.health);
    expect(health?['transport'], 'in-process-bridge');
    expect(health?['localOnly'], isTrue);
    expect(health?['rawSocketProtocol'], isFalse);
    expect(health?['webSocketCommandProtocol'], isFalse);
    expect(health?['providerEndpointBypass'], isFalse);
    expect(health?['recommendedExternalTransport'], 'platform-device-bridge');
    final scenario = await tester.runAsync(
      () => bridge.scenario(
        id: 'mobile-ui-dashboard-open-smoke',
        prompt:
            'Open the app-started workflow page and verify mobile UI evidence.',
        expectTools: ['UIControl'],
        expectToolResultContains: ['"ok":true', pageFile.path],
        expectFinalContains: ['App Started Workflow'],
        expectUiEvidencePaths: ['dashboardCount'],
        expectUiArtifactKinds: ['mobile-semantic-snapshot'],
      ),
    );
    expect(scenario, isNotNull);

    final result = scenario!;
    expect(result['ok'], isTrue, reason: '${result['assertions']}');
    final runReport = result['run']['report'] as Map<String, dynamic>;
    expect(
      (runReport['uiArtifacts'] as List<dynamic>).single['kind'],
      'mobile-semantic-snapshot',
    );
    await tester.pump();
    Map<String, dynamic>? uiState;
    for (var i = 0; i < 20; i++) {
      final panels = await bridge.panels();
      uiState = panels['uiState'] as Map<String, dynamic>?;
      if (uiState?['activeDashboard'] != null) break;
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(uiState?['activeDashboard']['title'], 'App Started Workflow');
    expect(uiState?['activeDashboard']['filePath'], pageFile.path);
    expect(File(result['scenarioReportPath'] as String).existsSync(), true);

    final panels = await bridge.panels();
    final panelState = panels['uiState'] as Map<String, dynamic>?;
    final uiEvidence = panels['uiEvidence'] as Map<String, dynamic>;
    expect(uiEvidence['paths'], contains('activeDashboard.title'));
    expect(uiEvidence['semanticsAvailable'], isTrue);
    expect(uiEvidence['semanticsPaths'], contains('activeDashboard.title'));
    expect(
      (uiEvidence['semantics']['labels'] as List<dynamic>),
      contains('App Started Workflow'),
    );
    expect(panelState?['dashboardCount'], greaterThanOrEqualTo(1));

    final dataHealthScenario = await tester.runAsync(
      () => bridge.scenario(
        id: 'mobile-app-started-data-health-smoke',
        prompt:
            'Inspect data health through the governed MarketData interface before trying any provider refresh.',
        expectTools: ['MarketData'],
        expectToolResultContains: [
          '"action": "data_health"',
          '"interfaceId": "data.health"',
          '"provider": "local"',
          '"canonicalSchema": "data_health_report"',
          '"readbackAction": "data_health"',
        ],
        expectFinalContains: ['data health', 'data.health interface'],
        expectSessionContains: ['data.health'],
        expectUiStateKeys: ['runtime', 'sessionId', 'messages'],
        expectUiEvidencePaths: ['runtime', 'sessionId'],
      ),
    );
    expect(dataHealthScenario, isNotNull);
    final dataHealthResult = dataHealthScenario!;
    expect(
      dataHealthResult['ok'],
      isTrue,
      reason: '${dataHealthResult['assertions']}',
    );
    expect(
      File(dataHealthResult['scenarioReportPath'] as String).existsSync(),
      true,
    );
    final dataHealthReport =
        dataHealthResult['run']['report'] as Map<String, dynamic>;
    expect(dataHealthReport['uiEvidence']['semanticsAvailable'], isTrue);
    expect(
      dataHealthReport['uiEvidence']['semanticsPaths'],
      contains('activeTabLabel'),
    );
    final dataHealthToolResult =
        dataHealthReport['toolResults'] as List<dynamic>;
    expect(dataHealthToolResult.single['toolName'], 'MarketData');
    expect(
      '${dataHealthToolResult.single['result']}',
      contains('"credentialActivationRows"'),
    );

    final refreshScenario = await tester.runAsync(
      () => bridge.scenario(
        id: 'mobile-app-started-dashboard-refresh-smoke',
        prompt:
            'Refresh the app-started workflow dashboard and verify mobile UI evidence.',
        expectTools: ['WebView'],
        expectToolResultContains: [
          'Refreshed active dashboard from its source file.',
        ],
        expectFinalContains: ['refreshed', 'visible mobile UI state'],
        expectSessionContains: ['WebView', 'Refreshed active dashboard'],
        expectUiStateKeys: [
          'runtime',
          'sessionId',
          'messages',
          'activeDashboard.title',
          'activeDashboard.filePath',
        ],
        expectUiArtifactKinds: ['mobile-semantic-snapshot'],
      ),
    );
    expect(refreshScenario, isNotNull);
    final refreshResult = refreshScenario!;
    expect(
      refreshResult['ok'],
      isTrue,
      reason: '${refreshResult['assertions']}',
    );
    expect(
      File(refreshResult['scenarioReportPath'] as String).existsSync(),
      true,
    );
    await tester.pump();
    final afterRefreshPanels = await bridge.panels();
    final afterRefreshState =
        afterRefreshPanels['uiState'] as Map<String, dynamic>?;
    expect(
      afterRefreshState?['activeDashboard']['title'],
      'App Started Workflow',
    );
    expect(afterRefreshState?['activeDashboard']['filePath'], pageFile.path);

    final reports = await tester.runAsync(() => bridge.reports(limit: 10));
    expect(reports, isNotNull);
    final reportSummaries = (reports!['reports'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
    final dashboardSummary = reportSummaries.firstWhere(
      (report) => report['scenarioId'] == 'mobile-ui-dashboard-open-smoke',
    );
    final dataHealthSummary = reportSummaries.firstWhere(
      (report) =>
          report['scenarioId'] == 'mobile-app-started-data-health-smoke',
    );
    final refreshSummary = reportSummaries.firstWhere(
      (report) =>
          report['scenarioId'] == 'mobile-app-started-dashboard-refresh-smoke',
    );
    expect(dashboardSummary['kind'], 'scenario');
    expect(dashboardSummary['assertionFailCount'], 0);
    expect(dataHealthSummary['kind'], 'scenario');
    expect(dataHealthSummary['assertionCount'], greaterThan(0));
    expect(dataHealthSummary['assertionFailCount'], 0);
    expect(dataHealthSummary['failedAssertions'], isEmpty);
    expect(dataHealthSummary['uiEvidence']['semanticsAvailable'], isTrue);
    expect(refreshSummary['kind'], 'scenario');
    expect(refreshSummary['assertionCount'], greaterThan(0));
    expect(refreshSummary['assertionFailCount'], 0);
    expect(refreshSummary['failedAssertions'], isEmpty);
    expect(refreshSummary['uiArtifactCount'], greaterThanOrEqualTo(1));
    expect(refreshSummary['uiEvidence']['semanticsAvailable'], isTrue);

    runtime.agent.stopAutoProcessing();
    runtime.cronScheduler.stop();
    runtime.monitorScheduler.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'started FinAgent screen exposes in-process workflow bridge without default HTTP host',
    (tester) async {
      WebViewPlatform.instance = _FakeWebViewPlatform();
      MarketRuntimeProbeService.fixtureModeForTest = true;
      addTearDown(() => MarketRuntimeProbeService.fixtureModeForTest = false);
      _seedSessionAndHistory(tmpDir.path);
      _seedQuoteSnapshot(tmpDir.path);
      final runtime = createAgentRuntime(
        basePath: tmpDir.path,
        serverUrl: '',
        featurePrompt: finagentPromptForLocale(const Locale('en')),
        featureId: 'finance',
        skipPermissions: true,
        batchDrainQueue: true,
        enableWatchlistRefresher: false,
        llmClient: _MockLLMClient([
          ..._MockLLMResponse.toolThenText(
            id: 'app-bridge-interface-availability',
            name: 'MarketData',
            arguments: {
              'action': 'interface_availability',
              'interfaceId': 'stock.quote',
              'provider': 'tdx',
              'providerMode': 'preferred',
            },
            text:
                'I checked stock.quote availability through the app in-process bridge before any provider refresh.',
          ),
          ..._MockLLMResponse.toolThenText(
            id: 'app-bridge-runtime-probe-status',
            name: 'MarketData',
            arguments: {'action': 'runtime_probe', 'probeAction': 'status'},
            text:
                'I inspected runtime probe status through the app in-process bridge before running any live probe.',
          ),
          ..._MockLLMResponse.toolThenText(
            id: 'app-bridge-runtime-probe-fixture-run',
            name: 'MarketData',
            arguments: {
              'action': 'runtime_probe',
              'probeAction': 'run',
              'probeMode': 'all',
              'probeIds': ['mobile_marketdata_tdx_count'],
            },
            text:
                'I ran one bounded mobile runtime probe fixture through the app in-process bridge and persisted positive probe evidence.',
          ),
          ..._MockLLMResponse.toolThenText(
            id: 'app-bridge-data-feed-status',
            name: 'MarketData',
            arguments: {
              'action': 'interface_describe',
              'interfaceId': 'data.feed_status',
            },
            text:
                'I checked data.feed_status through the app in-process bridge and saw mobile keeps desktop Data Feeds explicitly unsupported.',
          ),
          ..._MockLLMResponse.toolThenText(
            id: 'app-bridge-query-quote-cache-readback',
            name: 'MarketData',
            arguments: {
              'action': 'query_quote',
              'symbols': ['600519'],
              'limit': 1,
            },
            text:
                'I reused local quote_snapshot cache for stock.quote through the app in-process bridge before any live provider refresh.',
          ),
          ..._MockLLMResponse.toolThenText(
            id: 'app-bridge-query-quote-validation-error',
            name: 'MarketData',
            arguments: {'action': 'query_quote', 'limit': 1},
            text:
                'I saw query_quote validation fail through the app in-process bridge and will ask for a stock code before retrying cache readback.',
          ),
          ..._MockLLMResponse.toolThenText(
            id: 'app-bridge-provider-diagnostic-boundary',
            name: 'MarketData',
            arguments: {
              'action': 'interface_describe',
              'interfaceId': 'provider.diagnostic',
            },
            text:
                'I saw provider.diagnostic is a known output-only mobile boundary, not a normal reusable data workflow.',
          ),
          ..._MockLLMResponse.toolThenText(
            id: 'app-bridge-finance-doctor',
            name: 'MarketData',
            arguments: {'action': 'finance_doctor'},
            text:
                'I checked Finance Doctor runtime and session history readiness through the app in-process bridge before continuing.',
          ),
          ..._MockLLMResponse.toolThenText(
            id: 'app-bridge-api-health-panel',
            name: 'UIControl',
            arguments: {
              'action': 'openPanel',
              'params': {
                'id': 'api_health',
                'panelType': 'api_health',
                'title': 'API Health',
              },
            },
            text:
                'I opened the API Health panel through the app in-process bridge before deciding whether to probe or refresh.',
          ),
          ..._MockLLMResponse.toolThenText(
            id: 'app-bridge-history-panel',
            name: 'UIControl',
            arguments: {
              'action': 'openPanel',
              'params': {'id': 'history', 'panelType': 'history'},
            },
            text:
                'I opened the History panel through the app in-process bridge and verified prior audit history is visible.',
          ),
          ..._MockLLMResponse.toolThenText(
            id: 'app-bridge-session-panel',
            name: 'UIControl',
            arguments: {
              'action': 'openPanel',
              'params': {'id': 'session', 'panelType': 'session'},
            },
            text:
                'I opened the Session panel through the app in-process bridge and verified archived sessions are resumable.',
          ),
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
          locale: const Locale('en'),
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

      expect(bridgeCompleter.isCompleted, isTrue);
      final bridge = await bridgeCompleter.future;
      final health = await tester.runAsync(bridge.health);
      expect(health?['transport'], 'in-process-bridge');
      expect(health?['localOnly'], isTrue);
      expect(health?['rawSocketProtocol'], isFalse);
      expect(health?['webSocketCommandProtocol'], isFalse);
      expect(health?['providerEndpointBypass'], isFalse);
      expect(health?['recommendedExternalTransport'], 'platform-device-bridge');

      final scenario = await tester.runAsync(
        () => bridge.scenario(
          id: 'mobile-app-in-process-interface-availability-smoke',
          prompt:
              'Check stock quote interface availability through the FinAgent app in-process bridge.',
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
          expectUiStateKeys: ['runtime', 'sessionId', 'messages'],
          expectUiArtifactKinds: ['mobile-semantic-snapshot'],
        ),
      );
      expect(scenario, isNotNull);
      expect(scenario?['ok'], isTrue, reason: '${scenario?['assertions']}');
      expect(
        File(scenario?['scenarioReportPath'] as String).existsSync(),
        isTrue,
      );

      final probeScenario = await tester.runAsync(
        () => bridge.scenario(
          id: 'mobile-app-in-process-runtime-probe-status-smoke',
          prompt:
              'Inspect runtime probe status through the FinAgent app in-process bridge.',
          expectTools: ['MarketData'],
          expectToolResultContains: [
            '"action": "runtime_probe"',
            '"probeAction": "status"',
            '"canonicalSchema": "runtime_probe_status"',
            'runtime-evidence',
          ],
          expectFinalContains: ['runtime probe status'],
          expectUiStateKeys: ['runtime', 'sessionId', 'messages'],
        ),
      );
      expect(probeScenario, isNotNull);
      expect(
        probeScenario?['ok'],
        isTrue,
        reason: '${probeScenario?['assertions']}',
      );
      expect(
        File(probeScenario?['scenarioReportPath'] as String).existsSync(),
        isTrue,
      );

      final probeFixtureScenario = await tester.runAsync(
        () => bridge.scenario(
          id: 'mobile-app-in-process-runtime-probe-fixture-run-smoke',
          prompt:
              'Run one explicit bounded mobile runtime probe fixture through the FinAgent app in-process bridge.',
          expectTools: ['MarketData'],
          expectToolResultContains: [
            '"probeAction": "run"',
            '"selectedCount": 1',
            '"mobile_marketdata_tdx_count"',
            '"passed": 1',
            '"outputPath":',
          ],
          expectFinalContains: ['positive probe evidence'],
          expectUiStateKeys: ['runtime', 'sessionId', 'messages'],
          expectUiArtifactKinds: ['mobile-semantic-snapshot'],
        ),
      );
      expect(probeFixtureScenario, isNotNull);
      expect(
        probeFixtureScenario?['ok'],
        isTrue,
        reason: '${probeFixtureScenario?['assertions']}',
      );
      expect(
        File(
          probeFixtureScenario?['scenarioReportPath'] as String,
        ).existsSync(),
        isTrue,
      );

      final feedStatusScenario = await tester.runAsync(
        () => bridge.scenario(
          id: 'mobile-app-in-process-data-feed-status-smoke',
          prompt:
              'Check the mobile Data Feed status contract through the FinAgent app in-process bridge.',
          expectTools: ['MarketData'],
          expectToolResultContains: [
            '"action": "interface_describe"',
            '"interfaceId": "data.feed_status"',
            '"status": "not-supported"',
            'desktop Data Manager feed status surface',
          ],
          expectFinalContains: ['data.feed_status'],
          expectUiStateKeys: ['runtime', 'sessionId', 'messages'],
        ),
      );
      expect(feedStatusScenario, isNotNull);
      expect(
        feedStatusScenario?['ok'],
        isTrue,
        reason: '${feedStatusScenario?['assertions']}',
      );
      expect(
        File(feedStatusScenario?['scenarioReportPath'] as String).existsSync(),
        isTrue,
      );

      final quoteReadbackScenario = await tester.runAsync(
        () => bridge.scenario(
          id: 'mobile-app-in-process-cache-readback-quote-smoke',
          prompt:
              'Reuse cached stock quote data through the FinAgent app in-process bridge before any live provider call.',
          expectTools: ['MarketData'],
          expectToolResultContains: [
            '"action": "query_quote"',
            '"interfaceId": "stock.quote"',
            '"cacheStatus": "cache-hit"',
            '"canonicalTable": "quote_snapshot"',
            '"provider": "local"',
            '"sourceProviders":',
            '"tdx"',
            '600519',
          ],
          expectFinalContains: ['quote_snapshot cache'],
          expectUiStateKeys: ['runtime', 'sessionId', 'messages'],
          expectUiArtifactKinds: ['mobile-semantic-snapshot'],
        ),
      );
      expect(quoteReadbackScenario, isNotNull);
      expect(
        quoteReadbackScenario?['ok'],
        isTrue,
        reason: '${quoteReadbackScenario?['assertions']}',
      );
      expect(
        File(
          quoteReadbackScenario?['scenarioReportPath'] as String,
        ).existsSync(),
        isTrue,
      );

      final validationScenario = await tester.runAsync(
        () => bridge.scenario(
          id: 'mobile-app-in-process-cache-readback-validation-error-smoke',
          prompt:
              'Attempt quote cache readback without a code through the FinAgent app in-process bridge.',
          expectTools: ['MarketData'],
          expectToolErrors: ['symbols required for query_quote'],
          expectFinalContains: ['validation fail', 'stock code'],
          expectUiStateKeys: ['runtime', 'sessionId', 'messages'],
        ),
      );
      expect(validationScenario, isNotNull);
      expect(
        validationScenario?['ok'],
        isTrue,
        reason: '${validationScenario?['assertions']}',
      );
      expect(
        File(validationScenario?['scenarioReportPath'] as String).existsSync(),
        isTrue,
      );

      final providerDiagnosticScenario = await tester.runAsync(
        () => bridge.scenario(
          id: 'mobile-app-in-process-provider-diagnostic-boundary-smoke',
          prompt:
              'Explain the provider diagnostic boundary through the FinAgent app in-process bridge before any raw provider inspection.',
          expectTools: ['MarketData'],
          expectToolResultContains: [
            '"action": "interface_describe"',
            '"interfaceId": "provider.diagnostic"',
            '"persistencePolicy": "output-only"',
            '"cacheStatus": "not-cacheable"',
            '"normalWorkflow": "not-supported"',
          ],
          expectFinalContains: ['output-only mobile boundary'],
          expectUiStateKeys: ['runtime', 'sessionId', 'messages'],
          expectUiArtifactKinds: ['mobile-semantic-snapshot'],
        ),
      );
      expect(providerDiagnosticScenario, isNotNull);
      expect(
        providerDiagnosticScenario?['ok'],
        isTrue,
        reason: '${providerDiagnosticScenario?['assertions']}',
      );
      expect(
        File(
          providerDiagnosticScenario?['scenarioReportPath'] as String,
        ).existsSync(),
        isTrue,
      );

      final financeDoctorScenario = await tester.runAsync(
        () => bridge.scenario(
          id: 'mobile-app-in-process-finance-doctor-smoke',
          prompt:
              'Check Finance Doctor runtime and session history readiness through the FinAgent app in-process bridge.',
          expectTools: ['MarketData'],
          expectToolResultContains: [
            '"action": "finance_doctor"',
            '"interfaceId": "data.health"',
            '"capabilityId": "local.finance_doctor"',
            '"id": "session_history"',
          ],
          expectFinalContains: ['Finance Doctor runtime', 'session history'],
          expectSessionContains: ['Finance Doctor runtime', 'session history'],
          expectUiStateKeys: ['runtime', 'sessionId', 'messages'],
          expectUiArtifactKinds: ['mobile-semantic-snapshot'],
        ),
      );
      expect(financeDoctorScenario, isNotNull);
      expect(
        financeDoctorScenario?['ok'],
        isTrue,
        reason: '${financeDoctorScenario?['assertions']}',
      );
      expect(
        File(
          financeDoctorScenario?['scenarioReportPath'] as String,
        ).existsSync(),
        isTrue,
      );

      final apiHealthScenario = await tester.runAsync(
        () => bridge.scenario(
          id: 'mobile-app-in-process-api-health-panel-smoke',
          prompt:
              'Open API Health through the FinAgent app in-process bridge before any provider retry.',
          expectTools: ['UIControl'],
          expectToolResultContains: [
            '"action":"openPanel"',
            '"panel":"api_health"',
            '"observed":true',
          ],
          expectFinalContains: ['API Health panel'],
          expectUiStateKeys: [
            'runtime',
            'sessionId',
            'messages',
            'apiHealthPanelVisible',
          ],
        ),
      );
      expect(apiHealthScenario, isNotNull);
      expect(
        apiHealthScenario?['ok'],
        isTrue,
        reason: '${apiHealthScenario?['assertions']}',
      );
      expect(
        File(apiHealthScenario?['scenarioReportPath'] as String).existsSync(),
        isTrue,
      );

      final historyScenario = await tester.runAsync(
        () => bridge.scenario(
          id: 'mobile-app-in-process-history-panel-smoke',
          prompt:
              'Open the FinAgent History panel through the app in-process bridge before continuing.',
          expectTools: ['UIControl'],
          expectToolResultContains: [
            '"action":"openPanel"',
            '"panel":"history"',
            '"observed":true',
            '"historyFiles":',
          ],
          expectFinalContains: ['History panel'],
          expectUiStateKeys: [
            'runtime',
            'sessionId',
            'messages',
            'historyPanelVisible',
          ],
          expectUiArtifactKinds: ['mobile-semantic-snapshot'],
        ),
      );
      expect(historyScenario, isNotNull);
      expect(
        historyScenario?['ok'],
        isTrue,
        reason: '${historyScenario?['assertions']}',
      );
      expect(
        File(historyScenario?['scenarioReportPath'] as String).existsSync(),
        isTrue,
      );

      Navigator.of(tester.element(find.byType(FinAgentScreen))).pop();
      await tester.pumpAndSettle();

      final sessionScenario = await tester.runAsync(
        () => bridge.scenario(
          id: 'mobile-app-in-process-session-panel-smoke',
          prompt:
              'Open the FinAgent Session panel through the app in-process bridge before continuing.',
          expectTools: ['UIControl'],
          expectToolResultContains: [
            '"action":"openPanel"',
            '"panel":"session"',
            '"observed":true',
            '"sessions":1',
          ],
          expectFinalContains: ['Session panel'],
          expectUiStateKeys: [
            'runtime',
            'sessionId',
            'messages',
            'sessionPanelVisible',
          ],
          expectUiArtifactKinds: ['mobile-semantic-snapshot'],
        ),
      );
      expect(sessionScenario, isNotNull);
      expect(
        sessionScenario?['ok'],
        isTrue,
        reason: '${sessionScenario?['assertions']}',
      );
      expect(
        File(sessionScenario?['scenarioReportPath'] as String).existsSync(),
        isTrue,
      );

      final reports = await tester.runAsync(() => bridge.reports(limit: 20));
      expect(reports, isNotNull);
      final reportSummaries = (reports?['reports'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      Map<String, dynamic> summaryFor(String scenarioId) => reportSummaries
          .firstWhere((report) => report['scenarioId'] == scenarioId);
      final quoteReadbackSummary = summaryFor(
        'mobile-app-in-process-cache-readback-quote-smoke',
      );
      final probeFixtureSummary = summaryFor(
        'mobile-app-in-process-runtime-probe-fixture-run-smoke',
      );
      final providerDiagnosticSummary = summaryFor(
        'mobile-app-in-process-provider-diagnostic-boundary-smoke',
      );
      final financeDoctorSummary = summaryFor(
        'mobile-app-in-process-finance-doctor-smoke',
      );
      final historySummary = summaryFor(
        'mobile-app-in-process-history-panel-smoke',
      );
      final sessionSummary = summaryFor(
        'mobile-app-in-process-session-panel-smoke',
      );
      for (final summary in [
        quoteReadbackSummary,
        probeFixtureSummary,
        providerDiagnosticSummary,
        financeDoctorSummary,
        historySummary,
        sessionSummary,
      ]) {
        expect(summary['kind'], 'scenario');
        expect(summary['assertionCount'], greaterThan(0));
        expect(summary['assertionFailCount'], 0);
        expect(summary['failedAssertions'], isEmpty);
        expect(summary['uiArtifactCount'], greaterThanOrEqualTo(1));
      }
      expect(quoteReadbackSummary['uiEvidence']['semanticsAvailable'], isTrue);
      expect(probeFixtureSummary['uiEvidence']['semanticsAvailable'], isTrue);
      expect(
        providerDiagnosticSummary['uiEvidence']['semanticsAvailable'],
        isTrue,
      );
      expect(financeDoctorSummary['uiEvidence']['semanticsAvailable'], isTrue);
      expect(historySummary['uiEvidence']['semanticsAvailable'], isTrue);
      expect(sessionSummary['uiEvidence']['semanticsAvailable'], isTrue);

      runtime.agent.stopAutoProcessing();
      runtime.cronScheduler.stop();
      runtime.monitorScheduler.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    },
  );
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

void _seedQuoteSnapshot(String basePath) {
  final dataManager = DataManager(basePath: basePath);
  dataManager.saveQuoteSnapshots([
    StockQuote(
      code: '600519',
      timestamp: '2026-06-25T09:30:00.000Z',
      fetchedAt: '2026-06-25T09:31:00.000Z',
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
      source: 'tdx',
    ),
  ], source: 'tdx');
}

void _seedSessionAndHistory(String basePath) {
  final sessionsDir = Directory('$basePath/sessions');
  final historyDir = Directory('${sessionsDir.path}/history')
    ..createSync(recursive: true);
  final archiveDir = Directory('${sessionsDir.path}/archive')
    ..createSync(recursive: true);
  File('${historyDir.path}/2026-06-25_finance.jsonl').writeAsStringSync(
    [
      jsonEncode({
        'type': 'message',
        'role': 'user',
        'content': 'Prior interface-first data provenance audit history',
      }),
      jsonEncode({
        'type': 'message',
        'role': 'assistant',
        'content': 'History evidence is available for workflow continuation.',
      }),
    ].join('\n'),
  );
  File('${archiveDir.path}/archived-session.jsonl').writeAsStringSync(
    [
      jsonEncode({
        'type': 'session_meta',
        'id': 'archived-session',
        'createdAt': '2026-06-25T00:00:00.000Z',
        'feature': 'finance',
      }),
      jsonEncode({'type': 'title', 'title': 'Archived Provenance Session'}),
      jsonEncode({
        'type': 'message',
        'role': 'user',
        'content': 'Archived provenance decision for resume testing',
      }),
      jsonEncode({
        'type': 'message',
        'role': 'assistant',
        'content':
            'The archived session can be resumed from the Session panel.',
      }),
    ].join('\n'),
  );
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

  String? _url;
  String? _title;

  @override
  Future<void> loadFile(String absoluteFilePath) async {
    _url = absoluteFilePath;
    _title = absoluteFilePath.split(Platform.pathSeparator).last;
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    _url = baseUrl ?? 'about:blank';
    _title = 'html';
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    _url = params.uri.toString();
    _title = params.uri.toString();
  }

  @override
  Future<String?> currentUrl() async => _url;

  @override
  Future<String?> getTitle() async => _title;

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
