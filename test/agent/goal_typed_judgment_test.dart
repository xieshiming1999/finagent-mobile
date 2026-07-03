import 'dart:io';

import 'package:finagent/agent/goal_judge.dart';
import 'package:finagent/agent/goal_manager.dart';
import 'package:finagent/agent/goal_automation_types.dart';
import 'package:finagent/agent/goal_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('goal judge accepts only goal-judge-result-v1', () {
    final result = parseGoalJudgeResponse('''
{"contract":"goal-judge-result-v1","outcome":"continue","reason":"Verification remains.","safetyBoundary":"no_side_effect","progress":{"kind":"implementation","summary":"Changed the parser.","evidenceRefs":["artifact:diff:1"]}}
''');

    expect(result.parseFailed, isFalse);
    expect(result.outcome, 'continue');
    expect(result.progressKind, 'implementation');
    expect(result.evidence, ['artifact:diff:1']);
  });

  test('goal judge rejects fenced, embedded, and coerced replies', () {
    for (final reply in [
      '```json\n{"done":true,"reason":"done"}\n```',
      'Result: {"done":"yes","reason":"done"}',
      '{"contract":"goal-judge-result-v1","outcome":"blocked","reason":"input required","safetyBoundary":"no_side_effect","progress":{"kind":"implementation","summary":"","evidenceRefs":[]}}',
    ]) {
      final result = parseGoalJudgeResponse(reply);
      expect(result.parseFailed, isTrue, reason: reply);
      expect(result.outcome, 'continue');
    }
  });

  test('goal manager uses typed progress and blocked outcome', () async {
    final dir = await Directory.systemTemp.createTemp('finagent-goal-judge-');
    addTearDown(() => dir.delete(recursive: true));
    final manager = GoalManager(dir.path)..set('Complete the task.');

    final progress = await manager.evaluateAfterTurn(
      'Arbitrary prose that contains no routing contract.',
      (_, _, _) async => const GoalJudgment(
        outcome: 'continue',
        reason: 'Verification remains.',
        parseFailed: false,
        progressKind: 'verification',
        progressSummary: 'Focused checks ran.',
        evidence: ['test:focused'],
      ),
    );
    expect(progress.status, 'active');
    expect(manager.state?.workPacket?.progressKind, 'verification');
    expect(manager.state?.workPacket?.evidence, contains('test:focused'));

    final blocked = await manager.evaluateAfterTurn(
      'This prose deliberately avoids blocker keywords.',
      (_, _, _) async => const GoalJudgment(
        outcome: 'blocked',
        reason: 'External input is required.',
        parseFailed: false,
        progressKind: 'blocked',
      ),
    );
    expect(blocked.status, 'blocked');
  });

  test(
    'goal verifier consumes typed context references, not response prose',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'finagent-goal-verify-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final context = File('${dir.path}/context.json')
        ..writeAsStringSync('''
{"recentApiFailures":[{"source":"eastmoney"}],"recentApiFailureClasses":[{"classification":"provider_contract","count":1}]}
''');
      final manager = GoalManager(dir.path)
        ..set(
          'Classify API failures.',
          options: GoalSetOptions(
            templateId: GoalTemplateId.apiErrorTriage,
            contextPackPath: context.path,
            automation: const GoalAutomationInfo(
              trigger: 'test',
              runId: 'run-1',
              source: 'test',
            ),
          ),
        );
      final state = manager.state!;

      final passed = await verifyGoalState(
        state,
        GoalJudgment(
          outcome: 'complete',
          reason: 'Typed evidence is complete.',
          parseFailed: false,
          progressKind: 'verification',
          evidence: [context.path],
          safetyBoundary: 'no_side_effect',
        ),
        basePath: dir.path,
      );
      expect(passed.status, 'passed');

      final failed = await verifyGoalState(
        state,
        const GoalJudgment(
          outcome: 'complete',
          reason: 'Unreferenced completion claim.',
          parseFailed: false,
          progressKind: 'verification',
        ),
        basePath: dir.path,
      );
      expect(failed.status, 'failed');
    },
  );
}
