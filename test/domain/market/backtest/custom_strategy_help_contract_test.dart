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
    expect(executable['stockExample'], isA<Map>());
    final stockExample = executable['stockExample'] as Map;
    expect(stockExample['indicators'], isA<List>());
    expect(
      (stockExample['indicators'] as List).any(
        (row) => row is Map && row['id'] == 'ema20' && row['type'] == 'ema',
      ),
      isTrue,
    );
    expect(executable['ruleCompositionExamples'], isA<Map>());
    final ruleExamples = executable['ruleCompositionExamples'] as Map;
    expect(
      (ruleExamples['declaredIndicatorPattern'] as Map)['entryRule'],
      containsPair('left', 'ema20'),
    );

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

  test('custom strategy accepts entryRules and exitRules lists', () async {
    final service = BacktestMarketDataService(
      candleLoader: (symbol, period, context) async =>
          _relativeStrengthCandles(symbol),
    );

    final validation = await service.customStrategyValidate({
      'strategySpec': {
        'name': 'EMA Cross Trend 600519',
        'market': 'cn',
        'symbols': ['600519'],
        'indicators': [
          {
            'id': 'ema_fast',
            'type': 'ema',
            'source': 'close',
            'params': {'period': 12},
          },
          {
            'id': 'ema_slow',
            'type': 'ema',
            'source': 'close',
            'params': {'period': 26},
          },
          {
            'id': 'rsi14',
            'type': 'rsi',
            'source': 'close',
            'params': {'period': 14},
          },
        ],
        'entryRules': [
          {
            'left': 'ema_fast',
            'operator': 'crosses_above',
            'right': 'ema_slow',
          },
        ],
        'exitRules': [
          {
            'left': 'ema_fast',
            'operator': 'crosses_below',
            'right': 'ema_slow',
          },
          {'left': 'rsi14', 'operator': '>', 'right': 70},
        ],
      },
    });

    expect(validation.isError, isFalse);
    final content = validation.content as Map<String, dynamic>;
    expect(content['status'], 'validated');
    final spec = content['spec'] as Map<String, dynamic>;
    expect((spec['entry'] as Map)['all'], contains(isA<Map>()));
    expect((spec['exit'] as Map)['any'], contains(isA<Map>()));
  });

  test('custom strategy accepts equality operators for flag rules', () {
    final validation = CustomStrategyEngine().validate({
      'name': 'volume flag equality',
      'market': 'cn',
      'symbols': ['300059'],
      'indicators': [
        {
          'id': 'volBreak20',
          'type': 'volume_breakout',
          'source': 'volume',
          'params': {'period': 20},
        },
      ],
      'entry': {
        'all': [
          {'left': 'volBreak20', 'op': '==', 'right': 1},
        ],
      },
      'exit': {
        'any': [
          {'left': 'volBreak20', 'op': '!=', 'right': 1},
          {'type': 'stop_loss_pct', 'value': 6},
        ],
      },
    });

    expect(validation['status'], 'validated');
    expect(validation['errors'], isEmpty);
  });

  test('custom strategy accepts agent-authored entrySignals and exitSignals lists', () async {
    final service = BacktestMarketDataService(
      candleLoader: (symbol, period, context) async =>
          _relativeStrengthCandles(symbol),
    );

    final validation = await service.customStrategyValidate({
      'strategySpec': {
        'name': 'Simple SMA Trend',
        'market': 'cn',
        'assetClass': 'stock',
        'dataRequirements': {'minBars': 120},
        'entrySignals': [
          {
            'indicator': 'sma',
            'params': {'period': 20},
            'operator': '>',
            'left': {'field': 'close'},
            'right': {
              'indicator': 'sma',
              'params': {'period': 20},
            },
          },
        ],
        'exitSignals': [
          {
            'indicator': 'sma',
            'params': {'period': 20},
            'operator': '<',
            'left': {'field': 'close'},
            'right': {
              'indicator': 'sma',
              'params': {'period': 20},
            },
          },
        ],
        'stopLossPct': 8,
        'positionSizing': {'type': 'full_capital'},
      },
    });

    expect(validation.isError, isFalse);
    final content = validation.content as Map<String, dynamic>;
    expect(content['status'], 'validated');
    final spec = content['spec'] as Map<String, dynamic>;
    final indicators = (spec['indicators'] as List).cast<Map>();
    expect(indicators.any((row) => row['id'] == 'sma20'), isTrue);
    expect(
      (spec['entry'] as Map)['all'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'close')
            .having((row) => row['op'], 'op', '>')
            .having((row) => row['right'], 'right', {'mul': ['sma20', 1]}),
      ),
    );
    expect(
      (spec['exit'] as Map)['any'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'close')
            .having((row) => row['op'], 'op', '<')
            .having((row) => row['right'], 'right', {'mul': ['sma20', 1]}),
      ),
    );
  });

  test('custom strategy preserves arithmetic right-hand multiplier objects', () async {
    final service = BacktestMarketDataService(
      candleLoader: (symbol, period, context) async =>
          _relativeStrengthCandles(symbol),
    );

    final validation = await service.customStrategyValidate({
      'strategySpec': {
        'name': 'volume multiplier rule',
        'market': 'cn',
        'assetClass': 'stock',
        'indicators': [
          {
            'id': 'vol20',
            'type': 'volume_sma',
            'source': 'volume',
            'params': {'period': 20},
          },
        ],
        'entry': {
          'all': [
            {
              'left': 'volume',
              'op': '>=',
              'right': {'left': 'volume_sma', 'op': '*', 'right': 1.2},
            },
          ],
        },
        'exit': {
          'any': [
            {'type': 'stop_loss_pct', 'value': 8},
          ],
        },
      },
    });

    expect(validation.isError, isFalse);
    final spec = (validation.content as Map<String, dynamic>)['spec']
        as Map<String, dynamic>;
    expect(
      (spec['entry'] as Map)['all'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'volume')
            .having((row) => row['op'], 'op', '>=')
            .having((row) => row['right'], 'right', {'mul': ['vol20', 1.2]}),
      ),
    );
  });

  test('custom strategy accepts top-level signals as indicator declarations', () async {
    final service = BacktestMarketDataService(
      candleLoader: (symbol, period, context) async =>
          _relativeStrengthCandles(symbol),
    );

    final validation = await service.customStrategyValidate({
      'strategySpec': {
        'name': 'Moutai EMA Trend',
        'market': 'cn',
        'assetClass': 'stock',
        'signals': [
          {'indicator': 'ema', 'period': 12, 'input': 'close', 'output': 'ema12'},
          {'indicator': 'ema', 'period': 26, 'input': 'close', 'output': 'ema26'},
        ],
        'entryRules': [
          {'lhs': 'ema12', 'op': 'crosses_above', 'rhs': 'ema26'},
        ],
        'exitRules': [
          {'lhs': 'ema12', 'op': 'crosses_below', 'rhs': 'ema26'},
        ],
      },
    });

    expect(validation.isError, isFalse);
    final content = validation.content as Map<String, dynamic>;
    expect(content['status'], 'validated');
    final spec = content['spec'] as Map<String, dynamic>;
    final indicators = (spec['indicators'] as List).cast<Map>();
    expect(indicators.any((row) => row['id'] == 'ema12'), isTrue);
    expect(indicators.any((row) => row['id'] == 'ema26'), isTrue);
    expect(
      (spec['entry'] as Map)['all'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'ema12')
            .having((row) => row['op'], 'op', 'crosses_above')
            .having((row) => row['right'], 'right', 'ema26'),
      ),
    );
    expect(
      (spec['exit'] as Map)['any'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'ema12')
            .having((row) => row['op'], 'op', 'crosses_below')
            .having((row) => row['right'], 'right', 'ema26'),
      ),
    );
  });

  test('custom strategy normalizes explicit buy/sell rule condition DSL', () async {
    final service = BacktestMarketDataService(
      candleLoader: (symbol, period, context) async =>
          _relativeStrengthCandles(symbol),
    );

    final validation = await service.customStrategyValidate({
      'strategySpec': {
        'name': 'SMA Trend DSL',
        'market': 'cn',
        'assetClass': 'stock',
        'indicators': [
          {
            'id': 'sma20',
            'type': 'sma',
            'params': {'period': 20},
          },
          {
            'id': 'sma60',
            'type': 'sma',
            'params': {'period': 60},
          },
        ],
        'rules': [
          {
            'name': 'buy',
            'action': 'buy',
            'condition': 'close > sma20 and sma20 > sma60',
          },
          {'name': 'sell', 'action': 'sell', 'condition': 'close < sma20'},
        ],
        'exits': {'stop_loss_pct': 8},
        'positionSizing': {'type': 'full_capital'},
      },
    });

    expect(validation.isError, isFalse);
    final content = validation.content as Map<String, dynamic>;
    expect(content['status'], 'validated');
    final spec = content['spec'] as Map<String, dynamic>;
    expect(
      (spec['entry'] as Map)['all'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'close')
            .having((row) => row['op'], 'op', '>')
            .having((row) => row['right'], 'right', 'sma20'),
      ),
    );
    expect(
      (spec['entry'] as Map)['all'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'sma20')
            .having((row) => row['op'], 'op', '>')
            .having((row) => row['right'], 'right', 'sma60'),
      ),
    );
    expect(
      (spec['exit'] as Map)['any'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'close')
            .having((row) => row['op'], 'op', '<')
            .having((row) => row['right'], 'right', 'sma20'),
      ),
    );
  });

  test('custom strategy returns structured repair feedback for invalid condition DSL', () async {
    final service = BacktestMarketDataService(
      candleLoader: (symbol, period, context) async =>
          _relativeStrengthCandles(symbol),
    );

    final validation = await service.customStrategyValidate({
      'strategySpec': {
        'name': 'Invalid DSL',
        'market': 'cn',
        'assetClass': 'stock',
        'indicators': [
          {
            'id': 'sma20',
            'type': 'sma',
            'params': {'period': 20},
          },
        ],
        'rules': [
          {
            'action': '买入',
            'condition': 'close rises above sma20 with strong mood',
          },
        ],
        'exit': {
          'any': [
            {'type': 'stop_loss_pct', 'value': 8},
          ],
        },
      },
    });

    expect(validation.isError, isFalse);
    final content = validation.content as Map<String, dynamic>;
    expect(content['status'], 'rejected');
    final issues = (content['validationIssues'] as List).cast<Map>();
    expect(
      issues,
      contains(
        isA<Map>()
            .having((row) => row['category'], 'category', 'condition_dsl')
            .having((row) => row['path'], 'path', 'rules[0].action')
            .having(
              (row) => row['allowedActions'],
              'allowedActions',
              ['entry', 'exit', 'buy', 'sell', 'long', 'close'],
            ),
      ),
    );
    expect(
      issues,
      contains(
        isA<Map>()
            .having((row) => row['category'], 'category', 'condition_dsl')
            .having((row) => row['path'], 'path', 'rules[0].condition')
            .having(
              (row) => '${row['grammar']}',
              'grammar',
              contains('<series-or-indicator-id>'),
            ),
      ),
    );
    final repairPlan = (content['repairPlan'] as List).cast<Map>();
    expect(
      repairPlan,
      contains(
        isA<Map>()
            .having((row) => row['category'], 'category', 'condition_dsl')
            .having((row) => row['repairAction'], 'repairAction', 'fix_condition_dsl'),
      ),
    );
  });

  test('custom strategy normalizes compact indicator-pair rules', () async {
    final service = BacktestMarketDataService(
      candleLoader: (symbol, period, context) async =>
          _relativeStrengthCandles(symbol),
    );

    final validation = await service.customStrategyValidate({
      'strategySpec': {
        'name': 'Compact EMA Cross Trend',
        'market': 'cn',
        'assetClass': 'stock',
        'indicators': [
          {
            'type': 'ema',
            'params': {'period': 12},
          },
          {
            'type': 'ema',
            'params': {'period': 26},
          },
          {
            'type': 'atr_pct',
            'params': {'period': 14},
          },
        ],
        'entry': {
          'all': [
            {
              'indicator': 'ema',
              'params': {'period': 12},
              'operator': 'crosses_above',
              'indicator2': 'ema',
              'params2': {'period': 26},
            },
          ],
        },
        'exit': {
          'any': [
            {'type': 'atr_stop_loss', 'value': 8},
            {'type': 'take_profit_pct', 'value': 15},
            {
              'indicator': 'ema',
              'params': {'period': 12},
              'operator': 'crosses_below',
              'indicator2': 'ema',
              'params2': {'period': 26},
            },
          ],
        },
        'positionSizing': 'full_capital',
        'dataRequirements': {'minBars': 120},
      },
    });

    expect(validation.isError, isFalse);
    final content = validation.content as Map<String, dynamic>;
    expect(content['status'], 'validated');
    final spec = content['spec'] as Map<String, dynamic>;
    final indicators = (spec['indicators'] as List).cast<Map>();
    expect(indicators.any((row) => row['id'] == 'ema12'), isTrue);
    expect(indicators.any((row) => row['id'] == 'ema26'), isTrue);
    expect(
      (spec['entry'] as Map)['all'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'ema12')
            .having((row) => row['op'], 'op', 'crosses_above')
            .having((row) => row['right'], 'right', 'ema26'),
      ),
    );
    expect(
      (spec['exit'] as Map)['any'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'ema12')
            .having((row) => row['op'], 'op', 'crosses_below')
            .having((row) => row['right'], 'right', 'ema26'),
      ),
    );
  });

  test('custom strategy normalizes type-as-operator explicit rules', () async {
    final service = BacktestMarketDataService(
      candleLoader: (symbol, period, context) async =>
          _relativeStrengthCandles(symbol),
    );

    final validation = await service.customStrategyValidate({
      'strategySpec': {
        'name': 'Type Operator EMA Cross',
        'market': 'cn',
        'assetClass': 'stock',
        'entryRules': [
          {
            'type': 'crosses_above',
            'left': {
              'indicator': 'ema',
              'params': {'period': 12},
            },
            'right': {
              'indicator': 'ema',
              'params': {'period': 26},
            },
          },
        ],
        'exitRules': [
          {
            'type': '>',
            'left': {
              'indicator': 'ema_slope',
              'params': {'period': 12},
            },
            'right': 0,
          },
          {'type': 'stop_loss_pct', 'value': 5},
        ],
      },
    });

    expect(validation.isError, isFalse);
    final content = validation.content as Map<String, dynamic>;
    expect(content['status'], 'validated');
    final spec = content['spec'] as Map<String, dynamic>;
    expect(
      (spec['entry'] as Map)['all'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'ema12')
            .having((row) => row['op'], 'op', 'crosses_above'),
      ),
    );
    expect(
      (spec['exit'] as Map)['any'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'ema_slope12')
            .having((row) => row['op'], 'op', '>'),
      ),
    );
  });

  test('custom strategy normalizes indicator names and string rule values', () async {
    final service = BacktestMarketDataService(
      candleLoader: (symbol, period, context) async =>
          _relativeStrengthCandles(symbol),
    );

    final validation = await service.customStrategyValidate({
      'strategySpec': {
        'name': 'Named Indicator Alias Trend',
        'market': 'cn',
        'assetClass': 'stock',
        'indicators': [
          {
            'name': 'ema',
            'params': {'period': 12},
          },
          {
            'name': 'ema',
            'params': {'period': 26},
          },
          {
            'name': 'sma',
            'params': {'period': 60},
          },
        ],
        'entry': {
          'conditions': [
            {
              'indicator': 'ema_12',
              'operator': 'crosses_above',
              'value': 'ema_26',
            },
            {'indicator': 'close', 'operator': '>', 'value': 'sma_60'},
          ],
        },
        'exit': {'stop_loss_pct': 8, 'take_profit_pct': 20},
        'positionSizing': 'fixed_fraction',
        'positionFraction': 0.2,
      },
    });

    expect(validation.isError, isFalse);
    final content = validation.content as Map<String, dynamic>;
    expect(content['status'], 'validated');
    final spec = content['spec'] as Map<String, dynamic>;
    final indicators = (spec['indicators'] as List).cast<Map>();
    expect(indicators.any((row) => row['id'] == 'ema12'), isTrue);
    expect(indicators.any((row) => row['id'] == 'ema26'), isTrue);
    expect(indicators.any((row) => row['id'] == 'sma60'), isTrue);
    expect(
      (spec['entry'] as Map)['all'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'ema12')
            .having((row) => row['right'], 'right', 'ema26'),
      ),
    );
    expect(
      (spec['entry'] as Map)['all'],
      contains(
        isA<Map>()
            .having((row) => row['left'], 'left', 'close')
            .having((row) => row['right'], 'right', 'sma60'),
      ),
    );
    expect(
      spec['positionSizing'],
      containsPair('value', 0.2),
    );
  });

  test(
    'preset backtest exposes cost assumptions when no trades occur',
    () async {
      final service = BacktestMarketDataService(
        candleLoader: (symbol, period, context) async => _flatCandles(),
      );

      final result = await service.backtest('600519', {
        'strategy': 'turtle_breakout',
        'period': '1y',
      }, ToolContext(basePath: '', serviceBaseUrl: 'http://localhost'));

      expect(result.isError, isFalse);
      final content = result.content as Map<String, dynamic>;
      expect(content['total_trades'], 0);
      expect(content['cost_model'], contains('commission='));
      expect(content['cost_assumption'], content['cost_model']);
    },
  );

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

    final nestedHelp = CustomStrategyEngine().help({
      'params': {'detail': 'catalog'},
    });
    final nestedExecutable = nestedHelp['executableV1'] as Map;
    expect(nestedExecutable['indicatorCatalog'], isNotEmpty);
    expect(
      nestedExecutable['indicatorCatalog'],
      contains(
        isA<Map>().having((row) => row['type'], 'type', 'volume_breakout'),
      ),
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

List<Candle> _flatCandles() {
  return List<Candle>.generate(60, (index) {
    return Candle(
      date: '2026-01-${(index % 28 + 1).toString().padLeft(2, '0')}',
      open: 100,
      high: 100,
      low: 100,
      close: 100,
      volume: 1000,
    );
  });
}
