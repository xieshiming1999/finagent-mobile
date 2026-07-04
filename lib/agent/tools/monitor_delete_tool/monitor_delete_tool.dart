import '../../message.dart';
import '../../monitor.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class MonitorDeleteTool extends Tool {
  final MonitorStore store;

  MonitorDeleteTool({required this.store});

  @override
  String get name => 'MonitorDelete';

  @override
  String get description => 'Delete a monitor by ID.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'id': {'type': 'string', 'description': 'The monitor ID to delete'},
    },
    'required': ['id'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) => true;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final id = input['id'] as String;

    if (store.remove(id)) {
      final remaining = store.monitors.length;
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Monitor "$id" deleted. $remaining monitor(s) remaining.',
      );
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: 'Monitor "$id" not found.',
      isError: true,
    );
  }
}
