import 'package:finagent/domain/market/backtest/custom_strategy_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macro factor prose is not an executable StrategySpec signal', () {
    final validation = CustomStrategyEngine().validate({
      'name': 'Macro factor context is not an executable rule',
      'assetClass': 'stock',
      'symbol': '600519',
      'indicators': [
        {
          'id': 'macro_context',
          'type': 'macro_factor',
          'source': 'market_moving_factor_v1',
        },
      ],
      'entry': {
        'all': [
          {'left': 'macro_context', 'op': '>', 'right': 0},
        ],
      },
      'exit': {
        'any': [
          {'type': 'stop_loss_pct', 'value': 8},
        ],
      },
    });

    expect(validation['status'], 'rejected');
    expect('${validation['unsupported']}', contains('macro_factor'));
    expect('${validation['unsupportedDetails']}', contains('macro_factor'));
    expect('${validation['workflowAdvice']}', contains('Do not replace'));
  });
}
