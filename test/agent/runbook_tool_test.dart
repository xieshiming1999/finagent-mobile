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
              (await tool.call('runbook-1', {
                'action': 'list',
              }, context)).content,
            )
            as Map<String, dynamic>;
    expect(list['contract'], 'runbook-list-v1');
    expect(list['workflows'], contains('stock_research'));
    expect(list['workflows'], contains('stock_selection'));

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

    final selection =
        jsonDecode(
              (await tool.call('runbook-selection', {
                'action': 'get',
                'workflow': 'stock_selection',
              }, context)).content,
            )
            as Map<String, dynamic>;
    expect(
      selection['requiredEvidence'],
      contains('screening_or_candidate_source'),
    );
    expect(selection['verifier'], contains('workflow:"stock_selection"'));
    expect(selection['approvalBoundary'], contains('No watchlist mutation'));

    final watchlist =
        jsonDecode(
              (await tool.call('runbook-watchlist', {
                'action': 'get',
                'workflow': 'watchlist_handoff',
              }, context)).content,
            )
            as Map<String, dynamic>;
    expect(watchlist['requiredEvidence'], contains('watchlist_readback'));
    expect(watchlist['verifier'], contains('workflow:"watchlist_handoff"'));

    final rerun =
        jsonDecode(
              (await tool.call('runbook-rerun', {
                'action': 'get',
                'workflow': 'strategy_rerun',
              }, context)).content,
            )
            as Map<String, dynamic>;
    expect(rerun['requiredEvidence'], contains('saved_strategy_identity'));
    expect(rerun['verifier'], contains('workflow:"strategy_rerun"'));

    final tradeReview =
        jsonDecode(
              (await tool.call('runbook-trade-review', {
                'action': 'get',
                'workflow': 'trade_review',
              }, context)).content,
            )
            as Map<String, dynamic>;
    expect(
      tradeReview['requiredEvidence'],
      contains('transactions_or_missing_reason'),
    );
    expect(
      tradeReview['approvalBoundary'],
      contains('Read-only simulated-account review'),
    );

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
    expect(macro['artifactTypes'], contains('report'));
    expect(
      macro['outputRequirements'],
      contains(
        'When the user asks for a reviewable report, dashboard, artifact, or panel output, create or register a durable report/dashboard artifact through ArtifactRegistry before finalizing.',
      ),
    );
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
  final dir = Directory.systemTemp.createTempSync(
    'finagent_runbook_tool_test_',
  );
  return ToolContext(basePath: dir.path, serviceBaseUrl: '');
}
