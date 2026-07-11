import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/data_fetcher/api_stats.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/budget_governor_tool/budget_governor_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => ApiStats.instance.resetForTest());

  test(
    'BudgetGovernor stops Wind calls when local Wind usage is exhausted',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final memory = Directory('${context.basePath}/memory')
        ..createSync(recursive: true);
      File('${memory.path}/wind_usage.json').writeAsStringSync(
        jsonEncode({
          'date': '2026-07-11',
          'count': 3,
          'exhausted': true,
          'exhaustedCode': 'RATE_LIMIT_DAILY',
        }),
      );

      final status =
          jsonDecode(
                (await BudgetGovernorTool().call('budget-1', {
                  'action': 'status',
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(status['contract'], 'budget-governor-status-v1');
      expect(status['decision'], 'stop_wind_calls');
      expect(status['nextAction'], contains('Do not call Wind'));
    },
  );

  test('BudgetGovernor detects quota-like API failures', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    ApiStats.instance.init(context.basePath);
    ApiStats.instance.record(
      source: 'tushare',
      method: 'GET',
      url: 'https://api.tushare.pro',
      statusCode: 429,
      durationMs: 20,
      success: false,
      error: 'rate limit',
    );

    final status =
        jsonDecode(
              (await BudgetGovernorTool().call('budget-2', {
                'action': 'status',
                'source': 'tushare',
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(status['decision'], 'stop_broad_live_calls');
    expect(status['quotaLikeFailures'], isNotEmpty);
  });
}

ToolContext _tempContext() {
  final dir = Directory.systemTemp.createTempSync(
    'finagent_budget_governor_test_',
  );
  return ToolContext(basePath: dir.path, serviceBaseUrl: '');
}
