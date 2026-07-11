import 'dart:convert';
import 'dart:io';

import '../../artifact_registry.dart';
import '../../interaction_evidence.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class AgentSelfDebugTool extends Tool {
  final List<Tool> Function() toolsProvider;

  AgentSelfDebugTool({required this.toolsProvider});

  @override
  String get name => 'AgentSelfDebug';

  @override
  String get description =>
      'Inspect recent agent runtime blockers, repeated tool failures, pending user interactions, artifacts, and discovery surfaces.';

  @override
  String get prompt =>
      'Use AgentSelfDebug(action:"status") when the workflow appears stuck, repeats tool calls, waits for user input, or cannot explain missing artifacts/evidence.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'status'],
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
    final action = (input['action'] as String?)?.trim() ?? 'status';
    if (action == 'help') {
      return ToolResult(toolUseId: toolUseId, content: jsonEncode(_help()));
    }
    if (action != 'status') {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid AgentSelfDebug action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }
    final limit = _intValue(input['limit'], defaultValue: 30).clamp(1, 100);
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode(_status(context, toolsProvider(), limit)),
    );
  }

  Map<String, dynamic> _help() => {
    'contract': 'agent-self-debug-help-v1',
    'actions': ['status'],
    'guidance': [
      'Use this before repeating failed calls or assuming the agent is idle.',
      'Resolve pending AskUserQuestion/approval outside hidden automation.',
      'Use discovery tools or runbooks when repeated failures show the wrong tool/action.',
    ],
  };
}

Map<String, dynamic> _status(ToolContext context, List<Tool> tools, int limit) {
  final session = _readSession(context, limit);
  final pending = readPendingInteractionState(context);
  final artifacts = ArtifactRegistry(
    context.basePath,
  ).list().take(limit).toList();
  final discoveryTools =
      tools
          .map(summarizeToolCapability)
          .where(
            (tool) =>
                tool.actionValues.contains('help') ||
                tool.name == 'ToolCatalog' ||
                tool.name == 'Runbook' ||
                tool.name == 'WorkflowVerifier',
          )
          .map((tool) => {'name': tool.name, 'actions': tool.actionValues})
          .toList()
        ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
  final blockerCount =
      pending.length +
      (session['recentFailedTools'] as List).length +
      (session['repeatedFailedToolCalls'] as List).length;
  return {
    'contract': 'agent-self-debug-status-v1',
    'runtime': 'finagent-mobile',
    'state': blockerCount > 0 ? 'needs_attention' : 'clear',
    'blockerCount': blockerCount,
    'pendingInteractions': pending,
    'recentFailedTools': session['recentFailedTools'],
    'repeatedFailedToolCalls': session['repeatedFailedToolCalls'],
    'artifacts': {
      'count': artifacts.length,
      'latest': artifacts.map((item) => item.toJson()).take(5).toList(),
    },
    'discoveryTools': discoveryTools,
    'nextAction': _nextAction(pending, session),
  };
}

String _nextAction(
  List<Map<String, dynamic>> pending,
  Map<String, dynamic> session,
) {
  if (pending.isNotEmpty) {
    return 'Resolve pending AskUserQuestion or approval explicitly before continuing.';
  }
  if ((session['repeatedFailedToolCalls'] as List).isNotEmpty) {
    return 'Stop repeating the same failing tool/input; inspect help, runbook, provider health, or choose a different tool.';
  }
  if ((session['recentFailedTools'] as List).isNotEmpty) {
    return 'Inspect the latest tool error, repair arguments or provider state, then retry narrowly.';
  }
  return 'No immediate runtime blocker is visible.';
}

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
