import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'artifact_registry.dart';
import 'goal_automation_types.dart';

const int _defaultMaxTurns = 20;
const int _maxConsecutiveParseFailures = 3;

class GoalState {
  String goal;
  String
  status; // 'active' | 'paused' | 'blocked' | 'budget_limited' | 'done' | 'cleared'
  int turnsUsed;
  int maxTurns;
  int createdAt; // unix ms
  int updatedAt; // unix ms
  int elapsedMs;
  int promptTokensUsed;
  int completionTokensUsed;
  int tokensUsed;
  int? tokenBudget;
  int lastTurnAt;
  String? lastVerdict; // 'done' | 'continue' | 'skipped'
  String? lastReason;
  String? pausedReason;
  int consecutiveParseFailures;
  List<String> subgoals;
  List<String> successCriteria;
  String? checkpoint;
  GoalVerifierResult? verifierResult;
  GoalTemplateId? templateId;
  GoalAutomationInfo? automation;
  String? contextPackPath;
  GoalArtifact artifact;
  GoalWorkPacket? workPacket;

  GoalState({
    required this.goal,
    this.status = 'active',
    this.turnsUsed = 0,
    this.maxTurns = _defaultMaxTurns,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.elapsedMs = 0,
    this.promptTokensUsed = 0,
    this.completionTokensUsed = 0,
    this.tokensUsed = 0,
    this.tokenBudget,
    this.lastTurnAt = 0,
    this.lastVerdict,
    this.lastReason,
    this.pausedReason,
    this.consecutiveParseFailures = 0,
    List<String>? subgoals,
    List<String>? successCriteria,
    this.checkpoint,
    this.verifierResult,
    this.templateId,
    this.automation,
    this.contextPackPath,
    required this.artifact,
    this.workPacket,
  }) : subgoals = subgoals ?? [],
       successCriteria = successCriteria ?? [];

  Map<String, dynamic> toJson() => {
    'goal': goal,
    'status': status,
    'turnsUsed': turnsUsed,
    'maxTurns': maxTurns,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'elapsedMs': elapsedMs,
    'promptTokensUsed': promptTokensUsed,
    'completionTokensUsed': completionTokensUsed,
    'tokensUsed': tokensUsed,
    'tokenBudget': tokenBudget,
    'lastTurnAt': lastTurnAt,
    'lastVerdict': lastVerdict,
    'lastReason': lastReason,
    'pausedReason': pausedReason,
    'consecutiveParseFailures': consecutiveParseFailures,
    'subgoals': subgoals,
    'successCriteria': successCriteria,
    'checkpoint': checkpoint,
    'verifierResult': verifierResult?.toJson(),
    'templateId': templateId?.wireName,
    'automation': automation?.toJson(),
    'contextPackPath': contextPackPath,
    'artifact': artifact.toJson(),
    'workPacket': workPacket?.toJson(),
  };

  factory GoalState.fromJson(Map<String, dynamic> json) {
    final verifierJson = json['verifierResult'];
    final automationJson = json['automation'];
    final goal = json['goal'] as String? ?? '';
    final createdAt = (json['createdAt'] as num?)?.toInt() ?? 0;
    final artifactJson = json['artifact'];
    final workPacketJson = json['workPacket'];
    return GoalState(
      goal: goal,
      status: json['status'] as String? ?? 'active',
      turnsUsed: (json['turnsUsed'] as num?)?.toInt() ?? 0,
      maxTurns: (json['maxTurns'] as num?)?.toInt() ?? _defaultMaxTurns,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt:
          (json['updatedAt'] as num?)?.toInt() ??
          (json['lastTurnAt'] as num?)?.toInt() ??
          (json['createdAt'] as num?)?.toInt() ??
          0,
      elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
      promptTokensUsed: (json['promptTokensUsed'] as num?)?.toInt() ?? 0,
      completionTokensUsed:
          (json['completionTokensUsed'] as num?)?.toInt() ?? 0,
      tokensUsed:
          (json['tokensUsed'] as num?)?.toInt() ??
          ((json['promptTokensUsed'] as num?)?.toInt() ?? 0) +
              ((json['completionTokensUsed'] as num?)?.toInt() ?? 0),
      tokenBudget: _positiveIntOrNull(json['tokenBudget']),
      lastTurnAt: (json['lastTurnAt'] as num?)?.toInt() ?? 0,
      lastVerdict: json['lastVerdict'] as String?,
      lastReason: json['lastReason'] as String?,
      pausedReason: json['pausedReason'] as String?,
      consecutiveParseFailures:
          (json['consecutiveParseFailures'] as num?)?.toInt() ?? 0,
      subgoals: (json['subgoals'] as List<dynamic>?)?.cast<String>() ?? [],
      successCriteria:
          (json['successCriteria'] as List<dynamic>?)?.cast<String>() ?? [],
      checkpoint: json['checkpoint'] as String?,
      verifierResult: verifierJson is Map<String, dynamic>
          ? GoalVerifierResult.fromJson(verifierJson)
          : null,
      templateId: GoalTemplateIdWire.parse(json['templateId'] as String? ?? ''),
      automation: automationJson is Map<String, dynamic>
          ? GoalAutomationInfo.fromJson(automationJson)
          : null,
      contextPackPath: json['contextPackPath'] as String?,
      artifact: artifactJson is Map<String, dynamic>
          ? GoalArtifact.fromJson(
              artifactJson,
              fallbackObjective: goal,
              fallbackTime: createdAt,
            )
          : GoalArtifact(
              objective: goal,
              source: 'goal-command',
              createdAt: createdAt,
              updatedAt:
                  (json['updatedAt'] as num?)?.toInt() ??
                  (createdAt == 0
                      ? DateTime.now().millisecondsSinceEpoch
                      : createdAt),
            ),
      workPacket: workPacketJson is Map<String, dynamic>
          ? GoalWorkPacket.fromJson(workPacketJson)
          : null,
    );
  }
}

class GoalDecision {
  final String status;
  final bool shouldContinue;
  final String? continuationPrompt;
  final String
  verdict; // 'done' | 'blocked' | 'continue' | 'skipped' | 'inactive'
  final String reason;
  final String message; // user-visible

  const GoalDecision({
    required this.status,
    required this.shouldContinue,
    this.continuationPrompt,
    required this.verdict,
    required this.reason,
    required this.message,
  });
}

class GoalJudgment {
  final String outcome;
  final String reason;
  final bool parseFailed;
  final String progressKind;
  final String? progressSummary;
  final List<String> evidence;
  final String safetyBoundary;

  const GoalJudgment({
    required this.outcome,
    required this.reason,
    required this.parseFailed,
    this.progressKind = 'unknown',
    this.progressSummary,
    this.evidence = const [],
    this.safetyBoundary = 'not_applicable',
  });

  bool get done => outcome == 'complete' || outcome == 'blocked';
  bool get blocked => outcome == 'blocked';
}

typedef JudgeFn =
    Future<GoalJudgment> Function(
      String goal,
      String response,
      List<String>? subgoals,
    );

typedef GoalVerifierFn =
    Future<GoalVerifierResult> Function(GoalState state, GoalJudgment judgment);

class GoalManager {
  GoalState? _state;
  final String _filePath;

  GoalManager(String basePath)
    : _filePath = p.join(basePath, 'memory', 'goal-state.json') {
    _load();
  }

  String get _basePath => p.dirname(p.dirname(_filePath));

  // --- State queries ---

  bool get isActive => _state != null && _state!.status == 'active';
  bool get hasGoal =>
      _state != null &&
      (_state!.status == 'active' ||
          _state!.status == 'paused' ||
          _state!.status == 'blocked' ||
          _state!.status == 'budget_limited');
  GoalState? get state => _state;

  String statusLine() {
    if (_state == null) return 'No goal set.';
    final s = _state!;
    final icon = switch (s.status) {
      'active' => '⊙',
      'paused' => '⏸',
      'blocked' => '!',
      'budget_limited' => '◷',
      'done' => '✓',
      _ => '✗',
    };
    final subgoalInfo = s.subgoals.isNotEmpty
        ? ', ${s.subgoals.length} subgoals'
        : '';
    final pauseInfo = s.pausedReason != null ? ' (${s.pausedReason})' : '';
    final reasonInfo = s.lastReason != null ? ' — ${s.lastReason}' : '';
    final elapsedInfo = ', elapsed ${_formatDuration(_elapsedMs())}';
    final tokenInfo = s.tokensUsed > 0 || s.tokenBudget != null
        ? ', tokens ${_formatTokenUsage(s)}'
        : '';
    return '$icon Goal [${s.status}] ${s.turnsUsed}/${s.maxTurns} turns$elapsedInfo$tokenInfo$subgoalInfo$pauseInfo$reasonInfo\n  ${s.goal}';
  }

  // --- Mutations ---

  GoalState set(
    String goal, {
    int maxTurns = _defaultMaxTurns,
    GoalSetOptions options = const GoalSetOptions(),
  }) {
    goal = goal.trim();
    if (goal.isEmpty) throw ArgumentError('Goal text cannot be empty.');

    final now = DateTime.now().millisecondsSinceEpoch;
    final artifact = _buildGoalArtifact(goal, options, now);
    _state = GoalState(
      goal: goal,
      status: 'active',
      turnsUsed: 0,
      maxTurns: maxTurns,
      createdAt: now,
      updatedAt: now,
      elapsedMs: 0,
      tokenBudget: _positiveIntOrNull(options.tokenBudget),
      successCriteria: options.successCriteria,
      checkpoint: options.checkpoint,
      verifierResult: options.verifierResult,
      templateId: options.templateId,
      automation: options.automation,
      contextPackPath: options.contextPackPath,
      artifact: artifact,
    );
    _save();
    _registerGoalArtifacts(artifact);
    return _state!;
  }

  void _registerGoalArtifacts(GoalArtifact artifact) {
    final registry = ArtifactRegistry(_basePath);
    registry.register(
      kind: ArtifactKind.goal,
      path: _filePath,
      title: artifact.objective,
      source: artifact.source,
      id: 'goal:${artifact.createdAt}',
      ownerTask: artifact.objective,
      verificationStatus: ArtifactVerificationStatus.unverified,
      freshness: {
        'sourceTime': _artifactTime(artifact.createdAt),
        'fetchedAt': _artifactTime(artifact.updatedAt),
        'status': 'fresh',
      },
      provenance: {'source': artifact.source, 'artifactType': 'goal'},
      metadata: {
        'scope': artifact.scope,
        'doneCriteria': artifact.doneCriteria,
        'allowedTools': artifact.allowedTools,
      },
    );
    final plan = artifact.planSnapshot?.trim();
    if (plan != null && plan.isNotEmpty) {
      registry.register(
        kind: ArtifactKind.planSnapshot,
        path: _filePath,
        title: 'Plan snapshot for goal',
        source: artifact.source,
        id: 'plan_snapshot:${artifact.createdAt}',
        ownerTask: artifact.objective,
        verificationStatus: ArtifactVerificationStatus.unverified,
        freshness: {
          'sourceTime': _artifactTime(artifact.createdAt),
          'fetchedAt': _artifactTime(artifact.updatedAt),
          'status': 'fresh',
        },
        provenance: {
          'source': artifact.source,
          'artifactType': 'plan_snapshot',
          'goalArtifactId': 'goal:${artifact.createdAt}',
        },
        metadata: {
          'objective': artifact.objective,
          'planSnapshot': plan,
          'goalArtifactId': 'goal:${artifact.createdAt}',
        },
      );
    }
  }

  String _artifactTime(int millis) => DateTime.fromMillisecondsSinceEpoch(
    millis,
    isUtc: true,
  ).toIso8601String();

  void pause([String reason = 'user-paused']) {
    if (_state == null) return;
    _state!.status = 'paused';
    _state!.pausedReason = reason;
    _save();
  }

  void markBudgetLimited(String reason) {
    if (_state == null) return;
    _state!.status = 'budget_limited';
    _state!.pausedReason = reason;
    _state!.lastVerdict = 'continue';
    _state!.lastReason = reason;
    _save();
  }

  void markBlocked(String reason) {
    if (_state == null) return;
    _state!.status = 'blocked';
    _state!.pausedReason = reason;
    _state!.lastVerdict = 'done';
    _state!.lastReason = reason;
    _state!.verifierResult = GoalVerifierResult(
      status: 'unchecked',
      checkedAt: DateTime.now().millisecondsSinceEpoch,
      reason: 'Goal blocked before independent verifier: $reason',
      evidence: [if (_state!.contextPackPath != null) _state!.contextPackPath!],
    );
    _save();
  }

  void resume({bool resetBudget = true}) {
    if (_state == null) return;
    _state!.status = 'active';
    _state!.pausedReason = null;
    if (resetBudget) _state!.turnsUsed = 0;
    _save();
  }

  void clear() {
    if (_state == null) return;
    _state!.status = 'cleared';
    _save();
    _state = null;
  }

  void markDone(String reason, {GoalVerifierResult? verifierResult}) {
    if (_state == null) return;
    _state!.status = 'done';
    _state!.lastVerdict = 'done';
    _state!.lastReason = reason;
    _state!.verifierResult =
        verifierResult ??
        GoalVerifierResult(
          status: 'unchecked',
          checkedAt: DateTime.now().millisecondsSinceEpoch,
          reason: 'LLM judge marked done before independent verifier: $reason',
          evidence: [
            if (_state!.contextPackPath != null) _state!.contextPackPath!,
          ],
        );
    _save();
  }

  void updateVerifierResult(GoalVerifierResult result) {
    if (_state == null) return;
    _state!.verifierResult = result;
    _save();
  }

  void recordTokenUsage(int promptTokens, int completionTokens) {
    if (_state == null || (promptTokens <= 0 && completionTokens <= 0)) return;
    _state!.promptTokensUsed += promptTokens < 0 ? 0 : promptTokens;
    _state!.completionTokensUsed += completionTokens < 0 ? 0 : completionTokens;
    _state!.tokensUsed =
        _state!.promptTokensUsed + _state!.completionTokensUsed;
    _save();
  }

  // --- Subgoals ---

  String addSubgoal(String text) {
    if (!hasGoal) throw StateError('No active goal.');
    text = text.trim();
    if (text.isEmpty) throw ArgumentError('Subgoal text cannot be empty.');
    _state!.subgoals.add(text);
    _save();
    return text;
  }

  String removeSubgoal(int index1Based) {
    if (_state == null || _state!.subgoals.isEmpty) {
      throw StateError('No subgoals.');
    }
    final idx = index1Based - 1;
    if (idx < 0 || idx >= _state!.subgoals.length) {
      throw RangeError(
        'Invalid index. Valid range: 1-${_state!.subgoals.length}',
      );
    }
    final removed = _state!.subgoals.removeAt(idx);
    _save();
    return removed;
  }

  int clearSubgoals() {
    if (_state == null) return 0;
    final count = _state!.subgoals.length;
    _state!.subgoals.clear();
    _save();
    return count;
  }

  String _renderSubgoalsBlock() {
    if (_state == null) return '';
    return _state!.subgoals
        .asMap()
        .entries
        .map((e) => '- ${e.key + 1}. ${e.value}')
        .join('\n');
  }

  // --- Core loop driver ---

  Future<GoalDecision> evaluateAfterTurn(
    String lastResponse,
    JudgeFn judgeFn, [
    GoalVerifierFn? verifierFn,
  ]) async {
    if (_state == null || _state!.status != 'active') {
      return const GoalDecision(
        status: 'inactive',
        shouldContinue: false,
        verdict: 'inactive',
        reason: 'no active goal',
        message: '',
      );
    }

    _state!.turnsUsed += 1;
    _state!.lastTurnAt = DateTime.now().millisecondsSinceEpoch;

    final subgoals = _state!.subgoals.isNotEmpty ? _state!.subgoals : null;
    final judgment = await judgeFn(_state!.goal, lastResponse, subgoals);
    final done = judgment.done;
    final reason = judgment.reason;
    final parseFailed = judgment.parseFailed;

    _state!.lastVerdict = done ? 'done' : 'continue';
    _state!.lastReason = reason;

    if (parseFailed) {
      _state!.consecutiveParseFailures += 1;
    } else {
      _state!.consecutiveParseFailures = 0;
    }

    // Done?
    if (done) {
      if (judgment.blocked) {
        markBlocked(reason);
        return GoalDecision(
          status: 'blocked',
          shouldContinue: false,
          verdict: 'blocked',
          reason: reason,
          message:
              '! Goal blocked — $reason. /goal resume after resolving the blocker.',
        );
      }
      if (verifierFn != null) {
        final verifierResult = await verifierFn(_state!, judgment);
        _state!.verifierResult = verifierResult;
        if (verifierResult.status != 'passed') {
          final msg =
              'verifier ${verifierResult.status}: ${verifierResult.reason}';
          pause(msg);
          return GoalDecision(
            status: 'paused',
            shouldContinue: false,
            verdict: 'continue',
            reason: msg,
            message: '⏸ Goal paused — $msg. /goal resume to continue.',
          );
        }
        markDone(reason, verifierResult: verifierResult);
      } else {
        markDone(reason);
      }
      return GoalDecision(
        status: 'done',
        shouldContinue: false,
        verdict: 'done',
        reason: reason,
        message:
            '✓ Goal complete (${_state!.turnsUsed}/${_state!.maxTurns} turns): $reason',
      );
    }

    // Parse failures?
    if (_state!.consecutiveParseFailures >= _maxConsecutiveParseFailures) {
      final msg = 'judge连续${_state!.consecutiveParseFailures}次返回不可解析结果';
      pause(msg);
      return GoalDecision(
        status: 'paused',
        shouldContinue: false,
        verdict: 'continue',
        reason: msg,
        message: '⏸ Goal paused — $msg. /goal resume to continue.',
      );
    }

    // Budget?
    if (_state!.turnsUsed >= _state!.maxTurns) {
      final msg = 'turn额度耗尽 (${_state!.turnsUsed}/${_state!.maxTurns})';
      markBudgetLimited(msg);
      return GoalDecision(
        status: 'budget_limited',
        shouldContinue: false,
        verdict: 'continue',
        reason: msg,
        message: '◷ Goal budget limited — $msg. /goal resume to continue.',
      );
    }

    // Continue
    _state!.workPacket = _buildWorkPacket(reason, judgment);
    _save();
    return GoalDecision(
      status: 'active',
      shouldContinue: true,
      verdict: 'continue',
      reason: reason,
      continuationPrompt: nextContinuationPrompt(),
      message: '→ Turn ${_state!.turnsUsed}/${_state!.maxTurns}, continuing...',
    );
  }

  String? nextContinuationPrompt() {
    if (_state == null || _state!.status != 'active') return null;
    _state!.workPacket ??= _buildWorkPacket(
      _state!.lastReason ?? 'Goal is not complete yet.',
    );
    _save();
    final artifactBlock = _renderGoalArtifact(_state!.artifact);
    final packetBlock = _renderWorkPacket(_state!.workPacket!);
    final goalBlock = '${_state!.goal}\n\n$artifactBlock\n\n$packetBlock';
    if (_state!.subgoals.isNotEmpty) {
      return '[继续执行目标]\n目标: $goalBlock\n\n'
          '用户追加的条件（全部须满足）:\n${_renderSubgoalsBlock()}\n\n'
          '继续朝目标及所有追加条件推进，执行下一个具体步骤。\n'
          '如果目标和所有条件都已完成，请明确说明并停止。\n'
          '如果被阻塞需要用户输入，请明确说明并停止。';
    }
    return '[继续执行目标]\n目标: $goalBlock\n\n'
        '继续朝目标推进，执行下一个具体步骤。\n'
        '如果你认为目标已完成，请明确说明并停止。\n'
        '如果被阻塞需要用户输入，请明确说明并停止。';
  }

  GoalWorkPacket _buildWorkPacket(String reason, [GoalJudgment? judgment]) {
    final state = _state;
    if (state == null) throw StateError('No active goal state.');
    final artifact = state.artifact;
    final criteria = [
      ...artifact.doneCriteria,
      ...state.successCriteria,
      ...state.subgoals,
    ].where((item) => item.trim().isNotEmpty).toList();
    final verification =
        artifact.verification ??
        (criteria.isNotEmpty
            ? 'Verify these criteria: ${criteria.join('; ')}'
            : 'Verify the current turn against the objective and report concrete evidence.');
    final currentGap = reason.trim().isEmpty
        ? 'The goal has not been verified as complete.'
        : reason.trim();
    final progressKind = judgment?.progressKind ?? 'unknown';
    final nextPrompt = progressKind == 'progress_only'
        ? 'The previous turn was progress-only. Produce concrete implementation, readback, or verification evidence that moves the objective forward: $currentGap'
        : 'Address the current gap with the smallest concrete implementation step that moves the objective forward: $currentGap';
    return GoalWorkPacket(
      targetArtifact: artifact.planSnapshot != null
          ? 'plan_snapshot'
          : artifact.objective,
      currentGap: currentGap,
      evidence: [
        if (state.contextPackPath != null)
          'context pack: ${state.contextPackPath}',
        if (state.checkpoint != null) 'checkpoint: ${state.checkpoint}',
        ...?judgment?.evidence,
        ...?state.verifierResult?.evidence,
      ],
      implementationScope: artifact.scope,
      progressKind: progressKind,
      progressSummary: judgment?.progressSummary,
      nextPrompt: nextPrompt,
      verification: verification,
      stopCondition:
          'Stop when the done criteria are proven or the turn budget is exhausted.',
      escalationCondition:
          artifact.escalation ??
          'Escalate when required input, credentials, destructive schema changes, or unsafe side effects are needed.',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      turn: state.turnsUsed + 1,
    );
  }

  GoalArtifact _buildGoalArtifact(
    String goal,
    GoalSetOptions options,
    int now,
  ) {
    final existing = options.goalArtifact;
    if (existing != null) {
      return GoalArtifact(
        objective: existing.objective.isNotEmpty ? existing.objective : goal,
        source: existing.source.isNotEmpty
            ? existing.source
            : (options.source ?? 'goal-command'),
        planSnapshot: existing.planSnapshot ?? options.planSnapshot,
        scope: existing.scope ?? options.scope,
        doneCriteria: existing.doneCriteria.isNotEmpty
            ? existing.doneCriteria
            : (options.doneCriteria.isNotEmpty
                  ? options.doneCriteria
                  : options.successCriteria),
        allowedTools: existing.allowedTools.isNotEmpty
            ? existing.allowedTools
            : options.allowedTools,
        verification: existing.verification ?? options.verification,
        escalation: existing.escalation ?? options.escalation,
        createdAt: existing.createdAt == 0 ? now : existing.createdAt,
        updatedAt: existing.updatedAt == 0 ? now : existing.updatedAt,
      );
    }
    return GoalArtifact(
      objective: goal,
      source: options.source ?? 'goal-command',
      planSnapshot: options.planSnapshot,
      scope: options.scope,
      doneCriteria: options.doneCriteria.isNotEmpty
          ? options.doneCriteria
          : options.successCriteria,
      allowedTools: options.allowedTools,
      verification: options.verification,
      escalation: options.escalation,
      createdAt: now,
      updatedAt: now,
    );
  }

  String _renderGoalArtifact(GoalArtifact artifact) {
    final lines = <String>[
      '[Goal artifact]',
      'Objective: ${artifact.objective}',
      'Source: ${artifact.source}',
    ];
    if (artifact.planSnapshot != null) {
      lines.add('Plan snapshot:\n${artifact.planSnapshot}');
    }
    if (artifact.scope != null) lines.add('Scope: ${artifact.scope}');
    if (artifact.doneCriteria.isNotEmpty) {
      lines.add(
        'Done criteria:\n${artifact.doneCriteria.map((item) => '- $item').join('\n')}',
      );
    }
    if (artifact.allowedTools.isNotEmpty) {
      lines.add(
        'Allowed tools:\n${artifact.allowedTools.map((item) => '- $item').join('\n')}',
      );
    }
    if (artifact.verification != null) {
      lines.add('Verification: ${artifact.verification}');
    }
    if (artifact.escalation != null) {
      lines.add('Escalation: ${artifact.escalation}');
    }
    return lines.join('\n');
  }

  String _renderWorkPacket(GoalWorkPacket packet) => [
    '[Loop work packet]',
    'Target artifact: ${packet.targetArtifact ?? 'not specified'}',
    'Current gap: ${packet.currentGap}',
    packet.evidence.isNotEmpty
        ? 'Evidence:\n${packet.evidence.map((item) => '- $item').join('\n')}'
        : 'Evidence: none recorded yet',
    'Implementation scope: ${packet.implementationScope ?? 'use the goal scope and current repo context'}',
    'Progress classification: ${packet.progressKind}${packet.progressSummary != null ? ' — ${packet.progressSummary}' : ''}',
    'Next prompt: ${packet.nextPrompt}',
    'Verification: ${packet.verification}',
    'Stop condition: ${packet.stopCondition}',
    'Escalation condition: ${packet.escalationCondition}',
  ].join('\n');

  // --- Persistence ---

  void _load() {
    final file = File(_filePath);
    if (!file.existsSync()) return;
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final state = GoalState.fromJson(data);
      if (state.status == 'active' ||
          state.status == 'paused' ||
          state.status == 'blocked' ||
          state.status == 'budget_limited') {
        _state = state;
      }
    } catch (_) {
      // corrupted — start fresh
    }
  }

  void _save() {
    if (_state == null) return;
    _refreshAccounting();
    final file = File(_filePath);
    final dir = file.parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_state!.toJson()),
    );
  }

  int _elapsedMs() {
    if (_state == null) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final createdAt = _state!.createdAt == 0 ? now : _state!.createdAt;
    if (_state!.status == 'active') {
      return (now - createdAt).clamp(0, 1 << 62).toInt();
    }
    final end = _state!.updatedAt != 0
        ? _state!.updatedAt
        : (_state!.lastTurnAt != 0 ? _state!.lastTurnAt : now);
    return (end - createdAt).clamp(0, 1 << 62).toInt();
  }

  void _refreshAccounting() {
    if (_state == null) return;
    _state!.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _state!.elapsedMs = _elapsedMs();
  }
}

String _formatTokenUsage(GoalState state) {
  final used = _formatTokenCount(state.tokensUsed);
  final budget = state.tokenBudget;
  return budget == null ? used : '$used/${_formatTokenCount(budget)}';
}

String _formatTokenCount(int value) {
  if (value < 1000) return '$value';
  if (value < 10000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '${(value / 1000).round()}k';
}

int? _positiveIntOrNull(Object? value) {
  if (value is num && value > 0) return value.toInt();
  return null;
}

String _formatDuration(int ms) {
  final totalSeconds = (ms / 1000).floor().clamp(0, 1 << 62).toInt();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}
