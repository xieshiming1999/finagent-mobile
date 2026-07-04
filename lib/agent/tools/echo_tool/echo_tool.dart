import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// A minimal tool for testing the agent loop.
/// Reference: No direct Claude Code equivalent — test-only tool.
class EchoTool extends Tool {
  @override
  String get name => 'echo';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'message': {'type': 'string', 'description': 'The message to echo back'},
    },
    'required': ['message'],
  };

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
    final message = input['message'] as String? ?? '';
    return ToolResult(toolUseId: toolUseId, content: 'Echo: $message');
  }
}
