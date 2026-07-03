import 'dart:convert';
import 'dart:io';

import 'goal_automation_types.dart';

class GoalLoopState {
  final GoalTemplateId templateId;
  final bool enabled;
  final bool paused;
  final int? lastRunAt;
  final int? nextRunAt;
  final String? lastTrigger;
  final String? lastTriggerEvidence;
  final String? lastCheckpoint;
  final String? lastError;
  final bool escalationNeeded;
  final String? lastResult;
  final int failureCount;
  final List<GoalTriggerLedgerEntry> triggerLedger;

  const GoalLoopState({
    required this.templateId,
    this.enabled = false,
    this.paused = false,
    this.lastRunAt,
    this.nextRunAt,
    this.lastTrigger,
    this.lastTriggerEvidence,
    this.lastCheckpoint,
    this.lastError,
    this.escalationNeeded = false,
    this.lastResult,
    this.failureCount = 0,
    this.triggerLedger = const [],
  });

  GoalLoopState copyWith({
    bool? enabled,
    bool? paused,
    int? lastRunAt,
    int? nextRunAt,
    String? lastTrigger,
    String? lastTriggerEvidence,
    String? lastCheckpoint,
    String? lastError,
    bool? escalationNeeded,
    String? lastResult,
    int? failureCount,
    List<GoalTriggerLedgerEntry>? triggerLedger,
  }) => GoalLoopState(
    templateId: templateId,
    enabled: enabled ?? this.enabled,
    paused: paused ?? this.paused,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    nextRunAt: nextRunAt ?? this.nextRunAt,
    lastTrigger: lastTrigger ?? this.lastTrigger,
    lastTriggerEvidence: lastTriggerEvidence ?? this.lastTriggerEvidence,
    lastCheckpoint: lastCheckpoint ?? this.lastCheckpoint,
    lastError: lastError,
    escalationNeeded: escalationNeeded ?? this.escalationNeeded,
    lastResult: lastResult ?? this.lastResult,
    failureCount: failureCount ?? this.failureCount,
    triggerLedger: triggerLedger ?? this.triggerLedger,
  );

  Map<String, dynamic> toJson() => {
    'templateId': templateId.wireName,
    'enabled': enabled,
    'paused': paused,
    'lastRunAt': lastRunAt,
    'nextRunAt': nextRunAt,
    'lastTrigger': lastTrigger,
    'lastTriggerEvidence': lastTriggerEvidence,
    'lastCheckpoint': lastCheckpoint,
    'lastError': lastError,
    'escalationNeeded': escalationNeeded,
    'lastResult': lastResult,
    'failureCount': failureCount,
    'triggerLedger': triggerLedger.map((entry) => entry.toJson()).toList(),
  };

  factory GoalLoopState.fromJson(Map<String, dynamic> json) => GoalLoopState(
    templateId:
        GoalTemplateIdWire.parse(json['templateId'] as String? ?? '') ??
        GoalTemplateId.apiErrorTriage,
    enabled: json['enabled'] as bool? ?? false,
    paused: json['paused'] as bool? ?? false,
    lastRunAt: (json['lastRunAt'] as num?)?.toInt(),
    nextRunAt: (json['nextRunAt'] as num?)?.toInt(),
    lastTrigger: json['lastTrigger'] as String?,
    lastTriggerEvidence: json['lastTriggerEvidence'] as String?,
    lastCheckpoint: json['lastCheckpoint'] as String?,
    lastError: json['lastError'] as String?,
    escalationNeeded: json['escalationNeeded'] as bool? ?? false,
    lastResult: json['lastResult'] as String?,
    failureCount: (json['failureCount'] as num?)?.toInt() ?? 0,
    triggerLedger: _parseLedger(json['triggerLedger']),
  );
}

class GoalTriggerLedgerEntry {
  final int at;
  final GoalTemplateId templateId;
  final String requestedTrigger;
  final String resolvedTrigger;
  final String status;
  final String reason;
  final String? evidence;
  final int? nextRunAt;
  final String? runId;
  final int repeatCount;

  const GoalTriggerLedgerEntry({
    required this.at,
    required this.templateId,
    required this.requestedTrigger,
    required this.resolvedTrigger,
    required this.status,
    required this.reason,
    this.evidence,
    this.nextRunAt,
    this.runId,
    this.repeatCount = 1,
  });

  GoalTriggerLedgerEntry copyWith({
    int? at,
    int? nextRunAt,
    String? runId,
    int? repeatCount,
  }) => GoalTriggerLedgerEntry(
    at: at ?? this.at,
    templateId: templateId,
    requestedTrigger: requestedTrigger,
    resolvedTrigger: resolvedTrigger,
    status: status,
    reason: reason,
    evidence: evidence,
    nextRunAt: nextRunAt ?? this.nextRunAt,
    runId: runId ?? this.runId,
    repeatCount: repeatCount ?? this.repeatCount,
  );

  Map<String, dynamic> toJson() => {
    'at': at,
    'templateId': templateId.wireName,
    'requestedTrigger': requestedTrigger,
    'resolvedTrigger': resolvedTrigger,
    'status': status,
    'reason': reason,
    'evidence': evidence,
    'nextRunAt': nextRunAt,
    'runId': runId,
    'repeatCount': repeatCount,
  };

  factory GoalTriggerLedgerEntry.fromJson(Map<String, dynamic> json) {
    final templateId =
        GoalTemplateIdWire.parse(json['templateId'] as String? ?? '') ??
        GoalTemplateId.apiErrorTriage;
    return GoalTriggerLedgerEntry(
      at: (json['at'] as num?)?.toInt() ?? 0,
      templateId: templateId,
      requestedTrigger: json['requestedTrigger'] as String? ?? '',
      resolvedTrigger:
          json['resolvedTrigger'] as String? ??
          json['requestedTrigger'] as String? ??
          '',
      status: _normalizeStatus(json['status'] as String?),
      reason: json['reason'] as String? ?? '',
      evidence: json['evidence'] as String?,
      nextRunAt: (json['nextRunAt'] as num?)?.toInt(),
      runId: json['runId'] as String?,
      repeatCount: (json['repeatCount'] as num?)?.toInt() ?? 1,
    );
  }
}

class GoalAutomationStateStore {
  final String basePath;
  final Map<GoalTemplateId, GoalLoopState> _states = {};
  static const int _maxLedgerEntries = 30;
  static const Duration _ledgerDedupeWindow = Duration(minutes: 5);

  GoalAutomationStateStore(this.basePath) {
    _load();
  }

  String get _path => '$basePath/memory/goal-automation-state.json';

  List<GoalLoopState> list() {
    for (final id in GoalTemplateId.values) {
      get(id);
    }
    return GoalTemplateId.values.map(get).toList();
  }

  GoalLoopState get(GoalTemplateId templateId) => _states.putIfAbsent(
    templateId,
    () => GoalLoopState(templateId: templateId),
  );

  GoalLoopState update(
    GoalTemplateId templateId,
    GoalLoopState Function(GoalLoopState state) update,
  ) {
    final next = update(get(templateId));
    _states[templateId] = next;
    _save();
    return next;
  }

  GoalLoopState recordDecision(
    GoalTemplateId templateId, {
    required String requestedTrigger,
    required String resolvedTrigger,
    required String status,
    required String reason,
    String? evidence,
    int? nextRunAt,
    String? runId,
    int? at,
  }) {
    final state = get(templateId);
    final now = at ?? DateTime.now().millisecondsSinceEpoch;
    final entry = GoalTriggerLedgerEntry(
      at: now,
      templateId: templateId,
      requestedTrigger: requestedTrigger,
      resolvedTrigger: resolvedTrigger,
      status: _normalizeStatus(status),
      reason: reason,
      evidence: evidence,
      nextRunAt: nextRunAt,
      runId: runId,
    );
    final ledger = List<GoalTriggerLedgerEntry>.from(state.triggerLedger);
    if (ledger.isNotEmpty &&
        now - ledger.first.at <= _ledgerDedupeWindow.inMilliseconds &&
        _sameDecision(ledger.first, entry)) {
      ledger[0] = ledger.first.copyWith(
        at: now,
        nextRunAt: entry.nextRunAt,
        runId: entry.runId ?? ledger.first.runId,
        repeatCount: ledger.first.repeatCount + 1,
      );
    } else {
      ledger.insert(0, entry);
    }
    return update(
      templateId,
      (state) => state.copyWith(
        triggerLedger: ledger.take(_maxLedgerEntries).toList(),
      ),
    );
  }

  void _load() {
    final file = File(_path);
    if (!file.existsSync()) return;
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final value in data.values) {
        if (value is! Map<String, dynamic>) continue;
        final state = GoalLoopState.fromJson(value);
        _states[state.templateId] = state;
      }
    } catch (_) {}
  }

  void _save() {
    final file = File(_path);
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        for (final entry in _states.entries)
          entry.key.wireName: entry.value.toJson(),
      }),
    );
  }
}

List<GoalTriggerLedgerEntry> _parseLedger(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (entry) => GoalTriggerLedgerEntry.fromJson(
          entry.map((key, value) => MapEntry('$key', value)),
        ),
      )
      .where(
        (entry) =>
            entry.at > 0 &&
            entry.requestedTrigger.isNotEmpty &&
            entry.resolvedTrigger.isNotEmpty &&
            entry.reason.isNotEmpty,
      )
      .toList();
}

bool _sameDecision(GoalTriggerLedgerEntry a, GoalTriggerLedgerEntry b) =>
    a.requestedTrigger == b.requestedTrigger &&
    a.resolvedTrigger == b.resolvedTrigger &&
    a.status == b.status &&
    a.reason == b.reason &&
    a.evidence == b.evidence;

String _normalizeStatus(String? value) {
  const allowed = {'not_due', 'queued', 'skipped', 'failed', 'paused'};
  return allowed.contains(value) ? value! : 'skipped';
}
