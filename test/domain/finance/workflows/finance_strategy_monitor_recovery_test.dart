import 'package:finagent/agent/message.dart';
import 'package:finagent/agent/tool.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/domain/finance/workflows/finance_strategy_monitor_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('structured monitor state creates monitor without prompt keywords', () async {
    final recovery = FinanceStrategyMonitorRecovery();
    final calls = <Map<String, dynamic>>[];

    final answer = await recovery.build(
      prompt:
          'stateful request\n'
          'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"monitor_review","assetClass":"stock","intentMode":"observe","executionMode":"preview_only","safetyBoundary":"observation only","evidenceRefs":["watchlist"],"confirmationState":"none","subject":"300059","source":"agent-structured-intent"}}',
      messages: [
        Message(
          role: Role.user,
          content:
              'stateful request\n'
              'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"monitor_review","assetClass":"stock","intentMode":"observe","executionMode":"preview_only","safetyBoundary":"observation only","evidenceRefs":["watchlist"],"confirmationState":"none","subject":"300059","source":"agent-structured-intent"}}',
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'indicator',
            content:
                '{"symbol":"300059","name":"东方财富","price":20.5,"rsi":48.2,"ma10":20.1,"ma20":19.8,"sourceDataTime":"2026-07-03 15:00","fetchedAt":"2026-07-03T15:01:00Z"}',
          ),
        ),
      ],
      toolByName: (name) => _FakeTool(name),
      callTool: (tool, toolUseId, input) async {
        calls.add({'tool': tool.name, 'input': input});
        return ToolResult(
          toolUseId: toolUseId,
          content: '{"ok":true,"id":"created"}',
        );
      },
    );

    expect(answer, isNotNull);
    expect(answer, contains('东方财富（300059）'));
    expect(
      calls.map((call) => call['tool']),
      containsAll(['Watchlist', 'MonitorCreate', 'MonitorList']),
    );
    final monitorCreate =
        calls.firstWhere((call) => call['tool'] == 'MonitorCreate')['input']
            as Map<String, dynamic>;
    expect(monitorCreate['name'], contains('300059'));
    expect(monitorCreate['name'], isNot(contains('600519')));
  });

  test('prompt text alone does not enter monitor recovery', () async {
    final recovery = FinanceStrategyMonitorRecovery();

    final answer = await recovery.build(
      prompt: '回测结果不错，帮我设置监控并回读确认。',
      messages: [
        Message(role: Role.user, content: '回测结果不错，帮我设置监控并回读确认。'),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'indicator',
            content:
                '{"symbol":"300059","name":"东方财富","price":20.5,"rsi":48.2,"ma10":20.1,"ma20":19.8}',
          ),
        ),
      ],
      toolByName: (name) => _FakeTool(name),
      callTool: (tool, toolUseId, input) async =>
          ToolResult(toolUseId: toolUseId, content: '{"ok":true}'),
    );

    expect(answer, isNull);
  });
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
