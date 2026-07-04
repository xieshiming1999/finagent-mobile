import 'dart:convert';

import '../../cron_scheduler.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Lists all scheduled tasks.
/// Reference: claude-code-best/src/tools/ScheduleCronTool/CronListTool.ts
class CronListTool extends Tool {
  final CronScheduler scheduler;

  CronListTool({required this.scheduler});

  @override
  String get name => 'CronList';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {'type': 'object', 'properties': {}};

  @override
  bool get isReadOnly => true;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final tasks = scheduler.listTasks();

    if (tasks.isEmpty) {
      return ToolResult(toolUseId: toolUseId, content: 'No scheduled tasks.');
    }

    final jobs = tasks
        .map(
          (t) => {
            'id': t.id,
            'schedule': t.schedule,
            'humanSchedule': scheduleToHuman(t.schedule),
            'prompt': t.prompt,
            'recurring': t.recurring,
            'durable': t.durable,
            'runInBackground': t.runInBackground,
          },
        )
        .toList();

    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({'jobs': jobs}),
    );
  }
}
