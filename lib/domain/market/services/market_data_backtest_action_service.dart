import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/tool_context.dart';
import 'backtest_market_data_service.dart';

class MarketDataBacktestActionService {
  final BacktestMarketDataService _backtest;

  MarketDataBacktestActionService({
    DataManager? dataManager,
    BacktestMarketDataService? backtest,
  }) : _backtest =
           backtest ?? BacktestMarketDataService(dataManager: dataManager);

  Future<BacktestServiceResponse> run(
    String action,
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    switch (action) {
      case 'backtest':
        return _backtest.backtest(
          _firstSymbol(symbols, _backtestError),
          input,
          context,
        );
      case 'backtest_enhanced':
        return _backtest.backtestEnhanced(
          _firstSymbol(symbols, _backtestEnhancedError),
          input,
          context,
        );
      case 'backtest_composite':
        return _backtest.backtestComposite(
          _firstSymbol(symbols, _backtestCompositeError),
          input,
          context,
        );
      case 'custom_strategy_help':
        return _backtest.customStrategyHelp();
      case 'custom_strategy_validate':
        return _backtest.customStrategyValidate(input);
      case 'custom_strategy_backtest':
        return _backtest.customStrategyBacktest(
          _firstCustomStrategySymbol(
            symbols,
            input,
            _customStrategyBacktestError,
          ),
          input,
          context,
        );
      case 'custom_strategy_observe':
        return _backtest.customStrategyObserve(input, context);
      case 'custom_strategy_fund_backtest':
        return _backtest.customStrategyFundBacktest(input, context);
      case 'custom_strategy_rank':
        _requireSymbols(symbols, _customStrategyRankError);
        return _backtest.customStrategyRank(symbols, input, context);
      case 'custom_strategy_save':
        return _backtest.customStrategySave(input, context);
      case 'custom_strategy_list':
        return _backtest.customStrategyList(context);
      case 'custom_strategy_compare':
        return _backtest.customStrategyCompare(input, context);
      case 'custom_strategy_run':
        return _backtest.customStrategyRun(
          _firstCustomStrategyRunSymbol(symbols, input, context, _backtest),
          input,
          context,
        );
      case 'backtest_batch':
        _requireSymbols(symbols, _backtestBatchError);
        return _backtest.backtestBatch(symbols, input, context);
      case 'optimize_params':
        return _backtest.optimizeParams(
          _firstSymbol(symbols, _optimizeParamsError),
          input,
          context,
        );
      default:
        throw ArgumentError('Unsupported MarketData backtest action: $action');
    }
  }
}

String _firstSymbol(List<String> symbols, String error) {
  if (symbols.isEmpty) throw ArgumentError(error);
  return symbols.first;
}

String _firstCustomStrategySymbol(
  List<String> symbols,
  Map<String, dynamic> input,
  String error,
) {
  if (symbols.isNotEmpty) return symbols.first;
  final spec = input['strategySpec'];
  if (spec is Map) {
    final singleSymbol = '${spec['symbol'] ?? ''}'.trim();
    if (singleSymbol.isNotEmpty) return singleSymbol;
    final embedded = spec['symbols'];
    if (embedded is List && embedded.isNotEmpty) {
      return '${embedded.first}'.trim();
    }
    final universe = spec['universe'];
    if (universe is List && universe.isNotEmpty) {
      return '${universe.first}'.trim();
    }
    if (universe is Map) {
      final universeSymbols = universe['symbols'];
      if (universeSymbols is List && universeSymbols.isNotEmpty) {
        return '${universeSymbols.first}'.trim();
      }
    }
  }
  throw ArgumentError(error);
}

String _firstCustomStrategyRunSymbol(
  List<String> symbols,
  Map<String, dynamic> input,
  ToolContext context,
  BacktestMarketDataService backtest,
) {
  if (symbols.isNotEmpty) return symbols.first;
  final direct = '${input['symbol'] ?? input['code'] ?? ''}'.trim();
  if (direct.isNotEmpty) return direct;
  final strategyId = '${input['strategyId'] ?? ''}'.trim();
  if (strategyId.isNotEmpty) {
    final saved = backtest.savedCustomStrategySymbol(context, strategyId);
    if (saved != null && saved.isNotEmpty) return saved;
  }
  return '';
}

void _requireSymbols(List<String> symbols, String error) {
  if (symbols.isEmpty) throw ArgumentError(error);
}

const _backtestError =
    'symbols required. Example: MarketData(action:"backtest", symbols:["600519"], strategy:"compare")';
const _backtestEnhancedError =
    'symbols required. Example: MarketData(action:"backtest_enhanced", symbols:["600519"], strategy:"rsi", stopLoss:8, positionSizing:"kelly")';
const _backtestCompositeError =
    'symbols + strategies required. Example: MarketData(action:"backtest_composite", symbols:["600519"], strategies:["rsi","macd","ema_cross"], mode:"majority")';
const _customStrategyBacktestError =
    'symbols + strategySpec required. Example: MarketData(action:"custom_strategy_backtest", symbols:["600519"], strategySpec:{...})';
const _customStrategyRankError =
    'symbols + strategySpec required. Example: MarketData(action:"custom_strategy_rank", symbols:["600519","000858","300750"], strategySpec:{...}, topN:2)';
const _backtestBatchError =
    'symbols required. Example: MarketData(action:"backtest_batch", symbols:["600519","000858","601318"], strategy:"rsi")';
const _optimizeParamsError =
    'symbols + strategy + paramGrid required. Example: MarketData(action:"optimize_params", symbols:["600519"], strategy:"rsi", paramGrid:{"period":[10,14,20],"oversold":[30,40]})';
