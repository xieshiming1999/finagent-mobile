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

/// Code-owned tool capability summary for progressive discovery.
///
/// This is intentionally runtime-neutral: it describes what the tool contract
/// exposes without inferring user intent from prompt text.
class ToolCapabilitySummary {
  final String name;
  final String description;
  final bool readOnly;
  final bool canParallel;
  final bool requiresUserInteraction;
  final String permission;
  final List<String> propertyNames;
  final List<String> required;
  final List<String> actionValues;

  const ToolCapabilitySummary({
    required this.name,
    required this.description,
    required this.readOnly,
    required this.canParallel,
    required this.requiresUserInteraction,
    required this.permission,
    required this.propertyNames,
    required this.required,
    required this.actionValues,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'readOnly': readOnly,
    'canParallel': canParallel,
    'requiresUserInteraction': requiresUserInteraction,
    'permission': permission,
    'schema': {
      'propertyNames': propertyNames,
      'required': required,
      'actionValues': actionValues,
    },
  };
}

ToolCapabilitySummary summarizeToolCapability(Tool tool) {
  final schema = tool.inputSchema;
  final properties = _mapValue(schema['properties']);
  return ToolCapabilitySummary(
    name: tool.name,
    description: tool.description,
    readOnly: tool.isReadOnly,
    canParallel: tool.canParallel,
    requiresUserInteraction: tool.requiresUserInteraction,
    permission: tool.isReadOnly ? 'read-only' : 'write-or-side-effect',
    propertyNames: properties.keys.toList()..sort(),
    required: _stringList(schema['required'])..sort(),
    actionValues: _stringList(_mapValue(properties['action'])['enum'])..sort(),
  );
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<String> _stringList(Object? value) {
  if (value is! List) return <String>[];
  return value.whereType<String>().toList();
}
