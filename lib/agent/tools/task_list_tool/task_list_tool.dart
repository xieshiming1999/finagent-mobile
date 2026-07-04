import 'dart:convert';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Lists all tasks with summary information.
///
/// Reference: claude-code-best/src/tools/TaskListTool/TaskListTool.ts
class TaskListTool extends Tool {
  @override
  String get name => 'TaskList';

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
    final tasks = context.taskStore.list();

    if (tasks.isEmpty) {
      return ToolResult(toolUseId: toolUseId, content: 'No tasks found.');
    }

    // Filter completed task IDs from blockedBy lists
    final completedIds = tasks
        .where((t) => t.status == 'completed')
        .map((t) => t.id)
        .toSet();

    final summaries = tasks.map((t) {
      final summary = t.toSummary();
      // Remove completed tasks from blockedBy
      if (summary.containsKey('blockedBy')) {
        final filtered = (summary['blockedBy'] as List<String>)
            .where((id) => !completedIds.contains(id))
            .toList();
        if (filtered.isEmpty) {
          summary.remove('blockedBy');
        } else {
          summary['blockedBy'] = filtered;
        }
      }
      return summary;
    }).toList();

    return ToolResult(toolUseId: toolUseId, content: jsonEncode(summaries));
  }
}
