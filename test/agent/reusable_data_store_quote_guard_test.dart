import 'dart:io';

import 'package:finagent/agent/data_fetcher/models.dart';
import 'package:finagent/agent/data_fetcher/reusable_data_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quote readback drops impossible legacy valuation values', () async {
    final dir = await Directory.systemTemp.createTemp('quote-valuation-guard-');
    addTearDown(() => dir.deleteSync(recursive: true));

    final store = ReusableDataStore(dir.path);
    store.saveQuoteSnapshots([
      StockQuote(
        code: '301308',
        name: '江波龙',
        price: 587.6,
        change: 1,
        changePct: 0.1,
        open: 580,
        high: 590,
        low: 570,
        prevClose: 586.6,
        volume: 1000,
        amount: 587600,
        pe: 9.12,
        pb: 744,
        source: '东方财富',
      ),
    ], '东方财富');

    final quote = store.queryQuotes('301308').single;
    expect(quote.price, 587.6);
    expect(quote.pe, 9.12);
    expect(quote.pb, isNull);
  });
}
