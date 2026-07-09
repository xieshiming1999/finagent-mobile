import 'dart:io';

import 'package:finagent/agent/data_fetcher/models.dart';
import 'package:finagent/agent/data_fetcher/reusable_data_store.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/data_process_tool/data_process_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'DataProcess rejects stock-only actions for core market index codes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'finagent-index-fund-disambiguation-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = ReusableDataStore(dir.path)..cleanup();
      store.saveFundList([
        {
          'code': '000300',
          'name': '华夏沪深300ETF联接',
          'fund_type': '指数型',
          'fund_category': 'index',
          'updated_at': '2026-06-26',
        },
      ]);
      store.saveKline(
        '000300',
        List.generate(
          25,
          (index) => KlineBar(
            date: '2026-05-${(index + 1).toString().padLeft(2, '0')}',
            open: 10 + index * 0.1,
            high: 10.2 + index * 0.1,
            low: 9.8 + index * 0.1,
            close: 10.1 + index * 0.1,
            volume: 1000 + index.toDouble(),
          ),
        ),
        source: 'fixture',
      );

      final result = await DataProcessTool().call('dp-index-signals', {
        'action': 'signals',
        'symbol': '000300',
      }, ToolContext(basePath: dir.path, serviceBaseUrl: ''));

      expect(result.isError, isTrue);
      expect(
        result.content,
        contains('does not provide governed index technical indicators'),
      );
    },
  );
}
