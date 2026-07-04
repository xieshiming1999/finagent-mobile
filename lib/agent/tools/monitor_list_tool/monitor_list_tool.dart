import '../../message.dart';
import '../../monitor.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class MonitorListTool extends Tool {
  final MonitorStore store;

  MonitorListTool({required this.store});

  @override
  String get name => 'MonitorList';

  @override
  String get description => 'List all active monitors and their latest status.';

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
    final monitors = store.monitors;

    if (monitors.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'No monitors configured. Use MonitorCreate to add one.',
      );
    }

    final summaries = monitors.map((m) => m.toSummary()).join('\n\n');
    return ToolResult(
      toolUseId: toolUseId,
      content: '${monitors.length} monitor(s):\n\n$summaries',
    );
  }
}
