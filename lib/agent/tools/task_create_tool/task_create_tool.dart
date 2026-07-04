import 'dart:convert';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Creates a task in the in-memory task store.
///
/// Reference: claude-code-best/src/tools/TaskCreateTool/TaskCreateTool.ts
class TaskCreateTool extends Tool {
  @override
  String get name => 'TaskCreate';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'subject': {
        'type': 'string',
        'description': 'A brief title for the task',
      },
      'description': {'type': 'string', 'description': 'What needs to be done'},
      'activeForm': {
        'type': 'string',
        'description':
            'Present continuous form for status display '
            '(e.g. "Analyzing AAPL")',
      },
      'metadata': {
        'type': 'object',
        'description': 'Arbitrary metadata to attach to the task',
      },
    },
    'required': ['subject', 'description'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final subject = input['subject'] as String?;
    if (subject == null || subject.trim().isEmpty) {
      return 'subject is required.';
    }
    final desc = input['description'] as String?;
    if (desc == null || desc.trim().isEmpty) {
      return 'description is required.';
    }
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final task = context.taskStore.create(
      subject: input['subject'] as String,
      description: input['description'] as String,
      activeForm: input['activeForm'] as String?,
      metadata: input['metadata'] as Map<String, dynamic>?,
    );

    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'task': {'id': task.id, 'subject': task.subject, 'status': task.status},
        'totalTasks': context.taskStore.list().length,
      }),
    );
  }
}
