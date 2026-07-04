part of 'market_data_tool.dart';

mixin _MarketDataToolMarketActions
    on _MarketDataToolBase, _MarketDataToolSchema {
  Future<ToolResult> _action(
    String toolUseId,
    String action,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final symbols = _marketDataSymbolsFromInput(input);
    final response = await _actionService.run(action, symbols, input, context);
    return _resultFormatter.format(toolUseId, response);
  }
}
