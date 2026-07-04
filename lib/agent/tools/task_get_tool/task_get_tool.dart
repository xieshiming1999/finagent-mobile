import 'dart:convert';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Gets full details of a task by ID.
///
/// Reference: claude-code-best/src/tools/TaskGetTool/TaskGetTool.ts
class TaskGetTool extends Tool {
  @override
  String get name => 'TaskGet';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'taskId': {
        'type': 'string',
        'description': 'The ID of the task to retrieve',
      },
    },
    'required': ['taskId'],
  };

  @override
  bool get isReadOnly => true;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final taskId = input['taskId'] as String?;
    if (taskId == null || taskId.trim().isEmpty) {
      return 'taskId is required.';
    }
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final taskId = input['taskId'] as String;
    final task = context.taskStore.get(taskId);

    if (task == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Task not found: $taskId',
        isError: true,
      );
    }

    return ToolResult(toolUseId: toolUseId, content: jsonEncode(task.toFull()));
  }
}
