import 'dart:convert';

import '../../cron_scheduler.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Creates a scheduled task.
/// Reference: claude-code-best/src/tools/ScheduleCronTool/CronCreateTool.ts
class CronCreateTool extends Tool {
  final CronScheduler scheduler;

  CronCreateTool({required this.scheduler});

  @override
  String get name => 'CronCreate';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'schedule': {
        'type': 'string',
        'description':
            'Schedule expression: cron ("*/5 * * * *"), '
            'interval ("every 1 minute"), or delay ("after 30 minutes")',
      },
      'prompt': {
        'type': 'string',
        'description': 'The prompt to execute when the schedule fires',
      },
      'recurring': {
        'type': 'boolean',
        'description': 'true for repeating, false for one-shot (default true)',
      },
      'durable': {
        'type': 'boolean',
        'description': 'true to persist across app restarts (default false)',
      },
      'run_in_background': {
        'type': 'boolean',
        'description':
            'true to run without blocking user interaction (default true)',
      },
    },
    'required': ['schedule', 'prompt'],
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
    final schedule = input['schedule'] as String?;
    if (schedule == null || schedule.trim().isEmpty) {
      return 'schedule is required.';
    }
    final prompt = input['prompt'] as String?;
    if (prompt == null || prompt.trim().isEmpty) {
      return 'prompt is required.';
    }

    // Validate schedule expression
    final config = parseSchedule(schedule);
    if (config.type == 'cron') {
      final fields = parseCronExpression(config.cron ?? schedule);
      if (fields == null) {
        return 'Invalid cron expression: $schedule. Use 5 fields: minute hour day month weekday.';
      }
      final next = computeNextCronRun(fields, DateTime.now());
      if (next == null) {
        return 'Cron expression "$schedule" will never fire (no match in next 366 days).';
      }
    }

    // Check max jobs
    if (scheduler.taskCount >= maxCronJobs) {
      return 'Maximum $maxCronJobs scheduled tasks reached. Delete some first.';
    }

    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final task = scheduler.addTask(
      schedule: input['schedule'] as String,
      prompt: input['prompt'] as String,
      recurring: input['recurring'] as bool? ?? true,
      durable: input['durable'] as bool? ?? false,
      runInBackground: input['run_in_background'] as bool? ?? true,
    );

    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'id': task.id,
        'schedule': task.schedule,
        'humanSchedule': scheduleToHuman(task.schedule),
        'recurring': task.recurring,
        'durable': task.durable,
        'runInBackground': task.runInBackground,
      }),
    );
  }
}
