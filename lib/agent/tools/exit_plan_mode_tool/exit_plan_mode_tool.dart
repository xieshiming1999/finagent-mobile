import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Exits plan mode and presents the plan for user approval.
///
/// Reference: claude-code-best/src/tools/ExitPlanModeTool/ExitPlanModeV2Tool.ts
class ExitPlanModeTool extends Tool {
  @override
  String get name => 'ExitPlanMode';

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
    if (!context.planMode) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Not currently in plan mode.',
      );
    }

    context.planMode = false;
    return ToolResult(
      toolUseId: toolUseId,
      content: 'Exited plan mode. Ready to execute.',
    );
  }
}
