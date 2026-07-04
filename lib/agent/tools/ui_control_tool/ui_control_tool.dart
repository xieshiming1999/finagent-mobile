import 'dart:async';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Callback type for UI control commands.
/// Registered by the UI layer to handle Agent commands.
typedef UIControlHandler =
    Future<String> Function(String action, Map<String, dynamic> params);

/// Controls the app UI via event mechanism.
///
/// Agent emits a command → UI layer executes it (navigate, show chart, etc.).
/// This keeps Agent layer free of Flutter dependency.
class UIControlTool extends Tool {
  /// Handler registered by the UI layer.
  UIControlHandler? handler;

  @override
  String get name => 'UIControl';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'description':
            'The UI action to perform (e.g., navigate, showChart, showTable)',
      },
      'params': {'type': 'object', 'description': 'Parameters for the action'},
    },
    'required': ['action'],
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
    final action = input['action'] as String?;
    if (action == null || action.trim().isEmpty) {
      return 'action is required.';
    }
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = input['action'] as String;
    final params =
        (input['params'] ?? input['payload']) as Map<String, dynamic>? ?? {};

    if (handler == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'UIControl not available: no UI handler registered.',
        isError: true,
      );
    }

    try {
      final result = await handler!(action, params);
      return ToolResult(toolUseId: toolUseId, content: result);
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'UIControl error: $e',
        isError: true,
      );
    }
  }
}
