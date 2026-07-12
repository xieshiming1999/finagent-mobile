import 'dart:convert';

import 'package:finagent/agent/message.dart';
import 'package:finagent/domain/finance/workflows/finance_stock_candidate_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single-stock summary accepts governed live quote and kline actions', () {
    final summary = FinanceStockCandidateSummary().build(
      messages: [
        _tool('quote', {
          'action': 'quote',
          'source': '东方财富',
          'cacheStatus': 'provider-hit',
          'data': [
            {
              'code': '300059',
              'name': '东方财富',
              'price': 20.19,
              'changePct': -1.94,
              'source': '东方财富',
            },
          ],
        }),
        _tool('kline', {
          'action': 'kline',
          'symbol': '300059',
          'source': '东方财富',
          'cacheStatus': 'provider-hit',
          'bars': 367,
          'range': '2025-01-02 ~ 2026-07-10',
          'latest5': [
            {'date': '2026-07-10', 'close': 20.19, 'changePct': -1.94},
          ],
        }),
        _tool('valuation', {
          'action': 'query_stock_daily_valuation',
          'symbol': '300059',
          'source': 'local fundamental',
          'cacheStatus': 'cache-miss',
          'count': 0,
          'data': const [],
        }),
        _tool('flow', {
          'action': 'query_money_flow',
          'symbol': '300059',
          'source': 'local money_flow',
          'cacheStatus': 'cache-miss',
          'count': 0,
          'data': const [],
        }),
      ],
      turnStartIndex: 0,
      failureSummary: 'stock_risk_metrics credential-gated',
    );

    expect(summary, isNotNull);
    expect(summary, contains('东方财富 300059'));
    expect(summary, contains('单股研究摘要'));
    expect(summary, contains('2025-01-02 ~ 2026-07-10'));
    expect(summary, contains('估值/基本面'));
    expect(summary, contains('stock_risk_metrics credential-gated'));
  });

  test('single-stock summary labels macro and news evidence', () {
    final summary = FinanceStockCandidateSummary().build(
      messages: [
        _tool('quote', {
          'action': 'query_quote',
          'source': 'local quote_snapshot',
          'sourceDataTime': '2026-07-09T05:01:00Z',
          'fetchedAt': '2026-07-09T05:02:00Z',
          'cacheStatus': 'cache-hit',
          'data': [
            {
              'code': '600519',
              'name': '贵州茅台',
              'price': 1185.62,
              'changePct': -1.14,
            },
          ],
        }),
        _tool('kline', {
          'action': 'query_kline',
          'source': 'local kline_daily',
          'count': 60,
          'data': [
            {'date': '2026-04-10'},
            {'date': '2026-07-08'},
          ],
        }),
        _tool('macro', {
          'action': 'query_macro_factors',
          'status': 'missing',
          'missingReason': 'No matching macro rows',
          'rows': const [],
        }),
        _tool('sources', {
          'action': 'macro_research_sources',
          'status': 'ok',
          'rows': [
            {
              'provider': 'pboc_news_releases',
              'providerName': 'PBOC News Releases',
              'accessClass': 'official-public-source',
              'categories': ['china_liquidity'],
            },
          ],
        }),
        _tool('news', {
          'action': 'query_finance_news',
          'query': '贵州茅台',
          'sourceDataTime': '2026-07-09 16:02:00',
          'fetchedAt': '2026-07-09T09:52:21Z',
          'count': 1,
          'data': [
            {
              'title': '白酒股下跌 贵州茅台收盘',
              'source': '东方财富',
              'published_at': '2026-07-09 16:02:00',
            },
          ],
        }),
      ],
      turnStartIndex: 0,
      failureSummary: 'none',
    );

    expect(summary, isNotNull);
    expect(summary, contains('官方事实'));
    expect(summary, contains('研究观点'));
    expect(summary, contains('新闻线索'));
    expect(summary, contains('置信度影响'));
    expect(summary, contains('缺失证据'));
    expect(summary, contains('PBOC News Releases'));
    expect(summary, contains('白酒股下跌'));
  });
}

Message _tool(String id, Map<String, dynamic> payload) {
  return Message(
    role: Role.tool,
    toolResult: ToolResult(toolUseId: id, content: jsonEncode(payload)),
  );
}
