import 'dart:io';

import 'package:finagent/agent/message.dart';
import 'package:finagent/agent/prompt_builder.dart';
import 'package:finagent/agent/tool.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/ask_user_question_tool/ask_user_question_tool.dart';
import 'package:finagent/agent/tools/webview_tool/webview_tool.dart';
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

    expect(ask.requiresUserInteraction, isTrue);
    expect(ask.readOnly, isTrue);
    expect(ask.propertyNames, contains('questions'));
    expect(interactionEvidence.requiresUserInteraction, isFalse);
    expect(interactionEvidence.actionValues, ['help', 'recent', 'summary']);
    expect(toolCatalog.actionValues, ['detail', 'help', 'list']);
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
