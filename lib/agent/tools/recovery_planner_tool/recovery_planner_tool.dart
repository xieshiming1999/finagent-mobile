import 'dart:convert';
import 'dart:io';

import '../../interaction_evidence.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class RecoveryPlannerTool extends Tool {
  @override
  String get name => 'RecoveryPlanner';

  @override
  String get description =>
      'Plan structured recovery steps from failed tool calls, provider blocks, missing evidence, pending user input, or approval boundaries.';

  @override
  String get prompt =>
      'Use RecoveryPlanner(action:"plan") after verifier/self-debug/provider failures. It returns structured recovery options; do not keep retrying broad calls without a recovery plan.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'plan'],
      },
      'failureClass': {
        'type': 'string',
        'enum': [
          'auto',
          'pending_interaction',
          'repeated_tool_failure',
          'provider_unhealthy',
          'credential_required',
          'missing_artifact',
          'missing_evidence',
          'approval_boundary',
          'unsupported_request',
        ],
      },
      'workflow': {'type': 'string'},
      'toolName': {'type': 'string'},
      'provider': {'type': 'string'},
      'interfaceId': {'type': 'string'},
      'details': {'type': 'object'},
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
    final action = (input['action'] as String?)?.trim() ?? 'plan';
    if (action == 'help') {
      return ToolResult(toolUseId: toolUseId, content: jsonEncode(_help()));
    }
    if (action != 'plan') {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid RecoveryPlanner action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }
    final limit = _intValue(input['limit'], defaultValue: 30).clamp(1, 100);
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode(_plan(context, input, limit)),
    );
  }

  Map<String, dynamic> _help() => {
    'contract': 'recovery-planner-help-v1',
    'actions': ['plan'],
    'failureClasses': [
      'auto',
      'pending_interaction',
      'repeated_tool_failure',
      'provider_unhealthy',
      'credential_required',
      'missing_artifact',
      'missing_evidence',
      'approval_boundary',
      'unsupported_request',
    ],
    'guidance': [
      'Use structured failureClass/details when available.',
      'Use failureClass:auto to infer from pending interactions and recent failed tool calls.',
      'RecoveryPlanner suggests safe next steps; it does not execute side effects.',
    ],
  };
}

Map<String, dynamic> _plan(
  ToolContext context,
  Map<String, dynamic> input,
  int limit,
) {
  final requestedClass = (input['failureClass'] as String?)?.trim() ?? 'auto';
  final observed = _observed(context, limit);
  final failureClass = requestedClass == 'auto'
      ? _inferFailureClass(observed)
      : requestedClass;
  final options = _optionsFor(failureClass, input, observed);
  return {
    'contract': 'recovery-planner-plan-v1',
    'runtime': 'finagent-mobile',
    'workflow': (input['workflow'] as String?)?.trim(),
    'failureClass': failureClass,
    'observed': observed,
    'options': options,
    'recommended': options.isEmpty ? null : options.first,
  };
}

Map<String, dynamic> _observed(ToolContext context, int limit) {
  final pending = readPendingInteractionState(context);
  final session = _readSession(context, limit);
  return {
    'pendingInteractions': pending,
    'recentFailedTools': session['recentFailedTools'],
    'repeatedFailedToolCalls': session['repeatedFailedToolCalls'],
  };
}

String _inferFailureClass(Map<String, dynamic> observed) {
  if ((observed['pendingInteractions'] as List).isNotEmpty) {
    return 'pending_interaction';
  }
  if ((observed['repeatedFailedToolCalls'] as List).isNotEmpty) {
    return 'repeated_tool_failure';
  }
  if ((observed['recentFailedTools'] as List).isNotEmpty) {
    return 'missing_evidence';
  }
  return 'missing_evidence';
}

List<Map<String, dynamic>> _optionsFor(
  String failureClass,
  Map<String, dynamic> input,
  Map<String, dynamic> observed,
) {
  switch (failureClass) {
    case 'pending_interaction':
      return [
        _option(
          'resolve_user_input',
          'Resolve the pending AskUserQuestion or approval explicitly, then continue.',
          stopBeforeFinalAnswer: true,
        ),
      ];
    case 'repeated_tool_failure':
      return [
        _option(
          'stop_repeating_call',
          'Stop repeating the same tool/input. Inspect tool help, ProviderRouter, or AgentSelfDebug before retrying.',
          stopBeforeFinalAnswer: true,
        ),
        _option(
          'change_route_or_scope',
          'Switch provider through ProviderRouter, reduce scope, or use cache/readback if available.',
        ),
      ];
    case 'provider_unhealthy':
      return [
        _option(
          'use_cache_or_alternate_provider',
          'Use reusable cache/readback or ask ProviderRouter for a healthy allowed provider.',
        ),
        _option(
          'bounded_probe',
          'Run only a bounded serial probe for the affected provider/interface before retrying live data.',
        ),
      ];
    case 'credential_required':
      return [
        _option(
          'request_or_configure_credential',
          'Stop live provider calls until the required credential/quota is configured and verified.',
          stopBeforeFinalAnswer: true,
        ),
      ];
    case 'missing_artifact':
      return [
        _option(
          'create_or_register_artifact',
          'Create the expected artifact, then register it through ArtifactRegistry before finalizing.',
        ),
      ];
    case 'approval_boundary':
      return [
        _option(
          'stop_for_approval',
          'Stop before side effects and ask for explicit approval through the supported user-interaction path.',
          stopBeforeFinalAnswer: true,
        ),
      ];
    case 'unsupported_request':
      return [
        _option(
          'return_unsupported_with_contract',
          'Return a clear unsupported result with the missing contract/capability and a supported alternative.',
          stopBeforeFinalAnswer: true,
        ),
      ];
    case 'missing_evidence':
    default:
      return [
        _option(
          'collect_required_evidence',
          'Use Runbook and WorkflowVerifier to identify missing evidence, then collect it through typed tools.',
        ),
        _option(
          'disclose_missing_evidence',
          'If evidence is unavailable, disclose what is missing and reduce confidence instead of inventing data.',
        ),
      ];
  }
}

Map<String, dynamic> _option(
  String id,
  String description, {
  bool stopBeforeFinalAnswer = false,
}) => {
  'id': id,
  'description': description,
  'stopBeforeFinalAnswer': stopBeforeFinalAnswer,
};

Map<String, dynamic> _readSession(ToolContext context, int limit) {
  final file = File('${context.basePath}/sessions/current.jsonl');
  if (!file.existsSync()) {
    return {
      'recentFailedTools': <Map<String, dynamic>>[],
      'repeatedFailedToolCalls': <Map<String, dynamic>>[],
    };
  }
  final toolUses = <String, Map<String, dynamic>>{};
  final failures = <Map<String, dynamic>>[];
  final repeated = <String, Map<String, dynamic>>{};
  for (final line in file.readAsLinesSync().take(limit)) {
    final text = line.trim();
    if (text.isEmpty) continue;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) continue;
      final uses = decoded['toolUses'];
      if (uses is List) {
        for (final item in uses) {
          if (item is Map && item['id'] is String) {
            toolUses[item['id'] as String] = {
              'name': item['name'],
              'input': item['input'],
            };
          }
        }
      }
      final result = decoded['toolResult'] ?? decoded['tool_result'];
      if (result is Map && result['isError'] == true) {
        final id = result['toolUseId']?.toString() ?? '';
        final use = toolUses[id];
        final failure = {
          'toolUseId': id,
          'toolName': use?['name'],
          'input': use?['input'],
          'content': _truncate(result['content']?.toString() ?? ''),
        };
        failures.add(failure);
        final signature =
            '${failure['toolName']}|${jsonEncode(failure['input'])}';
        final current = repeated[signature] ?? {...failure, 'count': 0};
        current['count'] = (current['count'] as int) + 1;
        repeated[signature] = current;
      }
    } catch (_) {
      continue;
    }
  }
  return {
    'recentFailedTools': failures.reversed.take(5).toList(),
    'repeatedFailedToolCalls': repeated.values
        .where((item) => (item['count'] as int) >= 3)
        .toList(),
  };
}

String _truncate(String value, [int max = 240]) =>
    value.length <= max ? value : '${value.substring(0, max)}...';

int _intValue(Object? value, {required int defaultValue}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? defaultValue;
}
