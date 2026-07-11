import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/message.dart';
import 'package:finagent/agent/tool.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/agent_self_debug_tool/agent_self_debug_tool.dart';
import 'package:finagent/agent/tools/runbook_tool/runbook_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'AgentSelfDebug reports repeated failed tool calls and discovery tools',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      _seedRepeatedFailures(context);

      final tool = AgentSelfDebugTool(
        toolsProvider: () => [_ExampleTool(), RunbookTool()],
      );
      final status =
          jsonDecode(
                (await tool.call('debug-1', {
                  'action': 'status',
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(status['contract'], 'agent-self-debug-status-v1');
      expect(status['state'], 'needs_attention');
      expect(status['repeatedFailedToolCalls'], isNotEmpty);
      expect(status['nextAction'], contains('Stop repeating'));
      expect(
        status['discoveryTools'],
        contains(isA<Map>().having((row) => row['name'], 'name', 'Runbook')),
      );
    },
  );

  test('AgentSelfDebug rejects unknown action through tool error', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final result = await AgentSelfDebugTool(
      toolsProvider: () => [],
    ).call('debug-2', {'action': 'unknown'}, context);

    expect(result.isError, true);
    expect(result.content, contains('Invalid AgentSelfDebug action'));
  });
}

ToolContext _tempContext() {
  final dir = Directory.systemTemp.createTempSync('finagent_self_debug_test_');
  return ToolContext(basePath: dir.path, serviceBaseUrl: '');
}

void _seedRepeatedFailures(ToolContext context) {
  final dir = Directory('${context.basePath}/sessions')
    ..createSync(recursive: true);
  final rows = <String>[];
  for (var i = 0; i < 3; i++) {
    rows.add(
      jsonEncode({
        'type': 'message',
        'role': 'assistant',
        'toolUses': [
          {
            'id': 'tool-$i',
            'name': 'MarketData',
            'input': {'action': 'query_quote', 'symbol': '300059'},
          },
        ],
      }),
    );
    rows.add(
      jsonEncode({
        'type': 'message',
        'role': 'tool',
        'toolResult': {
          'toolUseId': 'tool-$i',
          'content': 'unknown action',
          'isError': true,
        },
      }),
    );
  }
  File('${dir.path}/current.jsonl').writeAsStringSync(rows.join('\n'));
}

class _ExampleTool extends Tool {
  @override
  String get name => 'Example';

  @override
  String get description => 'example';

  @override
  Map<String, dynamic> get inputSchema => const {
    'type': 'object',
    'properties': {},
  };

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async => ToolResult(toolUseId: toolUseId, content: '{}');
}
