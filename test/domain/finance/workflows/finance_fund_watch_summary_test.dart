import 'dart:convert';

import 'package:finagent/agent/message.dart';
import 'package:finagent/domain/finance/workflows/finance_fund_watch_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fund watch summary emits analysis evidence', () {
    final answer = FinanceFundWatchSummary().build(
      messages: [
        Message(
          role: Role.assistant,
          content: '',
          toolUses: const [
            ToolUse(
              id: 'add',
              name: 'Watchlist',
              input: {
                'action': 'add',
                'type': 'fund',
                'symbol': '110022',
                'name': '易方达消费行业',
                'entryCondition': '回撤后定投观察',
              },
            ),
            ToolUse(id: 'list', name: 'Watchlist', input: {'action': 'list'}),
            ToolUse(
              id: 'fund-list',
              name: 'MarketData',
              input: {'action': 'query_fund_list'},
            ),
            ToolUse(
              id: 'nav',
              name: 'MarketData',
              input: {
                'action': 'query_fund_nav',
                'symbols': ['110022'],
              },
            ),
          ],
        ),
        _tool('add', 'Added 易方达消费行业 (id: fund-watch-1, symbol: 110022)'),
        _tool('list', {
          'count': 1,
          'items': [
            {
              'id': 'fund-watch-1',
              'symbol': '110022',
              'name': '易方达消费行业',
              'type': 'fund',
              'entryCondition': '回撤后定投观察',
            },
          ],
        }),
        _tool('fund-list', {
          'action': 'query_fund_list',
          'source': 'local fund_list',
          'cacheStatus': 'cache-hit',
          'data': [
            {'code': '110022', 'name': '易方达消费行业', 'fund_type': '混合型'},
          ],
        }),
        _tool('nav', {
          'action': 'query_fund_nav',
          'source': 'local fund_nav',
          'cacheStatus': 'cache-hit',
          'sourceDataTime': '2026-07-02',
          'fetchedAt': '2026-07-02T10:00:00Z',
          'seriesSummary': [
            {
              'code': '110022',
              'rows': 120,
              'startDate': '2026-01-01',
              'endDate': '2026-07-02',
              'startNav': 3.1,
              'endNav': 3.4,
              'maxDrawdownPct': -8.2,
            },
          ],
        }),
      ],
      turnStartIndex: 0,
      failureSummary: 'none',
    );

    expect(answer, isNotNull);
    final evidence = _analysisEvidence(answer!);
    expect(evidence['contract'], 'analysis-evidence-v1');
    expect(evidence['kind'], 'fund_analysis');
    expect(evidence['strategyReadiness'], 'analysis_only');
    expect((evidence['subject'] as Map<String, dynamic>)['id'], '110022');
    expect(
      (evidence['sourceCoverage'] as Map<String, dynamic>)['interfaceId'],
      'fund.nav_history',
    );
    expect(
      (evidence['sourceCoverage'] as Map<String, dynamic>)['coverageStatus'],
      'sufficient_for_analysis',
    );
  });
}

Message _tool(String id, Object payload) {
  return Message(
    role: Role.tool,
    toolResult: ToolResult(
      toolUseId: id,
      content: payload is String ? payload : jsonEncode(payload),
    ),
  );
}

Map<String, dynamic> _analysisEvidence(String summary) {
  final line = summary
      .split('\n')
      .firstWhere((item) => item.startsWith('analysisEvidence:'));
  return jsonDecode(line.substring('analysisEvidence:'.length))
      as Map<String, dynamic>;
}
