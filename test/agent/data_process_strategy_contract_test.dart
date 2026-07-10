import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DataProcess strategy_list exposes the required execution contract', () {
    final source = File(
      'lib/agent/tools/data_process_tool/data_process_tool.dart',
    ).readAsStringSync();

    expect(source, contains('strategy_list 只列出预设策略，不执行策略'));
    expect(source, contains('strategy_execute 必须提供 symbol 或非空 symbols'));
  });
}
