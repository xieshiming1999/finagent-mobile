part of 'market_data_tool.dart';

Future<ToolResult> _marketDataToolCall(
  MarketDataTool tool,
  String toolUseId,
  Map<String, dynamic> input,
  ToolContext context,
) async {
  final action = input['action'] as String? ?? 'help';
  tool._dataManager.ensureBasePath(context.basePath);

  try {
    return switch (action) {
      'help' => tool._help(toolUseId),
      'interfaces' => tool._interfaces(toolUseId, input),
      'interface_describe' => tool._interfaceDescribe(toolUseId, input),
      'interface_availability' => tool._interfaceAvailability(toolUseId, input),
      'sources' => tool._sources(toolUseId),
      'stats' => tool._stats(toolUseId),
      'data_health' => tool._dataHealth(toolUseId, input),
      'finance_doctor' => tool._financeDoctor(toolUseId, context),
      'runtime_probe' => await tool._runtimeProbe(toolUseId, input, context),
      'fetch_status' => tool._fetchStatus(toolUseId, input, context),
      'coverage' => tool._coverage(
        toolUseId,
        _marketDataSymbolsFromInput(input),
      ),
      'reusable_summary' => tool._coverage(toolUseId, const []),
      _ => await tool._action(toolUseId, action, input, context),
    };
  } catch (e) {
    return tool._resultFormatter.formatError(toolUseId, e);
  }
}

List<String> _marketDataSymbolsFromInput(Map<String, dynamic> input) {
  final symbols = input['symbols'];
  if (symbols is List) {
    return symbols
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
  if (symbols is String && symbols.trim().isNotEmpty) {
    return [symbols.trim()];
  }
  final symbol = input['symbol'];
  if (symbol is String && symbol.trim().isNotEmpty) {
    return [symbol.trim()];
  }
  final code = input['code'];
  if (code is String && code.trim().isNotEmpty) {
    return [code.trim()];
  }
  return const [];
}
