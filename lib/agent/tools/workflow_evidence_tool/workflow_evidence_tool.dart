import 'dart:convert';
import 'dart:io';

import '../../interaction_evidence.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class WorkflowEvidenceTool extends Tool {
  @override
  String get name => 'WorkflowEvidence';

  @override
  String get description =>
      'Summarize workflow evidence from session messages, tool results, pending user interactions, and UI artifacts.';

  @override
  String get prompt =>
      'Use WorkflowEvidence to inspect what the current workflow actually proved before finalizing or resuming work. '
      'Call action="summary" to inspect recent tool calls, failures, pending AskUserQuestion/approval state, and generated UI artifacts.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'summary'],
        'description': 'help or summary',
      },
      'limit': {
        'type': 'integer',
        'description': 'Maximum recent session evidence rows to return, default 20',
      },
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
    final action = (input['action'] as String?)?.trim() ?? 'summary';
    if (action == 'help') {
      return ToolResult(toolUseId: toolUseId, content: jsonEncode(_help()));
    }
    if (action != 'summary') {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid WorkflowEvidence action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }

    final rawLimit = input['limit'];
    final limit = rawLimit is int ? rawLimit.clamp(1, 100) : 20;
    final sessionEvidence = _readCurrentSession(context, limit);
    final artifacts = _listArtifacts(context, limit);
    final pending = readPendingInteractionState(context);
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'contract': 'workflow-evidence-summary-v1',
        'sources': {
          'session': '${context.basePath}/sessions/current.jsonl',
          'interactionPending': '${context.memoryDir}/interaction_pending.json',
          'artifacts': [
            '${context.basePath}/memory/pages',
            '${context.basePath}/memory/dashboards',
          ],
        },
        'pendingInteractions': pending,
        'session': sessionEvidence,
        'artifacts': artifacts,
        'guidance':
            'Use this summary to verify tool calls, failures, pending human input, and UI artifacts. It is evidence, not a substitute for a full app workflow check.',
      }),
    );
  }

  Map<String, dynamic> _help() => {
    'contract': 'workflow-evidence-help-v1',
    'actions': ['summary'],
    'reads': [
      'sessions/current.jsonl',
      'memory/interaction_pending.json',
      'memory/pages',
      'memory/dashboards',
    ],
    'guidance':
        'Call summary before claiming a workflow is complete, after restart, or when the agent reported tool/UI failures.',
  };

  Map<String, dynamic> _readCurrentSession(ToolContext context, int limit) {
    final file = File('${context.basePath}/sessions/current.jsonl');
    if (!file.existsSync()) {
      return {
        'exists': false,
        'messageCount': 0,
        'toolCallCount': 0,
        'toolResultCount': 0,
        'toolErrorCount': 0,
        'recent': <Map<String, dynamic>>[],
      };
    }

    final recent = <Map<String, dynamic>>[];
    var messageCount = 0;
    var toolCallCount = 0;
    var toolResultCount = 0;
    var toolErrorCount = 0;

    for (final line in file.readAsLinesSync()) {
      final text = line.trim();
      if (text.isEmpty) continue;
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded['type'] != 'message') continue;
        messageCount++;
        final role = decoded['role']?.toString() ?? '';
        final item = <String, dynamic>{
          'role': role,
          if (decoded['timestamp'] != null) 'timestamp': decoded['timestamp'],
        };
        final toolUses = decoded['toolUses'];
        if (toolUses is List && toolUses.isNotEmpty) {
          toolCallCount += toolUses.length;
          item['toolUses'] = toolUses
              .whereType<Map>()
              .map(
                (tool) => {
                  'name': tool['name'],
                  'input': _compactValue(tool['input']),
                },
              )
              .toList();
        }
        final toolResult = decoded['toolResult'] ?? decoded['tool_result'];
        if (toolResult is Map) {
          toolResultCount++;
          final isError = toolResult['isError'] == true;
          if (isError) toolErrorCount++;
          item['toolResult'] = {
            'isError': isError,
            if (toolResult['toolUseId'] != null)
              'toolUseId': toolResult['toolUseId'],
            'content': _truncate('${toolResult['content'] ?? ''}', 500),
          };
        }
        final content = decoded['content'];
        if (content is String && content.trim().isNotEmpty) {
          item['content'] = _truncate(content, 300);
        }
        recent.add(item);
        if (recent.length > limit) recent.removeAt(0);
      } catch (_) {}
    }

    return {
      'exists': true,
      'messageCount': messageCount,
      'toolCallCount': toolCallCount,
      'toolResultCount': toolResultCount,
      'toolErrorCount': toolErrorCount,
      'recent': recent,
    };
  }

  Map<String, dynamic> _listArtifacts(ToolContext context, int limit) {
    final roots = {
      'pages': Directory('${context.basePath}/memory/pages'),
      'dashboards': Directory('${context.basePath}/memory/dashboards'),
    };
    final out = <String, dynamic>{};
    for (final entry in roots.entries) {
      final dir = entry.value;
      if (!dir.existsSync()) {
        out[entry.key] = {'exists': false, 'count': 0, 'recent': []};
        continue;
      }
      final files = dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.html'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      out[entry.key] = {
        'exists': true,
        'count': files.length,
        'recent': files
            .take(limit)
            .map(
              (file) => {
                'path': file.path,
                'updatedAt': file.lastModifiedSync().toIso8601String(),
                'sizeBytes': file.lengthSync(),
              },
            )
            .toList(),
      };
    }
    return out;
  }

  Object? _compactValue(Object? value) {
    if (value is String) return _truncate(value, 180);
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry('$key', item is String ? _truncate(item, 120) : item),
      );
    }
    return value;
  }

  String _truncate(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}...';
}
