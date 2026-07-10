import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/domain/market/backtest/custom_strategy_engine.dart';
import 'package:finagent/domain/market/backtest/backtest_core.dart';
import 'package:finagent/domain/market/backtest/strategy_indicator_calculators.dart';
import 'package:finagent/domain/market/backtest/strategy_spec_validator.dart';
import 'package:finagent/domain/market/services/backtest_market_data_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom strategy help is compact by default and lifecycle-complete', () {
    final help = CustomStrategyEngine().help();

    expect(help['action'], 'custom_strategy_help');
    expect(help['detail'], 'summary');
    expect(help['supportedActions'], contains('custom_strategy_run'));

    final executable = help['executableV1'] as Map;
    expect(executable['indicatorCount'], greaterThan(20));
    expect(executable['indicatorsPreview'], contains('rsi'));
    expect(executable['catalogRequest'], containsPair('detail', 'catalog'));
    expect(executable.containsKey('indicatorPreviewCatalog'), isFalse);
    expect(executable.containsKey('indicators'), isFalse);
    expect(executable.containsKey('indicatorCatalog'), isFalse);
    expect(executable.containsKey('indicatorCatalogByCategory'), isFalse);
    expect(executable.containsKey('stockExample'), isFalse);
    expect(executable.containsKey('ruleCompositionExamples'), isFalse);

    final fundObservation = help['fundObservationV1'] as Map;
    expect(fundObservation['indicatorCount'], greaterThan(5));
    expect(fundObservation['indicatorsPreview'], contains('fund_drawdown'));
    expect(
      fundObservation['catalogRequest'],
      containsPair('detail', 'catalog'),
    );
    expect(fundObservation.containsKey('indicatorPreviewCatalog'), isFalse);
    expect(fundObservation.containsKey('indicators'), isFalse);
    expect(fundObservation.containsKey('indicatorCatalog'), isFalse);
    expect(fundObservation.containsKey('indicatorCatalogByCategory'), isFalse);
    expect(fundObservation.containsKey('ordinaryFundExample'), isFalse);
    expect(fundObservation.containsKey('moneyFundExample'), isFalse);
    expect(help.containsKey('proxyContract'), isFalse);
    expect(help.containsKey('unsupportedV1'), isFalse);
    expect(help.containsKey('inputContracts'), isFalse);
    expect(help.containsKey('outputContracts'), isFalse);
  });

  test('custom strategy help exposes full catalogs only when requested', () {
    final help = CustomStrategyEngine().help({'detail': 'catalog'});

    expect(help['detail'], 'catalog');

    final executable = help['executableV1'] as Map;
    expect(executable['indicators'], contains('rsi'));
    expect(executable['indicatorCatalog'], isNotEmpty);
    expect(
      executable['indicatorCatalogByCategory'],
      containsPair('momentum', isNotEmpty),
    );
    expect(
      executable['indicatorCatalogByCategory'],
      containsPair(
        'trend',
        contains(
          isA<Map>()
              .having((row) => row['type'], 'type', 'vortex_spread')
              .having((row) => row['requiredFields'], 'requiredFields', [
                'high',
                'low',
                'close',
              ])
              .having((row) => row['lookbackBars'], 'lookbackBars', 14),
        ),
      ),
    );

    final fundObservation = help['fundObservationV1'] as Map;
    expect(fundObservation['indicators'], contains('fund_drawdown'));
    expect(fundObservation['indicatorCatalog'], isNotEmpty);
    expect(
      fundObservation['indicatorCatalogByCategory'],
      containsPair('fund_return_quality', isNotEmpty),
    );
  });

  test(
    'custom strategy help treats field catalog requests as detailed help',
    () {
      final help = CustomStrategyEngine().help({
        'fields': 'executableV1.indicatorCatalog,executableV1.indicators',
        'indicators': ['sma', 'rsi'],
      });

      expect(help['detail'], 'catalog');
      final executable = help['executableV1'] as Map;
      expect(executable['indicatorCatalog'], isNotEmpty);
      expect(
        executable['indicatorCatalog'],
        contains(isA<Map>().having((row) => row['type'], 'type', 'rsi')),
      );
      expect(executable['stockExample'], isA<Map>());
    },
  );

  test(
    'normalizes structured top-level fund signals into observation rules',
    () {
      final validation = CustomStrategyEngine().validate({
        'name': '基金回撤趋势定投观察策略',
        'description':
            'Fund DCA observation with top-level structured signals.',
        'assetClass': 'fund',
        'market': 'fund',
        'dataRequirements': {
          'dataClass': 'ordinary_fund_nav',
          'requiredFields': ['date', 'nav'],
          'minBars': 60,
        },
        'signals': [
          {
            'type': 'fund_drawdown',
            'period': 60,
            'operator': '<',
            'threshold': -0.1,
            'name': '中期回撤超10%',
          },
          {
            'type': 'nav_trend',
            'period': 20,
            'operator': '>',
            'threshold': 0,
            'name': '短期净值趋势向上',
          },
        ],
        'observation': {'name': '定投观察窗口', 'type': 'dca_window'},
      });

      expect(validation['status'], 'validated');
      final spec = validation['spec'] as Map;
      final entry = (spec['entry'] as Map)['all'] as List;
      expect(
        entry,
        contains(
          isA<Map>()
              .having((row) => row['left'], 'left', 'fundDrawdown60')
              .having((row) => row['op'], 'op', '>=')
              .having((row) => row['right'], 'right', 10),
        ),
      );
      expect(
        entry,
        contains(
          isA<Map>()
              .having((row) => row['left'], 'left', 'navTrend20')
              .having((row) => row['op'], 'op', '>')
              .having((row) => row['right'], 'right', 0),
        ),
      );
      expect(
        validation['accepted'],
        containsAll(['entry:fundDrawdown60:>=', 'entry:navTrend20:>']),
      );
    },
  );

  test('normalizes fund output aliases and object-form rule sides', () {
    final validation = CustomStrategyEngine().validate({
      'name': 'fund_dca_drawdown_trend',
      'description':
          'Fund DCA observation using output aliases and object-form rule sides.',
      'assetClass': 'fund',
      'market': 'fund',
      'dataRequirements': {
        'fields': ['date', 'nav'],
        'minimumBars': 120,
      },
      'indicators': [
        {
          'type': 'nav_trend',
          'params': {'period': 20},
          'output': 'nav_trend_20',
        },
        {
          'type': 'fund_drawdown',
          'params': {'period': 120},
          'output': 'dd_120',
        },
      ],
      'signals': [
        {
          'name': 'deep_drawdown_add',
          'category': 'dca_observation',
          'condition': {
            'left': {'indicator': 'dd_120', 'field': 'value'},
            'op': '>',
            'right': {'value': 0.1},
          },
        },
        {
          'name': 'trend_recovery',
          'category': 'dca_observation',
          'condition': {
            'left': {'indicator': 'nav_trend_20', 'field': 'value'},
            'op': '>',
            'right': {'value': 0},
          },
        },
      ],
    });

    expect(validation['status'], 'validated');
    final spec = validation['spec'] as Map;
    final indicatorIds = (spec['indicators'] as List)
        .whereType<Map>()
        .map((row) => row['id'])
        .toList();
    expect(indicatorIds, containsAll(['dd_120', 'nav_trend_20']));
    final entry = (spec['entry'] as Map)['all'] as List;
    expect(
      entry,
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'dd_120')
            .having((row) => row['op'], 'op', '>')
            .having((row) => row['right'], 'right', 10),
      ),
    );
    expect(
      entry,
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'nav_trend_20')
            .having((row) => row['op'], 'op', '>')
            .having((row) => row['right'], 'right', 0),
      ),
    );
  });

  test(
    'normalizes legacy structured signals and exits into StrategySpec v1',
    () {
      final validation = CustomStrategyEngine().validate({
        'name': '茅台RSI均值回归',
        'type': 'stockTrading',
        'market': 'cn',
        'signals': {
          'entry': [
            {'indicator': 'rsi', 'period': 14, 'operator': '<', 'value': 35},
            {
              'indicator': 'price_change_pct',
              'period': 1,
              'operator': '>',
              'value': 0,
            },
          ],
        },
        'exits': {
          'stop_loss_pct': 8,
          'take_profit_pct': 12,
          'trailing_stop_pct': 6,
        },
        'positionSizing': 'fixed_fraction',
        'fixedFraction': 0.3,
      });

      expect(validation['status'], 'validated');
      final spec = validation['spec'] as Map;
      final indicatorIds = (spec['indicators'] as List)
          .whereType<Map>()
          .map((row) => row['id'])
          .toList();
      expect(indicatorIds, containsAll(['rsi14', 'price_change_pct1']));
      expect(
        (spec['entry'] as Map)['all'],
        containsAll([
          isA<Map>()
              .having((row) => row['left'], 'left', 'rsi14')
              .having((row) => row['op'], 'op', '<')
              .having((row) => row['right'], 'right', 35.0),
          isA<Map>()
              .having((row) => row['left'], 'left', 'price_change_pct1')
              .having((row) => row['op'], 'op', '>')
              .having((row) => row['right'], 'right', 0.0),
        ]),
      );
      expect(
        (spec['exit'] as Map)['any'],
        containsAll([
          {'type': 'stop_loss_pct', 'value': 8},
          {'type': 'take_profit_pct', 'value': 12},
          {'type': 'trailing_stop_pct', 'value': 6},
        ]),
      );
      expect(spec['positionSizing'], {'type': 'fixed_fraction', 'value': 0.3});
      expect(
        validation['suggestedActions'],
        contains(
          isA<Map>()
              .having(
                (row) => row['action'],
                'action',
                'custom_strategy_backtest',
              )
              .having((row) => row['strategySpec'], 'strategySpec', isA<Map>()),
        ),
      );
    },
  );

  test('custom strategy list summary does not expose storage paths', () {
    final dir = Directory.systemTemp.createTempSync(
      'finagent_strategy_list_contract_',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
    final engine = CustomStrategyEngine();
    final spec = {
      'id': 'path_free_summary_v1',
      'name': 'Path Free Summary',
      'assetClass': 'stock',
      'symbols': ['300059'],
      'indicators': [
        {
          'id': 'sma20',
          'type': 'sma',
          'params': {'period': 20},
        },
      ],
      'entry': {
        'all': [
          {'left': 'close', 'op': '>', 'right': 'sma20'},
        ],
      },
      'exit': {
        'any': [
          {'type': 'stop_loss_pct', 'value': 6},
        ],
      },
      'positionSizing': {'type': 'fixed_fraction', 'value': 0.2},
      'dataRequirements': {'minBars': 40},
    };

    engine.save(context, spec);
    final summary = engine.list(context);

    expect(summary['action'], 'custom_strategy_list');
    expect(summary['detail'], 'summary');
    expect(summary.containsKey('paths'), isFalse);
    final rows = summary['strategies'] as List;
    expect(rows, hasLength(1));
    expect((rows.first as Map).containsKey('itemPath'), isFalse);
    expect((rows.first as Map).containsKey('dataRequirements'), isFalse);
    expect(jsonEncode(summary).length, lessThan(9000));

    final full = engine.list(
      context,
      detail: 'full',
      strategyIds: ['path_free_summary_v1'],
    );
    expect(full['detail'], 'full');
    expect(full['paths'], isA<Map>());
    expect(
      ((full['strategies'] as List).first as Map)['itemPath'],
      isA<String>(),
    );
    final readback = engine.readSaved(context, 'path_free_summary_v1');
    final serviceRead = {
      'action': 'custom_strategy_read',
      'strategyId': readback['strategyId'],
      'status': readback['status'],
    };
    expect(serviceRead, {
      'action': 'custom_strategy_read',
      'strategyId': 'path_free_summary_v1',
      'status': 'validated',
    });
  });

  test(
    'custom strategy read exposes portfolio rebalance monitor contract',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'finagent_ranked_strategy_read_contract_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
      final service = BacktestMarketDataService(
        candleLoader: (symbol, period, context) async =>
            _relativeStrengthCandles(symbol),
      );
      final spec = {
        'id': 'ranked_portfolio_read_v1',
        'name': 'Ranked Portfolio Read',
        'assetClass': 'stock',
        'symbols': ['600519', '000858', '300059'],
        'dataRequirements': {'minBars': 60},
        'indicators': [
          {
            'id': 'rsi14',
            'type': 'rsi',
            'params': {'period': 14},
          },
        ],
        'entry': {
          'all': [
            {'left': 'rsi14', 'op': '>', 'right': 50},
          ],
        },
        'exit': {
          'any': [
            {'type': 'stop_loss_pct', 'value': 6},
          ],
        },
        'positionSizing': {'type': 'fixed_fraction', 'value': 0.2},
      };
      final evidence = {
        'action': 'custom_strategy_rank',
        'status': 'ranked',
        'portfolioEvidence': {
          'mode': 'equal_weight_selected_metrics',
          'selectedCount': 2,
          'aggregateMetrics': {
            'selectedSymbols': ['600519', '000858'],
            'expectedReturnPct': 8.4,
            'portfolioMaxDrawdownPct': -5.2,
          },
          'concentrationEvidence': {
            'mode': 'portfolio_concentration_v1',
            'status': 'within_cap',
            'effectivePositionCount': 2,
          },
        },
        'rebalanceDraft': {
          'mode': 'equal_weight_top_n',
          'rebalanceInterval': 'monthly',
          'maxPositionWeight': 0.4,
          'positions': [
            {'symbol': '600519', 'targetWeight': 0.4, 'weightCapped': true},
            {'symbol': '000858', 'targetWeight': 0.4},
          ],
          'tradeBoundary': 'evidence only; confirmation required before order',
        },
      };

      final save = await service.customStrategySave({
        'strategySpec': spec,
        'evidence': evidence,
      }, context);
      expect(save.isError, isFalse);
      expect(save.content, isA<Map>());
      expect((save.content as Map)['status'], 'ranked');

      final read = await service.customStrategyRead({
        'strategyId': 'ranked_portfolio_read_v1',
      }, context);
      expect(read.isError, isFalse);
      final readback = read.content as Map;
      expect(readback['action'], 'custom_strategy_read');
      expect(readback['strategyId'], 'ranked_portfolio_read_v1');
      expect(readback['runnable'], isFalse);
      expect(readback['readbackMode'], 'portfolio_rank_readback');
      expect(readback['evidenceMode'], 'portfolio_rank_evidence');
      expect(readback['portfolioEvidence'], isA<Map>());
      expect(readback['rebalanceDraft'], isA<Map>());
      expect(
        readback['monitorAction'],
        containsPair('template', 'portfolio_rebalance_monitor'),
      );
      expect(
        readback['monitorAction'],
        containsPair('strategyId', 'ranked_portfolio_read_v1'),
      );
      expect(
        '${(readback['monitorAction'] as Map)['boundary']}',
        allOf(
          contains('Review-only portfolio rebalance monitor'),
          contains('must not create per-symbol strategy_signal monitors'),
        ),
      );

      final run = await service.customStrategyRun('', {
        'strategyId': 'ranked_portfolio_read_v1',
      }, context);
      expect(run.isError, isFalse);
      final runReadback = run.content as Map;
      expect(runReadback['status'], 'readback_only');
      expect(
        runReadback['monitorAction'],
        containsPair('template', 'portfolio_rebalance_monitor'),
      );
      final rerank = await service.customStrategyRank(
        ['600519', '000858', '300059'],
        {
          'strategyId': 'ranked_portfolio_read_v1',
          'topN': 2,
          'rankingMetric': 'relative_strength_pct',
          'rebalanceInterval': 'monthly',
          'detail': 'full',
        },
        context,
      );
      expect(rerank.isError, isFalse);
      final reranked = rerank.content as Map;
      expect(reranked['action'], 'custom_strategy_rank');
      expect(reranked['status'], 'ranked');
      expect(
        reranked['portfolioEvidence'],
        containsPair('mode', 'equal_weight_selected_metrics'),
      );
      final compactRerank = await service.customStrategyRank(
        ['600519', '000858', '300059'],
        {
          'strategyId': 'ranked_portfolio_read_v1',
          'topN': 2,
          'rankingMetric': 'relative_strength_pct',
          'rebalanceInterval': 'monthly',
        },
        context,
      );
      expect(compactRerank.isError, isFalse);
      final compact = compactRerank.content as Map;
      expect(
        compact['monitorAction'],
        containsPair('template', 'portfolio_rebalance_monitor'),
      );
      expect(
        compact['monitorAction'],
        containsPair('strategyId', 'ranked_portfolio_read_v1'),
      );
      expect(
        '${(compact['monitorAction'] as Map)['boundary']}',
        allOf(
          contains('Use MonitorCreate(template:"portfolio_rebalance_monitor")'),
          contains('Do not write raw monitor script'),
        ),
      );
    },
  );

  test('vortex_spread is a validated executable strategy indicator', () {
    final candles = List<Candle>.generate(36, (index) {
      final close = 10.0 + index * 0.4;
      return Candle(
        date: '2026-01-${(index + 1).toString().padLeft(2, '0')}',
        open: close - 0.1,
        high: close + 0.5,
        low: close - 0.4,
        close: close,
        volume: 1000 + index * 10,
      );
    });
    final spec = {
      'id': 'vortex_test',
      'name': 'Vortex trend test',
      'version': 1,
      'market': 'stock',
      'universe': {
        'symbols': ['600519'],
      },
      'dataRequirements': {'minBars': 30},
      'indicators': [
        {
          'id': 'vortex',
          'type': 'vortex_spread',
          'params': {'period': 14},
        },
      ],
      'entry': {
        'all': [
          {'left': 'vortex', 'op': '>', 'right': 0},
        ],
      },
      'exit': {
        'any': [
          {'type': 'stop_loss_pct', 'value': 8},
        ],
      },
      'positionSizing': {'type': 'fixed_fraction', 'fraction': 0.5},
    };

    final validation = validateStockStrategySpec(spec);
    expect(validation['status'], 'validated');
    expect(validation['errors'], isEmpty);
    final requirements = validation['dataRequirements'] as Map;
    final indicators = requirements['indicators'] as Map;
    expect(indicators['vortex']['requiredFields'], ['high', 'low', 'close']);
    expect(indicators['vortex']['lookbackBars'], 14);

    final values = computeStrategyIndicators(spec, candles)['vortex']!;
    expect(values.take(14), everyElement(isNull));
    expect(values.skip(14).whereType<double>(), isNotEmpty);
    expect(values.last, greaterThan(0));
  });
}

List<Candle> _relativeStrengthCandles(String symbol) {
  final drift = symbol == '300059'
      ? 0.18
      : symbol == '000858'
      ? 0.1
      : 0.04;
  return List<Candle>.generate(80, (index) {
    final close = 10 + index * drift + (index % 5) * 0.03;
    return Candle(
      date: '2026-01-${(index % 28 + 1).toString().padLeft(2, '0')}',
      open: close - 0.05,
      high: close + 0.2,
      low: close - 0.2,
      close: close,
      volume: 1000 + index * 10,
    );
  });
}
