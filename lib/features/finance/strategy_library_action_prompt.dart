import 'package:finagent/domain/market/backtest/strategy_action_contract.dart'
    as strategy_action_contract;

import '../../shared/strategy_library_model.dart';

String buildStrategyActionPrompt(String action, StrategyLibraryItem item) {
  return strategy_action_contract.buildStrategyActionPrompt(
    action,
    strategy_action_contract.StrategyActionItem(
      strategyId: item.strategyId,
      status: item.status,
      assetClass: item.assetClass,
      strategyType: item.strategyType,
      symbols: item.symbols,
      evidenceAction: item.evidenceAction,
    ),
  );
}
