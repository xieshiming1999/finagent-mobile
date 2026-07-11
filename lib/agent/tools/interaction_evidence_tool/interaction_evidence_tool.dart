import 'dart:convert';
import 'dart:io';

import '../../interaction_evidence.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class InteractionEvidenceTool extends Tool {
  @override
  String get name => 'InteractionEvidence';

  @override
  String get description =>
      'Inspect structured user-question and approval lifecycle evidence. Use summary first, then recent for details.';

  @override
  String get prompt =>
      'Use InteractionEvidence to inspect pending or recently resolved AskUserQuestion and permission approval states. '
      'Call action="summary" first; call action="recent" with an optional type filter for details.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'summary', 'recent'],
        'description': 'help, summary, or recent interaction evidence rows',
      },
      'limit': {
        'type': 'integer',
        'description': 'Maximum recent rows to return, default 20',
      },
      'type': {
        'type': 'string',
        'description':
            'Optional evidence type filter, for example user_question_pending or permission_resolved',
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
    if (action != 'summary' && action != 'recent') {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid InteractionEvidence action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }

    final rows = _readRows(context);
    final type = (input['type'] as String?)?.trim() ?? '';
    final filtered = type.isEmpty
        ? rows
        : rows.where((row) => row['type'] == type).toList();

    if (action == 'recent') {
      final rawLimit = input['limit'];
      final limit = rawLimit is int ? rawLimit.clamp(1, 100) : 20;
      final returned = filtered.length < limit ? filtered.length : limit;
      return ToolResult(
        toolUseId: toolUseId,
        content: jsonEncode({
          'contract': 'interaction-evidence-result-v1',
          'action': action,
          'count': filtered.length,
          'returned': returned,
          'rows': filtered.skip(filtered.length - returned).toList(),
        }),
      );
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'contract': 'interaction-evidence-result-v1',
        'action': action,
        'count': filtered.length,
        'byType': _countByType(filtered),
        'pending': _pendingState(context, rows),
        'latest': rows.isEmpty ? null : rows.last,
      }),
    );
  }

  Map<String, dynamic> _help() => {
    'contract': 'interaction-evidence-help-v1',
    'actions': ['summary', 'recent'],
    'evidenceTypes': [
      'user_question_pending',
      'user_question_resolved',
      'user_question_timeout',
      'permission_request',
      'permission_resolved',
    ],
    'guidance':
        'Use summary to inspect whether user input or approval is pending. Use recent with a type filter for detailed rows.',
  };

  List<Map<String, dynamic>> _readRows(ToolContext context) {
    final file = File('${context.memoryDir}/interaction_evidence.jsonl');
    if (!file.existsSync()) return [];
    final rows = <Map<String, dynamic>>[];
    for (final line in file.readAsLinesSync()) {
      final text = line.trim();
      if (text.isEmpty) continue;
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) rows.add(decoded);
      } catch (_) {}
    }
    return rows;
  }

  Map<String, int> _countByType(List<Map<String, dynamic>> rows) {
    final out = <String, int>{};
    for (final row in rows) {
      final type = row['type']?.toString() ?? 'unknown';
      out[type] = (out[type] ?? 0) + 1;
    }
    return out;
  }

  List<Map<String, dynamic>> _latestPending(List<Map<String, dynamic>> rows) {
    final resolved = <String>{};
    for (final row in rows) {
      final requestId = row['requestId']?.toString() ?? '';
      if (requestId.isEmpty) continue;
      final type = row['type'];
      if (type == 'user_question_resolved' ||
          type == 'user_question_timeout' ||
          type == 'permission_resolved') {
        resolved.add(requestId);
      }
    }
    return rows.where((row) {
      final requestId = row['requestId']?.toString() ?? '';
      if (requestId.isEmpty || resolved.contains(requestId)) return false;
      final type = row['type'];
      return type == 'user_question_pending' || type == 'permission_request';
    }).toList();
  }

  List<Map<String, dynamic>> _pendingState(
    ToolContext context,
    List<Map<String, dynamic>> rows,
  ) {
    final state = readPendingInteractionState(context);
    return state.isNotEmpty ? state : _latestPending(rows);
  }
}
