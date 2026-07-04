import '../../../agent/message.dart';
import 'finance_workflow_state.dart';

/// Finance-owned custom strategy safety policy.
///
/// This keeps unsupported executable-source vocabulary out of the generic
/// agent loop while preserving the existing guard behavior.
class FinanceCustomStrategyPolicy {
  final bool Function(String toolName) isBypassTool;

  const FinanceCustomStrategyPolicy({required this.isBypassTool});

  String get validateOnlySkipReason =>
      'Skipped: the current user request asked to validate the custom strategy first and not save/backtest in this turn. '
      'A successful custom_strategy_validate result already exists, so no provider request, script execution, backtest, or save was made.';

  String get backtestSkipReason =>
      'Skipped: custom_strategy_backtest already returned executable backtest evidence for this turn. '
      'No extra DataProcess, provider request, script, file inspection, save, or run action was made.';

  String get rejectedValidationSkipReason =>
      'Skipped: custom_strategy_validate rejected unsupported executable strategy parts. '
      'No proxy strategy, backtest, save, provider request, script, file inspection, monitor, or trade action was made.';

  String get unsupportedProxySkipReason =>
      'Skipped: the current user request asked about unsupported custom strategy sources. '
      'No proxy StrategySpec, backtest, save, provider request, script, monitor, or trade action was made without explicit user approval.';

  String get saveSkipReason =>
      'Skipped: custom_strategy_save already persisted the validated/backtested strategy for this turn. '
      'No extra DataProcess, provider request, script, file inspection, run, monitor, or trade action was made.';

  bool shouldStopAfterValidateOnly({
    required FinanceWorkflowState? state,
    required List<ToolUse> toolCalls,
  }) {
    final structuredValidateOnly =
        state?.isStrategy == true &&
        state?.intentMode == FinanceIntentMode.validate &&
        state?.safetyBoundary == 'validate only';
    final bypassDrift =
        !structuredValidateOnly &&
        toolCalls.any(
          (toolCall) =>
              isBypassTool(toolCall.name) ||
              toolCall.name == 'DataProcess' ||
              toolCall.name == 'Script',
        );
    return (structuredValidateOnly || bypassDrift) &&
        toolCalls.any(_isValidateOnlyOverrunToolCall);
  }

  bool shouldStopAfterBacktest({
    required FinanceWorkflowState? state,
    required List<ToolUse> toolCalls,
  }) {
    return state?.isStrategy == true &&
        state?.intentMode == FinanceIntentMode.backtest &&
        toolCalls.any(_isBacktestOverrunToolCall);
  }

  bool shouldStopAfterRejectedValidation(List<ToolUse> toolCalls) {
    return toolCalls.any(_isRejectedOverrunToolCall);
  }

  bool shouldStopAfterSave({
    required FinanceWorkflowState? state,
    required List<ToolUse> toolCalls,
  }) {
    if (toolCalls.any(_isCustomStrategySaveToolCall)) return true;
    if (toolCalls.any(_isCustomStrategyRunToolCall)) return false;
    final saveMode =
        state == null ||
        (state.isStrategy == true &&
            state.intentMode == FinanceIntentMode.save);
    return saveMode && toolCalls.any(_isSaveOverrunToolCall);
  }

  bool shouldStopAfterSaveRunBoundary(List<ToolUse> toolCalls) {
    return toolCalls.any(_isSaveRunBoundaryOverrunToolCall);
  }

  String? unsupportedProxyStopAnswer({
    required FinanceWorkflowState? state,
    required List<ToolUse> toolCalls,
  }) {
    if (state?.isStrategy != true ||
        state?.hasUnsupportedExecutableParts != true) {
      return null;
    }
    if (!toolCalls.any(isUnsupportedProxyToolCall)) return null;
    return [
      '该策略没有进入可执行回测，并已停止代理策略、脚本、文件或额外行情工具调用。',
      '',
      '- 当前结构化工作流状态显示 StrategySpec 含有不支持的可执行部分。',
      '- 本轮未调用 `custom_strategy_backtest`，未调用 `custom_strategy_save`，也未创建代理规则。',
      '- 如果需要代理版策略，必须作为新的用户请求明确设计；代理版结果不能冒充原始策略回测。',
    ].join('\n');
  }

  bool isUnsupportedProxyToolCall(ToolUse toolCall) {
    if (isBypassTool(toolCall.name)) return true;
    if (toolCall.name == 'DataProcess') return true;
    if (toolCall.name != 'MarketData') return false;
    final action = toolCall.input['action']?.toString() ?? '';
    if (action == 'custom_strategy_help') return false;
    if (action == 'custom_strategy_validate') {
      return FinanceWorkflowState.fromToolCall(
            toolCall,
          )?.hasUnsupportedExecutableParts !=
          true;
    }
    return action == 'custom_strategy_backtest' ||
        action == 'custom_strategy_save' ||
        action == 'custom_strategy_run' ||
        action.startsWith('query_') ||
        action == 'kline' ||
        action == 'quote' ||
        action == 'price' ||
        action == 'technical_indicator';
  }

  bool _isValidateOnlyOverrunToolCall(ToolUse toolCall) {
    if (isBypassTool(toolCall.name)) return true;
    if (toolCall.name == 'DataProcess') return true;
    if (toolCall.name != 'MarketData') return false;
    final action = toolCall.input['action']?.toString() ?? '';
    if (action.isEmpty) return true;
    if (action == 'custom_strategy_validate') return false;
    if (action == 'custom_strategy_help') return false;
    return action == 'custom_strategy_backtest' ||
        action == 'custom_strategy_save' ||
        action == 'custom_strategy_run' ||
        action.startsWith('query_') ||
        action == 'kline' ||
        action == 'quote' ||
        action == 'price' ||
        action == 'technical_indicator';
  }

  bool _isRejectedOverrunToolCall(ToolUse toolCall) {
    if (isBypassTool(toolCall.name)) return true;
    if (toolCall.name == 'DataProcess') return true;
    if (toolCall.name != 'MarketData') return false;
    final action = toolCall.input['action']?.toString() ?? '';
    return action == 'custom_strategy_backtest' ||
        action == 'custom_strategy_save' ||
        action == 'custom_strategy_run' ||
        action.startsWith('query_') ||
        action == 'kline' ||
        action == 'quote' ||
        action == 'price' ||
        action == 'technical_indicator';
  }

  bool _isBacktestOverrunToolCall(ToolUse toolCall) {
    if (isBypassTool(toolCall.name)) return true;
    if (toolCall.name == 'DataProcess') return true;
    if (toolCall.name != 'MarketData') return false;
    final action = toolCall.input['action']?.toString() ?? '';
    if (action == 'custom_strategy_validate' ||
        action == 'custom_strategy_backtest' ||
        action == 'custom_strategy_help') {
      return false;
    }
    return action.startsWith('query_') ||
        action == 'kline' ||
        action == 'quote' ||
        action == 'price' ||
        action == 'technical_indicator' ||
        action == 'backtest' ||
        action == 'backtest_batch' ||
        action == 'optimize_params';
  }

  bool _isSaveOverrunToolCall(ToolUse toolCall) {
    if (isBypassTool(toolCall.name)) return true;
    if (toolCall.name == 'DataProcess') return true;
    if (toolCall.name != 'MarketData') return false;
    final action = toolCall.input['action']?.toString() ?? '';
    if (action == 'custom_strategy_validate' ||
        action == 'custom_strategy_backtest' ||
        action == 'custom_strategy_save' ||
        action == 'custom_strategy_help' ||
        action == 'custom_strategy_list') {
      return false;
    }
    return action.startsWith('query_') ||
        action == 'kline' ||
        action == 'quote' ||
        action == 'price' ||
        action == 'technical_indicator' ||
        action == 'custom_strategy_run';
  }

  bool _isCustomStrategyRunToolCall(ToolUse toolCall) {
    return toolCall.name == 'MarketData' &&
        toolCall.input['action'] == 'custom_strategy_run';
  }

  bool _isCustomStrategySaveToolCall(ToolUse toolCall) {
    return toolCall.name == 'MarketData' &&
        toolCall.input['action'] == 'custom_strategy_save';
  }

  bool _isSaveRunBoundaryOverrunToolCall(ToolUse toolCall) {
    if (isBypassTool(toolCall.name)) return true;
    if (toolCall.name == 'DataProcess') return true;
    if (toolCall.name != 'MarketData') return false;
    final action = toolCall.input['action']?.toString() ?? '';
    return action.startsWith('query_') ||
        action == 'kline' ||
        action == 'quote' ||
        action == 'price' ||
        action == 'technical_indicator' ||
        action == 'backtest' ||
        action == 'backtest_batch' ||
        action == 'optimize_params';
  }
}
