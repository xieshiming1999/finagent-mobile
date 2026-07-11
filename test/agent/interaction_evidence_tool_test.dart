import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/interaction_evidence_tool/interaction_evidence_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('InteractionEvidence summarizes pending and resolved rows', () async {
    final dir = Directory.systemTemp.createTempSync(
      'finagent_interaction_evidence_tool_test_',
    );
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
    Directory(context.memoryDir).createSync(recursive: true);
    File('${context.memoryDir}/interaction_evidence.jsonl').writeAsStringSync(
      [
        jsonEncode({
          'type': 'user_question_pending',
          'requestId': 'ask-1',
          'toolName': 'AskUserQuestion',
        }),
        jsonEncode({
          'type': 'permission_request',
          'requestId': 'perm-1',
          'toolName': 'FileWrite',
        }),
        jsonEncode({
          'type': 'permission_resolved',
          'requestId': 'perm-1',
          'toolName': 'FileWrite',
          'approved': true,
        }),
      ].join('\n'),
    );
    File('${context.memoryDir}/interaction_pending.json').writeAsStringSync(
      jsonEncode({
        'contract': 'interaction-pending-state-v1',
        'updatedAt': '2026-07-11T00:00:00.000Z',
        'pending': [
          {
            'type': 'user_question_pending',
            'requestId': 'ask-snapshot',
            'toolName': 'AskUserQuestion',
          },
        ],
      }),
    );

    final tool = InteractionEvidenceTool();
    final summary =
        jsonDecode(
              (await tool.call('tool-1', {
                'action': 'summary',
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(summary['contract'], 'interaction-evidence-result-v1');
    expect(summary['count'], 3);
    expect(summary['byType'], {
      'user_question_pending': 1,
      'permission_request': 1,
      'permission_resolved': 1,
    });
    expect(summary['pending'], [
      {
        'type': 'user_question_pending',
        'requestId': 'ask-snapshot',
        'toolName': 'AskUserQuestion',
      },
    ]);

    final recent =
        jsonDecode(
              (await tool.call('tool-2', {
                'action': 'recent',
                'type': 'permission_resolved',
              }, context)).content,
            )
            as Map<String, dynamic>;
    expect(recent['rows'], [
      {
        'type': 'permission_resolved',
        'requestId': 'perm-1',
        'toolName': 'FileWrite',
        'approved': true,
      },
    ]);
  });
}
