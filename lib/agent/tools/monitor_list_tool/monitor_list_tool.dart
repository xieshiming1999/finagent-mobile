import 'dart:convert';

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
    final structured = {
      'contract': 'monitor-list-v1',
      'count': monitors.length,
      'monitors': monitors.map(_monitorRecord).toList(growable: false),
    };
    return ToolResult(
      toolUseId: toolUseId,
      content:
          '${monitors.length} monitor(s):\n\n$summaries\n\nmonitorList:${jsonEncode(structured)}',
    );
  }

  Map<String, dynamic> _monitorRecord(Monitor monitor) {
    final strategyRules = monitor.strategyRules;
    final portfolioEvidence = strategyRules?['portfolioEvidence'];
    final rebalanceDraft = strategyRules?['rebalanceDraft'];
    return {
      'id': monitor.id,
      'name': monitor.name,
      'enabled': monitor.enabled,
      'intervalMinutes': monitor.interval.inMinutes,
      'displayType': monitor.displayType,
      if (monitor.strategyId != null) 'strategyId': monitor.strategyId,
      if (monitor.lastRunTime != null)
        'lastRunTime': monitor.lastRunTime!.toIso8601String(),
      if (monitor.lastError != null) 'lastError': monitor.lastError,
      if (monitor.lastResult != null) 'lastResult': monitor.lastResult,
      if (portfolioEvidence is Map)
        'portfolioEvidence': Map<String, dynamic>.from(portfolioEvidence),
      if (rebalanceDraft is Map)
        'rebalanceDraft': Map<String, dynamic>.from(rebalanceDraft),
      if (portfolioEvidence is Map || rebalanceDraft is Map)
        'template': 'portfolio_rebalance_monitor',
    };
  }
}
