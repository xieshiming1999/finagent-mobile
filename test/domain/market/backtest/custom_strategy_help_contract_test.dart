import 'dart:io';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/domain/market/backtest/custom_strategy_engine.dart';
import 'package:finagent/domain/market/backtest/backtest_core.dart';
import 'package:finagent/domain/market/backtest/strategy_indicator_calculators.dart';
import 'package:finagent/domain/market/backtest/strategy_spec_validator.dart';
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
    expect(
      executable['indicatorPreviewCatalog'],
      contains(isA<Map>().having((row) => row['type'], 'type', 'rsi')),
    );
    expect(
      executable['indicatorPreviewCatalog'],
      contains(
        isA<Map>()
            .having((row) => row['type'], 'type', 'volume_breakout')
            .having(
              (row) => row['parameterSchema'],
              'parameterSchema',
              isNotEmpty,
            ),
      ),
    );
    expect(executable['catalogRequest'], containsPair('detail', 'catalog'));
    expect(executable.containsKey('indicators'), isFalse);
    expect(executable.containsKey('indicatorCatalog'), isFalse);
    expect(executable.containsKey('indicatorCatalogByCategory'), isFalse);
    expect(executable.containsKey('stockExample'), isFalse);
    expect(executable.containsKey('ruleCompositionExamples'), isFalse);
    expect(
      (executable['indicatorPreviewCatalog'] as List).length,
      lessThanOrEqualTo(8),
    );

    final fundObservation = help['fundObservationV1'] as Map;
    expect(fundObservation['indicatorCount'], greaterThan(5));
    expect(fundObservation['indicatorsPreview'], contains('fund_drawdown'));
    expect(
      fundObservation['indicatorPreviewCatalog'],
      contains(
        isA<Map>()
            .having((row) => row['type'], 'type', 'fund_drawdown')
            .having((row) => row['scoreDirection'], 'scoreDirection', -1),
      ),
    );
    expect(
      fundObservation['catalogRequest'],
      containsPair('detail', 'catalog'),
    );
    expect(fundObservation.containsKey('indicators'), isFalse);
    expect(fundObservation.containsKey('indicatorCatalog'), isFalse);
    expect(fundObservation.containsKey('indicatorCatalogByCategory'), isFalse);
    expect(fundObservation.containsKey('ordinaryFundExample'), isFalse);
    expect(fundObservation.containsKey('moneyFundExample'), isFalse);
    expect(
      (fundObservation['indicatorPreviewCatalog'] as List).length,
      lessThanOrEqualTo(8),
    );
    expect(help.containsKey('proxyContract'), isFalse);
    expect(help.containsKey('unsupportedV1'), isFalse);

    final inputContracts = help['inputContracts'] as Map;
    expect(
      inputContracts.keys,
      containsAll([
        'custom_strategy_validate',
        'custom_strategy_backtest',
        'custom_strategy_observe',
        'custom_strategy_fund_backtest',
        'custom_strategy_rank',
        'custom_strategy_save',
        'custom_strategy_list',
        'custom_strategy_compare',
        'custom_strategy_run',
      ]),
    );
    expect(
      (inputContracts['custom_strategy_run'] as Map)['requiredFields'],
      contains('strategyId'),
    );

    final outputContracts = help['outputContracts'] as Map;
    expect(
      outputContracts.keys,
      containsAll([
        'custom_strategy_validate',
        'custom_strategy_backtest',
        'custom_strategy_observe',
        'custom_strategy_fund_backtest',
        'custom_strategy_rank',
        'custom_strategy_save',
        'custom_strategy_list',
        'custom_strategy_compare',
        'custom_strategy_run',
      ]),
    );
    expect(outputContracts['custom_strategy_run'], contains('lifecycleIssue'));
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
  });

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
