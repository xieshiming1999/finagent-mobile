import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/runbook_tool/runbook_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Runbook lists and returns structured workflow guidance', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final tool = RunbookTool();

    final list =
        jsonDecode(
              (await tool.call('runbook-1', {'action': 'list'}, context)).content,
            )
            as Map<String, dynamic>;
    expect(list['contract'], 'runbook-list-v1');
    expect(list['workflows'], contains('stock_research'));

    final detail =
        jsonDecode(
              (await tool.call('runbook-2', {
                'action': 'get',
                'workflow': 'strategy_backtest',
              }, context)).content,
            )
            as Map<String, dynamic>;
    expect(detail['contract'], 'runbook-detail-v1');
    expect(detail['workflow'], 'strategy_backtest');
    expect(detail['requiredEvidence'], contains('StrategySpec'));
    expect(detail['approvalBoundary'], contains('Backtest and monitor only'));

    final macro =
        jsonDecode(
              (await tool.call('runbook-macro', {
                'action': 'get',
                'workflow': 'macro_factor_lookup',
              }, context)).content,
            )
            as Map<String, dynamic>;
    expect(macro['requiredEvidence'], contains('macro-evidence-record-v1'));
    expect(macro['allowedTools'], contains('SourceReader'));
    expect(macro['approvalBoundary'], contains('not a direct buy/sell rule'));
  });

  test('Runbook rejects unknown workflow through tool error channel', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final result = await RunbookTool().call('runbook-3', {
      'action': 'get',
      'workflow': 'unknown',
    }, context);

    expect(result.isError, true);
    expect(result.content, contains('Unknown Runbook workflow "unknown"'));
    expect(result.content, contains('action:"list"'));
  });
}

ToolContext _tempContext() {
  final dir = Directory.systemTemp.createTempSync('finagent_runbook_tool_test_');
  return ToolContext(basePath: dir.path, serviceBaseUrl: '');
}
