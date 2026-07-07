import 'package:finagent/domain/market/backtest/custom_strategy_engine.dart';
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

    final fundObservation = help['fundObservationV1'] as Map;
    expect(fundObservation['indicators'], contains('fund_drawdown'));
    expect(fundObservation['indicatorCatalog'], isNotEmpty);
    expect(
      fundObservation['indicatorCatalogByCategory'],
      containsPair('fund_return_quality', isNotEmpty),
    );
  });
}
