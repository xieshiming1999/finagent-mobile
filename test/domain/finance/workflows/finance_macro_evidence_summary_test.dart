import 'dart:convert';

import 'package:finagent/agent/message.dart';
import 'package:finagent/agent/tool.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/domain/finance/workflows/finance_macro_evidence_summary.dart';
import 'package:finagent/domain/finance/workflows/finance_workflow_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rewrites macro evidence calls to include attribution readback', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final rewritten = hooks.rewriteToolCalls(
      messages: [
        Message(
          role: Role.user,
          content:
              'macro analysis\n'
              'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"macro_attribution","assetClass":"stock","intentMode":"analysis","executionMode":"readback","safetyBoundary":"read-only macro attribution","confirmationState":"none","source":"agent-structured-intent"}}',
        ),
      ],
      turnStartIndex: 0,
      prompt: null,
      toolCalls: const [
        ToolUse(
          id: 'factor',
          name: 'MarketData',
          input: {'action': 'query_macro_factors', 'target': 'A-shares'},
        ),
      ],
    );

    expect(rewritten.length, 3);
    expect(
      rewritten.map((call) => call.input['action']),
      contains('query_macro_attribution'),
    );
    expect(
      rewritten.map((call) => call.input['action']),
      contains('query_finance_news'),
    );
    final attribution = rewritten.firstWhere(
      (call) => call.input['action'] == 'query_macro_attribution',
    );
    expect(attribution.name, 'MarketData');
    expect(attribution.input['target'], 'A-shares');
  });

  test('adds governed finance news refresh before macro news readback', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final rewritten = hooks.rewriteToolCalls(
      messages: [Message(role: Role.user, content: 'macro source update')],
      turnStartIndex: 0,
      prompt: null,
      toolCalls: const [
        ToolUse(
          id: 'sources',
          name: 'MarketData',
          input: {'action': 'macro_research_sources', 'target': 'A-shares'},
        ),
        ToolUse(
          id: 'news-readback',
          name: 'MarketData',
          input: {'action': 'query_finance_news', 'query': 'A-shares'},
        ),
      ],
    );

    final actions = rewritten.map((call) => call.input['action']).toList();
    expect(actions, isNot(contains('finance_news')));
    expect(actions.where((action) => action == 'query_finance_news').length, 1);
    expect(actions, contains('query_macro_attribution'));
    expect(actions, contains('query_macro_research_evidence'));
  });

  test('labels raw finance news result as refresh and readback evidence', () {
    final summary = FinanceMacroEvidenceSummary().build(
      messages: [
        Message(role: Role.user, content: 'macro source update'),
        Message(
          role: Role.assistant,
          content: '',
          toolUses: const [
            ToolUse(
              id: 'factor',
              name: 'MarketData',
              input: {'action': 'query_macro_factors', 'target': 'A-shares'},
            ),
            ToolUse(
              id: 'news-refresh',
              name: 'MarketData',
              input: {'action': 'finance_news', 'query': 'A-shares'},
            ),
          ],
        ),
        _tool('factor', {
          'action': 'query_macro_factors',
          'rows': [
            {'title': 'Policy liquidity context', 'family': 'rates_liquidity'},
          ],
        }),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'news-refresh',
            content:
                'finance_news | provider:akshare | asOf:2026-07-09 | '
                'fetchedAt:2026-07-09T08:00:00Z\n'
                'A-share policy clue',
          ),
        ),
      ],
      turnStartIndex: 0,
      failureSummary: 'test',
    );

    expect(summary, contains('新闻刷新与读回'));
    expect(summary, contains('fetchedAt=2026-07-09T08:00:00Z'));
  });

  test(
    'does not retry finance news refresh after same-turn provider failure',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
      final rewritten = hooks.rewriteToolCalls(
        messages: [
          Message(role: Role.user, content: 'macro source update'),
          Message(
            role: Role.assistant,
            content: '',
            toolUses: const [
              ToolUse(
                id: 'factor',
                name: 'MarketData',
                input: {'action': 'query_macro_factors', 'target': 'A-shares'},
              ),
              ToolUse(
                id: 'failed-news',
                name: 'MarketData',
                input: {'action': 'finance_news', 'query': 'A-shares'},
              ),
            ],
          ),
          _tool('factor', {
            'action': 'query_macro_factors',
            'rows': [
              {
                'title': 'Policy liquidity context',
                'family': 'rates_liquidity',
              },
            ],
          }),
          Message(
            role: Role.tool,
            toolResult: ToolResult(
              toolUseId: 'failed-news',
              content: 'arbitrary provider display text',
              isError: true,
            ),
          ),
        ],
        turnStartIndex: 0,
        prompt: null,
        toolCalls: const [
          ToolUse(
            id: 'retry-news',
            name: 'MarketData',
            input: {'action': 'finance_news', 'query': 'A-shares'},
          ),
        ],
      );

      final actions = rewritten.map((call) => call.input['action']).toList();
      expect(actions, isNot(contains('finance_news')));
      expect(actions, contains('query_finance_news'));
    },
  );

  test('intercepts generic search after governed macro evidence exists', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(
        role: Role.user,
        content:
            'macro analysis\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"macro_attribution","assetClass":"stock","intentMode":"analysis","executionMode":"readback","safetyBoundary":"read-only macro attribution","confirmationState":"none","source":"agent-structured-intent"}}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'factors',
            name: 'MarketData',
            input: {'action': 'query_macro_factors', 'target': 'A-shares'},
          ),
          ToolUse(
            id: 'content',
            name: 'MarketData',
            input: {
              'action': 'query_macro_research_content',
              'provider': 'pboc',
            },
          ),
          ToolUse(
            id: 'news',
            name: 'MarketData',
            input: {'action': 'query_finance_news', 'query': 'A-shares'},
          ),
        ],
      ),
      _tool('factors', {
        'action': 'query_macro_factors',
        'status': 'ok',
        'rows': [
          {
            'title': '政策利率和流动性预期',
            'family': 'rates_liquidity',
            'source': 'pboc',
            'sourceDataTime': '2026-07-01',
            'affectedAssets': [
              'equity',
              'fund',
              'consumption funds',
              'consumer equities',
              'technology equities',
            ],
            'regions': ['China'],
            'sectors': ['policy-sensitive sectors'],
            'transmissionChannels': ['liquidity', 'risk_appetite'],
            'expectedDirection': 'mixed',
          },
        ],
      }),
      _tool('content', {
        'action': 'query_macro_research_content',
        'status': 'ok',
        'contentEvidence': [
          {
            'title': 'Monetary Policy Report',
            'sourceName': 'PBOC',
            'sourceDataTime': '2026-06-30',
            'contentHash': 'abcdef1234567890',
            'keyClaims': [
              'liquidity remains an important transmission channel',
            ],
            'bodyPreview':
                'The official report discusses liquidity, credit and policy transmission.',
            'evidenceTier': 'official_event_document',
            'accessStatus': 'public',
            'confidenceEffect': 'raises confidence',
            'nextEvidenceAction': 'use cache/readback',
          },
        ],
      }),
      _tool('news', {
        'action': 'query_finance_news',
        'status': 'ok',
        'sourceDataTime': '2026-07-01T09:00:00.000Z',
        'fetchedAt': '2026-07-09T06:00:00.000Z',
        'count': 1,
        'data': [
          {
            'title': 'A-share policy news clue',
            'source': 'akshare',
            'published_at': '2026-07-01T09:00:00.000Z',
            'url': 'https://example.com/news',
          },
        ],
      }),
    ];

    final interception = hooks.interceptToolCalls(
      messages: messages,
      turnStartIndex: 0,
      prompt: null,
      toolCalls: const [
        ToolUse(
          id: 'search',
          name: 'Research',
          input: {'action': 'search', 'query': 'A股 宏观 风险偏好'},
        ),
      ],
    );

    expect(interception, isNotNull);
    expect(interception!.skippedReason, contains('governed macro evidence'));
    expect(interception.answer, contains('宏观证据与来源状态'));
    expect(interception.answer, contains('政策利率和流动性预期'));
    expect(interception.answer, contains('Monetary Policy Report'));
    expect(interception.answer, contains('可靠性'));
    expect(interception.answer, contains('新鲜度'));
    expect(interception.answer, contains('资产影响'));
    expect(interception.answer, contains('消费基金'));
    expect(interception.answer, contains('科技基金'));
    expect(interception.answer, contains('基金分类口径'));
    expect(interception.answer, contains('置信度/下一步'));
    expect(interception.answer, contains('tier=official_event_document'));
    expect(interception.answer, contains('impact=mixed'));
    expect(interception.answer, contains('Research/WebFetch'));
  });

  test('cites EIA numeric evidence for oil-market A-share sector risk', () {
    final summary = FinanceMacroEvidenceSummary().build(
      messages: [
        Message(
          role: Role.user,
          content: 'EIA oil inventory macro sector risk',
        ),
        Message(
          role: Role.assistant,
          content: '',
          toolUses: const [
            ToolUse(
              id: 'eia',
              name: 'MarketData',
              input: {
                'action': 'query_macro_numeric_series',
                'provider': 'eia',
                'seriesId': 'WCESTUS1',
                'target': 'A-shares',
              },
            ),
          ],
        ),
        _tool('eia', {
          'action': 'query_macro_numeric_series',
          'status': 'ok',
          'series': [
            {
              'seriesId': 'WCESTUS1',
              'metricName': 'WCESTUS1 US commercial crude oil inventories',
              'provider': 'eia',
              'sourceName': 'EIA',
              'value': 420000,
              'unit': 'MBBL',
              'sourceDataTime': '2026-07-03',
              'fetchedAt': '2026-07-10T02:20:00.000Z',
              'affectedAssets': ['oil', 'energy equities', 'A-shares'],
              'affectedSectors': ['Energy', 'Transport', 'Materials'],
              'transmissionChannels': ['energy inventory', 'inflation input'],
              'expectedDirection': 'mixed',
              'evidenceTier': 'official_numeric_fact',
              'accessStatus': 'public',
              'confidenceEffect': 'mixed',
              'nextEvidenceAction': 'use cache/readback',
            },
          ],
        }),
      ],
      turnStartIndex: 0,
      failureSummary: 'test',
    );

    expect(summary, contains('WCESTUS1 US commercial crude oil inventories'));
    expect(summary, contains('EIA'));
    expect(summary, contains('value=420000 MBBL'));
    expect(summary, contains('能源'));
    expect(summary, contains('商品/能源'));
    expect(summary, contains('不能直接编译成可执行交易信号'));
  });

  test('uses EIA only as stock and fund macro context', () {
    final summary = FinanceMacroEvidenceSummary().build(
      messages: [
        Message(role: Role.user, content: 'stock and fund macro context'),
        Message(
          role: Role.assistant,
          content: '',
          toolUses: const [
            ToolUse(
              id: 'quote',
              name: 'MarketData',
              input: {'action': 'query_quote', 'code': '601857'},
            ),
            ToolUse(
              id: 'fund',
              name: 'MarketData',
              input: {'action': 'query_fund_nav', 'code': '162411'},
            ),
            ToolUse(
              id: 'eia',
              name: 'MarketData',
              input: {
                'action': 'query_macro_numeric_series',
                'provider': 'eia',
                'seriesId': 'WCESTUS1',
                'assets': 'funds',
              },
            ),
          ],
        ),
        _tool('quote', {
          'action': 'query_quote',
          'status': 'ok',
          'rows': [
            {'code': '601857', 'name': '中国石油', 'source': 'local'},
          ],
        }),
        _tool('fund', {
          'action': 'query_fund_nav',
          'status': 'ok',
          'code': '162411',
          'source': 'local',
          'count': 1,
        }),
        _tool('eia', {
          'action': 'query_macro_numeric_series',
          'status': 'ok',
          'series': [
            {
              'seriesId': 'WCESTUS1',
              'metricName': 'US commercial crude oil inventories',
              'provider': 'eia',
              'sourceName': 'EIA',
              'value': 420000,
              'unit': 'MBBL',
              'sourceDataTime': '2026-07-03',
              'fetchedAt': '2026-07-10T02:20:00.000Z',
              'affectedAssets': ['oil', 'energy equities', 'funds'],
              'affectedSectors': ['Energy'],
              'transmissionChannels': ['energy inventory', 'oil supply demand'],
              'expectedDirection': 'mixed',
              'evidenceTier': 'official_numeric_fact',
              'accessStatus': 'public',
            },
          ],
        }),
      ],
      turnStartIndex: 0,
      failureSummary: 'test',
    );

    expect(summary, contains('个股行情'));
    expect(summary, contains('基金净值'));
    expect(summary, contains('US commercial crude oil inventories'));
    expect(summary, contains('基金'));
    expect(summary, contains('不能直接编译成可执行交易信号'));
    expect(summary, contains('本轮没有执行下单'));
  });

  test('keeps EIA strategy and watchlist use as observation context', () {
    final summary = FinanceMacroEvidenceSummary().build(
      messages: [
        Message(role: Role.user, content: 'strategy watch with EIA'),
        Message(
          role: Role.assistant,
          content: '',
          toolUses: const [
            ToolUse(
              id: 'watch',
              name: 'Watchlist',
              input: {'action': 'list', 'type': 'macro-condition'},
            ),
            ToolUse(
              id: 'eia',
              name: 'MarketData',
              input: {
                'action': 'query_macro_numeric_series',
                'provider': 'eia',
                'seriesId': 'WCESTUS1',
                'assets': 'strategy',
              },
            ),
          ],
        ),
        _tool('eia', {
          'action': 'query_macro_numeric_series',
          'status': 'ok',
          'series': [
            {
              'seriesId': 'WCESTUS1',
              'metricName': 'US commercial crude oil inventories',
              'provider': 'eia',
              'sourceName': 'EIA',
              'value': 420000,
              'unit': 'MBBL',
              'sourceDataTime': '2026-07-03',
              'fetchedAt': '2026-07-10T02:20:00.000Z',
              'affectedAssets': ['strategy', 'oil', 'energy equities'],
              'affectedSectors': ['Energy'],
              'transmissionChannels': ['energy inventory'],
              'expectedDirection': 'mixed',
              'evidenceTier': 'official_numeric_fact',
              'accessStatus': 'public',
              'nextEvidenceAction': 'use cache/readback',
            },
          ],
        }),
      ],
      turnStartIndex: 0,
      failureSummary: 'test',
    );

    expect(summary, contains('自选股'));
    expect(summary, contains('策略'));
    expect(summary, contains('观察条件'));
    expect(summary, contains('失效条件'));
    expect(summary, contains('本轮没有执行下单、保存策略'));
    expect(summary, contains('不能直接编译成可执行交易信号'));
  });

  test(
    'rewrites generic fallback to attribution when prior macro evidence exists',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
      final rewritten = hooks.rewriteToolCalls(
        messages: [
          Message(role: Role.user, content: 'macro analysis'),
          Message(
            role: Role.assistant,
            content: '',
            toolUses: [
              ToolUse(
                id: 'factor',
                name: 'MarketData',
                input: {
                  'action': 'query_macro_factors',
                  'assets': 'bond funds',
                },
              ),
            ],
          ),
          _tool('factor', {
            'action': 'query_macro_factors',
            'rows': [
              {
                'title': 'FRED official series',
                'family': 'macro_official_series',
              },
            ],
          }),
        ],
        turnStartIndex: 0,
        prompt: null,
        toolCalls: const [
          ToolUse(
            id: 'search',
            name: 'Research',
            input: {'action': 'search', 'query': 'bond fund macro'},
          ),
        ],
      );

      expect(rewritten.length, 2);
      expect(
        rewritten.map((call) => call.input['action']),
        contains('query_macro_attribution'),
      );
      expect(
        rewritten.map((call) => call.input['action']),
        contains('query_finance_news'),
      );
    },
  );

  test('bounded macro summary preserves structured non-macro context', () {
    final summary = FinanceMacroEvidenceSummary().build(
      messages: [
        Message(role: Role.user, content: 'macro analysis'),
        Message(
          role: Role.assistant,
          content: '',
          toolUses: [
            ToolUse(
              id: 'quote',
              name: 'MarketData',
              input: {'action': 'query_quote', 'code': '600519'},
            ),
            ToolUse(
              id: 'kline',
              name: 'MarketData',
              input: {'action': 'query_kline', 'code': '600519', 'limit': 120},
            ),
            ToolUse(
              id: 'fund',
              name: 'MarketData',
              input: {'action': 'query_fundamental', 'code': '600519'},
            ),
            ToolUse(id: 'watch', name: 'Watchlist', input: {'action': 'list'}),
            ToolUse(
              id: 'factor',
              name: 'MarketData',
              input: {
                'action': 'query_macro_factors',
                'assets': 'bond funds',
                'target': '600519',
              },
            ),
          ],
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'auto-retained-quote',
            content:
                '600519 quote | interface:stock.quote | provider:local | cacheStatus:local-hit | asOf:2026-07-10T14:06:20Z | fetchedAt:2026-07-10T14:06:21Z Price: 1204.98 change: +1.93%',
          ),
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'auto-retained-kline',
            content:
                '600519 daily kline | interface:stock.daily_kline | provider:tencent | cacheStatus:local-hit | asOf:2026-07-07 | fetchedAt:2026-07-10T13:47:08Z: 120 bars (2026-01-06 ~ 2026-07-07)',
          ),
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'auto-retained-fund',
            content:
                '600519 fundamentals | interface:stock.daily_valuation | provider:eastmoney | cacheStatus:local-hit | asOf:2026-03-31 | fetchedAt:2026-07-07T07:43:20Z: 2026-03-31 PE:13.64 PB:6.3 ROE:10.57%',
          ),
        ),
        _tool('factor', {
          'action': 'query_macro_factors',
          'rows': [
            {
              'title': 'FRED official series',
              'family': 'macro_official_series',
            },
          ],
        }),
      ],
      turnStartIndex: 0,
      failureSummary: 'test',
    );

    expect(summary, contains('贵州茅台'));
    expect(summary, contains('债券基金'));
    expect(summary, contains('price=1204.98'));
    expect(summary, contains('120 bars'));
    expect(summary, contains('PE=13.64'));
    expect(summary, contains('自选股'));
    expect(summary, contains('信用'));
  });

  test(
    'bounded hook waits for stock quote evidence on named stock macro target',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
      final withoutQuote = hooks.buildBudgetStopText(
        messages: [
          _macroStockUser('贵州茅台'),
          Message(
            role: Role.assistant,
            content: '',
            toolUses: const [
              ToolUse(
                id: 'factor',
                name: 'MarketData',
                input: {
                  'action': 'query_macro_factors',
                  'target': '贵州茅台；白酒；政策',
                },
              ),
              ToolUse(
                id: 'news',
                name: 'MarketData',
                input: {'action': 'query_finance_news', 'query': '贵州茅台；白酒；政策'},
              ),
            ],
          ),
          _tool('factor', {'action': 'query_macro_factors', 'rows': []}),
          _tool('news', {'action': 'query_finance_news', 'data': []}),
        ],
        turnStartIndex: 0,
        prompt: null,
        failureSummary: 'test',
      );

      expect(withoutQuote, isNot(contains('宏观证据与来源状态')));

      final withQuote = hooks.buildBudgetStopText(
        messages: [
          _macroStockUser('贵州茅台'),
          Message(
            role: Role.assistant,
            content: '',
            toolUses: const [
              ToolUse(
                id: 'factor',
                name: 'MarketData',
                input: {
                  'action': 'query_macro_factors',
                  'target': '贵州茅台；白酒；政策',
                },
              ),
              ToolUse(
                id: 'quote',
                name: 'MarketData',
                input: {'action': 'query_quote', 'code': '600519'},
              ),
            ],
          ),
          _tool('factor', {'action': 'query_macro_factors', 'rows': []}),
          _tool('quote', {
            'action': 'query_quote',
            'data': [
              {'code': '600519', 'name': '贵州茅台', 'price': 1500},
            ],
          }),
        ],
        turnStartIndex: 0,
        prompt: null,
        failureSummary: 'test',
      );

      expect(withQuote, contains('宏观证据与来源状态'));
      expect(withQuote, contains('个股行情'));
    },
  );

  test(
    'bounded hook prefers named stock macro target over broad industry target',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
      final waiting = hooks.buildBudgetStopText(
        messages: [
          _macroStockUser('贵州茅台'),
          Message(
            role: Role.assistant,
            content: '',
            toolUses: const [
              ToolUse(
                id: 'industry',
                name: 'MarketData',
                input: {'action': 'query_macro_factors', 'target': '白酒'},
              ),
              ToolUse(
                id: 'stock',
                name: 'MarketData',
                input: {'action': 'query_macro_factors', 'target': '贵州茅台'},
              ),
              ToolUse(
                id: 'attr',
                name: 'MarketData',
                input: {'action': 'query_macro_attribution', 'target': '白酒'},
              ),
            ],
          ),
          _tool('industry', {'action': 'query_macro_factors', 'rows': []}),
          _tool('stock', {'action': 'query_macro_factors', 'rows': []}),
          _tool('attr', {'action': 'query_macro_attribution', 'rows': []}),
        ],
        turnStartIndex: 0,
        prompt: null,
        failureSummary: 'test',
      );

      expect(waiting, isNot(contains('宏观证据与来源状态')));

      final withQuote = hooks.buildBudgetStopText(
        messages: [
          _macroStockUser('贵州茅台'),
          Message(
            role: Role.assistant,
            content: '',
            toolUses: const [
              ToolUse(
                id: 'industry',
                name: 'MarketData',
                input: {'action': 'query_macro_factors', 'target': '白酒'},
              ),
              ToolUse(
                id: 'stock',
                name: 'MarketData',
                input: {'action': 'query_macro_factors', 'target': '贵州茅台'},
              ),
              ToolUse(
                id: 'quote',
                name: 'MarketData',
                input: {'action': 'query_quote', 'code': '600519'},
              ),
            ],
          ),
          _tool('industry', {'action': 'query_macro_factors', 'rows': []}),
          _tool('stock', {'action': 'query_macro_factors', 'rows': []}),
          _tool('quote', {
            'action': 'query_quote',
            'data': [
              {'code': '600519', 'name': '贵州茅台', 'price': 1500},
            ],
          }),
        ],
        turnStartIndex: 0,
        prompt: null,
        failureSummary: 'test',
      );

      expect(withQuote, contains('宏观证据与来源状态'));
      expect(withQuote, contains('贵州茅台'));
    },
  );

  test(
    'uses typed workflow subject instead of inferring stock identity from Research query',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
      final waiting = hooks.buildBudgetStopText(
        messages: [
          _macroStockUser('贵州茅台'),
          Message(
            role: Role.assistant,
            content: '',
            toolUses: const [
              ToolUse(
                id: 'factor',
                name: 'MarketData',
                input: {'action': 'query_macro_factors', 'target': '白酒'},
              ),
              ToolUse(
                id: 'research',
                name: 'Research',
                input: {'query': '白酒 贵州茅台 政策 新闻 2026'},
              ),
            ],
          ),
          _tool('factor', {'action': 'query_macro_factors', 'rows': []}),
        ],
        turnStartIndex: 0,
        prompt: null,
        failureSummary: 'test',
      );

      expect(waiting, isNot(contains('宏观证据与来源状态')));

      final withQuote = hooks.buildBudgetStopText(
        messages: [
          _macroStockUser('贵州茅台'),
          Message(
            role: Role.assistant,
            content: '',
            toolUses: const [
              ToolUse(
                id: 'factor',
                name: 'MarketData',
                input: {'action': 'query_macro_factors', 'target': '白酒'},
              ),
              ToolUse(
                id: 'research',
                name: 'Research',
                input: {'query': '白酒 贵州茅台 政策 新闻 2026'},
              ),
              ToolUse(
                id: 'quote',
                name: 'MarketData',
                input: {'action': 'query_quote', 'code': '600519'},
              ),
            ],
          ),
          _tool('factor', {'action': 'query_macro_factors', 'rows': []}),
          _tool('quote', {
            'action': 'query_quote',
            'data': [
              {'code': '600519', 'name': '贵州茅台', 'price': 1500},
            ],
          }),
        ],
        turnStartIndex: 0,
        prompt: null,
        failureSummary: 'test',
      );

      expect(withQuote, contains('宏观证据与来源状态'));
      expect(withQuote, contains('贵州茅台'));
    },
  );

  test('preflights stock identity readback for named macro stock target', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final calls = hooks.buildPreflightToolCalls([
      _macroStockUser('贵州茅台'),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'factor',
            name: 'MarketData',
            input: {'action': 'query_macro_factors', 'target': '贵州茅台；白酒；政策'},
          ),
        ],
      ),
      _tool('factor', {'action': 'query_macro_factors', 'rows': []}),
    ]);

    expect(calls, isNotNull);
    expect(calls!.single.name, 'MarketData');
    expect(calls.single.input['action'], 'query_stock_list');
    expect(calls.single.input['keyword'], '贵州茅台');
  });

  test('recovers quote from typed stock identity without parsing display text', () async {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    Map<String, dynamic>? recoveryInput;
    await hooks.buildRecovery(
      prompt: null,
      messages: [
        _macroStockUser('Guizhou Moutai'),
        Message(
          role: Role.assistant,
          content: '',
          toolUses: const [
            ToolUse(
              id: 'factor',
              name: 'MarketData',
              input: {
                'action': 'query_macro_factors',
                'target': 'Guizhou Moutai',
              },
            ),
            ToolUse(
              id: 'identity',
              name: 'MarketData',
              input: {
                'action': 'query_stock_list',
                'keyword': 'Guizhou Moutai',
              },
            ),
          ],
        ),
        _tool('factor', {'action': 'query_macro_factors', 'rows': []}),
        _tool('identity', {
          'action': 'query_stock_list',
          'data': [
            {'code': '600519', 'name': '贵州茅台', 'market': 'SH'},
          ],
        }),
      ],
      toolByName: (name) => _FakeTool(name),
      callTool: (tool, toolUseId, input) async {
        recoveryInput = input;
        return ToolResult(toolUseId: toolUseId, content: '{}');
      },
    );

    expect(recoveryInput, {
      'action': 'query_quote',
      'code': '600519',
      'limit': 1,
    });
  });
}

Message _tool(String id, Map<String, dynamic> payload) {
  return Message(
    role: Role.tool,
    toolResult: ToolResult(toolUseId: id, content: jsonEncode(payload)),
  );
}

Message _macroStockUser(String subject) {
  return Message(
    role: Role.user,
    content:
        'macro stock analysis\n'
        'data: ${jsonEncode({
          'workflowState': {
            'contract': 'finance-workflow-state-v1',
            'workflowKind': 'macro_factor_lookup',
            'assetClass': 'stock',
            'intentMode': 'analysis',
            'executionMode': 'preview_only',
            'safetyBoundary': 'read-only macro attribution',
            'evidenceRefs': <String>[],
            'confirmationState': 'none',
            'subject': subject,
            'source': 'agent-structured-intent',
          },
        })}',
  );
}

class _FakeTool extends Tool {
  _FakeTool(this.name);

  @override
  final String name;

  @override
  String get description => name;

  @override
  Map<String, dynamic> get inputSchema => const {};

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async => ToolResult(toolUseId: toolUseId, content: '{}');
}
