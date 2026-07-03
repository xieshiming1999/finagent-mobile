import 'dart:convert';
import 'dart:io';

import 'artifact_registry.dart';
import 'goal_automation_types.dart';
import 'goal_manager.dart';

Future<GoalVerifierResult> verifyGoalState(
  GoalState state,
  GoalJudgment judgment, {
  String? basePath,
}) async {
  final checkedAt = DateTime.now().millisecondsSinceEpoch;
  if (state.templateId == null && state.automation == null) {
    return GoalVerifierResult(
      status: 'passed',
      checkedAt: checkedAt,
      reason: 'Manual non-template goal has no automation verifier contract.',
    );
  }
  final contextPath = state.contextPackPath;
  if (contextPath == null || !File(contextPath).existsSync()) {
    return GoalVerifierResult(
      status: 'failed',
      checkedAt: checkedAt,
      reason: 'Goal automation context pack is missing.',
      evidence: [if (contextPath != null) contextPath],
    );
  }
  final contextPack = _readContextPack(contextPath);
  if (contextPack == null) {
    return GoalVerifierResult(
      status: 'failed',
      checkedAt: checkedAt,
      reason: 'Goal automation context pack is not valid JSON.',
      evidence: [contextPath],
    );
  }
  if (judgment.safetyBoundary == 'approved_side_effect') {
    return GoalVerifierResult(
      status: 'failed',
      checkedAt: checkedAt,
      reason: 'Goal automation templates do not authorize side effects.',
      evidence: [contextPath],
    );
  }

  final refs = _validatedEvidenceRefs(
    state,
    judgment.evidence,
    basePath: basePath,
  );
  if (refs.isEmpty) {
    return GoalVerifierResult(
      status: 'failed',
      checkedAt: checkedAt,
      reason:
          'Typed goal judgment did not provide a verifiable context, file, or artifact reference.',
      evidence: [contextPath],
    );
  }

  switch (state.templateId) {
    case GoalTemplateId.apiErrorTriage:
    case GoalTemplateId.providerContractProbe:
      final failures = contextPack['recentApiFailures'];
      final classes = contextPack['recentApiFailureClasses'];
      return _result(
        _hasRows(failures) && _hasRows(classes),
        checkedAt,
        refs,
        passedReason:
            'Typed API failure rows and failure-class records are present.',
        failedReason:
            'Verifier requires typed API failure rows and failure-class records.',
      );
    case GoalTemplateId.dailyDataHealth:
      return _result(
        _hasRows(contextPack['dataCoverage']) ||
            _hasRows(contextPack['providerHealth']) ||
            _hasRows(contextPack['activeTasks']),
        checkedAt,
        refs,
        passedReason:
            'Typed data-health context and evidence references are present.',
        failedReason: 'Verifier requires typed data-health context.',
      );
    case GoalTemplateId.dashboardRefresh:
    case GoalTemplateId.reportGeneration:
      final kinds = state.templateId == GoalTemplateId.dashboardRefresh
          ? const {ArtifactKind.dashboard}
          : const {ArtifactKind.report};
      final artifactRefs = _matchingArtifactRefs(
        state,
        judgment.evidence,
        kinds,
        basePath,
      );
      return _result(
        artifactRefs.isNotEmpty &&
            (_hasRows(contextPack['dataCoverage']) ||
                _hasRows(contextPack['providerHealth'])),
        checkedAt,
        {...refs, ...artifactRefs}.toList(),
        passedReason:
            'A current typed output artifact and data-source context are present.',
        failedReason:
            'Verifier requires a current typed output artifact and data-source context.',
      );
    case GoalTemplateId.marketPulseRefresh:
    case GoalTemplateId.watchlistMonitor:
      return _result(
        _hasRows(contextPack['dataCoverage']) ||
            _hasWatchlistRows(contextPack['watchlists']) ||
            _hasRows(contextPack['providerHealth']),
        checkedAt,
        refs,
        passedReason:
            'Typed market/watchlist context and evidence references are present.',
        failedReason: 'Verifier requires typed market or watchlist context.',
      );
    case null:
      return GoalVerifierResult(
        status: 'passed',
        checkedAt: checkedAt,
        reason: 'Typed context and evidence-reference checks passed.',
        evidence: refs,
      );
  }
}

GoalVerifierResult _result(
  bool ok,
  int checkedAt,
  List<String> evidence, {
  required String passedReason,
  required String failedReason,
}) => GoalVerifierResult(
  status: ok ? 'passed' : 'failed',
  checkedAt: checkedAt,
  reason: ok ? passedReason : failedReason,
  evidence: evidence,
);

Map<String, dynamic>? _readContextPack(String path) {
  try {
    final data = jsonDecode(File(path).readAsStringSync());
    return data is Map<String, dynamic> ? data : null;
  } catch (_) {
    return null;
  }
}

List<String> _validatedEvidenceRefs(
  GoalState state,
  List<String> refs, {
  String? basePath,
}) {
  final artifacts = basePath == null
      ? const <ArtifactRecord>[]
      : ArtifactRegistry(basePath).list();
  return refs
      .where((ref) {
        if (ref == state.contextPackPath || ref == state.checkpoint)
          return true;
        if (File(ref).existsSync()) return true;
        return artifacts.any(
          (record) =>
              ref == record.id || ref == record.stableRef || ref == record.path,
        );
      })
      .toSet()
      .toList();
}

List<String> _matchingArtifactRefs(
  GoalState state,
  List<String> refs,
  Set<ArtifactKind> kinds,
  String? basePath,
) {
  if (basePath == null) return const [];
  final goalStart = DateTime.fromMillisecondsSinceEpoch(state.createdAt);
  return ArtifactRegistry(basePath)
      .list()
      .where(
        (record) =>
            kinds.contains(record.kind) &&
            !record.createdAt.isBefore(goalStart) &&
            File(record.path).existsSync() &&
            refs.any(
              (ref) =>
                  ref == record.id ||
                  ref == record.stableRef ||
                  ref == record.path,
            ),
      )
      .map((record) => record.stableRef)
      .toList();
}

bool _hasRows(Object? value) {
  if (value is List) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return false;
}

bool _hasWatchlistRows(Object? value) {
  if (value is! Map) return false;
  for (final list in value.values) {
    if (list is List && list.isNotEmpty) return true;
    if (list is Map &&
        list['items'] is List &&
        (list['items'] as List).isNotEmpty) {
      return true;
    }
  }
  return false;
}
