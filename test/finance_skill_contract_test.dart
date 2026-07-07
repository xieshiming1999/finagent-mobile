import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ETF rotation skills require bounded listed-price evidence sample', () {
    final fund = _read('assets/finance/skills/fund/skill.md');
    final fundScreening = _read(
      'assets/finance/skills/fund-screening/skill.md',
    );
    final strategy = _read('assets/finance/skills/strategy-system/skill.md');

    for (final content in [fund, fundScreening, strategy]) {
      expect(content, contains('510300'));
      expect(content, contains('MarketData(action: "quote"'));
      expect(content, contains('510300.SH'));
      expect(content, contains('custom_strategy_rank'));
      expect(content, contains('custom_strategy_backtest'));
      expect(content, contains('Research(search)'));
    }
    expect(fund, contains('sample listed-market evidence'));
    expect(fundScreening, contains('mobile-safe default'));
    expect(strategy, contains('mobile-safe quote sample'));
  });

  test('trade preview skills require same-turn market evidence', () {
    final tradeExecution = _read(
      'assets/finance/skills/trade-execution/skill.md',
    );
    final xueqiu = _read('assets/finance/skills/xueqiu-trade/skill.md');

    for (final content in [tradeExecution, xueqiu]) {
      expect(content, contains('MarketData(action:"query_quote"'));
      expect(content, contains('MarketData(action:"custom_strategy_read"'));
      expect(content, contains('preview_order'));
    }
    expect(tradeExecution, contains('Before any preview action'));
    expect(xueqiu, contains('before `preview_order`'));
  });
}

String _read(String path) => File(path).readAsStringSync();
