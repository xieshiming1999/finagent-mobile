// ignore_for_file: avoid_print
// Live test for ExTdxFetcher — run from finagent root:
//   dart run scripts/test_ex_tdx.dart
//
// Compare output with gotdx: go run scripts/test_ex_tdx.go

import 'dart:convert';
import 'dart:io';
import 'package:finagent/agent/data_fetcher/ex_tdx_fetcher.dart';

void main() async {
  final fetcher = ExTdxFetcher();
  fetcher.basePath = '/tmp/ex_tdx_test';

  // Create server file for testing
  final serverDir = Directory('/tmp/ex_tdx_test/memory');
  serverDir.createSync(recursive: true);
  File('/tmp/ex_tdx_test/memory/.tdx_ex_servers.json').writeAsStringSync(jsonEncode([
    {"host": "112.74.214.43", "port": 7727, "name": "扩展市场深圳1"},
    {"host": "150.158.9.199", "port": 7727, "name": "扩展市场上海1"},
    {"host": "123.60.173.210", "port": 7727, "name": "扩展市场广州3b"},
  ]));

  // 1. Categories
  print('=== ExCategories ===');
  try {
    final cats = await fetcher.getExCategories();
    print('Got ${cats.length} categories:');
    for (final c in cats) {
      print('  [${c.category}] ${c.name} (${c.abbr})');
    }
  } catch (e) {
    print('FAILED: $e');
  }

  // 2. Count
  print('\n=== ExCount ===');
  try {
    final count = await fetcher.getExCount();
    print('Total extended securities: $count');
  } catch (e) {
    print('FAILED: $e');
  }

  // 3. List (上期所期货, category=30, first 10)
  print('\n=== ExList (start=0, count=10) ===');
  try {
    final list = await fetcher.getExList(start: 0, count: 10);
    for (final item in list) {
      print('  [${item.category}] ${item.code} - ${item.name}');
    }
  } catch (e) {
    print('FAILED: $e');
  }

  // 4. ExKline (螺纹钢主力连续 RBL8, category=30, daily)
  print('\n=== ExKline (category=30, code=RBL8, daily, last 10) ===');
  try {
    final bars = await fetcher.getExKline(30, 'RBL8', period: 9, count: 10);
    print('Got ${bars.length} bars:');
    for (final bar in bars) {
      print('  ${bar.date} O:${bar.open} H:${bar.high} L:${bar.low} C:${bar.close} V:${bar.volume} A:${bar.amount}');
    }
  } catch (e) {
    print('FAILED: $e');
  }

  // 5. ExQuote (螺纹钢 RBL8)
  print('\n=== ExQuote (category=30, code=RBL8) ===');
  try {
    final q = await fetcher.getExQuote(30, 'RBL8');
    print('  code=${q.code} close=${q.close} open=${q.open} high=${q.high} low=${q.low}');
    print('  vol=${q.vol} amount=${q.amount} hold=${q.holdPosition}');
    print('  settlement=${q.settlement} preSettlement=${q.preSettlement}');
    if (q.bidLevels.isNotEmpty) {
      print('  bid1: ${q.bidLevels[0].price} x ${q.bidLevels[0].vol}');
      print('  ask1: ${q.askLevels[0].price} x ${q.askLevels[0].vol}');
    }
  } catch (e) {
    print('FAILED: $e');
  }

  // 6. Also test international index (恒生指数, category=27)
  print('\n=== ExKline (category=27, code=HSI, daily, last 5) ===');
  try {
    final bars = await fetcher.getExKline(27, 'HSI', period: 9, count: 5);
    print('Got ${bars.length} bars:');
    for (final bar in bars) {
      print('  ${bar.date} O:${bar.open} H:${bar.high} L:${bar.low} C:${bar.close} V:${bar.volume}');
    }
  } catch (e) {
    print('FAILED: $e');
  }

  exit(0);
}
