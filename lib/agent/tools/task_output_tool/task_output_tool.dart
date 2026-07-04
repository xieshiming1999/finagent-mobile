import 'dart:convert';

import '../../background_task.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Retrieves output from a background sub-agent task.
///
/// Supports blocking (wait for completion) and non-blocking (check status) modes.
/// Reference: claude-code-best/src/tools/TaskOutputTool/TaskOutputTool.tsx
class TaskOutputTool extends Tool {
  @override
  String get name => 'TaskOutput';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'task_id': {
        'type': 'string',
        'description': 'The task ID to get output from',
      },
      'block': {
        'type': 'boolean',
        'description': 'Whether to wait for completion (default true)',
      },
      'timeout': {
        'type': 'integer',
        'description': 'Max wait time in ms (default 30000, max 600000)',
      },
    },
    'required': ['task_id'],
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
    final taskId = input['task_id'] as String?;
    if (taskId == null || taskId.trim().isEmpty) {
      return 'task_id is required.';
    }
    if (context.taskRegistry.get(taskId) == null) {
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
    final taskId = input['task_id'] as String;
    final block = input['block'] as bool? ?? true;
    final timeoutMs = (input['timeout'] as num?)?.toInt() ?? 600000;
    final effectiveTimeout = timeoutMs.clamp(0, 600000);

    var task = context.taskRegistry.get(taskId);
    if (task == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Task not found: $taskId',
        isError: true,
      );
    }

    if (block) {
      // Polling wait (reference: claude-code-best waitForTaskCompletion)
      final deadline = DateTime.now().add(
        Duration(milliseconds: effectiveTimeout),
      );

      while (task!.status == BackgroundTaskStatus.running ||
          task.status == BackgroundTaskStatus.pending) {
        if (DateTime.now().isAfter(deadline)) {
          return ToolResult(
            toolUseId: toolUseId,
            content: jsonEncode({
              'retrieval_status': 'timeout',
              'task_id': taskId,
              'status': task.status.name,
              'progress': {
                'toolUseCount': task.toolUseCount,
                'estimatedTokens': task.estimatedTokens,
                'recentActivities': task.recentActivities,
              },
            }),
          );
        }
        await Future.delayed(const Duration(milliseconds: 250));
        task = context.taskRegistry.get(taskId);
        if (task == null) {
          return ToolResult(
            toolUseId: toolUseId,
            content: 'Task disappeared: $taskId',
            isError: true,
          );
        }
      }
    }

    // Check if still running (non-blocking mode)
    if (task.status == BackgroundTaskStatus.running ||
        task.status == BackgroundTaskStatus.pending) {
      return ToolResult(
        toolUseId: toolUseId,
        content: jsonEncode({
          'retrieval_status': 'not_ready',
          'task_id': taskId,
          'status': task.status.name,
          'progress': {
            'toolUseCount': task.toolUseCount,
            'estimatedTokens': task.estimatedTokens,
            'recentActivities': task.recentActivities,
          },
        }),
      );
    }

    if (task.status == BackgroundTaskStatus.failed ||
        task.status == BackgroundTaskStatus.killed) {
      return ToolResult(
        toolUseId: toolUseId,
        content: jsonEncode({
          'retrieval_status': 'failed',
          'task_id': taskId,
          'status': task.status.name,
          if (task.error != null) 'error': task.error,
          if (context.taskRegistry.readOutput(taskId) != null)
            'result': context.taskRegistry.readOutput(taskId),
          'toolUseCount': task.toolUseCount,
          'estimatedTokens': task.estimatedTokens,
        }),
        isError: true,
      );
    }

    // Task completed
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'retrieval_status': 'success',
        'task_id': taskId,
        'status': task.status.name,
        if (task.result != null)
          'result': context.taskRegistry.readOutput(taskId) ?? task.result,
        if (task.error != null) 'error': task.error,
        'toolUseCount': task.toolUseCount,
        'estimatedTokens': task.estimatedTokens,
      }),
    );
  }
}
