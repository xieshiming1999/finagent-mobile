import 'package:flutter_test/flutter_test.dart';
import 'package:finagent/features/finance/strategy_library_action_prompt.dart';
import 'package:finagent/shared/strategy_library_model.dart';

void main() {
  test('parses saved strategy records with symbols and runnable status', () {
    final rows = parseStrategyLibraryRows([
      {
        'strategyId': 'strategy_a',
        'status': 'backtested',
        'updatedAt': '2026-07-01T10:00:00Z',
        'strategySpec': {
          'name': '趋势策略',
          'assetClass': 'stock',
          'symbol': '600519',
          'symbols': ['000858', '600519'],
        },
        'backtestEvidence': {
          'action': 'custom_strategy_backtest',
          'metrics': {
            'totalReturnPct': 12.345,
            'maxDrawdownPct': -4.2,
            'sharpe': 1.234,
          },
          'riskRewardEvidence': {
            'completedTrades': 4,
            'winningTrades': 3,
            'losingTrades': 1,
            'payoffRatio': 1.75,
            'profitFactor': 3.5,
            'expectancyPct': 2.25,
          },
          'dataEvidence': {
            'source': 'cache',
            'cacheStatus': 'cache-hit',
            'sourceDataTime': '2026-06-30',
            'bars': 250,
          },
        },
        'dataAndAssumptionSummary': {
          'feesAndSlippage': {'commissionPct': 0.1, 'slippagePct': 0.05},
          'positionSizing': {
            'type': 'kelly_fraction',
            'maxPositionPct': 0.25,
            'kellyScale': 0.5,
          },
        },
      },
    ]);

    expect(rows, hasLength(1));
    expect(rows.single.strategyId, 'strategy_a');
    expect(rows.single.name, '趋势策略');
    expect(rows.single.runnable, isTrue);
    expect(rows.single.strategyType, StrategyLibraryItem.stockStrategy);
    expect(rows.single.symbols, ['600519', '000858']);
    expect(rows.single.evidenceAction, 'custom_strategy_backtest');
    expect(rows.single.evidenceSummary, contains('return=12.35%'));
    expect(rows.single.evidenceSummary, contains('maxDD=-4.20%'));
    expect(rows.single.evidenceSummary, contains('sharpe=1.23'));
    expect(rows.single.dataSummary, contains('source=cache'));
    expect(rows.single.dataSummary, contains('cacheStatus=cache-hit'));
    expect(rows.single.dataSummary, contains('sourceDataTime=2026-06-30'));
    expect(rows.single.dataSummary, contains('bars=250'));
    expect(rows.single.riskRewardSummary, contains('trades=4'));
    expect(rows.single.riskRewardSummary, contains('profitFactor=3.50'));
    expect(rows.single.riskRewardSummary, contains('expectancy=2.25%'));
    expect(rows.single.assumptionSummary, contains('sizing=kelly_fraction'));
    expect(rows.single.assumptionSummary, contains('maxPosition=0.25'));
    expect(rows.single.assumptionSummary, contains('kellyScale=0.50'));
    expect(rows.single.assumptionSummary, contains('commission=0.10%'));
  });

  test(
    'parses bounded custom_strategy_list rows with fund evidence summary',
    () {
      final rows = parseStrategyLibraryRows([
        {
          'strategyId': 'fund_period_v1',
          'name': '基金周期观察',
          'status': 'observed',
          'assetClass': 'fund',
          'symbols': ['000001'],
          'updatedAt': '2026-07-02T10:00:00Z',
          'evidenceAction': 'custom_strategy_fund_backtest',
          'dataAndAssumptionSummary': {
            'fundCoverageEvidence': {'status': 'sufficient'},
            'fundRiskEvidence': {
              'assetClass': 'fund',
              'pricingBasis': 'fund_nav',
              'worstDrawdownPct': 3.25,
              'maxVolatilityPct': 8.5,
              'averageGainToPainRatio': 1.42,
              'averageOmegaRatio': 1.36,
              'averageTailRatio': 1.8,
            },
          },
        },
      ]);

      expect(rows, hasLength(1));
      expect(rows.single.strategyId, 'fund_period_v1');
      expect(rows.single.name, '基金周期观察');
      expect(rows.single.assetClass, 'fund');
      expect(rows.single.strategyType, StrategyLibraryItem.fundStrategy);
      expect(rows.single.symbols, ['000001']);
      expect(rows.single.evidenceAction, 'custom_strategy_fund_backtest');
      expect(rows.single.evidenceSummary, contains('fundMaxDD=3.25%'));
      expect(rows.single.evidenceSummary, contains('fundVol=8.50%'));
      expect(rows.single.evidenceSummary, contains('fundGTP=1.42'));
      expect(rows.single.evidenceSummary, contains('fundOmega=1.36'));
      expect(rows.single.evidenceSummary, contains('fundTail=1.80'));
      expect(rows.single.dataSummary, contains('fundCoverage=sufficient'));
      expect(rows.single.dataSummary, contains('pricingBasis=fund_nav'));
    },
  );

  test('builds governed action prompts without direct state mutation', () {
    const item = StrategyLibraryItem(
      strategyId: 'strategy_b',
      name: '基金观察',
      status: 'observed',
      assetClass: 'fund',
      symbols: ['000001'],
      updatedAt: '2026-07-01T10:00:00Z',
      evidenceAction: 'custom_strategy_observe',
      evidenceSummary: 'signal=observe_or_prepare',
      dataSummary: 'sourceDataTime=2026-06-30',
    );

    expect(item.runnable, isFalse);
    expect(
      buildStrategyActionPrompt('rerun', item),
      contains('custom_strategy_run'),
    );
    expect(
      buildStrategyActionPrompt('watch', item),
      allOf(
        contains('Watchlist(action:"add")'),
        contains(
          'Watchlist(action:"list", strategyId:"strategy_b", symbol:"000001", status:"watching")',
        ),
        contains('strategyRules'),
        contains('避免重复标的误认'),
        contains('不要直接下单'),
      ),
    );
    expect(
      buildStrategyActionPrompt('monitor', item),
      allOf(
        contains('MonitorCreate'),
        contains('fund_rule_monitor'),
        contains('MonitorList'),
        contains('monitorDraft'),
        contains('基金 NAV/yield'),
        contains('不要直接交易'),
      ),
    );
    expect(buildStrategyActionPrompt('read', item), contains('是否可重跑'));
  });

  test(
    'uses stock strategy_signal monitor for backtested stock strategies',
    () {
      const item = StrategyLibraryItem(
        strategyId: 'strategy_stock',
        name: '股票策略',
        status: 'backtested',
        assetClass: 'stock',
        symbols: ['600519'],
        updatedAt: '2026-07-01T10:00:00Z',
        evidenceAction: 'custom_strategy_backtest',
      );

      final prompt = buildStrategyActionPrompt('monitor', item);
      expect(prompt, contains('MonitorCreate(template:"strategy_signal")'));
      expect(prompt, contains('quote/kline'));
      expect(prompt, isNot(contains('fund_rule_monitor')));
    },
  );

  test('uses portfolio_rebalance_monitor for ranked strategy artifacts', () {
    const item = StrategyLibraryItem(
      strategyId: 'ranked_portfolio_v1',
      name: '组合排序策略',
      status: 'ranked',
      assetClass: 'stock',
      symbols: ['300059', '600519'],
      updatedAt: '2026-07-01T10:00:00Z',
      evidenceAction: 'custom_strategy_rank',
    );

    final prompt = buildStrategyActionPrompt('monitor', item);
    expect(
      prompt,
      allOf(
        contains('MonitorCreate(template:"portfolio_rebalance_monitor")'),
        contains('portfolioEvidence'),
        contains('rebalanceDraft'),
        contains('不自动调仓或下单'),
      ),
    );
    expect(
      prompt,
      isNot(contains('MonitorCreate(template:"strategy_signal")')),
    );
  });

  test('classifies portfolio and ETF strategy artifacts', () {
    final rows = parseStrategyLibraryRows([
      {
        'strategyId': 'ranked_portfolio_v1',
        'status': 'ranked',
        'strategySpec': {
          'name': '组合排序',
          'assetClass': 'stock',
          'symbols': ['300059', '600519'],
        },
        'backtestEvidence': {'action': 'custom_strategy_rank'},
      },
      {
        'strategyId': 'etf_rotation_v1',
        'status': 'observed',
        'strategySpec': {
          'name': 'ETF 轮动',
          'assetClass': 'listed_fund',
          'codes': ['510300'],
        },
        'backtestEvidence': {'action': 'custom_strategy_observe'},
      },
    ]);

    expect(rows[0].strategyType, StrategyLibraryItem.portfolioStrategy);
    expect(rows[1].strategyType, StrategyLibraryItem.etfMarketStrategy);
  });
}
