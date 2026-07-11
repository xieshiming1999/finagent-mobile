import 'dart:convert';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class ToolCatalogTool extends Tool {
  final List<Tool> Function() toolsProvider;

  ToolCatalogTool({required this.toolsProvider});

  @override
  String get name => 'ToolCatalog';

  @override
  String get description =>
      'Inspect the runtime tool catalog and capability summaries. Use list first, then detail for a specific tool.';

  @override
  String get prompt =>
      'Use ToolCatalog to inspect registered tools before calling broad or unfamiliar tools. '
      'Call action="list" first; call action="detail" with a tool name for schema and action values.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'list', 'detail'],
        'description':
            'help, list all tool capabilities, or detail for one tool',
      },
      'tool': {'type': 'string', 'description': 'Tool name for detail action'},
    },
  };

  @override
  bool get isReadOnly => true;

  @override
  bool get canParallel => true;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = (input['action'] as String?)?.trim() ?? 'list';
    if (action == 'help') {
      return ToolResult(toolUseId: toolUseId, content: jsonEncode(_help()));
    }
    if (action != 'list' && action != 'detail') {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid ToolCatalog action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }

    final capabilities = toolsProvider().map(summarizeToolCapability).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (action == 'detail') {
      final toolName = (input['tool'] as String?)?.trim() ?? '';
      if (toolName.isEmpty) {
        return ToolResult(
          toolUseId: toolUseId,
          content:
              'ToolCatalog detail requires "tool". Use action="list" to inspect tool names.',
          isError: true,
        );
      }
      final matches = capabilities.where((c) => c.name == toolName).toList();
      if (matches.isEmpty) {
        return ToolResult(
          toolUseId: toolUseId,
          content:
              'Tool "$toolName" is not registered. Use ToolCatalog(action:"list") for available tools.',
          isError: true,
        );
      }
      return ToolResult(
        toolUseId: toolUseId,
        content: jsonEncode({
          'contract': 'tool-catalog-result-v1',
          'action': action,
          'tool': matches.single.toJson(),
        }),
      );
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'contract': 'tool-catalog-result-v1',
        'action': action,
        'count': capabilities.length,
        'tools': capabilities
            .map(
              (capability) => {
                'name': capability.name,
                'permission': capability.permission,
                'readOnly': capability.readOnly,
                'canParallel': capability.canParallel,
                'requiresUserInteraction': capability.requiresUserInteraction,
                'actions': capability.actionValues,
              },
            )
            .toList(),
      }),
    );
  }

  Map<String, dynamic> _help() => {
    'contract': 'tool-catalog-help-v1',
    'actions': ['list', 'detail'],
    'guidance':
        'Use list to inspect registered tools and action values. Use detail with a tool name before calling broad or unfamiliar tools.',
  };
}
