import 'dart:async';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Callback type for UI state queries.
/// Registered by the UI layer to respond to Agent queries.
typedef UIQueryHandler = Future<String> Function(String key);

/// Queries the current UI state via event mechanism.
///
/// Agent emits a query → UI layer responds with the current value.
/// This keeps Agent layer free of Flutter dependency.
class UIQueryTool extends Tool {
  /// Handler registered by the UI layer.
  UIQueryHandler? handler;

  @override
  String get name => 'UIQuery';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'key': {
        'type': 'string',
        'description':
            'Identifier of the UI state value. Use "help" to list supported keys.',
      },
    },
    'required': ['key'],
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
    final key = input['key'] as String?;
    if (key == null || key.trim().isEmpty) {
      return 'key is required.';
    }
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final key = input['key'] as String;

    if (handler == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'UIQuery not available: no UI handler registered.',
        isError: true,
      );
    }

    try {
      final result = await handler!(key);
      return ToolResult(toolUseId: toolUseId, content: result);
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'UIQuery error: $e',
        isError: true,
      );
    }
  }
}
