import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/message.dart';
import 'package:finagent/agent/tool.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/capability_status_tool/capability_status_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CapabilityStatus summarizes runtime capability and workflow health', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    _seedEvidence(context);

    final tool = CapabilityStatusTool(
      toolsProvider: () => [_ExampleTool(), _InteractionTool()],
    );
    final summary =
        jsonDecode(
              (await tool.call('cap-1', {'action': 'summary'}, context)).content,
            )
            as Map<String, dynamic>;

    expect(summary['contract'], 'capability-status-summary-v1');
    expect(summary['runtime'], 'finagent-mobile');
    expect(summary['capabilitySummary']['count'], 2);
    expect(summary['capabilitySummary']['writeOrSideEffect'], 2);
    expect(summary['capabilitySummary']['userInteraction'], 1);
    expect(summary['health']['pendingInteractionCount'], 1);
    expect(summary['health']['toolCallCount'], 1);
    expect(summary['health']['toolErrorCount'], 1);
    expect(summary['health']['uiArtifactCount'], 1);
    expect(summary['runtimeState']['contract'], 'agent-runtime-state-v1');
    expect(summary['runtimeState']['state'], 'waiting_for_user');
    expect(summary['runtimeState']['observed']['pendingInteractions'], 1);
  });

  test('CapabilityStatus evaluates required evidence', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    _seedEvidence(context);

    final tool = CapabilityStatusTool(toolsProvider: () => [_ExampleTool()]);
    final result =
        jsonDecode(
              (await tool.call('cap-2', {
                'action': 'evaluate',
                'workflow': 'market_overview',
                'requiredEvidence': [
                  'agent_discovery',
                  'tool_calls',
                  'no_tool_errors',
                  'no_pending_interactions',
                  'ui_artifacts',
                ],
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(result['contract'], 'capability-status-evaluation-v1');
    expect(result['workflow'], 'market_overview');
    expect(result['passed'], false);
    expect(result['missing'], ['no_tool_errors', 'no_pending_interactions']);
  });

  test('CapabilityStatus rejects invalid evidence names', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final tool = CapabilityStatusTool(toolsProvider: () => [_ExampleTool()]);

    final result = await tool.call('cap-3', {
      'action': 'evaluate',
      'requiredEvidence': ['made_up'],
    }, context);

    expect(result.isError, true);
    expect(result.content, contains('Unsupported requiredEvidence "made_up"'));
  });

  test('CapabilityStatus reports repeated identical failed tool calls', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    _seedRepeatedFailureEvidence(context);

    final tool = CapabilityStatusTool(toolsProvider: () => [_ExampleTool()]);
    final summary =
        jsonDecode(
              (await tool.call('cap-4', {'action': 'summary'}, context)).content,
            )
            as Map<String, dynamic>;

    expect(summary['health']['repeatedFailureCount'], 1);
    expect(summary['runtimeState']['state'], 'blocked');
    final repeated =
        (summary['session']['repeatedFailedToolCalls'] as List).single
            as Map<String, dynamic>;
    expect(repeated['toolName'], 'MarketData');
    expect(repeated['count'], 3);
    expect(repeated['warning'], contains('Stop repeating this call'));
  });
}

ToolContext _tempContext() {
  final dir = Directory.systemTemp.createTempSync(
    'finagent_capability_status_test_',
  );
  return ToolContext(basePath: dir.path, serviceBaseUrl: '');
}

void _seedEvidence(ToolContext context) {
  Directory('${context.basePath}/sessions').createSync(recursive: true);
  Directory('${context.memoryDir}/dashboards').createSync(recursive: true);
  File('${context.basePath}/sessions/current.jsonl').writeAsStringSync(
    [
      jsonEncode({
        'type': 'message',
        'role': 'assistant',
        'toolUses': [
          {
            'id': 'call-1',
            'name': 'MarketData',
            'input': {'action': 'quote'},
          },
        ],
      }),
      jsonEncode({
        'type': 'message',
        'role': 'tool',
        'toolResult': {
          'toolUseId': 'call-1',
          'content': 'failed',
          'isError': true,
        },
      }),
    ].join('\n'),
  );
  File('${context.memoryDir}/interaction_pending.json').writeAsStringSync(
    jsonEncode({
      'contract': 'interaction-pending-state-v1',
      'pending': [
        {'type': 'user_question_pending', 'requestId': 'ask-1'},
      ],
    }),
  );
  File('${context.memoryDir}/dashboards/market.html').writeAsStringSync(
    '<html>market</html>',
  );
}

void _seedRepeatedFailureEvidence(ToolContext context) {
  Directory('${context.basePath}/sessions').createSync(recursive: true);
  final rows = <String>[];
  for (var i = 1; i <= 3; i++) {
    rows.add(
      jsonEncode({
        'type': 'message',
        'role': 'assistant',
        'toolUses': [
          {
            'id': 'call-$i',
            'name': 'MarketData',
            'input': {'action': 'query_quote'},
          },
        ],
      }),
    );
    rows.add(
      jsonEncode({
        'type': 'message',
        'role': 'tool',
        'toolResult': {
          'toolUseId': 'call-$i',
          'content': 'symbols required',
          'isError': true,
        },
      }),
    );
  }
  File('${context.basePath}/sessions/current.jsonl').writeAsStringSync(
    rows.join('\n'),
  );
}

class _ExampleTool extends Tool {
  @override
  String get name => 'Example';

  @override
  String get description => 'Example write tool';

  @override
  bool get isReadOnly => false;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'run'],
      },
    },
  };

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async =>
      ToolResult(toolUseId: toolUseId, content: 'ok');
}

class _InteractionTool extends Tool {
  @override
  String get name => 'AskUserQuestion';

  @override
  String get description => 'Ask the user';

  @override
  bool get isReadOnly => false;

  @override
  bool get requiresUserInteraction => true;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'question': {'type': 'string'},
    },
  };

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async =>
      ToolResult(toolUseId: toolUseId, content: 'ok');
}
