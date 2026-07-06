import 'dart:convert';

import 'package:finagent/agent/ask_user_question_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads structured AskUserQuestion JSON answer contract', () {
    final contract = buildAskUserQuestionContract([
      {
        'question': 'Proceed?',
        'answer': '{"decision":"allow_preview","selectedOptionIndex":3}',
        'structuredAnswer': {
          'decision': 'allow_preview',
          'selectedOptionIndex': 3,
        },
      },
    ]);
    final answer = latestAskUserQuestionStructuredAnswer(
      'User has answered your questions.\n'
      '$askUserQuestionContractPrefix${jsonEncode(contract)}',
    );

    expect(answer, isNotNull);
    expect(answer!['decision'], 'allow_preview');
    expect(answer['selectedOptionIndex'], 3);
  });

  test('reads selected option metadata without interpreting label prose', () {
    final contract = buildAskUserQuestionContract([
      {
        'question': 'Proceed?',
        'answer': '允许模拟执行',
        'structuredAnswer': {
          'selectedOptionIndex': 3,
          'selectedOptionLabel': '允许模拟执行',
        },
      },
    ]);
    final answer = latestAskUserQuestionStructuredAnswer(
      '$askUserQuestionContractPrefix${jsonEncode(contract)}',
    );

    expect(answer, isNotNull);
    expect(answer!['selectedOptionIndex'], 3);
    expect(answer['selectedOptionLabel'], '允许模拟执行');
  });

  test('plain prose answer has no structured contract', () {
    final answer = latestAskUserQuestionStructuredAnswer(
      'User has answered your questions: "Proceed?"="允许模拟执行".',
    );

    expect(answer, isNull);
  });
}
