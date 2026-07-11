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
  required int limit,
}) {
  final session = _readSession(context, limit);
  final pending = readPendingInteractionState(context);
  final artifactEvidence = _artifactEvidence(context, spec, artifactId);
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
