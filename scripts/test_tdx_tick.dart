// ignore_for_file: avoid_print
// Quick test for TDX tick chart — run from finagent root:
//   dart run scripts/test_tdx_tick.dart

import 'package:finagent/agent/data_fetcher/tdx_fetcher.dart';

void main() async {
  final fetcher = TdxFetcher();
  fetcher.basePath = '/tmp';

  print('[TDX Test] Getting tick chart for 600519...');
  try {
    final data = await fetcher.getTickChart('600519');
    print('[TDX Test] Success! Got ${data.length} points');
    // Show first 5 and last 5
    print('\nFirst 5:');
    for (final d in data.take(5)) {
      print('  ${d['time']} price=${d['price']} avg=${d['avg']} vol=${d['volume']}');
    }
    print('\nLast 5:');
    for (final d in data.skip(data.length - 5)) {
      print('  ${d['time']} price=${d['price']} avg=${d['avg']} vol=${d['volume']}');
    }
  } catch (e) {
    print('[TDX Test] Failed: $e');
  }
}
