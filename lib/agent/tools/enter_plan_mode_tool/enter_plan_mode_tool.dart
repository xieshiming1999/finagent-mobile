import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Enters plan mode for complex task planning.
///
/// Reference: claude-code-best/src/tools/EnterPlanModeTool/EnterPlanModeTool.ts
class EnterPlanModeTool extends Tool {
  @override
  String get name => 'EnterPlanMode';

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
    if (context.planMode) {
      return ToolResult(toolUseId: toolUseId, content: 'Already in plan mode.');
    }

    context.planMode = true;
    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Entered plan mode. '
          'Explore the problem and design your approach. '
          'Use ExitPlanMode when your plan is ready for review.',
    );
  }
}
