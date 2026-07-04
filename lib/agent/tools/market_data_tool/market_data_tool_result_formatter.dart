import 'dart:convert';

import '../../../domain/market/services/backtest_market_data_service.dart';
import '../../message.dart';

class MarketDataToolResultFormatter {
  const MarketDataToolResultFormatter();

  ToolResult format(
    String toolUseId,
    Object? response,
  ) {
    if (response is BacktestServiceResponse) {
      return ToolResult(
        toolUseId: toolUseId,
        content: response.content is String
            ? response.content as String
            : const JsonEncoder.withIndent('  ').convert(response.content),
        isError: response.isError,
      );
    }
    if (response is Map<String, dynamic>) {
      return ToolResult(
        toolUseId: toolUseId,
        content: const JsonEncoder.withIndent('  ').convert(response),
      );
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(response),
    );
  }

  ToolResult formatError(
    String toolUseId,
    Object error,
  ) => ToolResult(
    toolUseId: toolUseId,
    content: '$error',
    isError: true,
  );
}
