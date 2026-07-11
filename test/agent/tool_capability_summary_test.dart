import 'dart:io';

import 'package:finagent/agent/message.dart';
import 'package:finagent/agent/prompt_builder.dart';
import 'package:finagent/agent/tool.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/artifact_registry_tool/artifact_registry_tool.dart';
import 'package:finagent/agent/tools/ask_user_question_tool/ask_user_question_tool.dart';
import 'package:finagent/agent/tools/finance_workflow_state_tool/finance_workflow_state_tool.dart';
import 'package:finagent/agent/tools/provider_router_tool/provider_router_tool.dart';
import 'package:finagent/agent/tools/recovery_planner_tool/recovery_planner_tool.dart';
import 'package:finagent/agent/tools/tool_catalog_tool/tool_catalog_tool.dart';
import 'package:finagent/agent/tools/ui_control_tool/ui_control_tool.dart';
import 'package:finagent/agent/tools/webview_tool/webview_tool.dart';
import 'package:finagent/agent/tools/workflow_verifier_tool/workflow_verifier_tool.dart';
import 'package:finagent/shared/agent_factory.dart';
import 'package:flutter_test/flutter_test.dart';

class _ExampleTool extends Tool {
  @override
  String get name => 'Example';

  @override
  String get description => 'Example broad tool';

  @override
  bool get isReadOnly => false;

  @override
  bool get requiresUserInteraction => true;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'required': ['action'],
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'run'],
      },
      'symbol': {'type': 'string'},
    },
  };

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async => ToolResult(toolUseId: toolUseId, content: 'ok');
}

void main() {
  test('summarizes mobile tool metadata for progressive discovery', () {
    final summary = summarizeToolCapability(_ExampleTool());

    expect(summary.toJson(), {
      'name': 'Example',
      'description': 'Example broad tool',
      'readOnly': false,
      'canParallel': false,
      'requiresUserInteraction': true,
      'permission': 'write-or-side-effect',
      'schema': {
        'propertyNames': ['action', 'symbol'],
        'required': ['action'],
        'actionValues': ['help', 'run'],
      },
    });
  });

  test('exposes live agent tool capabilities without prompt scraping', () {
    final dir = Directory.systemTemp.createTempSync(
      'finagent_tool_capability_summary_test_',
    );
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final runtime = createAgentRuntime(
      basePath: dir.path,
      serverUrl: '',
      featurePrompt: 'test',
      skipPermissions: true,
      enableWatchlistRefresher: false,
    );
    addTearDown(() {
      runtime.agent.stopAutoProcessing();
      runtime.monitorScheduler.stop();
      runtime.cronScheduler.stop();
    });

    final ask = runtime.agent.toolCapabilities.singleWhere(
      (capability) => capability.name == 'AskUserQuestion',
    );
    final interactionEvidence = runtime.agent.toolCapabilities.singleWhere(
      (capability) => capability.name == 'InteractionEvidence',
    );
    final toolCatalog = runtime.agent.toolCapabilities.singleWhere(
      (capability) => capability.name == 'ToolCatalog',
    );
    final agent = runtime.agent.toolCapabilities.singleWhere(
      (capability) => capability.name == 'Agent',
    );
    final uiControl = runtime.agent.toolCapabilities.singleWhere(
      (capability) => capability.name == 'UIControl',
    );

    expect(ask.requiresUserInteraction, isTrue);
    expect(ask.readOnly, isTrue);
    expect(ask.propertyNames, contains('questions'));
    expect(interactionEvidence.requiresUserInteraction, isFalse);
    expect(interactionEvidence.actionValues, ['help', 'recent', 'summary']);
    expect(toolCatalog.actionValues, [
      'detail',
      'help',
      'list',
      'module',
      'modules',
      'providerModules',
    ]);
    expect(agent.actionValues, ['help', 'run']);
    expect(uiControl.actionValues, contains('help'));
    expect(uiControl.actionValues, contains('openPage'));
  });

  test(
    'chat and event runtimes expose provider and workflow harness tools',
    () {
      final dir = Directory.systemTemp.createTempSync(
        'finagent_agent_path_reachability_test_',
      );
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final chatRuntime = createAgentRuntime(
        basePath: '${dir.path}/chat',
        serverUrl: '',
        featurePrompt: 'chat test',
        agentRole: 'chat',
        skipPermissions: true,
        enableWatchlistRefresher: false,
      );
      final eventRuntime = createAgentRuntime(
        basePath: '${dir.path}/event',
        serverUrl: '',
        featurePrompt: 'event test',
        agentRole: 'event',
        skipPermissions: true,
        enableWatchlistRefresher: false,
      );
      addTearDown(() {
        for (final runtime in [chatRuntime, eventRuntime]) {
          runtime.agent.stopAutoProcessing();
          runtime.monitorScheduler.stop();
          runtime.cronScheduler.stop();
        }
      });

      const expected = {
        'ToolCatalog',
        'CapabilityStatus',
        'AgentSelfDebug',
        'ProviderRouter',
        'RecoveryPlanner',
        'Runbook',
        'WorkflowEvidence',
        'WorkflowVerifier',
        'FinanceWorkflowState',
        'ArtifactRegistry',
        'BudgetGovernor',
        'SourceReader',
      };

      for (final runtime in [chatRuntime, eventRuntime]) {
        final names = runtime.agent.toolCapabilities
            .map((capability) => capability.name)
            .toSet();
        expect(names, containsAll(expected));
        final router = runtime.agent.toolCapabilities.singleWhere(
          (capability) => capability.name == 'ProviderRouter',
        );
        final verifier = runtime.agent.toolCapabilities.singleWhere(
          (capability) => capability.name == 'WorkflowVerifier',
        );
        final catalog = runtime.agent.toolCapabilities.singleWhere(
          (capability) => capability.name == 'ToolCatalog',
        );
        expect(router.actionValues, ['help', 'route', 'tasks']);
        expect(verifier.actionValues, ['check', 'help', 'list']);
        expect(catalog.actionValues, [
          'detail',
          'help',
          'list',
          'module',
          'modules',
          'providerModules',
        ]);
      }
    },
  );

  test('ToolCatalog module descriptors expose agent path usability', () async {
    final tool = ToolCatalogTool(
      toolsProvider: () => [
        ToolCatalogTool(toolsProvider: () => const []),
        ProviderRouterTool(),
        WorkflowVerifierTool(),
        FinanceWorkflowStateTool(),
        RecoveryPlannerTool(),
        ArtifactRegistryTool(),
      ],
    );
    final context = ToolContext(
      basePath: '/tmp/tool-catalog-modules',
      serviceBaseUrl: '',
    );

    final modules = await tool.call('modules', {'action': 'modules'}, context);
    expect(modules.isError, isFalse);
    expect(modules.content, contains('"id":"finance-data"'));
    expect(modules.content, contains('"agentPaths":["chat","event"]'));

    final workflow = await tool.call('workflow-module', {
      'action': 'module',
      'module': 'workflow-harness',
    }, context);
    expect(workflow.isError, isFalse);
    expect(workflow.content, contains('chat and event agents'));
    expect(workflow.content, contains('WorkflowVerifier'));
    expect(workflow.content, contains('FinanceWorkflowState'));

    final providers = await tool.call('provider-modules', {
      'action': 'providerModules',
    }, context);
    expect(providers.isError, isFalse);
    expect(
      providers.content,
      contains('"contract":"provider-module-matrix-v1"'),
    );
    expect(providers.content, contains('"runtime":"finagent-mobile"'));
    expect(providers.content, contains('"provider":"eastmoneyDirect"'));
    expect(providers.content, contains('"statusCounts"'));
  });

  test('AskUserQuestion summary is derived from tool contract', () {
    final summary = summarizeToolCapability(AskUserQuestionTool());

    expect(summary.name, 'AskUserQuestion');
    expect(summary.requiresUserInteraction, isTrue);
    expect(summary.propertyNames, contains('questions'));
  });

  test('WebView help is available without an active target', () async {
    final dir = Directory.systemTemp.createTempSync(
      'finagent_webview_help_test_',
    );
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final tool = WebViewTool();
    final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

    final result = await tool.call('wv-help', {'action': 'help'}, context);
    final decoded = result.content;

    expect(result.isError, isFalse);
    expect(decoded, contains('"contract": "webview-help-v1"'));
    expect(decoded, contains('"navigate"'));
    expect(decoded, contains('"screenshot"'));
  });

  test('UIControl help is available without a registered UI handler', () async {
    final tool = UIControlTool();
    final context = ToolContext(
      basePath: '/tmp/ui-control-help',
      serviceBaseUrl: '',
    );

    final result = await tool.call('ui-help', {'action': 'help'}, context);

    expect(result.isError, isFalse);
    expect(result.content, contains('"contract": "ui-control-help-v1"'));
    expect(result.content, contains('"showChartFromStore"'));
    expect(result.content, contains('"openPage"'));
  });

  test('PromptBuilder includes compact tool capability flags', () {
    final dir = Directory.systemTemp.createTempSync(
      'finagent_prompt_capability_summary_test_',
    );
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final prompt = PromptBuilder(
      basePath: dir.path,
    ).build(tools: [_ExampleTool()]);

    expect(prompt, contains('# Available Tools'));
    expect(
      prompt,
      contains(
        '- Example [write-or-side-effect, requires-user-input, serial, actions=help|run]: Example broad tool',
      ),
    );
  });
}
