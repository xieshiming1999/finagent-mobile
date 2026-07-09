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
    expect(actions, contains('finance_news'));
    expect(actions.where((action) => action == 'query_finance_news').length, 1);
    expect(
      actions.indexOf('finance_news') <
          actions.lastIndexOf('query_finance_news'),
      isTrue,
    );
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
            'affectedAssets': ['equity', 'fund'],
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
    expect(interception.answer, contains('资产影响'));
    expect(interception.answer, contains('置信度/下一步'));
    expect(interception.answer, contains('tier=official_event_document'));
    expect(interception.answer, contains('impact=mixed'));
    expect(interception.answer, contains('Research/WebFetch'));
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
