import 'message.dart';
import 'tool_context.dart';

/// Abstract interface for a Tool that the Agent can invoke.
///
/// Reference: Claude Code's Tool type in Tool.ts
/// Each tool defines its name, description, prompt (instructions for LLM),
/// input schema, permission rules, and a call() method.
abstract class Tool {
  /// Unique tool name, sent to the LLM.
  String get name;

  /// Short description, sent to the LLM.
  String get description;

  /// Full prompt / instructions for the LLM on how to use this tool.
  String get prompt => description;

  /// JSON Schema describing the expected input parameters.
  Map<String, dynamic> get inputSchema;

  /// Whether this tool only reads data (no side effects).
  /// Read-only tools can be executed concurrently.
  bool get isReadOnly => true;

  /// Whether this tool can run in parallel with other canParallel tools.
  /// Defaults to isReadOnly. Override to true for write tools that produce
  /// independent output files (e.g. PaperPageRender, ImageExtract, WebFetch).
  bool get canParallel => isReadOnly;

  /// Whether this specific tool input can run in parallel.
  /// Defaults to [canParallel]. Override when a broad read-mostly tool has
  /// specific mutation or lifecycle actions that must be serialized.
  bool canRunInParallel(Map<String, dynamic> input) => canParallel;

  /// Whether this tool requires interactive user input (e.g. AskUserQuestion).
  /// Tools with this flag are excluded from sub-agents and background execution.
  bool get requiresUserInteraction => false;

  /// Whether this tool call needs user confirmation before executing.
  /// Reference: Claude Code's needsPermissions(input) in each tool.
  bool needsPermissions(Map<String, dynamic> input) => !isReadOnly;

  /// Validate input before execution. Return null if valid,
  /// or an error message string if invalid.
  /// Reference: Claude Code's validateInput(input, context).
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async => null;

  /// Execute the tool with the given input and context.
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  );

  /// Convert to OpenAI function tool format for the server API.
  Map<String, dynamic> toOpenAI() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': inputSchema,
    },
  };
}
