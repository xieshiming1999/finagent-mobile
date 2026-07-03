enum GoalTemplateId {
  apiErrorTriage,
  dailyDataHealth,
  marketPulseRefresh,
  watchlistMonitor,
  dashboardRefresh,
  reportGeneration,
  providerContractProbe,
}

extension GoalTemplateIdWire on GoalTemplateId {
  String get wireName => switch (this) {
    GoalTemplateId.apiErrorTriage => 'api_error_triage',
    GoalTemplateId.dailyDataHealth => 'daily_data_health',
    GoalTemplateId.marketPulseRefresh => 'market_pulse_refresh',
    GoalTemplateId.watchlistMonitor => 'watchlist_monitor',
    GoalTemplateId.dashboardRefresh => 'dashboard_refresh',
    GoalTemplateId.reportGeneration => 'report_generation',
    GoalTemplateId.providerContractProbe => 'provider_contract_probe',
  };

  static GoalTemplateId? parse(String value) {
    for (final id in GoalTemplateId.values) {
      if (id.wireName == value) return id;
    }
    return null;
  }
}

class GoalVerifierResult {
  final String status;
  final int checkedAt;
  final String reason;
  final List<String> evidence;

  const GoalVerifierResult({
    required this.status,
    required this.checkedAt,
    required this.reason,
    this.evidence = const [],
  });

  Map<String, dynamic> toJson() => {
    'status': status,
    'checkedAt': checkedAt,
    'reason': reason,
    'evidence': evidence,
  };

  factory GoalVerifierResult.fromJson(Map<String, dynamic> json) =>
      GoalVerifierResult(
        status: json['status'] as String? ?? 'unchecked',
        checkedAt: (json['checkedAt'] as num?)?.toInt() ?? 0,
        reason: json['reason'] as String? ?? '',
        evidence:
            (json['evidence'] as List<dynamic>?)?.cast<String>() ?? const [],
      );
}

class GoalAutomationInfo {
  final String trigger;
  final String runId;
  final String source;

  const GoalAutomationInfo({
    required this.trigger,
    required this.runId,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
    'trigger': trigger,
    'runId': runId,
    'source': source,
  };

  factory GoalAutomationInfo.fromJson(Map<String, dynamic> json) =>
      GoalAutomationInfo(
        trigger: json['trigger'] as String? ?? 'manual',
        runId: json['runId'] as String? ?? '',
        source: json['source'] as String? ?? '',
      );
}

class GoalArtifact {
  final String objective;
  final String source;
  final String? planSnapshot;
  final String? scope;
  final List<String> doneCriteria;
  final List<String> allowedTools;
  final String? verification;
  final String? escalation;
  final int createdAt;
  final int updatedAt;

  const GoalArtifact({
    required this.objective,
    required this.source,
    this.planSnapshot,
    this.scope,
    this.doneCriteria = const [],
    this.allowedTools = const [],
    this.verification,
    this.escalation,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'objective': objective,
    'source': source,
    'planSnapshot': planSnapshot,
    'scope': scope,
    'doneCriteria': doneCriteria,
    'allowedTools': allowedTools,
    'verification': verification,
    'escalation': escalation,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory GoalArtifact.fromJson(
    Map<String, dynamic> json, {
    required String fallbackObjective,
    required int fallbackTime,
  }) => GoalArtifact(
    objective: _stringOr(json['objective'], fallbackObjective),
    source: _stringOr(json['source'], 'goal-command'),
    planSnapshot: _optionalString(json['planSnapshot']),
    scope: _optionalString(json['scope']),
    doneCriteria: _stringList(json['doneCriteria']),
    allowedTools: _stringList(json['allowedTools']),
    verification: _optionalString(json['verification']),
    escalation: _optionalString(json['escalation']),
    createdAt: (json['createdAt'] as num?)?.toInt() ?? fallbackTime,
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? fallbackTime,
  );
}

class GoalWorkPacket {
  final String? targetArtifact;
  final String currentGap;
  final List<String> evidence;
  final String? implementationScope;
  final String progressKind;
  final String? progressSummary;
  final String nextPrompt;
  final String verification;
  final String stopCondition;
  final String escalationCondition;
  final int createdAt;
  final int turn;

  const GoalWorkPacket({
    this.targetArtifact,
    required this.currentGap,
    this.evidence = const [],
    this.implementationScope,
    this.progressKind = 'unknown',
    this.progressSummary,
    required this.nextPrompt,
    required this.verification,
    required this.stopCondition,
    required this.escalationCondition,
    required this.createdAt,
    required this.turn,
  });

  Map<String, dynamic> toJson() => {
    'targetArtifact': targetArtifact,
    'currentGap': currentGap,
    'evidence': evidence,
    'implementationScope': implementationScope,
    'progressKind': progressKind,
    'progressSummary': progressSummary,
    'nextPrompt': nextPrompt,
    'verification': verification,
    'stopCondition': stopCondition,
    'escalationCondition': escalationCondition,
    'createdAt': createdAt,
    'turn': turn,
  };

  factory GoalWorkPacket.fromJson(Map<String, dynamic> json) => GoalWorkPacket(
    targetArtifact: _optionalString(json['targetArtifact']),
    currentGap: _stringOr(
      json['currentGap'],
      'The goal has not been verified as complete.',
    ),
    evidence: _stringList(json['evidence']),
    implementationScope: _optionalString(json['implementationScope']),
    progressKind: _progressKind(json['progressKind']),
    progressSummary: _optionalString(json['progressSummary']),
    nextPrompt: _stringOr(
      json['nextPrompt'],
      'Execute the next concrete step.',
    ),
    verification: _stringOr(
      json['verification'],
      'Verify the result against the goal.',
    ),
    stopCondition: _stringOr(
      json['stopCondition'],
      'Stop when completion is proven.',
    ),
    escalationCondition: _stringOr(
      json['escalationCondition'],
      'Escalate when user input or unsafe side effects are needed.',
    ),
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    turn: (json['turn'] as num?)?.toInt() ?? 0,
  );
}

class GoalSetOptions {
  final GoalTemplateId? templateId;
  final List<String> successCriteria;
  final String? checkpoint;
  final GoalVerifierResult? verifierResult;
  final GoalAutomationInfo? automation;
  final String? contextPackPath;
  final int? tokenBudget;
  final String? source;
  final String? planSnapshot;
  final String? scope;
  final List<String> doneCriteria;
  final List<String> allowedTools;
  final String? verification;
  final String? escalation;
  final GoalArtifact? goalArtifact;

  const GoalSetOptions({
    this.templateId,
    this.successCriteria = const [],
    this.checkpoint,
    this.verifierResult,
    this.automation,
    this.contextPackPath,
    this.tokenBudget,
    this.source,
    this.planSnapshot,
    this.scope,
    this.doneCriteria = const [],
    this.allowedTools = const [],
    this.verification,
    this.escalation,
    this.goalArtifact,
  });
}

class GoalTemplate {
  final GoalTemplateId id;
  final String title;
  final String objective;
  final int defaultMaxTurns;
  final bool persistentDuty;
  final List<String> successCriteria;
  final List<String> contextNeeds;
  final List<String> guardrails;
  final List<String> verifierChecks;

  const GoalTemplate({
    required this.id,
    required this.title,
    required this.objective,
    required this.defaultMaxTurns,
    this.persistentDuty = false,
    required this.successCriteria,
    required this.contextNeeds,
    required this.guardrails,
    required this.verifierChecks,
  });
}

String? _optionalString(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _stringOr(dynamic value, String fallback) =>
    _optionalString(value) ?? fallback;

String _progressKind(dynamic value) {
  final text = _optionalString(value);
  const allowed = {
    'unknown',
    'progress_only',
    'implementation',
    'verification',
    'blocked',
  };
  return allowed.contains(text) ? text! : 'unknown';
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}
