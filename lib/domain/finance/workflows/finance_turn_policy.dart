import 'dart:convert';

import '../../../agent/domain_workflow_hooks.dart';
import '../../../agent/message.dart';

/// Finance-specific turn safety rules.
///
/// Keep these rules outside the generic agent loop so non-finance agents do not
/// inherit application-domain side-effect semantics.
class FinanceTurnPolicy implements DomainTurnPolicy {
  bool _xueqiuWriteFailed = false;
  String? _savedCustomStrategyId;

  @override
  void reset() {
    _xueqiuWriteFailed = false;
    _savedCustomStrategyId = null;
  }

  @override
  String? blockedToolUseReason(ToolUse toolUse) {
    if (_savedCustomStrategyId != null) {
      if (_isCustomStrategySave(toolUse)) {
        return _blockedReason(
          code: 'custom_strategy_save_already_succeeded',
          action: 'custom_strategy_save',
          strategyId: _savedCustomStrategyId,
          nextAction: 'custom_strategy_run',
          message:
              'custom_strategy_save already succeeded in this user turn. Do not save the same strategy again.',
        );
      }
      if (_isDifferentCustomStrategyRun(toolUse)) {
        return _blockedReason(
          code: 'custom_strategy_run_wrong_identity',
          action: 'custom_strategy_run',
          strategyId: _savedCustomStrategyId,
          nextAction: 'custom_strategy_run',
          message:
              'A saved custom strategy is already active in this user turn. custom_strategy_run.strategyId must use the saved strategy identity.',
        );
      }
      if (_isPostCustomStrategySaveDrift(toolUse)) {
        return _blockedReason(
          code: 'custom_strategy_post_save_drift',
          action: '${toolUse.input['action'] ?? toolUse.name}',
          strategyId: _savedCustomStrategyId,
          nextAction: 'custom_strategy_run',
          message:
              'custom_strategy_save already succeeded in this user turn. Do not call unrelated tools after saving.',
        );
      }
    }
    if (!_xueqiuWriteFailed) return null;
    if (_isXueqiuWriteToolUse(toolUse)) {
      return 'Blocked: an earlier Xueqiu simulated-trading write failed in this user turn. Do not retry buy/sell/transfer automatically. Inspect the Xueqiu error, report it, and wait for a new explicit user instruction after credential or endpoint state is fixed.';
    }
    if (_isLocalTradeMutationAfterExternalFailure(toolUse)) {
      return 'Blocked: an earlier Xueqiu simulated-trading write failed in this user turn. Local Portfolio or Watchlist trade-state mutation must not proceed because it would diverge from the external Xueqiu simulation. Report the failure and leave local state unchanged.';
    }
    return null;
  }

  String _blockedReason({
    required String code,
    required String action,
    required String? strategyId,
    required String nextAction,
    required String message,
  }) {
    return jsonEncode({
      'action': 'finance_turn_policy_block',
      'status': 'blocked',
      'code': code,
      'blockedAction': action,
      'strategyId': strategyId,
      'nextAction': nextAction,
      'message': message,
    });
  }

  @override
  void recordToolResult(ToolUse toolUse, ToolResult result) {
    if (!result.isError && _isCustomStrategySave(toolUse)) {
      _savedCustomStrategyId =
          _strategyIdFromSaveResult(result) ??
          _strategyIdFromSaveInput(toolUse) ??
          _savedCustomStrategyId;
    }
    if (!result.isError && _isCustomStrategyRun(toolUse)) {
      _savedCustomStrategyId ??=
          _strategyIdFromRunResult(result) ??
          _strategyIdFromRunInput(toolUse);
    }
    if (result.isError && _isXueqiuWriteToolUse(toolUse)) {
      _xueqiuWriteFailed = true;
    }
  }

  @override
  bool shouldStopToolBatchAfterResult(ToolUse toolUse, ToolResult result) {
    if (result.isError || _savedCustomStrategyId == null) return false;
    return _isCustomStrategySave(toolUse) ||
        _isCustomStrategyRunForSavedStrategy(toolUse);
  }

  bool _isXueqiuWriteToolUse(ToolUse toolUse) {
    if (toolUse.name != 'XueqiuTrade') return false;
    final action = (toolUse.input['action'] ?? '').toString().toLowerCase();
    return action == 'buy' ||
        action == 'sell' ||
        action == 'transfer_in' ||
        action == 'transfer_out';
  }

  bool _isLocalTradeMutationAfterExternalFailure(ToolUse toolUse) {
    final action = (toolUse.input['action'] ?? '').toString().toLowerCase();
    if (toolUse.name == 'Portfolio') {
      return action == 'trade' ||
          action == 'add' ||
          action == 'remove' ||
          action == 'clear';
    }
    if (toolUse.name == 'Watchlist') {
      return action == 'enter' || action == 'exit' || action == 'update';
    }
    return false;
  }

  bool _isCustomStrategySave(ToolUse toolUse) {
    if (toolUse.name != 'MarketData') return false;
    return '${toolUse.input['action'] ?? ''}' == 'custom_strategy_save';
  }

  bool _isCustomStrategyRun(ToolUse toolUse) {
    if (toolUse.name != 'MarketData') return false;
    return '${toolUse.input['action'] ?? ''}' == 'custom_strategy_run';
  }

  bool _isDifferentCustomStrategyRun(ToolUse toolUse) {
    if (toolUse.name != 'MarketData') return false;
    if ('${toolUse.input['action'] ?? ''}' != 'custom_strategy_run') {
      return false;
    }
    final strategyId = '${toolUse.input['strategyId'] ?? ''}'.trim();
    return strategyId.isNotEmpty && strategyId != _savedCustomStrategyId;
  }

  bool _isCustomStrategyRunForSavedStrategy(ToolUse toolUse) {
    if (toolUse.name != 'MarketData') return false;
    if ('${toolUse.input['action'] ?? ''}' != 'custom_strategy_run') {
      return false;
    }
    return '${toolUse.input['strategyId'] ?? ''}'.trim() ==
        _savedCustomStrategyId;
  }

  bool _isPostCustomStrategySaveDrift(ToolUse toolUse) {
    if (toolUse.name == 'MarketData') {
      final action = '${toolUse.input['action'] ?? ''}';
      return action != 'custom_strategy_run' &&
          action != 'custom_strategy_list' &&
          action != 'custom_strategy_help';
    }
    return toolUse.name == 'DataProcess' ||
        toolUse.name == 'Bash' ||
        toolUse.name == 'Read' ||
        toolUse.name == 'Grep' ||
        toolUse.name == 'Glob' ||
        toolUse.name == 'Portfolio' ||
        toolUse.name == 'Watchlist' ||
        toolUse.name == 'XueqiuTrade';
  }

  String? _strategyIdFromSaveResult(ToolResult result) {
    try {
      final decoded = jsonDecode(result.content);
      if (decoded is! Map) return null;
      if (decoded['action'] != 'custom_strategy_save') return null;
      final value = decoded['strategyId']?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  String? _strategyIdFromRunResult(ToolResult result) {
    try {
      final decoded = jsonDecode(result.content);
      if (decoded is! Map) return null;
      if (decoded['action'] != 'custom_strategy_run') return null;
      final value = decoded['strategyId']?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  String? _strategyIdFromSaveInput(ToolUse toolUse) {
    final spec = toolUse.input['strategySpec'];
    if (spec is! Map) return null;
    final value = spec['id']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _strategyIdFromRunInput(ToolUse toolUse) {
    final value = toolUse.input['strategyId']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }
}
