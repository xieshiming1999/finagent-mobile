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
}

String _read(String path) => File(path).readAsStringSync();
