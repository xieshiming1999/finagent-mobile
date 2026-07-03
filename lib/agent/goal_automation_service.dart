import 'dart:convert';
import 'dart:io';

import 'agent.dart';
import 'api_failure_classifier.dart';
import 'data_fetcher/api_stats.dart';
import 'data_task_engine.dart';
import 'goal_automation_suggestions.dart';
import 'goal_automation_state.dart';
import 'goal_automation_types.dart';
import 'goal_context_pack.dart';
import 'goal_templates.dart';
import 'notification_queue.dart';

class GoalAutomationRun {
  final String runId;
  final GoalTemplateId templateId;
  final String trigger;
  final String status;
  final String reason;
  final String? contextPackPath;

  const GoalAutomationRun({
    required this.runId,
    required this.templateId,
    required this.trigger,
    required this.status,
    required this.reason,
    this.contextPackPath,
  });
}

class GoalAutomationService {
  final String basePath;
  final Agent agent;
  final DataTaskEngine? dataTaskEngine;
  late final GoalAutomationStateStore stateStore;
  late final GoalAutomationSuggestionStore suggestionStore;
  static const Duration _minRunGap = Duration(minutes: 10);
  static const int _maxFailureCount = 3;

  GoalAutomationService({
    required this.basePath,
    required this.agent,
    this.dataTaskEngine,
  }) {
    stateStore = GoalAutomationStateStore(basePath);
    suggestionStore = GoalAutomationSuggestionStore(basePath);
  }

  List<Map<String, dynamic>> list() {
    final activeGoal = agent.goalManager.state;
    return goalTemplates
        .map(
          (template) => {
            'template': {
              'id': template.id.wireName,
              'title': template.title,
              'objective': template.objective,
            },
            'state': stateStore.get(template.id).toJson(),
            'activeGoal': activeGoal?.templateId == template.id
                ? {
                    'status': activeGoal?.status,
                    'turnsUsed': activeGoal?.turnsUsed,
                    'maxTurns': activeGoal?.maxTurns,
                    'tokenBudget': activeGoal?.tokenBudget,
                    'tokensUsed': activeGoal?.tokensUsed,
                    'artifact': activeGoal?.artifact.toJson(),
                    'successCriteria': activeGoal?.successCriteria,
                    'checkpoint': activeGoal?.checkpoint,
                    'contextPackPath': activeGoal?.contextPackPath,
                    'workPacket': activeGoal?.workPacket?.toJson(),
                    'verifierResult': activeGoal?.verifierResult?.toJson(),
                  }
                : null,
          },
        )
        .toList();
  }

  GoalLoopState setEnabled(GoalTemplateId templateId, bool enabled) =>
      stateStore.update(
        templateId,
        (state) => state.copyWith(enabled: enabled, paused: false),
      );

  GoalLoopState pause(GoalTemplateId templateId, bool paused) =>
      stateStore.update(templateId, (state) => state.copyWith(paused: paused));

  List<GoalAutomationSuggestion> listSuggestions() => suggestionStore
      .seedCatalog(goalTemplates, (id) => stateStore.get(id).enabled);

  Map<String, dynamic> acceptSuggestion(String ref) {
    final suggestion = suggestionStore.accept(ref);
    if (suggestion == null) {
      return {
        'ok': false,
        'error':
            'Goal automation suggestion not found or already resolved: $ref',
      };
    }
    final state = setEnabled(suggestion.templateId, true);
    return {
      'ok': true,
      'suggestion': suggestion.toJson(),
      'state': state.toJson(),
    };
  }

  Map<String, dynamic> dismissSuggestion(String ref) {
    final suggestion = suggestionStore.dismiss(ref);
    if (suggestion == null) {
      return {
        'ok': false,
        'error':
            'Goal automation suggestion not found or already resolved: $ref',
      };
    }
    return {'ok': true, 'suggestion': suggestion.toJson()};
  }

  List<GoalAutomationRun> evaluateTriggers({String trigger = 'schedule'}) {
    final runs = <GoalAutomationRun>[];
    for (final template in goalTemplates) {
      final state = stateStore.get(template.id);
      if (!state.enabled || state.paused) continue;
      if (!template.persistentDuty) {
        const reason =
            'Skipped because this template is manual run-now only, not a persistent duty.';
        stateStore.update(
          template.id,
          (state) => state.copyWith(
            lastResult: reason,
            lastTriggerEvidence:
                'Loop automation is limited to narrow persistent duties.',
            escalationNeeded: false,
          ),
        );
        stateStore.recordDecision(
          template.id,
          requestedTrigger: trigger,
          resolvedTrigger: trigger,
          status: 'skipped',
          reason: reason,
          evidence: 'Loop automation is limited to narrow persistent duties.',
          nextRunAt: state.nextRunAt,
        );
        continue;
      }
      if (state.failureCount >= _maxFailureCount) {
        stateStore.update(
          template.id,
          (state) => state.copyWith(
            paused: true,
            escalationNeeded: true,
            lastResult:
                'Paused after ${state.failureCount} automation failures.',
            lastError: state.lastError ?? 'Automation retry limit reached',
          ),
        );
        stateStore.recordDecision(
          template.id,
          requestedTrigger: trigger,
          resolvedTrigger: trigger,
          status: 'paused',
          reason: 'Paused after ${state.failureCount} automation failures.',
          evidence: state.lastError ?? 'Automation retry limit reached',
          nextRunAt: state.nextRunAt,
        );
        continue;
      }
      final decision = _triggerDecision(template.id, trigger, state.lastRunAt);
      if (!decision.due) {
        if (decision.nextRunAt != null || decision.evidence != null) {
          stateStore.update(
            template.id,
            (state) => state.copyWith(
              nextRunAt: decision.nextRunAt,
              lastTriggerEvidence: decision.evidence,
            ),
          );
        }
        stateStore.recordDecision(
          template.id,
          requestedTrigger: trigger,
          resolvedTrigger: decision.trigger,
          status: 'not_due',
          reason: decision.evidence ?? 'Trigger conditions were not met.',
          evidence: decision.evidence,
          nextRunAt: decision.nextRunAt ?? state.nextRunAt,
        );
        continue;
      }
      final run = runNow(
        template.id,
        trigger: decision.trigger,
        triggerEvidence: decision.evidence,
      );
      runs.add(run);
      if (run.status == 'queued') break;
    }
    return runs;
  }

  GoalAutomationRun runNow(
    GoalTemplateId templateId, {
    String trigger = 'run_now',
    String? triggerEvidence,
  }) {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final runId = '${templateId.wireName}-$startedAt';
    final template = getGoalTemplate(templateId.wireName);
    if (template == null) {
      return GoalAutomationRun(
        runId: runId,
        templateId: templateId,
        trigger: trigger,
        status: 'failed',
        reason: 'Unknown goal template: ${templateId.wireName}',
      );
    }
    if (agent.goalManager.isActive) {
      const reason = 'Skipped because a user-controlled goal is active.';
      stateStore.update(
        templateId,
        (state) => state.copyWith(
          lastRunAt: startedAt,
          lastResult: reason,
          escalationNeeded: true,
        ),
      );
      stateStore.recordDecision(
        templateId,
        at: startedAt,
        requestedTrigger: trigger,
        resolvedTrigger: trigger,
        status: 'skipped',
        reason: reason,
        evidence: triggerEvidence,
        nextRunAt: stateStore.get(templateId).nextRunAt,
        runId: runId,
      );
      return GoalAutomationRun(
        runId: runId,
        templateId: templateId,
        trigger: trigger,
        status: 'skipped',
        reason: reason,
      );
    }

    final context = buildGoalContextPack(
      basePath: basePath,
      templateId: templateId,
      trigger: trigger,
      dataTaskEngine: dataTaskEngine,
      sessionState: {
        'sessionId': agent.sessionManager.currentSession?.id,
        'messageCount': agent.messages.length,
        'queueLength': agent.notificationQueue.length,
      },
      window: templateId == GoalTemplateId.apiErrorTriage
          ? const Duration(minutes: 30)
          : const Duration(days: 1),
    );
    if (templateId == GoalTemplateId.apiErrorTriage &&
        context.pack.recentApiFailures.isEmpty) {
      const reason = 'No recent finance API failures in the last 30 minutes.';
      stateStore.update(
        templateId,
        (state) => state.copyWith(
          lastRunAt: startedAt,
          nextRunAt: _computeNextRunAt(templateId, startedAt),
          lastTrigger: trigger,
          lastTriggerEvidence:
              triggerEvidence ??
              '0 recent finance API failures in the last 30 minutes; api_error_triage skipped.',
          lastCheckpoint: context.path,
          lastResult: reason,
          lastError: null,
          escalationNeeded: false,
        ),
      );
      stateStore.recordDecision(
        templateId,
        at: startedAt,
        requestedTrigger: trigger,
        resolvedTrigger: trigger,
        status: 'skipped',
        reason: reason,
        evidence:
            triggerEvidence ??
            '0 recent finance API failures in the last 30 minutes; api_error_triage skipped.',
        nextRunAt: _computeNextRunAt(templateId, startedAt),
        runId: runId,
      );
      return GoalAutomationRun(
        runId: runId,
        templateId: templateId,
        trigger: trigger,
        status: 'skipped',
        reason: reason,
        contextPackPath: context.path,
      );
    }

    final prompt = buildGoalPrompt(template, contextSummary: context.summary);
    agent.goalManager.set(
      prompt,
      maxTurns: template.defaultMaxTurns,
      options: GoalSetOptions(
        templateId: template.id,
        successCriteria: template.successCriteria,
        checkpoint: context.path,
        contextPackPath: context.path,
        automation: GoalAutomationInfo(
          trigger: trigger,
          runId: runId,
          source: 'goal-automation',
        ),
        verifierResult: GoalVerifierResult(
          status: 'unchecked',
          checkedAt: startedAt,
          reason: 'Goal queued; verifier has not run yet.',
        ),
      ),
    );
    final accepted = agent.notificationQueue.enqueue(
      PendingNotification(
        prompt: prompt,
        priority: NotificationPriority.now,
        source: 'goal-automation',
      ),
    );
    final reason = accepted
        ? 'Queued goal automation.'
        : 'Notification queue rejected goal automation.';
    stateStore.update(
      templateId,
      (state) => state.copyWith(
        lastRunAt: startedAt,
        nextRunAt: _computeNextRunAt(templateId, startedAt),
        lastTrigger: trigger,
        lastTriggerEvidence:
            triggerEvidence ?? _defaultTriggerEvidence(templateId, trigger),
        lastCheckpoint: context.path,
        lastResult: reason,
        lastError: accepted ? null : reason,
        escalationNeeded: !accepted,
        failureCount: accepted ? 0 : state.failureCount + 1,
      ),
    );
    stateStore.recordDecision(
      templateId,
      at: startedAt,
      requestedTrigger: trigger,
      resolvedTrigger: trigger,
      status: accepted ? 'queued' : 'failed',
      reason: reason,
      evidence: triggerEvidence ?? _defaultTriggerEvidence(templateId, trigger),
      nextRunAt: _computeNextRunAt(templateId, startedAt),
      runId: runId,
    );
    return GoalAutomationRun(
      runId: runId,
      templateId: templateId,
      trigger: trigger,
      status: accepted ? 'queued' : 'failed',
      reason: reason,
      contextPackPath: context.path,
    );
  }

  _TriggerDecision _triggerDecision(
    GoalTemplateId templateId,
    String trigger,
    int? lastRunAt,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lastRunAt != null && now - lastRunAt < _minRunGap.inMilliseconds) {
      return _TriggerDecision(
        due: false,
        trigger: trigger,
        evidence: 'Minimum automation run gap is still active.',
        nextRunAt: lastRunAt + _minRunGap.inMilliseconds,
      );
    }
    if (trigger == 'startup') {
      final due =
          templateId == GoalTemplateId.dailyDataHealth ||
          templateId == GoalTemplateId.apiErrorTriage;
      return _TriggerDecision(
        due: due,
        trigger: templateId == GoalTemplateId.apiErrorTriage
            ? 'api_failure_threshold'
            : 'startup',
        evidence: due ? 'Startup scan selected this template.' : null,
      );
    }
    if (trigger == 'market_open' || trigger == 'market_close') {
      return _TriggerDecision(
        due:
            templateId == GoalTemplateId.marketPulseRefresh ||
            templateId == GoalTemplateId.watchlistMonitor,
        trigger: trigger,
        evidence: '$trigger signal received.',
      );
    }
    if (templateId == GoalTemplateId.apiErrorTriage) {
      final count = ApiStats.instance
          .getRecentFailures(range: const Duration(minutes: 30), limit: 80)
          .map((row) => row.toJson())
          .where(isFinanceApiFailure)
          .length;
      return _TriggerDecision(
        due: count >= 3,
        trigger: 'api_failure_threshold',
        evidence: '$count recent finance API failures in the last 30 minutes.',
      );
    }
    if (templateId == GoalTemplateId.dailyDataHealth) {
      return _TriggerDecision(
        due:
            lastRunAt == null ||
            now - lastRunAt >= const Duration(days: 1).inMilliseconds,
        trigger: trigger,
        evidence: 'Daily data health interval elapsed.',
      );
    }
    if (templateId == GoalTemplateId.marketPulseRefresh) {
      final boundary = _marketBoundarySignal(now);
      if (boundary != null) return boundary;
      return _TriggerDecision(
        due:
            lastRunAt == null ||
            now - lastRunAt >= const Duration(minutes: 30).inMilliseconds,
        trigger: 'stale_data',
        evidence: 'Market pulse refresh interval elapsed.',
      );
    }
    if (templateId == GoalTemplateId.watchlistMonitor) {
      final watchlist = _watchlistSignal();
      return _TriggerDecision(
        due:
            watchlist.hasActiveInputs &&
            (lastRunAt == null ||
                now - lastRunAt >= const Duration(minutes: 15).inMilliseconds),
        trigger: 'watchlist_condition',
        evidence: watchlist.evidence,
      );
    }
    if (templateId == GoalTemplateId.dashboardRefresh ||
        templateId == GoalTemplateId.reportGeneration) {
      return _TriggerDecision(
        due:
            lastRunAt == null ||
            now - lastRunAt >= const Duration(days: 1).inMilliseconds,
        trigger: trigger,
        evidence: 'Daily artifact refresh interval elapsed.',
      );
    }
    return _TriggerDecision(due: false, trigger: trigger);
  }

  String _defaultTriggerEvidence(GoalTemplateId templateId, String trigger) {
    if (trigger == 'run_now') return 'User requested Run Now.';
    return '${templateId.wireName} triggered by $trigger.';
  }

  _WatchlistSignal _watchlistSignal() {
    final active = _readWatchlistItems(basePath)
        .where(
          (item) =>
              item['status'] != 'exited' &&
              '${item['symbol'] ?? item['code'] ?? ''}'.trim().isNotEmpty,
        )
        .toList();
    final withRules = active.where((item) {
      final conditions = item['conditions'];
      final hasPendingCondition =
          conditions is List &&
          conditions.any((cond) => cond is Map && cond['triggered'] != true);
      return hasPendingCondition ||
          item['targetEntryPrice'] != null ||
          item['stopLoss'] != null ||
          item['targetPrice'] != null;
    }).length;
    if (withRules > 0) {
      return _WatchlistSignal(
        hasActiveInputs: true,
        evidence: '$withRules active watchlist items have monitor rules.',
      );
    }
    if (active.isNotEmpty) {
      return _WatchlistSignal(
        hasActiveInputs: true,
        evidence:
            '${active.length} active watchlist items are available for monitoring summary.',
      );
    }
    return const _WatchlistSignal(
      hasActiveInputs: false,
      evidence:
          'No active watchlist items found; watchlist monitor not scheduled.',
    );
  }

  int? _computeNextRunAt(GoalTemplateId templateId, int from) {
    return switch (templateId) {
      GoalTemplateId.apiErrorTriage => from + _minRunGap.inMilliseconds,
      GoalTemplateId.marketPulseRefresh =>
        from + const Duration(minutes: 30).inMilliseconds,
      GoalTemplateId.watchlistMonitor =>
        from + const Duration(minutes: 15).inMilliseconds,
      GoalTemplateId.dailyDataHealth ||
      GoalTemplateId.dashboardRefresh ||
      GoalTemplateId.reportGeneration =>
        from + const Duration(days: 1).inMilliseconds,
      GoalTemplateId.providerContractProbe => null,
    };
  }
}

class _TriggerDecision {
  final bool due;
  final String trigger;
  final String? evidence;
  final int? nextRunAt;

  const _TriggerDecision({
    required this.due,
    required this.trigger,
    this.evidence,
    this.nextRunAt,
  });
}

class _WatchlistSignal {
  final bool hasActiveInputs;
  final String evidence;

  const _WatchlistSignal({
    required this.hasActiveInputs,
    required this.evidence,
  });
}

List<Map<String, dynamic>> _readWatchlistItems(String basePath) {
  final paths = [
    '$basePath/watchlists.json',
    '$basePath/memory/watchlists.json',
    '$basePath/memory/watchlist.json',
    '$basePath/fund_watchlists.json',
    '$basePath/memory/fund_watchlists.json',
    '$basePath/memory/fund-watchlist.json',
  ];
  final out = <Map<String, dynamic>>[];
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final data = jsonDecode(file.readAsStringSync());
      final items = data is Map ? data['items'] : null;
      if (items is List) {
        out.addAll(
          items.whereType<Map>().map((item) {
            return item.map((key, value) => MapEntry('$key', value));
          }),
        );
      }
    } catch (_) {}
  }
  return out;
}

_TriggerDecision? _marketBoundarySignal(int nowMs) {
  final bj = DateTime.fromMillisecondsSinceEpoch(
    nowMs,
    isUtc: true,
  ).add(const Duration(hours: 8));
  if (bj.weekday == DateTime.saturday || bj.weekday == DateTime.sunday) {
    return null;
  }
  final minutes = bj.hour * 60 + bj.minute;
  if (minutes >= 9 * 60 + 30 && minutes < 9 * 60 + 40) {
    return const _TriggerDecision(
      due: true,
      trigger: 'market_open',
      evidence: 'A-share market open window in Beijing time.',
    );
  }
  if (minutes >= 15 * 60 && minutes < 15 * 60 + 10) {
    return const _TriggerDecision(
      due: true,
      trigger: 'market_close',
      evidence: 'A-share market close window in Beijing time.',
    );
  }
  return null;
}
