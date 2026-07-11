import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/workflow_evidence_tool/workflow_evidence_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WorkflowEvidence summarizes session, pending input, and artifacts', () async {
    final dir = Directory.systemTemp.createTempSync(
      'finagent_workflow_evidence_tool_test_',
    );
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
    Directory('${dir.path}/sessions').createSync(recursive: true);
    Directory(context.memoryDir).createSync(recursive: true);
    Directory('${context.memoryDir}/pages').createSync(recursive: true);
    Directory('${context.memoryDir}/dashboards').createSync(recursive: true);

    File('${dir.path}/sessions/current.jsonl').writeAsStringSync(
      [
        jsonEncode({
          'type': 'session_meta',
          'id': 'session-1',
          'createdAt': '2026-07-11T00:00:00.000Z',
        }),
        jsonEncode({
          'type': 'message',
          'role': 'user',
          'content': '今天市场怎么样',
          'timestamp': '2026-07-11T00:00:01.000Z',
        }),
        jsonEncode({
          'type': 'message',
          'role': 'assistant',
          'toolUses': [
            {
              'id': 'call-1',
              'name': 'MarketData',
              'input': {'action': 'query_quote', 'code': '000001'},
            },
          ],
          'timestamp': '2026-07-11T00:00:02.000Z',
        }),
        jsonEncode({
          'type': 'message',
          'role': 'tool',
          'toolResult': {
            'toolUseId': 'call-1',
            'content': 'Provider failed with timeout',
            'isError': true,
          },
          'timestamp': '2026-07-11T00:00:03.000Z',
        }),
      ].join('\n'),
    );
    File('${context.memoryDir}/interaction_pending.json').writeAsStringSync(
      jsonEncode({
        'contract': 'interaction-pending-state-v1',
        'updatedAt': '2026-07-11T00:00:04.000Z',
        'pending': [
          {
            'type': 'user_question_pending',
            'requestId': 'ask-1',
            'toolName': 'AskUserQuestion',
          },
        ],
      }),
    );
    File('${context.memoryDir}/dashboards/market.html').writeAsStringSync(
      '<html>market</html>',
    );
    File('${context.memoryDir}/pages/note.html').writeAsStringSync(
      '<html>note</html>',
    );

    final tool = WorkflowEvidenceTool();
    final summary =
        jsonDecode(
              (await tool.call('tool-1', {
                'action': 'summary',
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(summary['contract'], 'workflow-evidence-summary-v1');
    expect(summary['pendingInteractions'], [
      {
        'type': 'user_question_pending',
        'requestId': 'ask-1',
        'toolName': 'AskUserQuestion',
      },
    ]);
    expect(summary['session']['messageCount'], 3);
    expect(summary['session']['toolCallCount'], 1);
    expect(summary['session']['toolResultCount'], 1);
    expect(summary['session']['toolErrorCount'], 1);
    expect(summary['artifacts']['dashboards']['count'], 1);
    expect(summary['artifacts']['pages']['count'], 1);
  });
}
