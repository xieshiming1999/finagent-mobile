import '../../cron_scheduler.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Deletes a scheduled task.
/// Reference: claude-code-best/src/tools/ScheduleCronTool/CronDeleteTool.ts
class CronDeleteTool extends Tool {
  final CronScheduler scheduler;

  CronDeleteTool({required this.scheduler});

  @override
  String get name => 'CronDelete';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'id': {
        'type': 'string',
        'description': 'The ID of the scheduled task to cancel',
      },
    },
    'required': ['id'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) => true;

  @override
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final id = input['id'] as String?;
    if (id == null || id.trim().isEmpty) return 'id is required.';
    if (scheduler.getTask(id) == null) return 'Scheduled task not found: $id';
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final id = input['id'] as String;
    scheduler.removeTask(id);
    final remaining = scheduler.taskCount;
    return ToolResult(
      toolUseId: toolUseId,
      content: 'Scheduled task $id cancelled. $remaining task(s) remaining.',
    );
  }
}
