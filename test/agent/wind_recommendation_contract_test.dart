import 'dart:convert';

import 'package:finagent/agent/data_fetcher/normalizers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Wind recommendation normalization accepts numeric source fields', () {
    final rows = tryNormalizeWindGlobalRecommendationPayload(
      jsonEncode({
        'data': {
          'columns': ['Wind代码', '日期', '买入', '持有'],
          'rows': [
            ['AAPL.US', '20260714', 12, 3],
          ],
        },
      }),
    );

    expect(rows.single, containsPair('buy', 12.0));
    expect(rows.single, containsPair('hold', 3.0));
  });

  test('Wind recommendation normalization ignores free-form rating prose', () {
    final rows = tryNormalizeWindGlobalRecommendationPayload(
      jsonEncode({
        'data': {
          'columns': ['Wind代码', '日期', '投资评级'],
          'rows': [
            ['AAPL.US', '20260714', '强烈买入'],
          ],
        },
      }),
    );

    expect(rows, isEmpty);
  });
}
