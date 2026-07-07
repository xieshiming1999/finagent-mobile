import 'dart:math';

import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/tool_context.dart';
import '../backtest/backtest_engine.dart' as bt;
import '../backtest/custom_strategy_engine.dart';
import '../backtest/strategy_portfolio_ranker.dart';
import 'market_data_resolve_service.dart';
import 'yahoo_market_data_service.dart';

typedef BacktestCandleLoader =
    Future<List<bt.Candle>> Function(
      String symbol,
      String period,
      ToolContext? context,
    );

class BacktestServiceResponse {
  final Object content;
  final bool isError;

  const BacktestServiceResponse({required this.content, this.isError = false});
}

class BacktestMarketDataService {
  final DataManager _dataManager;
  final MarketDataResolveService _resolveService;
  final YahooMarketDataService _yahooMarketDataService;
  final BacktestCandleLoader? _candleLoader;
  final CustomStrategyEngine _customStrategyEngine = CustomStrategyEngine();

  BacktestMarketDataService({
    DataManager? dataManager,
    MarketDataResolveService? resolveService,
    YahooMarketDataService? yahooMarketDataService,
    BacktestCandleLoader? candleLoader,
  }) : this._internal(
         dataManager ?? DataManager(),
         resolveService: resolveService,
         yahooMarketDataService: yahooMarketDataService,
         candleLoader: candleLoader,
       );

  BacktestMarketDataService._internal(
    DataManager dataManager, {
    MarketDataResolveService? resolveService,
    YahooMarketDataService? yahooMarketDataService,
    BacktestCandleLoader? candleLoader,
  }) : _dataManager = dataManager,
       _resolveService =
           resolveService ?? MarketDataResolveService(dataManager: dataManager),
       _yahooMarketDataService =
           yahooMarketDataService ??
           YahooMarketDataService(dataManager: dataManager),
       _candleLoader = candleLoader;

  Future<BacktestServiceResponse> backtest(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final strategy = _normalizeStrategy(input['strategy'] as String?);
    final period = _normalizePeriod(input['period'] as String?);
    final candles = await _loadCandlesForInput(symbol, period, input, context);
    if (candles.length < 30) {
      return BacktestServiceResponse(
        content:
            'insufficient data — got ${candles.length} bars, need at least 30',
      );
    }

    final buyHold =
        (candles.last.close - candles.first.close) / candles.first.close * 100;

    if (strategy == 'compare') {
      final results = <Map<String, dynamic>>[];
      for (final entry in bt.strategyMap.entries) {
        final trades = entry.value(candles);
        final metrics = bt.calcMetrics(trades);
        final score = bt.scoreBacktest(
          candles,
          trades,
          metrics,
          strategy: entry.key,
        );
        results.add({
          'strategy': entry.key,
          'score': score['score'],
          'grade': score['grade'],
          'fitness': score['fitness'],
          'total_return_pct': metrics['total_return_pct'],
          'sharpe_ratio': metrics['sharpe_ratio'],
          'win_rate_pct': metrics['win_rate_pct'],
          'max_drawdown_pct': metrics['max_drawdown_pct'],
          'total_trades': metrics['total_trades'],
          'overfit_risk': score['overfit_risk'],
        });
      }
      results.sort(
        (a, b) =>
            ((b['score'] as num?) ?? 0).compareTo((a['score'] as num?) ?? 0),
      );
      for (var i = 0; i < results.length; i++) {
        results[i]['rank'] = i + 1;
      }

      final bestStrategy = results.first['strategy'] as String;
      final signal = bt.detectCurrentSignal(candles, bestStrategy);
      return BacktestServiceResponse(
        content: {
          'action': 'backtest',
          'mode': 'compare',
          'symbol': symbol,
          'period': period,
          'bars': candles.length,
          'buy_hold_return_pct': double.parse(buyHold.toStringAsFixed(2)),
          'recommendation':
              '${results.first['strategy']}策略最适合(评分${results.first['score']}, ${results.first['grade']}级)',
          'bestStrategy': bestStrategy,
          'currentSignal': signal,
          'strategies': results,
        },
      );
    }

    final strategyFn = bt.strategyMap[strategy];
    if (strategyFn == null) {
      return BacktestServiceResponse(
        content:
            'unknown strategy "$strategy". Use: ${bt.strategyMap.keys.join(", ")}, or "compare"',
        isError: true,
      );
    }

    final trades = strategyFn(candles);
    final metrics = bt.calcMetrics(trades);
    final score = bt.scoreBacktest(
      candles,
      trades,
      metrics,
      strategy: strategy,
    );
    final signal = bt.detectCurrentSignal(candles, strategy);
    final recentTrades = trades.length <= 5
        ? trades
        : trades.sublist(trades.length - 5);

    return BacktestServiceResponse(
      content: {
        'action': 'backtest',
        'symbol': symbol,
        'strategy': strategy,
        'period': period,
        if (_requestedStartDate(input).isNotEmpty)
          'requestedStartDate': _requestedStartDate(input),
        if (_requestedEndDate(input).isNotEmpty)
          'requestedEndDate': _requestedEndDate(input),
        if (candles.isNotEmpty) 'actualStartDate': candles.first.date,
        if (candles.isNotEmpty) 'actualEndDate': candles.last.date,
        'bars': candles.length,
        'buy_hold_return_pct': double.parse(buyHold.toStringAsFixed(2)),
        ...metrics,
        'score': score,
        'currentSignal': signal,
        'recent_trades': recentTrades
            .map(
              (t) => {
                'entry': '${t.entryDate} @ ${t.entryPrice.toStringAsFixed(2)}',
                'exit': '${t.exitDate} @ ${t.exitPrice.toStringAsFixed(2)}',
                'return_pct': double.parse(t.returnPct.toStringAsFixed(2)),
              },
            )
            .toList(),
      },
    );
  }

  Future<BacktestServiceResponse> backtestEnhanced(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final strategy = _normalizeStrategy(
      input['strategy'] as String?,
      fallback: 'rsi',
    );
    final period = _normalizePeriod(input['period'] as String?);
    final strategyFn = bt.strategyMap[strategy];
    if (strategyFn == null) {
      return BacktestServiceResponse(
        content:
            'unknown strategy "$strategy". Available: ${bt.strategyMap.keys.join(", ")}',
        isError: true,
      );
    }

    final candles = await _loadCandles(symbol, period, context);
    if (candles.length < 30) {
      return BacktestServiceResponse(
        content: 'insufficient data (${candles.length} bars)',
        isError: true,
      );
    }

    final sizingStr = input['positionSizing'] as String? ?? 'fullCapital';
    final sizing = bt.PositionSizing.values.firstWhere(
      (e) => e.name == sizingStr,
      orElse: () => bt.PositionSizing.fullCapital,
    );

    final result = bt.backtestEnhanced(
      candles,
      strategyFn,
      sizing: sizing,
      stopLossPct: (input['stopLoss'] as num?)?.toDouble() ?? 0,
      takeProfitPct: (input['takeProfit'] as num?)?.toDouble() ?? 0,
      trailingStopPct: (input['trailingStop'] as num?)?.toDouble() ?? 0,
    );

    return BacktestServiceResponse(
      content: {
        'action': 'backtest_enhanced',
        'symbol': symbol,
        'strategy': strategy,
        ...result,
      },
    );
  }

  Future<BacktestServiceResponse> optimizeParams(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final paramGrid = input['paramGrid'] as Map<String, dynamic>?;
    final strategy = _normalizeStrategy(
      input['strategy'] as String?,
      fallback: _looksLikeRsiGrid(paramGrid) ? 'rsi' : '',
    );
    if (strategy.isEmpty || paramGrid == null || paramGrid.isEmpty) {
      return const BacktestServiceResponse(
        content:
            'strategy + paramGrid required. Example: MarketData(action:"optimize_params", symbols:["600519"], strategy:"rsi", paramGrid:{"period":[10,14,20], "oversold":[30,40]})',
        isError: true,
      );
    }
    if (!bt.strategyMap.containsKey(strategy)) {
      return BacktestServiceResponse(
        content:
            'unknown strategy "$strategy". Use: ${bt.strategyMap.keys.join(", ")}',
        isError: true,
      );
    }

    final period = _normalizePeriod(input['period'] as String?);
    final candles = await _loadCandlesForInput(symbol, period, input, context);
    if (candles.length < 30) {
      return const BacktestServiceResponse(
        content: 'insufficient data',
        isError: true,
      );
    }

    final grid = _normalizeParamGrid(paramGrid);
    final result = bt.optimizeStrategy(candles, strategy, grid);
    final top5 = (result['top5'] as List?) ?? const [];
    if (top5.isEmpty) {
      return BacktestServiceResponse(
        content:
            'parameter search returned no valid results for strategy "$strategy". Use supported grid keys such as period, oversold, and overbought.',
        isError: true,
      );
    }
    final best = top5.isNotEmpty && top5.first is Map
        ? Map<String, dynamic>.from(top5.first as Map)
        : null;
    return BacktestServiceResponse(
      content: {
        'action': 'optimize_params',
        'symbol': symbol,
        'period': period,
        if (_requestedStartDate(input).isNotEmpty)
          'requestedStartDate': _requestedStartDate(input),
        if (_requestedEndDate(input).isNotEmpty)
          'requestedEndDate': _requestedEndDate(input),
        if (candles.isNotEmpty) 'actualStartDate': candles.first.date,
        if (candles.isNotEmpty) 'actualEndDate': candles.last.date,
        'bars': candles.length,
        ...result,
        'bestParams': best?['params'],
        'bestResult': best,
        'results': top5,
        'parameterStability': _parameterStabilityEvidence(top5),
        'overfit_note':
            'Parameter search is in-sample only; prefer simple grids, compare with buy-and-hold, and validate out of sample before using live.',
      },
    );
  }

  Map<String, dynamic> _parameterStabilityEvidence(List results) {
    final rows = results
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    if (rows.isEmpty) {
      return {'status': 'skipped', 'reason': 'no optimizer results available'};
    }
    final returns = rows
        .map((row) => _numOf(row['totalReturn']) ?? 0)
        .toList(growable: false);
    final bestReturn = returns.first;
    final tolerance = bestReturn.abs() * 0.1;
    final nearBestCount = returns
        .where((value) => (bestReturn - value).abs() <= tolerance)
        .length;
    final averageReturn = returns.reduce((a, b) => a + b) / returns.length;
    final variance = returns.length <= 1
        ? 0.0
        : returns
                  .map((value) => pow(value - averageReturn, 2).toDouble())
                  .reduce((a, b) => a + b) /
              (returns.length - 1);
    final spread = _parameterSpread(rows);
    final stabilityClass = _parameterStabilityClass(
      rows.length,
      nearBestCount,
      spread,
    );
    return {
      'status': 'evaluated',
      'basis': 'top optimizer results',
      'topResultCount': rows.length,
      'bestReturnPct': _round(bestReturn),
      'nearBestCountWithin10Pct': nearBestCount,
      'topReturnStdDevPct': _round(sqrt(variance)),
      'parameterSpread': spread,
      'testedParameterKeys': spread.keys.toList()..sort(),
      'stabilityClass': stabilityClass,
      'decisionBoundary':
          'Optimizer evidence is in-sample only. Use stable as a research signal, fragile as overfit risk, and inconclusive as insufficient grid evidence.',
      'interpretation': nearBestCount >= 2
          ? 'top parameters have nearby alternatives in the tested grid'
          : 'best parameter is isolated in the tested grid; treat as higher overfit risk',
    };
  }

  String _parameterStabilityClass(
    int rowCount,
    int nearBestCount,
    Map<String, dynamic> spread,
  ) {
    if (rowCount < 3 || spread.isEmpty) return 'inconclusive';
    return nearBestCount >= 2 ? 'stable' : 'fragile';
  }

  Map<String, dynamic> _parameterSpread(List<Map<String, dynamic>> rows) {
    final spread = <String, dynamic>{};
    for (final row in rows) {
      final params = row['params'];
      if (params is! Map) continue;
      for (final entry in params.entries) {
        final value = _numOf(entry.value);
        if (value == null) continue;
        final key = '${entry.key}';
        final existing = Map<String, dynamic>.from(
          spread[key] as Map? ?? {'min': value, 'max': value},
        );
        existing['min'] = min(_numOf(existing['min']) ?? value, value);
        existing['max'] = max(_numOf(existing['max']) ?? value, value);
        spread[key] = existing;
      }
    }
    return spread;
  }

  double _round(double value) => double.parse(value.toStringAsFixed(4));

  double? _numOf(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.replaceAll('%', ''));
    return null;
  }

  bool _looksLikeRsiGrid(Map<String, dynamic>? grid) {
    if (grid == null || grid.isEmpty) return false;
    final keys = grid.keys.map((key) => key.toLowerCase()).toSet();
    return keys.any(
      (key) =>
          key.contains('rsi') ||
          key.contains('oversold') ||
          key.contains('overbought'),
    );
  }

  Future<BacktestServiceResponse> backtestComposite(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final strategies = (input['strategies'] as List?)?.cast<String>() ?? [];
    if (strategies.length < 2) {
      return const BacktestServiceResponse(
        content:
            'need at least 2 strategies. Example: strategies: ["rsi","macd","ema_cross"]',
        isError: true,
      );
    }

    final mode = input['mode'] as String? ?? 'majority';
    final period = _normalizePeriod(input['period'] as String?);
    final candles = await _loadCandles(symbol, period, context);
    if (candles.length < 30) {
      return const BacktestServiceResponse(
        content: 'insufficient data',
        isError: true,
      );
    }

    final result = bt.strategyComposite(candles, strategies, mode: mode);
    return BacktestServiceResponse(
      content: {
        'action': 'backtest_composite',
        'symbol': symbol,
        'period': period,
        ...result,
      },
    );
  }

  Future<BacktestServiceResponse> backtestBatch(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final strategy = _normalizeStrategy(input['strategy'] as String?);
    final period = _normalizePeriod(input['period'] as String?);
    final limitedSymbols = symbols.take(10).toList();
    final results = <Map<String, dynamic>>[];

    for (final symbol in limitedSymbols) {
      try {
        final candles = await _loadCandles(symbol, period, context);
        if (candles.length < 30) {
          results.add({
            'symbol': symbol,
            'error': 'insufficient data (${candles.length} bars)',
          });
          continue;
        }

        if (strategy == 'compare') {
          Map<String, dynamic>? best;
          var bestScore = -1.0;
          for (final entry in bt.strategyMap.entries) {
            final trades = entry.value(candles);
            final metrics = bt.calcMetrics(trades);
            final score = bt.scoreBacktest(
              candles,
              trades,
              metrics,
              strategy: entry.key,
            );
            final currentScore = (score['score'] as num?)?.toDouble() ?? 0;
            if (currentScore > bestScore) {
              bestScore = currentScore;
              best = {
                'symbol': symbol,
                'bestStrategy': entry.key,
                'score': score['score'],
                'grade': score['grade'],
                'total_return_pct': metrics['total_return_pct'],
                'sharpe_ratio': metrics['sharpe_ratio'],
                'win_rate_pct': metrics['win_rate_pct'],
                'overfit_risk': score['overfit_risk'],
              };
            }
          }
          if (best != null) {
            final signal = bt.detectCurrentSignal(
              candles,
              best['bestStrategy'] as String,
            );
            best['currentSignal'] = signal['status'];
            best['signalSuggestion'] = signal['suggestion'];
            results.add(best);
          }
          continue;
        }

        final strategyFn = bt.strategyMap[strategy];
        if (strategyFn == null) {
          results.add({
            'symbol': symbol,
            'error': 'unknown strategy: $strategy',
          });
          continue;
        }
        final trades = strategyFn(candles);
        final metrics = bt.calcMetrics(trades);
        final score = bt.scoreBacktest(
          candles,
          trades,
          metrics,
          strategy: strategy,
        );
        final signal = bt.detectCurrentSignal(candles, strategy);
        results.add({
          'symbol': symbol,
          'strategy': strategy,
          'score': score['score'],
          'grade': score['grade'],
          'total_return_pct': metrics['total_return_pct'],
          'sharpe_ratio': metrics['sharpe_ratio'],
          'win_rate_pct': metrics['win_rate_pct'],
          'overfit_risk': score['overfit_risk'],
          'currentSignal': signal['status'],
          'signalSuggestion': signal['suggestion'],
        });
      } catch (e) {
        results.add({'symbol': symbol, 'error': '$e'});
      }
    }

    results.sort(
      (a, b) =>
          ((b['score'] as num?) ?? -1).compareTo((a['score'] as num?) ?? -1),
    );
    final best = results.isNotEmpty && results.first.containsKey('score')
        ? results.first
        : null;

    return BacktestServiceResponse(
      content: {
        'action': 'backtest_batch',
        'strategy': strategy,
        'period': period,
        'count': results.length,
        if (best != null)
          'recommendation':
              '${best['symbol']}最适合${strategy == "compare" ? best['bestStrategy'] : strategy}策略(评分${best['score']}, ${best['grade']}级)',
        'results': results,
      },
    );
  }

  Future<BacktestServiceResponse> customStrategyHelp(
    Map<String, dynamic> input,
  ) async {
    return BacktestServiceResponse(content: _customStrategyEngine.help(input));
  }

  Future<BacktestServiceResponse> customStrategyValidate(
    Map<String, dynamic> input,
  ) async {
    return BacktestServiceResponse(
      content: _customStrategyEngine.validate(input['strategySpec']),
    );
  }

  Future<BacktestServiceResponse> customStrategyBacktest(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final spec = input['strategySpec'];
    if (spec == null) {
      return const BacktestServiceResponse(
        content: 'strategySpec required for custom_strategy_backtest',
        isError: true,
      );
    }
    final period = _normalizePeriod(input['period'] as String?);
    final loaded = await _loadCandlesWithEvidenceForInput(
      symbol,
      period,
      input,
      context,
    );
    try {
      final content = _customStrategyEngine.backtest(
        spec,
        loaded.candles,
        symbol: symbol,
        outOfSampleRatio: _outOfSampleRatio(input),
        walkForwardFolds: _walkForwardFolds(input),
      );
      content['dataEvidence'] = loaded.evidence;
      content['dataCoverage'] = _strategyDataCoverage(
        spec,
        loaded.evidence,
        symbol,
      );
      return BacktestServiceResponse(content: content);
    } catch (error) {
      return BacktestServiceResponse(content: '$error', isError: true);
    }
  }

  double? _outOfSampleRatio(Map<String, dynamic> input) {
    final requested =
        input['outOfSampleRatio'] ??
        input['validationSplit'] ??
        input['holdoutRatio'];
    if (requested is num) return requested.toDouble();
    if (requested is String) return double.tryParse(requested);
    return null;
  }

  int? _walkForwardFolds(Map<String, dynamic> input) {
    final requested =
        input['walkForwardFolds'] ??
        input['walkForward_folds'] ??
        input['stabilityFolds'];
    if (requested is num) return requested.toInt();
    if (requested is String) return int.tryParse(requested);
    if (input['walkForward'] == true || input['parameterStability'] == true) {
      return 3;
    }
    return null;
  }

  Future<BacktestServiceResponse> customStrategyObserve(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final spec = input['strategySpec'];
    if (spec == null) {
      return const BacktestServiceResponse(
        content: 'strategySpec required for custom_strategy_observe',
        isError: true,
      );
    }
    try {
      final rows = _resolveFundRows(input, context);
      return BacktestServiceResponse(
        content: _customStrategyEngine.observe(spec, rows),
      );
    } catch (error) {
      return BacktestServiceResponse(content: '$error', isError: true);
    }
  }

  Future<BacktestServiceResponse> customStrategyFundBacktest(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final spec = input['strategySpec'];
    if (spec == null) {
      return const BacktestServiceResponse(
        content: 'strategySpec required for custom_strategy_fund_backtest',
        isError: true,
      );
    }
    try {
      final rows = _resolveFundRows(input, context);
      return BacktestServiceResponse(
        content: _customStrategyEngine.fundBacktest(spec, rows),
      );
    } catch (error) {
      return BacktestServiceResponse(content: '$error', isError: true);
    }
  }

  Future<BacktestServiceResponse> customStrategyRank(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final spec = input['strategySpec'];
    if (spec == null) {
      return const BacktestServiceResponse(
        content: 'strategySpec required for custom_strategy_rank',
        isError: true,
      );
    }
    if (symbols.length < 2) {
      return const BacktestServiceResponse(
        content: 'at least two symbols required for custom_strategy_rank',
        isError: true,
      );
    }
    final period = _normalizePeriod(input['period'] as String?);
    final candidates = <StrategyPortfolioCandidate>[];
    for (final symbol in symbols.take(20)) {
      final loaded = await _loadCandlesWithEvidenceForInput(
        symbol,
        period,
        input,
        context,
      );
      candidates.add(
        StrategyPortfolioCandidate(
          symbol: symbol,
          candles: loaded.candles,
          dataEvidence: loaded.evidence,
        ),
      );
    }
    try {
      return BacktestServiceResponse(
        content: _customStrategyEngine.rank(
          spec,
          candidates,
          topN: ((input['topN'] as num?)?.toInt() ?? 3).clamp(1, 10),
          rankingMetric: '${input['rankingMetric'] ?? 'score'}',
          rebalanceInterval:
              '${input['rebalanceInterval'] ?? input['rebalance_interval'] ?? 'single_period_draft'}',
          maxPositionWeight:
              (input['maxPositionWeight'] ?? input['max_position_weight'])
                  is num
              ? ((input['maxPositionWeight'] ?? input['max_position_weight'])
                        as num)
                    .toDouble()
              : null,
          minScore: (input['minScore'] ?? input['min_score']) is num
              ? ((input['minScore'] ?? input['min_score']) as num).toDouble()
              : null,
          maxPairwiseCorrelation:
              (input['maxPairwiseCorrelation'] ??
                      input['max_pairwise_correlation'])
                  is num
              ? ((input['maxPairwiseCorrelation'] ??
                            input['max_pairwise_correlation'])
                        as num)
                    .toDouble()
              : null,
        ),
      );
    } catch (error) {
      return BacktestServiceResponse(content: '$error', isError: true);
    }
  }

  Future<BacktestServiceResponse> customStrategySave(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final spec = input['strategySpec'];
    if (spec == null) {
      return const BacktestServiceResponse(
        content: 'strategySpec required for custom_strategy_save',
        isError: true,
      );
    }
    try {
      final saved = _customStrategyEngine.save(
        context,
        spec,
        evidence: input['evidence'],
      );
      return BacktestServiceResponse(
        content: _compactCustomStrategySaveResult(saved),
      );
    } catch (error) {
      return BacktestServiceResponse(content: '$error', isError: true);
    }
  }

  Map<String, dynamic> _compactCustomStrategySaveResult(
    Map<String, dynamic> saved,
  ) {
    final spec = _mapOf(saved['strategySpec']) ?? _mapOf(saved['spec']) ?? {};
    final lifecycle = _mapOf(saved['lifecycle']) ?? {};
    final backtestEvidence = _mapOf(saved['backtestEvidence']);
    final evidence = backtestEvidence ?? _mapOf(saved['evidence']) ?? {};
    final strategyId = '${saved['strategyId'] ?? spec['id'] ?? ''}'.trim();
    final symbols = _symbolsFromStrategySpec(spec);
    final runnable = lifecycle['runnable'] == true;
    return {
      'action': 'custom_strategy_save',
      'strategyId': strategyId,
      'version': saved['version'],
      'status': saved['status'],
      'artifactContract': saved['artifactContract'],
      'itemPath': saved['itemPath'],
      'updatedAt': saved['updatedAt'],
      'lifecycle': lifecycle,
      'strategySpecSummary': {
        'id': spec['id'],
        'name': spec['name'],
        'assetClass': spec['assetClass'] ?? spec['market'] ?? 'stock',
        'symbols': symbols,
      },
      'validationSummary': saved['validationSummary'],
      'validationIssues': saved['validationIssues'] ?? const [],
      'repairPlan': saved['repairPlan'] ?? const [],
      'unsupportedDetails': saved['unsupportedDetails'] ?? const [],
      'dataRequirements': saved['dataRequirements'],
      'backtestEvidenceSummary': {
        'action': evidence['action'],
        'status': evidence['status'],
        'symbol':
            evidence['symbol'] ?? (symbols.isEmpty ? null : symbols.first),
        'actualStartDate': evidence['actualStartDate'],
        'actualEndDate': evidence['actualEndDate'],
        'bars': evidence['bars'],
        'metrics': evidence['metrics'],
        'dataCoverage': evidence['dataCoverage'],
      },
      'dataAndAssumptionSummary': saved['dataAndAssumptionSummary'],
      'nextAction': runnable ? 'custom_strategy_run' : 'custom_strategy_list',
      'nextActionInput': runnable
          ? {
              'action': 'custom_strategy_run',
              'strategyId': strategyId,
              if (symbols.isNotEmpty) 'symbol': symbols.first,
            }
          : {'action': 'custom_strategy_list'},
      'artifactStorage': {
        'fullArtifactPersisted': true,
        'readbackActions': ['custom_strategy_list', 'custom_strategy_run'],
      },
    };
  }

  Future<BacktestServiceResponse> customStrategyList(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final params = _mapOf(input['params']) ?? const <String, dynamic>{};
    final ids =
        input['strategyIds'] ??
        input['strategy_ids'] ??
        input['strategyId'] ??
        input['strategy_id'] ??
        params['strategyIds'] ??
        params['strategy_ids'] ??
        params['strategyId'] ??
        params['strategy_id'];
    final strategyIds = ids is List
        ? ids.map((value) => '$value').toList(growable: false)
        : [if (ids != null && '$ids'.trim().isNotEmpty) '$ids'];
    final limitValue = input['limit'] ?? params['limit'];
    final detailValue = input['detail'] ?? params['detail'];
    return BacktestServiceResponse(
      content: _customStrategyEngine.list(
        context,
        limit: limitValue is num ? limitValue.toInt() : null,
        detail: '$detailValue'.toLowerCase() == 'full' ? 'full' : 'summary',
        strategyIds: strategyIds,
      ),
    );
  }

  Future<BacktestServiceResponse> customStrategyRead(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final params = _mapOf(input['params']) ?? const <String, dynamic>{};
    final strategyId =
        '${input['strategyId'] ?? input['strategy_id'] ?? params['strategyId'] ?? params['strategy_id'] ?? ''}'
            .trim();
    if (strategyId.isEmpty) {
      return const BacktestServiceResponse(
        content: 'strategyId required for custom_strategy_read',
        isError: true,
      );
    }
    try {
      final record = _customStrategyEngine.readSaved(context, strategyId);
      return BacktestServiceResponse(
        content: _savedStrategySummary(record, strategyId),
      );
    } catch (error) {
      return BacktestServiceResponse(content: '$error', isError: true);
    }
  }

  Future<BacktestServiceResponse> customStrategyCompare(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final ids = input['strategyIds'] ?? input['strategy_ids'];
    return BacktestServiceResponse(
      content: _customStrategyEngine.compare(
        context,
        strategyIds: ids is List
            ? ids.map((value) => '$value').toList(growable: false)
            : const [],
      ),
    );
  }

  String? savedCustomStrategySymbol(ToolContext context, String strategyId) =>
      _customStrategyEngine.savedSymbol(context, strategyId);

  Future<BacktestServiceResponse> customStrategyRun(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final strategyId = (input['strategyId'] as String?)?.trim();
    if (strategyId == null || strategyId.isEmpty) {
      return const BacktestServiceResponse(
        content: 'strategyId required for custom_strategy_run',
        isError: true,
      );
    }
    try {
      final saved = _customStrategyEngine.readSaved(context, strategyId);
      if (!_isRunnableBacktestedStrategyRecord(saved)) {
        return BacktestServiceResponse(
          content: _savedStrategyReadback(
            context,
            strategyId,
            'saved strategy status ${saved['status']} is not runnable',
          ),
        );
      }
    } catch (error) {
      return BacktestServiceResponse(content: '$error', isError: true);
    }
    final runSymbol = symbol.trim().isNotEmpty
        ? symbol.trim()
        : (_customStrategyEngine.savedSymbol(context, strategyId) ?? '').trim();
    if (runSymbol.isEmpty) {
      try {
        return BacktestServiceResponse(
          content: _savedStrategyReadback(
            context,
            strategyId,
            'code-unavailable',
          ),
        );
      } catch (error) {
        return BacktestServiceResponse(content: '$error', isError: true);
      }
    }
    final period = _normalizePeriod(input['period'] as String?);
    final loaded = await _loadCandlesWithEvidenceForInput(
      runSymbol,
      period,
      input,
      context,
    );
    try {
      final saved = _customStrategyEngine.readSaved(context, strategyId);
      final content = _customStrategyEngine.runSaved(
        context,
        strategyId,
        loaded.candles,
        symbol: runSymbol,
      );
      content['dataEvidence'] = loaded.evidence;
      content['dataCoverage'] = _strategyDataCoverage(
        saved['strategySpec'] ?? saved['spec'],
        loaded.evidence,
        runSymbol,
      );
      return BacktestServiceResponse(content: content);
    } catch (error) {
      try {
        return BacktestServiceResponse(
          content: _savedStrategyReadback(context, strategyId, '$error'),
        );
      } catch (readbackError) {
        return BacktestServiceResponse(
          content: '$readbackError',
          isError: true,
        );
      }
    }
  }

  bool _isRunnableBacktestedStrategyRecord(Map<String, dynamic> record) {
    if (record['status'] == 'backtested') return true;
    final backtestEvidence = record['backtestEvidence'];
    if (backtestEvidence is Map && backtestEvidence['status'] == 'backtested') {
      return true;
    }
    final evidence = record['evidence'];
    return evidence is Map && evidence['status'] == 'backtested';
  }

  Map<String, dynamic>? _mapOf(Object? value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  List<String> _symbolsFromStrategySpec(Map<String, dynamic> spec) {
    final values = <String>[];
    void add(Object? value) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && !values.contains(text)) values.add(text);
    }

    add(spec['symbol']);
    add(spec['code']);
    add(spec['fundCode']);
    final symbols = spec['symbols'];
    if (symbols is List) {
      for (final value in symbols) {
        add(value);
      }
    }
    final codes = spec['codes'];
    if (codes is List) {
      for (final value in codes) {
        add(value);
      }
    }
    final universe = spec['universe'];
    if (universe is List) {
      for (final value in universe) {
        add(value);
      }
    } else if (universe is Map) {
      final universeSymbols = universe['symbols'];
      if (universeSymbols is List) {
        for (final value in universeSymbols) {
          add(value);
        }
      }
    }
    return values;
  }

  List<Map<String, dynamic>> _resolveFundRows(
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final explicit = input['fundRows'];
    if (explicit is List &&
        explicit.any((row) => row is Map && row.isNotEmpty)) {
      return explicit
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    final code = _firstFundCode(input);
    if (code.isEmpty) return const [];
    final limit = (input['limit'] as num?)?.toInt() ?? 120;
    final navRows = _dataManager.queryFundNav(code, limit: limit);
    if (navRows.isNotEmpty) return navRows;
    return _dataManager.queryFundMoneyYield(code, limit: limit);
  }

  String _firstFundCode(Map<String, dynamic> input) {
    final direct =
        '${input['code'] ?? input['symbol'] ?? input['fundCode'] ?? ''}'.trim();
    if (direct.isNotEmpty) return direct;
    final spec = input['strategySpec'];
    if (spec is! Map) return '';
    final specDirect =
        '${spec['fundCode'] ?? spec['code'] ?? spec['symbol'] ?? ''}'.trim();
    if (specDirect.isNotEmpty) return specDirect;
    final name = '${spec['name'] ?? spec['id'] ?? ''}';
    final match = RegExp(r'(?:^|_)(\d{6})(?:_|$)').firstMatch(name);
    return match?.group(1) ?? '';
  }

  Map<String, dynamic> _savedStrategySummary(
    Map<String, dynamic> record,
    String fallbackStrategyId,
  ) {
    final spec =
        _mapOf(record['strategySpec']) ??
        _mapOf(record['spec']) ??
        const <String, dynamic>{};
    final evidence =
        _mapOf(record['backtestEvidence']) ??
        _mapOf(record['evidence']) ??
        const <String, dynamic>{};
    final summary =
        _mapOf(record['dataAndAssumptionSummary']) ?? const <String, dynamic>{};
    final validationSummary =
        _mapOf(record['validationSummary']) ??
        _mapOf(_mapOf(record['validationReport'])?['validationSummary']) ??
        _mapOf(evidence['validationSummary']);
    final strategyId = '${record['strategyId'] ?? fallbackStrategyId}';
    final runnable = _isRunnableBacktestedStrategyRecord(record);
    return {
      'action': 'custom_strategy_read',
      'strategyId': strategyId,
      'version': record['version'] ?? 1,
      'status': record['status'],
      'savedStatus': record['status'],
      'runnable': runnable,
      'strategySpec': {
        'id': spec['id'] ?? strategyId,
        'name': spec['name'],
        'assetClass': spec['assetClass'] ?? spec['market'] ?? 'stock',
        'symbols': _strategySymbolsOf(spec),
        'indicators': spec['indicators'] is List
            ? spec['indicators']
            : const [],
        'entry': spec['entry'],
        'exit': spec['exit'],
        'positionSizing': spec['positionSizing'],
        'dataRequirements': spec['dataRequirements'],
      },
      'validationSummary': validationSummary,
      'validationIssueCount': _listLength(record['validationIssues']),
      'repairStepCount': _listLength(record['repairPlan']),
      'unsupportedCount': _listLength(record['unsupportedDetails']),
      'evidenceAction': evidence['action'],
      'metrics': _mapOf(evidence['metrics']),
      'dataCoverage':
          _mapOf(evidence['dataCoverage']) ?? _mapOf(summary['dataCoverage']),
      'dataEvidence':
          _mapOf(evidence['dataEvidence']) ?? _mapOf(summary['dataEvidence']),
      'lifecycle': record['lifecycle'] ?? const <String, dynamic>{},
      'dataAndAssumptionSummary': summary,
      'nextActions': runnable
          ? [
              {'action': 'custom_strategy_run', 'strategyId': strategyId},
            ]
          : [
              {
                'action': 'custom_strategy_list',
                'strategyIds': [strategyId],
              },
            ],
    };
  }

  List<String> _strategySymbolsOf(Map<String, dynamic> spec) {
    final raw = spec['symbols'] ?? spec['codes'] ?? spec['universe'];
    if (raw is List) {
      return raw
          .map((value) => '$value'.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    final universe = _mapOf(raw);
    if (universe != null && universe['symbols'] is List) {
      return (universe['symbols'] as List)
          .map((value) => '$value'.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    final single = spec['symbol'] ?? spec['code'] ?? spec['fundCode'];
    return single == null || '$single'.trim().isEmpty
        ? const []
        : ['$single'.trim()];
  }

  int _listLength(Object? value) => value is List ? value.length : 0;

  Map<String, dynamic> _savedStrategyReadback(
    ToolContext context,
    String strategyId,
    String reason,
  ) {
    final record = _customStrategyEngine.readSaved(context, strategyId);
    final summary =
        _mapOf(record['dataAndAssumptionSummary']) ?? const <String, dynamic>{};
    final lifecycleIssue = {
      'category': 'lifecycle',
      'path': 'strategyId',
      'field': 'status',
      'value': '${record['status']}',
      'message': reason,
      'suggestion':
          'Use this readback evidence directly, or create/save a backtested stock StrategySpec before requesting executable rerun.',
    };
    return {
      'action': 'custom_strategy_run',
      'strategyId': strategyId,
      'status': 'readback_only',
      'runnable': false,
      'reason': reason,
      'savedStatus': record['status'],
      'spec': record['spec'],
      'validation': record['validation'],
      'evidence': record['evidence'],
      'evidenceAction': (record['evidence'] is Map)
          ? (record['evidence'] as Map)['action']
          : null,
      'dataAndAssumptionSummary': summary,
      'lifecycle': record['lifecycle'] ?? const <String, dynamic>{},
      'lifecycleIssue': lifecycleIssue,
      'validationIssues': [lifecycleIssue],
      'repairPlan': record['repairPlan'] ?? const [],
      'workflowAdvice':
          'This saved strategy is not a runnable stock backtest artifact. Use this readback evidence directly, or create/save a backtested stock StrategySpec before requesting executable rerun.',
      ..._portfolioRankReadbackFields(summary),
    };
  }

  Map<String, dynamic> _portfolioRankReadbackFields(
    Map<String, dynamic> summary,
  ) {
    final portfolioEvidence = _mapOf(summary['portfolioEvidence']);
    final rebalanceDraft = _mapOf(summary['rebalanceDraft']);
    if (portfolioEvidence == null && rebalanceDraft == null) {
      return const <String, dynamic>{};
    }
    final validation =
        _mapOf(summary['portfolioValidation']) ??
        _mapOf(portfolioEvidence?['portfolioValidation']);
    final backtestEvidence =
        _mapOf(summary['portfolioBacktestEvidence']) ??
        _mapOf(portfolioEvidence?['portfolioBacktestEvidence']);
    final stabilityEvidence =
        _mapOf(summary['portfolioStabilityEvidence']) ??
        _mapOf(portfolioEvidence?['portfolioStabilityEvidence']);
    final rebalanceSimulation =
        _mapOf(summary['portfolioRebalanceSimulation']) ??
        _mapOf(portfolioEvidence?['portfolioRebalanceSimulation']);
    final returnQualityEvidence =
        _mapOf(summary['portfolioReturnQualityEvidence']) ??
        _mapOf(portfolioEvidence?['portfolioReturnQualityEvidence']) ??
        _mapOf(rebalanceDraft?['portfolioReturnQualityEvidence']);
    final scoringEvidence =
        _mapOf(summary['portfolioScoringEvidence']) ??
        _mapOf(portfolioEvidence?['portfolioScoringEvidence']) ??
        _mapOf(rebalanceDraft?['portfolioScoringEvidence']);
    final drawdownBudgetEvidence =
        _mapOf(summary['portfolioDrawdownBudgetEvidence']) ??
        _mapOf(portfolioEvidence?['portfolioDrawdownBudgetEvidence']) ??
        _mapOf(rebalanceDraft?['portfolioDrawdownBudgetEvidence']);
    final concentrationEvidence =
        _mapOf(summary['concentrationEvidence']) ??
        _mapOf(portfolioEvidence?['concentrationEvidence']) ??
        _mapOf(rebalanceDraft?['concentrationEvidence']);
    final positions = rebalanceDraft?['positions'];
    final selectedSymbols = positions is List
        ? positions
              .whereType<Map>()
              .map((position) => '${position['symbol'] ?? ''}'.trim())
              .where((symbol) => symbol.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final fields = <String, dynamic>{
      'readbackMode': 'portfolio_rank_readback',
      'evidenceMode': 'portfolio_rank_evidence',
      if (selectedSymbols.isNotEmpty) 'selectedSymbols': selectedSymbols,
      if (summary['candidateFailureEvidence'] != null)
        'candidateFailureEvidence': summary['candidateFailureEvidence'],
      if (summary['rankedRowsEvidence'] != null)
        'rankedRowsEvidence': summary['rankedRowsEvidence'],
      'portfolioNextActions': const [
        'read_evidence',
        'create_monitor',
        'request_trade_preparation_after_confirmation',
      ],
      'tradeBoundary':
          'Portfolio rank readback only; no simulated or real orders without explicit confirmation, separate sizing, and non-writing preview.',
    };
    void addIfPresent(String key, Object? value) {
      if (value != null) fields[key] = value;
    }

    addIfPresent('portfolioEvidence', portfolioEvidence);
    addIfPresent('rebalanceDraft', rebalanceDraft);
    addIfPresent('portfolioValidation', validation);
    addIfPresent('portfolioBacktestEvidence', backtestEvidence);
    addIfPresent('portfolioScoringEvidence', scoringEvidence);
    addIfPresent('portfolioDrawdownBudgetEvidence', drawdownBudgetEvidence);
    addIfPresent('portfolioReturnQualityEvidence', returnQualityEvidence);
    addIfPresent('portfolioStabilityEvidence', stabilityEvidence);
    addIfPresent('portfolioRebalanceSimulation', rebalanceSimulation);
    addIfPresent('concentrationEvidence', concentrationEvidence);
    return fields;
  }

  Future<List<bt.Candle>> _loadCandles(
    String symbol,
    String period,
    ToolContext? context,
  ) async {
    return _loadCandlesForRange(symbol, period, context);
  }

  Future<List<bt.Candle>> _loadCandlesForInput(
    String symbol,
    String period,
    Map<String, dynamic> input,
    ToolContext? context,
  ) {
    return _loadCandlesForRange(
      symbol,
      period,
      context,
      startDate: _requestedStartDate(input),
      endDate: _requestedEndDate(input),
    );
  }

  Future<_LoadedCandles> _loadCandlesWithEvidenceForInput(
    String symbol,
    String period,
    Map<String, dynamic> input,
    ToolContext? context,
  ) {
    return _loadCandlesWithEvidenceForRange(
      symbol,
      period,
      context,
      startDate: _requestedStartDate(input),
      endDate: _requestedEndDate(input),
    );
  }

  Future<List<bt.Candle>> _loadCandlesForRange(
    String symbol,
    String period,
    ToolContext? context, {
    String startDate = '',
    String endDate = '',
  }) async {
    if (_candleLoader != null) {
      return _candleLoader(symbol, period, context);
    }

    if (_isAShare(symbol)) {
      final normalizedSymbol = _normalizeAShareSymbol(symbol);
      final resolvedStartDate = startDate.isNotEmpty
          ? startDate
          : _periodToStartDate(period);
      final result = await _resolveService.resolveKline(
        normalizedSymbol,
        context: context,
        startDate: resolvedStartDate,
        endDate: endDate,
      );
      return result.bars
          .map(
            (bar) => bt.Candle(
              date: bar.date,
              open: bar.open,
              high: bar.high,
              low: bar.low,
              close: bar.close,
              volume: bar.volume,
              turnoverRate: bar.turnoverRate,
            ),
          )
          .toList();
    }

    final bars = await _yahooMarketDataService.fetchHistoryBars(
      symbol,
      period,
      context: context,
    );
    return bars
        .map(
          (bar) => bt.Candle(
            date: bar.date,
            open: bar.open,
            high: bar.high,
            low: bar.low,
            close: bar.close,
            volume: bar.volume,
          ),
        )
        .toList();
  }

  Future<_LoadedCandles> _loadCandlesWithEvidenceForRange(
    String symbol,
    String period,
    ToolContext? context, {
    String startDate = '',
    String endDate = '',
  }) async {
    if (_candleLoader != null) {
      final candles = await _candleLoader(symbol, period, context);
      return _LoadedCandles(
        candles,
        _candleEvidence(candles, source: 'injected candleLoader'),
      );
    }

    if (_isAShare(symbol)) {
      final normalizedSymbol = _normalizeAShareSymbol(symbol);
      final resolvedStartDate = startDate.isNotEmpty
          ? startDate
          : _periodToStartDate(period);
      final result = await _resolveService.resolveKline(
        normalizedSymbol,
        context: context,
        startDate: resolvedStartDate,
        endDate: endDate,
      );
      final candles = result.bars
          .map(
            (bar) => bt.Candle(
              date: bar.date,
              open: bar.open,
              high: bar.high,
              low: bar.low,
              close: bar.close,
              volume: bar.volume,
              turnoverRate: bar.turnoverRate,
            ),
          )
          .toList();
      return _LoadedCandles(
        candles,
        _candleEvidence(
          candles,
          source: result.source,
          cacheStatus: result.source.startsWith('local')
              ? 'local-hit'
              : 'provider-fetch',
        ),
      );
    }

    final bars = await _yahooMarketDataService.fetchHistoryBars(
      symbol,
      period,
      context: context,
    );
    final candles = bars
        .map(
          (bar) => bt.Candle(
            date: bar.date,
            open: bar.open,
            high: bar.high,
            low: bar.low,
            close: bar.close,
            volume: bar.volume,
          ),
        )
        .toList();
    return _LoadedCandles(
      candles,
      _candleEvidence(candles, source: 'yahoo', cacheStatus: 'provider-fetch'),
    );
  }

  String _normalizeStrategy(String? value, {String fallback = 'compare'}) {
    final raw = (value ?? fallback).trim().toLowerCase();
    if (raw.isEmpty) return fallback;
    return switch (raw) {
      'buy_hold' || 'buy-hold' || 'buyhold' || 'buy_and_hold' => 'compare',
      'boll' => 'bollinger',
      'rsi mean reversion' ||
      'rsi_mean_reversion' ||
      'rsi-reversion' ||
      'rsi strategy' => 'rsi',
      _ => raw,
    };
  }

  Map<String, List<dynamic>> _normalizeParamGrid(Map<String, dynamic> grid) {
    final normalized = <String, List<dynamic>>{};
    for (final entry in grid.entries) {
      final key = switch (entry.key.trim()) {
        'rsiPeriod' || 'rsi_period' || 'rsi_periods' => 'period',
        'periods' => 'period',
        'oversoldThreshold' || 'oversold_threshold' => 'oversold',
        'overboughtThreshold' || 'overbought_threshold' => 'overbought',
        final value => value,
      };
      final values = entry.value is List ? entry.value as List : [entry.value];
      normalized[key] = values;
    }
    return normalized;
  }

  String _normalizePeriod(String? value) {
    final raw = (value ?? '1y').trim().toLowerCase();
    return switch (raw) {
      '1m' => '1mo',
      '3m' => '3mo',
      '6m' => '6mo',
      '1yr' => '1y',
      '2yr' => '2y',
      '3yr' => '3y',
      '5yr' => '5y',
      '7yr' => '7y',
      '10yr' => '10y',
      'max' => '10y',
      '' => '1y',
      _ => raw,
    };
  }

  String _requestedStartDate(Map<String, dynamic> input) {
    return (input['startDate'] ?? input['start'] ?? '').toString().trim();
  }

  String _requestedEndDate(Map<String, dynamic> input) {
    return (input['endDate'] ?? input['end'] ?? '').toString().trim();
  }

  bool _isAShare(String symbol) {
    return RegExp(r'^\d{6}$').hasMatch(_normalizeAShareSymbol(symbol));
  }

  String _normalizeAShareSymbol(String symbol) {
    final trimmed = symbol.trim().toUpperCase();
    final suffixRemoved = trimmed.replaceAll(RegExp(r'\.\w+$'), '');
    return suffixRemoved.replaceFirst(RegExp(r'^(SH|SZ)'), '');
  }

  String _periodToStartDate(String period) {
    final now = DateTime.now();
    final days = switch (period) {
      '1mo' => 30,
      '3mo' => 90,
      '6mo' => 180,
      '1y' => 365,
      '2y' => 730,
      '3y' => 1095,
      '5y' => 1825,
      '7y' => 2555,
      '10y' => 3650,
      _ => 365,
    };
    final date = now.subtract(Duration(days: days));
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _LoadedCandles {
  final List<bt.Candle> candles;
  final Map<String, dynamic> evidence;

  const _LoadedCandles(this.candles, this.evidence);
}

Map<String, dynamic> _candleEvidence(
  List<bt.Candle> candles, {
  required String source,
  String? cacheStatus,
}) {
  return {
    'source': source,
    'cacheStatus': cacheStatus ?? source,
    'rows': candles.length,
    'startDate': candles.isEmpty ? null : candles.first.date,
    'endDate': candles.isEmpty ? null : candles.last.date,
  };
}

Map<String, dynamic> _strategyDataCoverage(
  Object? rawSpec,
  Map<String, dynamic> evidence,
  String symbol,
) {
  final spec = rawSpec is Map ? Map<String, dynamic>.from(rawSpec) : {};
  final dataRequirements = spec['dataRequirements'] is Map
      ? Map<String, dynamic>.from(spec['dataRequirements'] as Map)
      : const <String, dynamic>{};
  final rows = (evidence['rows'] is num)
      ? (evidence['rows'] as num).toInt()
      : 0;
  final minBars = (dataRequirements['minBars'] is num)
      ? (dataRequirements['minBars'] as num).toInt()
      : 120;
  return {
    'mode': 'strategy_backtest_kline_coverage',
    'symbol': symbol,
    'source': evidence['source'],
    'cacheStatus': evidence['cacheStatus'],
    'rows': rows,
    'requiredBars': minBars,
    'sufficient': rows >= minBars,
    'actualStartDate': evidence['startDate'],
    'actualEndDate': evidence['endDate'],
    'dataRequirements': dataRequirements,
  };
}
