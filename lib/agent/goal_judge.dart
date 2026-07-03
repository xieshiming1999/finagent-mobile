import 'dart:convert';

import 'message.dart';
import 'llm_client.dart';
import 'goal_manager.dart';

const _judgeSystemPrompt =
    'You are a strict judge evaluating whether an autonomous agent has achieved a user\'s stated goal. '
    'You receive the goal text and the agent\'s most recent response. Your only job is to decide whether the goal is fully satisfied.\n\n'
    'A goal is COMPLETE only when:\n'
    '- The response explicitly confirms the goal was completed, OR\n'
    '- The response clearly shows the final deliverable was produced, OR\n'
    'Use outcome="blocked" only when progress requires user input or an external state change.\n'
    'Otherwise use outcome="continue".\n\n'
    'Classify this turn\'s concrete progress as unknown, progress_only, implementation, verification, or blocked.\n'
    'Evidence refs must be exact paths, artifact ids, tool-result ids, or command/test identifiers stated in the response; never invent one.\n\n'
    'Reply ONLY with one strict JSON object on one line and no markdown:\n'
    '{"contract":"goal-judge-result-v1","outcome":"continue|complete|blocked","reason":"<one-sentence rationale>","safetyBoundary":"no_side_effect|approved_side_effect|not_applicable","progress":{"kind":"unknown|progress_only|implementation|verification|blocked","summary":"<short summary or empty>","evidenceRefs":["<exact reference>"]}}';

const int _maxGoalChars = 2000;
const int _maxResponseChars = 4000;
const int _maxSubgoalsChars = 2000;

String _buildJudgeUserPrompt(
  String goal,
  String response,
  List<String>? subgoals,
) {
  final truncGoal = goal.length > _maxGoalChars
      ? goal.substring(0, _maxGoalChars)
      : goal;
  final truncResponse = response.length > _maxResponseChars
      ? response.substring(response.length - _maxResponseChars)
      : response;

  if (subgoals != null && subgoals.isNotEmpty) {
    var block = subgoals
        .asMap()
        .entries
        .map((e) => '- ${e.key + 1}. ${e.value}')
        .join('\n');
    if (block.length > _maxSubgoalsChars) {
      block = block.substring(0, _maxSubgoalsChars);
    }
    return 'Goal:\n$truncGoal\n\nAdditional criteria (all must be satisfied):\n$block\n\n'
        'Agent\'s most recent response:\n$truncResponse\n\nIs the goal AND every criterion satisfied?';
  }

  return 'Goal:\n$truncGoal\n\nAgent\'s most recent response:\n$truncResponse\n\nIs the goal satisfied?';
}

GoalJudgment parseGoalJudgeResponse(String text) {
  if (text.trim().isEmpty) {
    return const GoalJudgment(
      outcome: 'continue',
      reason: 'judge returned empty response',
      parseFailed: true,
    );
  }

  final cleaned = text.trim();
  Map<String, dynamic>? obj;
  try {
    final parsed = jsonDecode(cleaned);
    if (parsed is Map<String, dynamic>) obj = parsed;
  } catch (_) {}

  if (obj == null) {
    final snippet = cleaned.length > 100 ? cleaned.substring(0, 100) : cleaned;
    return GoalJudgment(
      outcome: 'continue',
      reason: 'judge reply was not one strict JSON object: $snippet',
      parseFailed: true,
    );
  }
  final contract = obj['contract'];
  final outcome = obj['outcome'];
  final reason = obj['reason'];
  final safetyBoundary = obj['safetyBoundary'];
  final progress = obj['progress'];
  if (contract != 'goal-judge-result-v1' ||
      !const {'continue', 'complete', 'blocked'}.contains(outcome) ||
      reason is! String ||
      reason.trim().isEmpty ||
      !const {
        'no_side_effect',
        'approved_side_effect',
        'not_applicable',
      }.contains(safetyBoundary) ||
      progress is! Map) {
    return const GoalJudgment(
      outcome: 'continue',
      reason: 'judge JSON does not satisfy goal-judge-result-v1',
      parseFailed: true,
    );
  }
  final kind = progress['kind'];
  final summary = progress['summary'];
  final refs = progress['evidenceRefs'];
  if (!const {
        'unknown',
        'progress_only',
        'implementation',
        'verification',
        'blocked',
      }.contains(kind) ||
      summary is! String ||
      refs is! List ||
      refs.any((value) => value is! String || value.trim().isEmpty)) {
    return const GoalJudgment(
      outcome: 'continue',
      reason: 'judge progress does not satisfy goal-judge-result-v1',
      parseFailed: true,
    );
  }
  if ((outcome == 'blocked') != (kind == 'blocked')) {
    return const GoalJudgment(
      outcome: 'continue',
      reason: 'judge outcome and progress kind are inconsistent',
      parseFailed: true,
    );
  }
  return GoalJudgment(
    outcome: outcome as String,
    reason: reason.trim(),
    parseFailed: false,
    progressKind: kind as String,
    progressSummary: summary.trim().isEmpty ? null : summary.trim(),
    evidence: refs.cast<String>(),
    safetyBoundary: safetyBoundary as String,
  );
}

JudgeFn createGoalJudge(LLMClient client) {
  return (String goal, String response, List<String>? subgoals) async {
    if (goal.trim().isEmpty) {
      return const GoalJudgment(
        outcome: 'continue',
        reason: 'empty goal',
        parseFailed: false,
      );
    }
    if (response.trim().isEmpty) {
      return const GoalJudgment(
        outcome: 'continue',
        reason: 'empty response (nothing to evaluate)',
        parseFailed: false,
      );
    }

    try {
      final userPrompt = _buildJudgeUserPrompt(goal, response, subgoals);
      final messages = [
        Message(
          role: Role.user,
          content: userPrompt,
          timestamp: DateTime.now(),
        ),
      ];

      final parts = <String>[];
      await for (final ev in client.sendMessage(
        systemPrompt: _judgeSystemPrompt,
        messages: messages,
        tools: [],
      )) {
        if (ev is SSETextDelta) parts.add(ev.text);
      }

      return parseGoalJudgeResponse(parts.join());
    } catch (e) {
      return GoalJudgment(
        outcome: 'continue',
        reason: 'judge error: $e',
        parseFailed: false,
      );
    }
  };
}
