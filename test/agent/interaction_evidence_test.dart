import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/ask_user_question_contract.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/ask_user_question_tool/ask_user_question_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AskUserQuestion records pending and resolved evidence rows', () async {
    final dir = Directory.systemTemp.createTempSync(
      'finagent_interaction_evidence_test_',
    );
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
    final tool = AskUserQuestionTool();
    tool.handler = (questions) async => {questions.first.question: '1'};

    final result = await tool.call('ask-1', {
      'questions': [
        {
          'question': 'Choose action',
          'header': 'Action',
          'multiSelect': false,
          'options': [
            {'label': 'Approve', 'description': 'Continue'},
            {'label': 'Cancel', 'description': 'Stop'},
          ],
        },
      ],
    }, context);

    expect(result.isError, isFalse);
    expect(result.content, contains(askUserQuestionContractPrefix));

    final rows = File('${context.memoryDir}/interaction_evidence.jsonl')
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    expect(rows, hasLength(2));
    expect(rows[0], {
      'type': 'user_question_pending',
      'requestId': 'ask-1',
      'toolName': 'AskUserQuestion',
      'questions': [
        {
          'question': 'Choose action',
          'header': 'Action',
          'options': [
            {'label': 'Approve', 'description': 'Continue'},
            {'label': 'Cancel', 'description': 'Stop'},
          ],
          'multiSelect': false,
        },
      ],
      'createdAt': rows[0]['createdAt'],
    });
    expect(rows[1]['type'], 'user_question_resolved');
    expect(rows[1]['requestId'], 'ask-1');
    expect(rows[1]['toolName'], 'AskUserQuestion');
    expect(rows[1]['answers'], {'Choose action': '1'});
    expect(rows[1]['structuredAnswers'], [
      {
        'question': 'Choose action',
        'answer': '1',
        'structuredAnswer': {
          'selectedOptionIndex': 1,
          'selectedOptionLabel': 'Approve',
        },
      },
    ]);

    final pendingState =
        jsonDecode(
              File(
                '${context.memoryDir}/interaction_pending.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(pendingState['contract'], 'interaction-pending-state-v1');
    expect(pendingState['pending'], isEmpty);
  });
}
