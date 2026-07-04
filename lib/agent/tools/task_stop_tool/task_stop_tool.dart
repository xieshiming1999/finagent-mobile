import '../../background_task.dart';
import '../../agent.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Stops a running background sub-agent task.
///
/// Reference: claude-code-best/src/tools/TaskStopTool/TaskStopTool.ts
class TaskStopTool extends Tool {
  /// Reference to parent agent for cancelling background agents.
  final Agent parentAgent;

  TaskStopTool({required this.parentAgent});

  @override
  String get name => 'TaskStop';

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
        'description': 'The ID of the background task to stop',
      },
    },
    'required': ['task_id'],
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
    final taskId = input['task_id'] as String?;
    if (taskId == null || taskId.trim().isEmpty) {
      return 'task_id is required.';
    }
    final task = context.taskRegistry.get(taskId);
    if (task == null) {
      return 'Task not found: $taskId';
    }
    if (task.status != BackgroundTaskStatus.running) {
      return 'Task is not running (status: ${task.status.name}).';
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

    // Cancel the sub-agent
    parentAgent.cancelBackgroundAgent(taskId);

    // Update status
    context.taskRegistry.updateStatus(
      taskId,
      BackgroundTaskStatus.killed,
      error: 'Stopped by user',
    );

    final running = context.taskRegistry.runningCount;
    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Task $taskId stopped. $running background task(s) still running.',
    );
  }
}
