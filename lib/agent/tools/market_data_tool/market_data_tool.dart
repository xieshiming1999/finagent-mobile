import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../domain/market/services/market_data_action_service.dart';
import '../../../domain/market/services/market_data_action_service_factory.dart';
import '../../../domain/market/services/market_data_runtime_probe_service.dart';
import '../../../domain/market/services/market_data_support_service.dart';
import '../../../domain/market/backtest/strategy_method_registry.dart';
import '../../data_fetcher/data_manager.dart';
import '../../data_fetcher/eastmoney_advanced_fetcher.dart';
import '../../data_task_engine.dart';
import '../../finance_doctor.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'market_data_tool_result_formatter.dart';

part 'market_data_tool_schema.dart';
part 'market_data_tool_dispatch.dart';
part 'market_data_tool_market_actions.dart';

abstract class _MarketDataToolBase extends Tool {
  MarketDataActionService get _actionService;
  MarketDataSupportService get _supportService;
  MarketRuntimeProbeService get _runtimeProbeService;
  MarketDataToolResultFormatter get _resultFormatter;
}

class MarketDataTool extends _MarketDataToolBase
    with _MarketDataToolSchema, _MarketDataToolMarketActions {
  final DataManager _dataManager;
  @override
  final MarketDataActionService _actionService;
  @override
  final MarketDataSupportService _supportService;
  @override
  late final MarketRuntimeProbeService _runtimeProbeService;
  @override
  final MarketDataToolResultFormatter _resultFormatter;

  MarketDataTool({
    DataManager? dataManager,
    http.Client? httpClient,
    EastMoneyAdvancedFetcher? advancedFetcher,
    DataTaskEngine? dataTaskEngine,
  }) : this._internal(
         dataManager ?? DataManager(),
         httpClient ?? http.Client(),
         advancedFetcher ?? EastMoneyAdvancedFetcher(),
         dataTaskEngine,
       );

  MarketDataTool._internal(
    DataManager dataManager,
    http.Client httpClient,
    EastMoneyAdvancedFetcher advancedFetcher,
    DataTaskEngine? dataTaskEngine,
  ) : _dataManager = dataManager,
      _supportService = MarketDataSupportService(
        dataManager: dataManager,
        dataTaskEngine: dataTaskEngine,
      ),
      _resultFormatter = const MarketDataToolResultFormatter(),
      _actionService = MarketDataActionServiceFactory.create(
        dataManager: dataManager,
        httpClient: httpClient,
        advancedFetcher: advancedFetcher,
      ) {
    _runtimeProbeService = MarketRuntimeProbeService(
      dataManager: dataManager,
      runAction:
          (
            String action,
            List<String> symbols,
            Map<String, dynamic> input,
            ToolContext context,
          ) => _actionService.run(action, symbols, input, context),
      getHealth: () => _supportService.dataHealth(section: 'all', limit: 200),
    );
  }

  @override
  String get name => 'MarketData';

  @override
  String get description =>
      'Fetch market data with local-first provenance. For broad market money-flow or unusual-stock discovery, use bounded query_* readbacks first and answer from available evidence before broad live refreshes.';

  @override
  bool get isReadOnly => true;

  @override
  bool get canParallel => true;

  @override
  bool canRunInParallel(Map<String, dynamic> input) {
    final action = input['action'];
    return action != 'custom_strategy_save' && action != 'custom_strategy_run';
  }

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) => _marketDataToolCall(this, toolUseId, input, context);
}
