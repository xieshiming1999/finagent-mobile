import 'package:finagent/agent/tools/research_tool/research_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Guba titles remain unclassified source observations', () {
    final result = buildUnclassifiedGubaObservation(['利好突破买入', '利空破位卖出']);

    expect(result['classification'], 'unclassified');
    expect(result['posts'], 2);
    expect(result, isNot(contains('bullish')));
    expect(result, isNot(contains('bearish')));
    expect(result, isNot(contains('ratio')));
  });
}
