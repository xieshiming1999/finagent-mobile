import 'dart:convert';
import 'dart:io';

import 'tool_context.dart';

void appendInteractionEvidence(
  ToolContext context,
  Map<String, dynamic> evidence,
) {
  final memoryDir = Directory(context.memoryDir)..createSync(recursive: true);
  final row = <String, dynamic>{
    ...evidence,
    'createdAt': evidence['createdAt'] ?? DateTime.now().toIso8601String(),
  };
  File(
    '${memoryDir.path}/interaction_evidence.jsonl',
  ).writeAsStringSync('${jsonEncode(row)}\n', mode: FileMode.append);
  _updatePendingInteractionState(memoryDir, row);
}

List<String> interactionInputKeys(Map<String, dynamic> input) =>
    input.keys.toList()..sort();

List<Map<String, dynamic>> readPendingInteractionState(ToolContext context) {
  final file = File('${context.memoryDir}/interaction_pending.json');
  if (!file.existsSync()) return [];
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) return [];
    final pending = decoded['pending'];
    if (pending is! List) return [];
    return pending.whereType<Map>().map((row) {
      return row.map((key, value) => MapEntry('$key', value));
    }).toList();
  } catch (_) {
    return [];
  }
}

void _updatePendingInteractionState(
  Directory memoryDir,
  Map<String, dynamic> row,
) {
  final requestId = row['requestId']?.toString() ?? '';
  if (requestId.isEmpty) return;
  final file = File('${memoryDir.path}/interaction_pending.json');
  final pending = <String, Map<String, dynamic>>{};
  if (file.existsSync()) {
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      final rows = decoded is Map<String, dynamic> ? decoded['pending'] : null;
      if (rows is List) {
        for (final item in rows.whereType<Map>()) {
          final normalized = item.map((key, value) => MapEntry('$key', value));
          final id = normalized['requestId']?.toString() ?? '';
          if (id.isNotEmpty) pending[id] = normalized;
        }
      }
    } catch (_) {}
  }

  final type = row['type'];
  if (type == 'user_question_pending' || type == 'permission_request') {
    pending[requestId] = row;
  } else if (type == 'user_question_resolved' ||
      type == 'user_question_timeout' ||
      type == 'permission_resolved') {
    pending.remove(requestId);
  }

  final state = {
    'contract': 'interaction-pending-state-v1',
    'updatedAt': DateTime.now().toIso8601String(),
    'pending': pending.values.toList()
      ..sort(
        (a, b) =>
            '${a['createdAt'] ?? ''}'.compareTo('${b['createdAt'] ?? ''}'),
      ),
  };
  file.writeAsStringSync(jsonEncode(state));
}
