import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/artifact_registry.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/workflow_verifier_tool/workflow_verifier_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WorkflowVerifier passes with tool and artifact evidence', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    _seedSession(context, toolName: 'MarketData');
    ArtifactRegistry(context.basePath).register(
      kind: ArtifactKind.analysis,
      path: 'memory/reports/stock-analysis.md',
      title: 'Stock analysis',
      source: 'agent-workflow',
      verificationStatus: ArtifactVerificationStatus.verified,
    );

    final result =
        jsonDecode(
              (await WorkflowVerifierTool().call('verify-1', {
                'action': 'check',
                'workflow': 'stock_research',
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(result['contract'], 'workflow-verifier-check-v1');
    expect(result['passed'], true);
    expect(result['missing'], isEmpty);
    expect(result['observed']['toolNames'], contains('MarketData'));
  });

  test('WorkflowVerifier reports missing artifact evidence', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    _seedSession(context, toolName: 'MarketData');

    final result =
        jsonDecode(
              (await WorkflowVerifierTool().call('verify-2', {
                'action': 'check',
                'workflow': 'stock_research',
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(result['passed'], false);
    expect(result['missing'], contains('artifact_evidence'));
    expect(result['nextAction'], contains('Do not finalize yet'));
  });

  test(
    'WorkflowVerifier accepts stock selection without stale artifact reuse',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      _seedSession(context, toolName: 'DataProcess');
      _seedWorkflowState(context, workflowKind: 'stock_selection');

      final result =
          jsonDecode(
                (await WorkflowVerifierTool().call('verify-selection', {
                  'action': 'check',
                  'workflow': 'stock_selection',
                  'requireWorkflowState': true,
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(result['passed'], true);
      expect(result['missing'], isEmpty);
      expect(
        result['observed']['workflowState']['workflowState']['workflowKind'],
        'stock_selection',
      );
      expect(
        result['checks'].firstWhere(
          (check) => check['id'] == 'artifact_evidence',
        )['message'],
        contains('Artifact evidence is optional'),
      );
    },
  );

  test('WorkflowVerifier requires fund-specific readback evidence', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    _seedSessionCalls(context, [
      {
        'id': 'tool-1',
        'name': 'MarketData',
        'input': {'action': 'query_macro_factors', 'target': 'bond funds'},
        'result': '{"status":"ok"}',
      },
    ]);

    final missingResult =
        jsonDecode(
              (await WorkflowVerifierTool().call('verify-fund-missing', {
                'action': 'check',
                'workflow': 'fund_selection',
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(missingResult['passed'], false);
    expect(missingResult['missing'], contains('fund_identity_evidence'));
    expect(missingResult['missing'], contains('fund_nav_or_yield_evidence'));

    _seedSessionCalls(context, [
      {
        'id': 'tool-1',
        'name': 'MarketData',
        'input': {'action': 'query_fund_list', 'limit': 20},
        'result': 'fund_list | interface:fund.identity_list',
      },
      {
        'id': 'tool-2',
        'name': 'MarketData',
        'input': {'action': 'query_fund_nav', 'code': '000083'},
        'result': '000083 fund NAV | interface:fund.nav_history',
      },
      {
        'id': 'tool-3',
        'name': 'MarketData',
        'input': {'action': 'query_macro_factors', 'target': 'bond funds'},
        'result': '{"status":"ok"}',
      },
    ]);

    final passedResult =
        jsonDecode(
              (await WorkflowVerifierTool().call('verify-fund-pass', {
                'action': 'check',
                'workflow': 'fund_selection',
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(passedResult['passed'], true);
    expect(passedResult['missing'], isEmpty);
    expect(
      passedResult['observed']['workflowSpecific']['navOrYield']['action'],
      'query_fund_nav',
    );
  });

  test(
    'WorkflowVerifier rejects stock selection with stock research state',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      _seedSession(context, toolName: 'DataProcess');
      _seedWorkflowState(context, workflowKind: 'stock_research');

      final result =
          jsonDecode(
                (await WorkflowVerifierTool().call('verify-selection-state', {
                  'action': 'check',
                  'workflow': 'stock_selection',
                  'requireWorkflowState': true,
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(result['passed'], false);
      expect(result['missing'], contains('workflow_state'));
      expect(
        result['checks'].firstWhere(
          (check) => check['id'] == 'workflow_state',
        )['message'],
        contains('stock_selection'),
      );
    },
  );

  test(
    'WorkflowVerifier requires watchlist handoff add, readback, condition, and source evidence',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      _seedSession(context, toolName: 'Watchlist');
      _seedWorkflowState(context, workflowKind: 'watchlist_handoff');

      final missingResult =
          jsonDecode(
                (await WorkflowVerifierTool().call('verify-watchlist-missing', {
                  'action': 'check',
                  'workflow': 'watchlist_handoff',
                  'requireWorkflowState': true,
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(missingResult['passed'], false);
      expect(missingResult['missing'], contains('watchlist_add_evidence'));
      expect(missingResult['missing'], contains('watchlist_readback_evidence'));

      _seedSessionCalls(context, [
        {
          'id': 'tool-1',
          'name': 'Watchlist',
          'input': {
            'action': 'add',
            'symbol': '002215',
            'name': '诺普信',
            'entryCondition': 'ROE remains above 15 and valuation gap is resolved',
            'stopLoss': 8,
            'source': 'stock-picking: query_stock_daily_valuation + query_fundamental',
          },
          'result': '{"status":"added","symbol":"002215"}',
        },
        {
          'id': 'tool-2',
          'name': 'Watchlist',
          'input': {'action': 'list', 'symbol': '002215'},
          'result':
              '{"count":1,"items":[{"symbol":"002215","entryCondition":"ROE remains above 15"}]}',
        },
      ]);

      final result =
          jsonDecode(
                (await WorkflowVerifierTool().call('verify-watchlist', {
                  'action': 'check',
                  'workflow': 'watchlist_handoff',
                  'requireWorkflowState': true,
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(result['passed'], true);
      expect(result['missing'], isEmpty);
      expect(result['observed']['toolNames'], contains('Watchlist'));
      expect(result['observed']['workflowSpecific']['added'], hasLength(1));
      expect(result['observed']['workflowSpecific']['readback'], hasLength(1));
    },
  );

  test(
    'WorkflowVerifier treats data fetch failures as recovered after valid watchlist handoff evidence',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      _seedWorkflowState(context, workflowKind: 'watchlist_handoff');
      _seedSessionCalls(context, [
        {
          'id': 'tool-1',
          'name': 'DataStore',
          'input': {
            'action': 'fetch',
            'code': '600519',
            'type': 'fundamental',
          },
          'result': 'DataStore fetch failed: provider unavailable',
          'isError': true,
        },
        {
          'id': 'tool-2',
          'name': 'Watchlist',
          'input': {
            'action': 'add',
            'symbol': '600519',
            'name': '贵州茅台',
            'entryCondition': 'Wait for valuation and price confirmation',
            'stopLoss': 1100,
            'source': 'query_stock_daily_valuation(local cache)',
          },
          'result': '{"status":"added","symbol":"600519"}',
        },
        {
          'id': 'tool-3',
          'name': 'Watchlist',
          'input': {'action': 'list', 'symbol': '600519'},
          'result':
              '{"count":1,"items":[{"symbol":"600519","entryCondition":"Wait for valuation and price confirmation"}]}',
        },
      ]);

      final result =
          jsonDecode(
                (await WorkflowVerifierTool().call(
                  'verify-watchlist-recovered-error',
                  {
                    'action': 'check',
                    'workflow': 'watchlist_handoff',
                    'requireWorkflowState': true,
                  },
                  context,
                )).content,
              )
              as Map<String, dynamic>;

      expect(result['passed'], true);
      expect(result['missing'], isEmpty);
      expect(
        result['checks'].firstWhere(
          (check) => check['id'] == 'no_tool_errors',
        )['message'],
        contains('recovered tool error'),
      );
    },
  );

  test(
    'WorkflowVerifier accepts strategy rerun with backtest artifact evidence',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      _seedSessionCalls(context, [
        {
          'id': 'tool-1',
          'name': 'MarketData',
          'input': {
            'action': 'custom_strategy_run',
            'strategyId': 'custom_moutai_ema_trend_v1_v1',
            'symbols': ['300059'],
          },
          'result': jsonEncode({
            'action': 'custom_strategy_run',
            'strategyId': 'custom_moutai_ema_trend_v1_v1',
            'code': '300059',
            'dataCoverage': {'symbol': '300059', 'sufficient': true},
          }),
        },
      ]);
      _seedWorkflowState(context, workflowKind: 'strategy_rerun');
      ArtifactRegistry(context.basePath).register(
        kind: ArtifactKind.backtest,
        path: 'memory/reports/backtest.md',
        title: 'Backtest',
        source: 'agent-workflow',
        verificationStatus: ArtifactVerificationStatus.verified,
      );

      final result =
          jsonDecode(
                (await WorkflowVerifierTool().call('verify-rerun', {
                  'action': 'check',
                  'workflow': 'strategy_rerun',
                  'requireWorkflowState': true,
                  'strategyId': 'custom_moutai_ema_trend_v1_v1',
                  'targetSymbols': ['300059'],
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(result['passed'], true);
      expect(result['missing'], isEmpty);
    },
  );

  test(
    'WorkflowVerifier rejects strategy rerun without selected target evidence',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      _seedSessionCalls(context, [
        {
          'id': 'tool-1',
          'name': 'MarketData',
          'input': {
            'action': 'custom_strategy_run',
            'strategyId': 'custom_moutai_ema_trend_v1_v1',
            'symbols': ['600519'],
          },
          'result': jsonEncode({
            'action': 'custom_strategy_run',
            'strategyId': 'custom_moutai_ema_trend_v1_v1',
            'code': '600519',
            'dataCoverage': {'symbol': '600519', 'sufficient': true},
          }),
        },
      ]);
      _seedWorkflowState(context, workflowKind: 'strategy_rerun');
      ArtifactRegistry(context.basePath).register(
        kind: ArtifactKind.backtest,
        path: 'memory/reports/backtest.md',
        title: 'Backtest',
        source: 'agent-workflow',
        verificationStatus: ArtifactVerificationStatus.verified,
      );

      final result =
          jsonDecode(
                (await WorkflowVerifierTool().call('verify-rerun-target', {
                  'action': 'check',
                  'workflow': 'strategy_rerun',
                  'requireWorkflowState': true,
                  'strategyId': 'custom_moutai_ema_trend_v1_v1',
                  'targetSymbols': ['300059'],
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(result['passed'], false);
      expect(result['missing'], contains('strategy_rerun_target_symbols'));
      expect(result['nextAction'], contains('Do not finalize yet'));
    },
  );

  test(
    'WorkflowVerifier accepts trade review with simulated trading evidence',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      _seedSession(context, toolName: 'XueqiuTrade');
      _seedWorkflowState(context, workflowKind: 'trade_review');

      final result =
          jsonDecode(
                (await WorkflowVerifierTool().call('verify-trade-review', {
                  'action': 'check',
                  'workflow': 'trade_review',
                  'requireWorkflowState': true,
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(result['passed'], true);
      expect(result['missing'], isEmpty);
    },
  );

  test(
    'WorkflowVerifier accepts trade preparation without order side effect',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      _seedSessionCalls(context, [
        {
          'id': 'tool-1',
          'name': 'XueqiuTrade',
          'input': {'action': 'balance'},
          'result': '{"cash":100000}',
        },
        {
          'id': 'tool-2',
          'name': 'MarketData',
          'input': {'action': 'quote', 'code': '600519'},
          'result': '{"price":1204.98}',
        },
        {
          'id': 'tool-3',
          'name': 'DataProcess',
          'input': {'action': 'indicators', 'code': '600519'},
          'result': '{"rsi":40.9}',
        },
      ]);

      final result =
          jsonDecode(
                (await WorkflowVerifierTool().call('verify-trade-prep', {
                  'action': 'check',
                  'workflow': 'trade_preparation',
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(result['passed'], true);
      expect(result['missing'], isEmpty);
      expect(result['observed']['approvalBoundary']['accountEvidence'], true);
      expect(result['observed']['approvalBoundary']['sizingEvidence'], true);
      expect(result['observed']['approvalBoundary']['sideEffectCalls'], isEmpty);
    },
  );

  test(
    'WorkflowVerifier rejects trade preparation with order side effect',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      _seedSessionCalls(context, [
        {
          'id': 'tool-1',
          'name': 'XueqiuTrade',
          'input': {'action': 'balance'},
          'result': '{"cash":100000}',
        },
        {
          'id': 'tool-2',
          'name': 'MarketData',
          'input': {'action': 'quote', 'code': '600519'},
          'result': '{"price":1204.98}',
        },
        {
          'id': 'tool-3',
          'name': 'XueqiuTrade',
          'input': {'action': 'buy', 'symbol': 'SH600519', 'shares': 8},
          'result': '{"success":true}',
        },
      ]);

      final result =
          jsonDecode(
                (await WorkflowVerifierTool().call('verify-trade-prep-write', {
                  'action': 'check',
                  'workflow': 'trade_preparation',
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(result['passed'], false);
      expect(result['missing'], contains('approval_boundary'));
      expect(result['missing'], contains('trade_no_side_effect'));
      expect(
        result['observed']['approvalBoundary']['sideEffectCalls'],
        ['XueqiuTrade.buy'],
      );
    },
  );

  test('WorkflowVerifier accepts matching typed workflow state', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    _seedSession(context, toolName: 'MarketData');
    _seedWorkflowState(context, workflowKind: 'stock_research');
    ArtifactRegistry(context.basePath).register(
      kind: ArtifactKind.analysis,
      path: 'memory/reports/stock-analysis.md',
      title: 'Stock analysis',
      source: 'agent-workflow',
      verificationStatus: ArtifactVerificationStatus.verified,
    );

    final result =
        jsonDecode(
              (await WorkflowVerifierTool().call('verify-state', {
                'action': 'check',
                'workflow': 'stock_research',
                'requireWorkflowState': true,
                'providerHealth': [
                  {'provider': 'tdx', 'status': 'healthy'},
                ],
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(result['passed'], true);
    expect(result['missing'], isEmpty);
    expect(result['observed']['workflowState']['id'], 'state-1');
  });

  test('WorkflowVerifier fails on blocking provider health', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    _seedSession(context, toolName: 'MarketData');
    ArtifactRegistry(context.basePath).register(
      kind: ArtifactKind.analysis,
      path: 'memory/reports/stock-analysis.md',
      title: 'Stock analysis',
      source: 'agent-workflow',
      verificationStatus: ArtifactVerificationStatus.verified,
    );

    final result =
        jsonDecode(
              (await WorkflowVerifierTool().call('verify-health', {
                'action': 'check',
                'workflow': 'stock_research',
                'providerHealth': [
                  {'provider': 'eastmoney', 'status': 'transport_unstable'},
                ],
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(result['passed'], false);
    expect(result['missing'], contains('provider_health'));
    expect(
      result['checks'].firstWhere(
        (check) => check['id'] == 'provider_health',
      )['message'],
      contains('eastmoney:transport_unstable'),
    );
  });

  test('WorkflowVerifier accepts durable macro evidence records', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    _seedSession(context, toolName: 'SourceReader');
    _seedWorkflowState(context, workflowKind: 'macro_attribution');
    _seedMacroEvidence(context);

    final result =
        jsonDecode(
              (await WorkflowVerifierTool().call('verify-macro', {
                'action': 'check',
                'workflow': 'macro_factor_lookup',
                'requireWorkflowState': true,
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(result['passed'], true);
    expect(result['missing'], isEmpty);
    expect(result['observed']['artifact']['kind'], 'macro_evidence');
    expect(result['observed']['artifact']['record']['contract'], 'macro-evidence-record-v1');
  });

  test(
    'WorkflowVerifier rejects unknown workflow through tool error',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final result = await WorkflowVerifierTool().call('verify-3', {
        'action': 'check',
        'workflow': 'unknown',
      }, context);

      expect(result.isError, true);
      expect(result.content, contains('Unknown WorkflowVerifier workflow'));
    },
  );
}

ToolContext _tempContext() {
  final dir = Directory.systemTemp.createTempSync(
    'finagent_workflow_verifier_tool_test_',
  );
  return ToolContext(basePath: dir.path, serviceBaseUrl: '');
}

void _seedSession(ToolContext context, {required String toolName}) {
  _seedSessionCalls(context, [
    {
      'id': 'tool-1',
      'name': toolName,
      'input': <String, dynamic>{},
      'result': '{}',
    },
  ]);
}

void _seedSessionCalls(
  ToolContext context,
  List<Map<String, dynamic>> calls,
) {
  final dir = Directory('${context.basePath}/sessions')
    ..createSync(recursive: true);
  final file = File('${dir.path}/current.jsonl');
  file.writeAsStringSync(
    [
      jsonEncode({
        'type': 'message',
        'role': 'assistant',
        'toolUses': calls
            .map(
              (call) => {
                'id': call['id'],
                'name': call['name'],
                'input': call['input'] ?? <String, dynamic>{},
              },
            )
            .toList(),
      }),
      for (final call in calls)
        jsonEncode({
          'type': 'message',
          'role': 'tool',
          'toolResult': {
            'toolUseId': call['id'],
            'content': call['result'] ?? '{}',
            'isError': call['isError'] == true,
          },
        }),
    ].join('\n'),
  );
}

void _seedWorkflowState(ToolContext context, {required String workflowKind}) {
  final dir = Directory('${context.memoryDir}/workflows')
    ..createSync(recursive: true);
  File('${dir.path}/state.json').writeAsStringSync(
    jsonEncode({
      'contract': 'workflow-state-store-v1',
      'records': [
        {
          'id': 'state-1',
          'contract': 'workflow-state-record-v1',
          'status': 'active',
          'workflowState': {
            'contract': 'finance-workflow-state-v1',
            'workflowKind': workflowKind,
            'assetClass': 'stock',
            'intentMode': 'analysis',
            'executionMode': 'preview_only',
            'safetyBoundary': 'no_trade',
            'evidenceRefs': ['quote'],
            'confirmationState': 'none',
            'source': 'test',
          },
          'requiredEvidence': ['quote'],
          'completedSteps': ['quote'],
          'generatedArtifacts': [],
          'updatedAt': '2026-07-11T00:00:00.000Z',
        },
      ],
    }),
  );
}

void _seedMacroEvidence(ToolContext context) {
  final dir = Directory('${context.memoryDir}/macro_evidence')
    ..createSync(recursive: true);
  File('${dir.path}/macro_test.json').writeAsStringSync(
    jsonEncode({
      'contract': 'macro-evidence-record-v1',
      'id': 'macro:test',
      'source': 'bea',
      'title': 'Official macro evidence',
      'topic': 'rates and demand',
      'region': 'US',
      'assetClass': 'equity',
      'keyClaims': ['Demand conditions affect cyclical earnings.'],
      'affectedAssets': ['A-shares', 'cyclical stocks'],
      'confidenceEffect': 'raises confidence in macro attribution, not a trade signal',
      'freshness': 'fresh',
      'tradeBoundary':
          'Macro evidence is context, hypothesis, and invalidation input. It is not a direct buy/sell rule.',
    }),
  );
}
