import 'package:finagent/agent/data_fetcher/eastmoney_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EastMoney stock quote parser maps valuation fields from push2 stock data', () {
    final quote = eastMoneyQuoteFromStockData(
      {
        'f43': 77.87,
        'f44': 77.87,
        'f45': 64.0,
        'f46': 65.88,
        'f47': 120000,
        'f48': 930000000,
        'f57': '688710',
        'f58': '益诺思',
        'f60': 64.89,
        'f115': 86.59,
        'f116': 10978082620.05,
        'f168': 7.56,
        'f170': 20.0,
        'f23': 8.66,
      },
      requestedCode: 'SH688710',
      source: '东方财富',
    );

    expect(quote.code, '688710');
    expect(quote.name, '益诺思');
    expect(quote.price, 77.87);
    expect(quote.pe, 86.59);
    expect(quote.pb, 8.66);
    expect(quote.marketCap, 10978082620.05);
    expect(quote.turnoverRate, 7.56);
  });

  test('EastMoney stock quote parser falls back to dynamic PE when TTM PE is absent', () {
    final quote = eastMoneyQuoteFromStockData(
      {
        'f43': 20.19,
        'f57': '300059',
        'f58': '东方财富',
        'f60': 19.22,
        'f9': 24.71,
        'f23': 3.82,
      },
      requestedCode: '300059',
      source: '东方财富',
    );

    expect(quote.pe, 24.71);
    expect(quote.pb, 3.82);
  });
}
