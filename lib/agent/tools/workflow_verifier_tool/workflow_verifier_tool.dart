import 'dart:convert';
import 'dart:io';

import '../../artifact_registry.dart';
import '../../interaction_evidence.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

const _workflows = <String, Map<String, dynamic>>{
  'market_overview': {
    'requiredAnyTools': ['MarketData', 'DataStore', 'Research'],
    'artifactKinds': ['analysis', 'dashboard', 'data_snapshot'],
    'approvalBoundary': 'no_trade',
  },
  'stock_research': {
    'requiredAnyTools': ['MarketData', 'DataStore', 'DataProcess', 'Research'],
    'artifactKinds': ['analysis', 'dashboard', 'data_snapshot'],
    'approvalBoundary': 'no_trade',
  },
  'fund_selection': {
    'requiredAnyTools': ['MarketData', 'DataStore', 'DataProcess', 'Research'],
    'artifactKinds': ['analysis', 'data_snapshot'],
    'approvalBoundary': 'no_trade',
  },
  'strategy_backtest': {
    'requiredAnyTools': ['DataProcess', 'MarketData'],
    'artifactKinds': ['strategy', 'backtest', 'report'],
    'approvalBoundary': 'no_trade',
  },
  'trade_preparation': {
    'requiredAnyTools': ['Portfolio', 'XueqiuTrade', 'AskUserQuestion'],
    'artifactKinds': ['trade_preparation', 'analysis'],
    'approvalBoundary': 'explicit_approval_required',
  },
};

class WorkflowVerifierTool extends Tool {
  @override
  String get name => 'WorkflowVerifier';

  @override
  String get description =>
      'Verify whether a workflow has enough structured evidence before the agent finalizes a claim or proceeds to a boundary.';

  @override
  String get prompt =>
      'Use WorkflowVerifier(action:"check", workflow:"...") before final answers for broad finance workflows. It checks structured tool/session/artifact evidence and returns missing evidence plus recovery guidance.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'list', 'check'],
      },
      'workflow': {'type': 'string', 'enum': _workflows.keys.toList()},
      'artifactId': {
        'type': 'string',
        'description':
            'Optional artifact id/stable ref to require for this check.',
      },
      'workflowStateId': {
        'type': 'string',
        'description':
            'Optional saved FinanceWorkflowState id to require for this check.',
      },
      'requireWorkflowState': {
        'type': 'boolean',
        'description':
            'Require a saved typed workflow-state record that matches this workflow family.',
      },
      'providerHealth': {
        'type': 'array',
        'items': {'type': 'object'},
        'description':
            'Optional provider-health rows from ProviderRouter/API health/probes. Blocking statuses fail this verifier check.',
      },
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100},
    },
  };

  @override
  bool get isReadOnly => true;

  @override
  bool get canParallel => true;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = (input['action'] as String?)?.trim() ?? 'list';
    if (action == 'help') {
      return ToolResult(toolUseId: toolUseId, content: jsonEncode(_help()));
    }
    if (action == 'list') {
      return ToolResult(
        toolUseId: toolUseId,
        content: jsonEncode({
          'contract': 'workflow-verifier-list-v1',
          'workflows': _workflows.keys.toList(),
          'guidance':
              'Call WorkflowVerifier(action:"check", workflow:<id>) before final workflow claims.',
        }),
      );
    }
    if (action != 'check') {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid WorkflowVerifier action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }
    final workflow = (input['workflow'] as String?)?.trim() ?? '';
    final spec = _workflows[workflow];
    if (spec == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Unknown WorkflowVerifier workflow "$workflow". Use action="list" to inspect available workflows.',
        isError: true,
      );
    }
    final limit = _intValue(input['limit'], defaultValue: 50).clamp(1, 100);
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode(
        _checkWorkflow(
          context,
          workflow: workflow,
          spec: spec,
          artifactId: (input['artifactId'] as String?)?.trim(),
          workflowStateId: (input['workflowStateId'] as String?)?.trim(),
          requireWorkflowState: input['requireWorkflowState'] == true,
          providerHealth: input['providerHealth'],
          limit: limit,
        ),
      ),
    );
  }

  Map<String, dynamic> _help() => {
    'contract': 'workflow-verifier-help-v1',
    'actions': ['list', 'check'],
    'workflows': _workflows.keys.toList(),
    'checks': [
      'tool_calls_present',
      'required_tool_family',
      'no_tool_errors',
      'no_pending_interactions',
      'artifact_evidence',
      'approval_boundary',
      'workflow_state',
      'provider_health',
    ],
    'guidance': [
      'This tool checks structured session, interaction, and artifact evidence.',
      'It does not parse the user prompt to infer intent.',
      'If a check fails, collect evidence, register an artifact, resolve pending input, or stop at the approval boundary.',
    ],
  };
}

Map<String, dynamic> _checkWorkflow(
  ToolContext context, {
  required String workflow,
  required Map<String, dynamic> spec,
  required String? artifactId,
  required String? workflowStateId,
  required bool requireWorkflowState,
  required Object? providerHealth,
  required int limit,
}) {
  final session = _readSession(context, limit);
  final pending = readPendingInteractionState(context);
  final artifactEvidence = _artifactEvidence(context, spec, artifactId);
  final workflowStateEvidence = _workflowStateEvidence(
    context,
    workflow: workflow,
    workflowStateId: workflowStateId,
    required: requireWorkflowState || workflowStateId != null,
  );
  final providerHealthEvidence = _providerHealthEvidence(providerHealth);
  final requiredAnyTools = _stringList(spec['requiredAnyTools']);
  final toolNames = (session['toolNames'] as List).whereType<String>().toSet();
  final usedRequiredTool = requiredAnyTools.any(toolNames.contains);
  final approvalBoundary = spec['approvalBoundary'] as String? ?? 'none';
  final checks = [
    _check(
      'tool_calls_present',
      (session['toolCallCount'] as int) > 0,
      'At least one tool call is visible.',
      'No tool call is visible for this workflow.',
    ),
    _check(
      'required_tool_family',
      usedRequiredTool,
      'A required tool family was used.',
      'No required tool family was used. Expected one of: ${requiredAnyTools.join(', ')}.',
    ),
    _check(
      'no_tool_errors',
      (session['toolErrorCount'] as int) == 0,
      'No tool errors are visible.',
      '${session['toolErrorCount']} tool error(s) are visible.',
    ),
    _check(
      'no_pending_interactions',
      pending.isEmpty,
      'No pending AskUserQuestion or approval is visible.',
      '${pending.length} pending interaction(s) must be resolved before finalizing.',
    ),
    _check(
      'artifact_evidence',
      artifactEvidence['passed'] == true,
      'Required artifact evidence is registered.',
      artifactEvidence['reason'] as String? ??
          'Required artifact evidence is missing.',
    ),
    _check(
      'approval_boundary',
      approvalBoundary != 'explicit_approval_required' || pending.isNotEmpty,
      approvalBoundary == 'explicit_approval_required'
          ? 'Trade-preparation boundary is explicit: approval or user question is pending.'
          : 'Workflow has no trade approval boundary.',
      'Trade-preparation workflow requires explicit approval evidence before any side-effect.',
    ),
    _check(
      'workflow_state',
      workflowStateEvidence['passed'] == true,
      workflowStateEvidence['passedMessage'] as String? ??
          'Typed workflow state is valid.',
      workflowStateEvidence['reason'] as String? ??
          'Typed workflow state is missing or invalid.',
    ),
    _check(
      'provider_health',
      providerHealthEvidence['passed'] == true,
      providerHealthEvidence['passedMessage'] as String? ??
          'Provider health is valid.',
      providerHealthEvidence['reason'] as String? ??
          'Provider health contains blocking evidence.',
    ),
  ];
  final missing = checks
      .where((check) => check['passed'] != true)
      .map((check) => check['id'])
      .toList();
  return {
    'contract': 'workflow-verifier-check-v1',
    'workflow': workflow,
    'passed': missing.isEmpty,
    'missing': missing,
    'checks': checks,
    'observed': {
      'toolNames': toolNames.toList()..sort(),
      'pendingInteractions': pending.length,
      'artifact': artifactEvidence['artifact'],
      'workflowState': workflowStateEvidence['record'],
      'providerHealth': providerHealthEvidence['observed'],
    },
    'nextAction': missing.isEmpty
        ? 'Final answer may cite the verified workflow evidence.'
        : 'Do not finalize yet. Resolve missing checks: ${missing.join(', ')}.',
  };
}

Map<String, dynamic> _readSession(ToolContext context, int limit) {
  final file = File('${context.basePath}/sessions/current.jsonl');
  if (!file.existsSync()) {
    return {'toolCallCount': 0, 'toolErrorCount': 0, 'toolNames': <String>[]};
  }
  final toolNames = <String>{};
  var toolCallCount = 0;
  var toolErrorCount = 0;
  for (final line in file.readAsLinesSync().take(limit)) {
    final text = line.trim();
    if (text.isEmpty) continue;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) continue;
      final toolUses = decoded['toolUses'];
      if (toolUses is List) {
        toolCallCount += toolUses.length;
        for (final item in toolUses) {
          if (item is Map && item['name'] is String)
            toolNames.add(item['name']);
        }
      }
      final result = decoded['toolResult'] ?? decoded['tool_result'];
      if (result is Map && result['isError'] == true) toolErrorCount++;
    } catch (_) {
      continue;
    }
  }
  return {
    'toolCallCount': toolCallCount,
    'toolErrorCount': toolErrorCount,
    'toolNames': toolNames.toList(),
  };
}

Map<String, dynamic> _artifactEvidence(
  ToolContext context,
  Map<String, dynamic> spec,
  String? artifactId,
) {
  final registry = ArtifactRegistry(context.basePath);
  final artifacts = registry.list();
  final normalizedId = artifactId != null && artifactId.startsWith('artifact:')
      ? artifactId.substring(9)
      : artifactId;
  if (normalizedId != null && normalizedId.isNotEmpty) {
    for (final artifact in artifacts) {
      if (artifact.id == normalizedId || artifact.stableRef == artifactId) {
        return {'passed': true, 'artifact': artifact.toJson()};
      }
    }
    return {
      'passed': false,
      'reason': 'Required artifact "$artifactId" is not registered.',
    };
  }
  final kinds = _stringList(spec['artifactKinds']);
  for (final artifact in artifacts) {
    if (kinds.contains(artifact.kind.wireName)) {
      return {'passed': true, 'artifact': artifact.toJson()};
    }
  }
  return {
    'passed': false,
    'reason': 'No registered artifact of required kind: ${kinds.join(', ')}.',
  };
}

Map<String, dynamic> _workflowStateEvidence(
  ToolContext context, {
  required String workflow,
  required String? workflowStateId,
  required bool required,
}) {
  final expectedKind = _workflowKindForVerifierWorkflow(workflow);
  final records = _readWorkflowStateRecords(context);
  Map<String, dynamic>? record;
  if (workflowStateId != null && workflowStateId.isNotEmpty) {
    record = records.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id'] == workflowStateId,
      orElse: () => null,
    );
  } else {
    record = records.cast<Map<String, dynamic>?>().firstWhere((item) {
      final state = item?['workflowState'];
      return item?['status'] == 'active' &&
          state is Map &&
          state['workflowKind'] == expectedKind;
    }, orElse: () => null);
  }
  if (record == null) {
    if (!required) {
      return {
        'passed': true,
        'passedMessage':
            'Typed workflow state was not required for this check.',
      };
    }
    return {
      'passed': false,
      'reason': workflowStateId != null && workflowStateId.isNotEmpty
          ? 'Required workflow state "$workflowStateId" is not saved.'
          : 'No active saved FinanceWorkflowState for expected kind "$expectedKind".',
    };
  }
  final state = record['workflowState'];
  final kind = state is Map ? state['workflowKind'] : null;
  if (kind != expectedKind) {
    return {
      'passed': false,
      'record': record,
      'reason':
          'Saved workflow state kind "$kind" does not match expected "$expectedKind".',
    };
  }
  if (record['status'] == 'blocked') {
    return {
      'passed': false,
      'record': record,
      'reason':
          'Saved workflow state is blocked: ${record['blocker'] ?? 'blocker not specified'}.',
    };
  }
  return {
    'passed': true,
    'passedMessage': 'Typed workflow state is saved and matches this workflow.',
    'record': record,
  };
}

Map<String, dynamic> _providerHealthEvidence(Object? raw) {
  final rows = raw is List
      ? raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : const <Map<String, dynamic>>[];
  if (rows.isEmpty) {
    return {
      'passed': true,
      'passedMessage':
          'Provider health evidence was not supplied for this check.',
      'observed': rows,
    };
  }
  const blockingStatuses = {
    'unhealthy',
    'blocked',
    'runtime_unavailable',
    'transport_unstable',
    'quota_exhausted',
    'credential_missing',
    'credential-or-quota-required',
  };
  final blocking = rows.where((row) {
    final status = '${row['status'] ?? row['classification'] ?? ''}'
        .trim()
        .toLowerCase();
    return blockingStatuses.contains(status);
  }).toList();
  if (blocking.isNotEmpty) {
    final labels = blocking
        .map((row) {
          final provider = row['provider'] ?? row['source'] ?? 'provider';
          final status = row['status'] ?? row['classification'] ?? 'blocked';
          return '$provider:$status';
        })
        .join(', ');
    return {
      'passed': false,
      'reason': 'Provider health has blocking rows: $labels.',
      'observed': rows,
    };
  }
  return {
    'passed': true,
    'passedMessage': 'Provider health evidence has no blocking rows.',
    'observed': rows,
  };
}

List<Map<String, dynamic>> _readWorkflowStateRecords(ToolContext context) {
  final file = File('${context.memoryDir}/workflows/state.json');
  if (!file.existsSync()) return const [];
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return const [];
    final records = decoded['records'];
    if (records is! List) return const [];
    return records
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  } catch (_) {
    return const [];
  }
}

String _workflowKindForVerifierWorkflow(String workflow) {
  switch (workflow) {
    case 'market_overview':
      return 'market_analysis';
    case 'stock_research':
      return 'stock_research';
    case 'fund_selection':
      return 'fund_research';
    case 'strategy_backtest':
      return 'strategy_review';
    case 'trade_preparation':
      return 'trade_prep';
    default:
      return 'unknown';
  }
}

Map<String, dynamic> _check(
  String id,
  bool passed,
  String passedMessage,
  String failedMessage,
) => {
  'id': id,
  'passed': passed,
  'message': passed ? passedMessage : failedMessage,
};

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList();
}

int _intValue(Object? value, {required int defaultValue}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? defaultValue;
}
