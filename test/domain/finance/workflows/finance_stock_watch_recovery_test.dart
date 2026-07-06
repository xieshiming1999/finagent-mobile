import 'dart:convert';

import 'package:finagent/agent/message.dart';
import 'package:finagent/agent/tool.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/domain/finance/workflows/finance_workflow_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'stock watch recovery writes watchlist and emits analysis evidence',
    () async {
      final calls = <Map<String, dynamic>>[];
      final request = _stockWatchStateContent();
      final answer = await FinanceWorkflowHooks(isBypassTool: (_) => false)
          .buildRecovery(
            prompt: request,
            messages: [
              Message(role: Role.user, content: request),
              _tool('quote', {
                'action': 'query_quote',
                'source': 'local quote_snapshot',
                'cacheStatus': 'cache-hit',
                'sourceDataTime': '2026-07-02',
                'fetchedAt': '2026-07-02T10:00:00Z',
                'data': [
                  {
                    'code': '300059',
                    'name': '东方财富',
                    'price': 20.1,
                    'changePct': 3.1,
                  },
                  {
                    'code': '600519',
                    'name': '贵州茅台',
                    'price': 1500,
                    'changePct': 0.8,
                  },
                  {
                    'code': '000858',
                    'name': '五粮液',
                    'price': 120,
                    'changePct': 1.2,
                  },
                ],
              }),
              _tool('hot', {
                'action': 'query_hot_rank',
                'source': 'local hot_rank',
                'data': [
                  {'code': '300059', 'name': '东方财富', 'rank': 2},
                  {'code': '600519', 'name': '贵州茅台', 'rank': 8},
                  {'code': '000858', 'name': '五粮液', 'rank': 12},
                ],
              }),
              _tool('flow', {
                'action': 'query_flow_rank',
                'source': 'local flow_rank',
                'data': [
                  {'code': '300059', 'main_net': 250000000},
                  {'code': '600519', 'main_net': 100000000},
                  {'code': '000858', 'main_net': 80000000},
                ],
              }),
            ],
            toolByName: (name) => name == 'Watchlist' ? _FakeTool(name) : null,
            callTool: (tool, toolUseId, input) async {
              calls.add(input);
              if (input['action'] == 'list') {
                return ToolResult(
                  toolUseId: toolUseId,
                  content: jsonEncode({
                    'count': calls.length - 1,
                    'items': const [],
                  }),
                );
              }
              return ToolResult(
                toolUseId: toolUseId,
                content: 'Added ${input['name']} (id: ${input['symbol']})',
              );
            },
          );

      expect(answer, isNotNull);
      expect(calls.where((call) => call['action'] == 'add'), hasLength(3));
      expect(calls.last['action'], 'list');
      final evidence = _analysisEvidence(answer!);
      expect(evidence['contract'], 'analysis-evidence-v1');
      expect(evidence['kind'], 'stock_analysis');
      expect(evidence['strategyReadiness'], 'analysis_only');
      expect(
        (evidence['subject'] as Map<String, dynamic>)['type'],
        'candidate_set',
      );
      expect(
        (evidence['sourceCoverage'] as Map<String, dynamic>)['interfaceId'],
        'stock.quote',
      );
    },
  );

  test('prompt text alone does not write stock watchlist', () async {
    final calls = <Map<String, dynamic>>[];
    final answer = await FinanceWorkflowHooks(isBypassTool: (_) => false)
        .buildRecovery(
          prompt: '帮我筛选值得观察的股票并加入观察池',
          messages: [
            Message(role: Role.user, content: '帮我筛选值得观察的股票并加入观察池'),
            _tool('quote', {
              'action': 'query_quote',
              'data': [
                {'code': '300059', 'name': '东方财富', 'price': 20.1},
                {'code': '600519', 'name': '贵州茅台', 'price': 1500},
                {'code': '000858', 'name': '五粮液', 'price': 120},
              ],
            }),
            _tool('hot', {
              'action': 'query_hot_rank',
              'data': [
                {'code': '300059', 'rank': 2},
                {'code': '600519', 'rank': 8},
                {'code': '000858', 'rank': 12},
              ],
            }),
          ],
          toolByName: (name) => name == 'Watchlist' ? _FakeTool(name) : null,
          callTool: (tool, toolUseId, input) async {
            calls.add(input);
            return ToolResult(toolUseId: toolUseId, content: '{}');
          },
        );

    expect(answer, isNull);
    expect(calls, isEmpty);
  });
}

String _stockWatchStateContent() {
  return 'structured stock watch request\n'
      'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"stock_research","assetClass":"stock","intentMode":"observe","executionMode":"preview_only","safetyBoundary":"watchlist observation only","evidenceRefs":["watchlist.add","stock-watchlist-candidates"],"confirmationState":"none","source":"agent-structured-intent"}}';
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

class _FakeTool extends Tool {
  @override
  final String name;

  _FakeTool(this.name);

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
