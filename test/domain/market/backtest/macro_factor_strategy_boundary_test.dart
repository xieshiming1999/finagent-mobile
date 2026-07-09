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

  test('macro research and news sources are not executable StrategySpec signals', () {
    final validation = CustomStrategyEngine().validate({
      'name': 'Macro research is evidence, not executable signal',
      'assetClass': 'stock',
      'symbol': '600519',
      'indicators': [
        {
          'id': 'research_claim',
          'type': 'macro_research_document',
          'source': 'query_macro_research_content',
        },
        {
          'id': 'news_sentiment',
          'type': 'news_sentiment',
          'source': 'finance_news',
        },
      ],
      'entry': {
        'all': [
          {'left': 'research_claim', 'op': '>', 'right': 0},
          {'left': 'macro_policy_event', 'op': '==', 'right': 'supportive'},
        ],
      },
      'exit': {
        'any': [
          {'left': 'news_sentiment', 'op': '<', 'right': -0.5},
        ],
      },
    });

    expect(validation['status'], 'rejected');
    expect(
      '${validation['unsupported']}',
      contains('unsupported indicator "macro_research_document"'),
    );
    expect(
      '${validation['unsupported']}',
      contains('unsupported indicator "news_sentiment"'),
    );
    expect(
      '${validation['unsupported']}',
      contains('entry rule source "macro_policy_event" is not declared'),
    );
    expect(
      '${validation['unsupported']}',
      contains('unsupported executable rule source "news_sentiment"'),
    );
    expect(
      '${validation['unsupportedDetails']}',
      contains('macro_research_document'),
    );
    expect('${validation['workflowAdvice']}', contains('Do not replace'));
  });
}
