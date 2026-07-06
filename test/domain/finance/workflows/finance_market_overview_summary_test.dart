import 'dart:convert';

import 'package:finagent/agent/message.dart';
import 'package:finagent/domain/finance/workflows/finance_market_overview_summary.dart';
import 'package:finagent/domain/finance/workflows/finance_workflow_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('market overview budget summary emits analysis evidence', () {
    final summary = FinanceMarketOverviewSummary().build(
      messages: [
        Message(role: Role.user, content: _marketState()),
        _tool('index', {
          'action': 'query_index_quote',
          'interfaceId': 'index.quote',
          'capabilityId': 'tdx.index.quote',
          'canonicalSchema': 'quote_snapshot',
          'canonicalTable': 'quote_snapshot',
          'readbackAction': 'query_index_quote',
          'source': 'local quote_snapshot',
          'provider': 'tdx',
          'sourceDataTime': '2026-07-02',
          'fetchedAt': '2026-07-02T10:00:00Z',
          'cacheStatus': 'cache-hit',
          'count': 2,
          'data': [
            {
              'code': '000001',
              'name': '上证指数',
              'price': 3100,
              'changePct': -0.2,
            },
            {'code': '399006', 'name': '创业板指', 'price': 1800, 'changePct': 0.6},
          ],
        }),
        _tool('sector', {
          'action': 'query_sector_ranking',
          'source': 'local sector_rank',
          'provider': 'eastmoney',
          'sourceDataTime': '2026-07-02',
          'fetchedAt': '2026-07-02T10:01:00Z',
          'cacheStatus': 'cache-hit',
          'count': 1,
          'data': [
            {'code': 'BK0428', 'name': '半导体', 'change_pct': 2.1},
          ],
        }),
      ],
      turnStartIndex: 0,
      failureSummary: 'none',
    );

    expect(summary, isNotNull);
    final evidence = _analysisEvidence(summary!);
    expect(evidence['contract'], 'analysis-evidence-v1');
    expect(evidence['kind'], 'market_analysis');
    expect(evidence['strategyReadiness'], 'analysis_only');
    expect((evidence['subject'] as Map<String, dynamic>)['type'], 'market');
    expect(
      (evidence['sourceCoverage'] as Map<String, dynamic>)['interfaceId'],
      'index.quote',
    );
    expect(
      (evidence['sourceCoverage'] as Map<String, dynamic>)['coverageStatus'],
      'sufficient_for_analysis',
    );
  });

  test('finance workflow hook can return market overview budget summary', () {
    final messages = [
      Message(role: Role.user, content: _marketState()),
      _tool('index', {
        'action': 'query_index_quote',
        'interfaceId': 'index.quote',
        'source': 'local quote_snapshot',
        'cacheStatus': 'cache-hit',
        'data': [
          {'code': '000001', 'name': '上证指数', 'price': 3100, 'changePct': 0.1},
        ],
      }),
    ];
    final answer = FinanceWorkflowHooks(isBypassTool: (_) => false)
        .buildBudgetStopText(
          messages: messages,
          turnStartIndex: 0,
          prompt: 'arbitrary wording',
          failureSummary: 'none',
        );

    expect(answer, contains('## 市场判断'));
    expect(answer, contains('analysisEvidence:'));
    expect(_analysisEvidence(answer)['kind'], 'market_analysis');
  });

  test('market overview prompt text alone does not enable budget summary', () {
    final summary = FinanceMarketOverviewSummary().build(
      messages: [
        Message(role: Role.user, content: '今天市场怎么样？'),
        _tool('index', {
          'action': 'query_index_quote',
          'data': [
            {'code': '000001', 'name': '上证指数', 'price': 3100, 'changePct': 0.1},
          ],
        }),
      ],
      turnStartIndex: 0,
      failureSummary: 'none',
    );

    expect(summary, isNull);
  });
}

Message _tool(String id, Map<String, dynamic> payload) {
  return Message(
    role: Role.tool,
    toolResult: ToolResult(toolUseId: id, content: jsonEncode(payload)),
  );
}

Map<String, dynamic> _analysisEvidence(String summary) {
  final line = summary
      .split('\n')
      .firstWhere((item) => item.startsWith('analysisEvidence:'));
  return jsonDecode(line.substring('analysisEvidence:'.length))
      as Map<String, dynamic>;
}

String _marketState() {
  return 'structured market overview\n'
      'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"marketAnalysis","assetClass":"mixed","intentMode":"analysis","executionMode":"previewOnly","safetyBoundary":"read-only market overview","evidenceRefs":["market_overview","index.quote","sector.rank"],"confirmationState":"none","subject":"cn-a-share-market-overview","source":"agent-structured-intent"}}';
}
