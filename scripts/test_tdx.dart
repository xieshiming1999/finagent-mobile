// ignore_for_file: avoid_print
// Quick test for TDX fetcher — run from finagent root:
//   dart run scripts/test_tdx.dart

import 'package:finagent/agent/data_fetcher/tdx_fetcher.dart';

void main() async {
  final fetcher = TdxFetcher();
  fetcher.basePath = '/tmp';

  print('[TDX Test] Attempting to connect and get kline for 600519...');
  try {
    final bars = await fetcher.getKline('600519', period: 'daily', startDate: '2026-04-01');
    print('[TDX Test] Success! Got ${bars.length} bars');
    for (final bar in bars.take(5)) {
      print('  ${bar.date} O:${bar.open} H:${bar.high} L:${bar.low} C:${bar.close} V:${bar.volume}');
    }
  } catch (e) {
    print('[TDX Test] Failed: $e');
  }

  print('\n[TDX Test] Attempting getStockCount...');
  try {
    final count = await fetcher.getStockCount();
    print('[TDX Test] Stock count: $count');
  } catch (e) {
    print('[TDX Test] Failed: $e');
  }
}
