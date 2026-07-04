import 'dart:convert';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Updates a task's status, details, or dependencies.
///
/// Reference: claude-code-best/src/tools/TaskUpdateTool/TaskUpdateTool.ts
class TaskUpdateTool extends Tool {
  @override
  String get name => 'TaskUpdate';

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
        'description': 'The ID of the task to update',
      },
      'subject': {'type': 'string', 'description': 'New subject for the task'},
      'description': {
        'type': 'string',
        'description': 'New description for the task',
      },
      'activeForm': {
        'type': 'string',
        'description': 'Present continuous form for status display',
      },
      'status': {
        'type': 'string',
        'enum': ['pending', 'in_progress', 'completed', 'deleted'],
        'description': 'New status for the task',
      },
      'addBlocks': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Task IDs that this task blocks',
      },
      'addBlockedBy': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Task IDs that block this task',
      },
      'owner': {'type': 'string', 'description': 'New owner for the task'},
      'metadata': {
        'type': 'object',
        'description':
            'Metadata keys to merge (set a key to null to delete it)',
      },
    },
    'required': ['taskId'],
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
    final taskId = input['taskId'] as String?;
    if (taskId == null || taskId.trim().isEmpty) {
      return 'taskId is required.';
    }
    if (context.taskStore.get(taskId) == null) {
      return 'Task not found: $taskId';
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

    final task = context.taskStore.update(
      taskId,
      subject: input['subject'] as String?,
      description: input['description'] as String?,
      activeForm: input['activeForm'] as String?,
      status: input['status'] as String?,
      owner: input['owner'] as String?,
      addBlocks: (input['addBlocks'] as List?)?.cast<String>(),
      addBlockedBy: (input['addBlockedBy'] as List?)?.cast<String>(),
      metadata: input['metadata'] as Map<String, dynamic>?,
    );

    if (task == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Task not found: $taskId',
        isError: true,
      );
    }

    if (task.status == 'deleted') {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Task #$taskId deleted.',
      );
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode(task.toSummary()),
    );
  }
}
