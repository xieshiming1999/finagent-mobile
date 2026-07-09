import '../../../agent/message.dart';
import '../../../agent/domain_workflow_hooks.dart';
import 'finance_workflow_state.dart';

/// Finance-specific data budget policy.
///
/// This keeps finance tool names and finance workflow-state checks out of the
/// generic loop while preserving the current bounded-workflow behavior.
class FinanceDataBudgetPolicy extends DomainDataBudgetPolicy {
  static const _maxDataToolCallsPerTurn = 20;
  static const _maxBroadMarketDataToolCallsPerTurn = 8;

  @override
  bool wouldExceedBudget({
    required String? prompt,
    required int currentDataToolCalls,
    required int existingBudgetWarnings,
    required List<ToolUse> proposedToolCalls,
  }) {
    if (_wouldBypassFinanceDataBoundary(
      prompt: prompt,
      currentDataToolCalls: currentDataToolCalls,
      proposedToolCalls: proposedToolCalls,
    )) {
      return true;
    }
    final proposedDataCalls = proposedToolCalls
        .where((toolCall) => isDataTool(toolCall.name))
        .length;
    if (proposedDataCalls == 0) return false;
    if (existingBudgetWarnings > 0) return true;
    final workflowState = FinanceWorkflowState.fromUserContent(prompt ?? '');
    final maxCalls = _isBroadMarketState(workflowState)
        ? _maxBroadMarketDataToolCallsPerTurn
        : _maxDataToolCallsPerTurn;
    return currentDataToolCalls + proposedDataCalls > maxCalls;
  }

  bool isBypassTool(String toolName) {
    return const {
      'Bash',
      'Script',
      'Read',
      'FileRead',
      'Grep',
      'Glob',
      'LS',
      'Edit',
      'FileEdit',
      'Write',
      'FileWrite',
      'MultiEdit',
    }.contains(toolName);
  }

  @override
  bool isDataTool(String toolName) {
    return const {
      'MarketData',
      'DataProcess',
      'WindMcp',
      'Research',
      'WebFetch',
      'Bash',
      'Script',
      'Read',
      'FileRead',
      'Grep',
      'Glob',
      'LS',
      'Edit',
      'FileEdit',
      'Write',
      'FileWrite',
      'MultiEdit',
    }.contains(toolName);
  }

  bool _wouldBypassFinanceDataBoundary({
    required String? prompt,
    required int currentDataToolCalls,
    required List<ToolUse> proposedToolCalls,
  }) {
    if (!_isFinanceWorkflowState(
      FinanceWorkflowState.fromUserContent(prompt ?? ''),
    )) {
      return false;
    }
    if (currentDataToolCalls <= 0) return false;
    return proposedToolCalls.any((toolCall) => isBypassTool(toolCall.name));
  }

  bool _isBroadMarketState(FinanceWorkflowState? state) {
    return state?.workflowKind == FinanceWorkflowKind.marketAnalysis;
  }

  bool _isFinanceWorkflowState(FinanceWorkflowState? state) {
    if (state == null) return false;
    return state.workflowKind != FinanceWorkflowKind.unknown;
  }
}
