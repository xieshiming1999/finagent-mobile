import 'dart:io';

import 'package:finagent/agent/api_failure_classifier.dart';
import 'package:finagent/agent/data_fetcher/api_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ApiStats.instance.resetForTest);

  test('classifies only typed failure state and protocol status', () {
    expect(classifyApiFailure({'status': 403}), 'auth_permission');
    expect(classifyApiFailure({'status': 429}), 'quota_rate_limit');
    expect(
      classifyApiFailure({
        'status': 0,
        'failureClass': 'schema-or-contract',
        'error': 'provider contract mismatch',
      }),
      'contract_mismatch',
    );
    expect(
      classifyApiFailure({'error': 'quota permission schema timeout'}),
      'unknown',
    );
  });

  test('finance scope uses typed domain, source, tool, or route identity', () {
    expect(isFinanceApiFailure({'domain': 'finance'}), isTrue);
    expect(isFinanceApiFailure({'source': 'eastmoney'}), isTrue);
    expect(isFinanceApiFailure({'tool': 'MarketData'}), isTrue);
    expect(
      isFinanceApiFailure({'endpoint': '/api/finance/index/quotes'}),
      isTrue,
    );
    expect(
      isFinanceApiFailure({'error': 'stock quote failed in watchlist'}),
      isFalse,
    );
  });

  test(
    'API stats persists the producer failure class without prose parsing',
    () {
      final dir = Directory.systemTemp.createTempSync(
        'api_failure_class_test_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      ApiStats.instance.init(dir.path);
      ApiStats.instance.record(
        source: 'eastmoney',
        method: 'GET',
        url: 'https://example.test/quote',
        statusCode: 0,
        durationMs: 5,
        success: false,
        failureClass: 'contract_mismatch',
        error: 'arbitrary display text',
      );

      final row = ApiStats.instance.getRecentFailures().single.toJson();
      expect(row['failureClass'], 'contract_mismatch');
      expect(classifyApiFailure(row), 'contract_mismatch');
    },
  );
}
