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
}

List<String> interactionInputKeys(Map<String, dynamic> input) =>
    input.keys.toList()..sort();
