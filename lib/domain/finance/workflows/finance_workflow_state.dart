import 'dart:convert';

import '../../../agent/message.dart';

enum FinanceWorkflowKind {
  marketAnalysis,
  stockResearch,
  fundResearch,
  macroFactorLookup,
  strategyDesign,
  strategyReview,
  tradePrep,
  monitorReview,
  evidenceReview,
  unknown,
}

enum FinanceAssetClass { stock, fund, portfolio, mixed, unknown }

enum FinanceIntentMode {
  analysis,
  validate,
  backtest,
  save,
  rerun,
  observe,
  size,
  confirm,
  review,
  unknown,
}

enum FinanceExecutionMode {
  none,
  previewOnly,
  requiresConfirmation,
  paperAllowedAfterConfirmation,
  blocked,
  unknown,
}

enum FinanceConfirmationState {
  none,
  pending,
  answered,
  denied,
  accepted,
  unknown,
}

class FinanceWorkflowState {
  final FinanceWorkflowKind workflowKind;
  final FinanceAssetClass assetClass;
  final FinanceIntentMode intentMode;
  final FinanceExecutionMode executionMode;
  final String safetyBoundary;
  final List<String> evidenceRefs;
  final FinanceConfirmationState confirmationState;
  final String? subject;
  final List<String> subjects;
  final DateTime? updatedAt;
  final String source;
  final bool hasUnsupportedExecutableParts;
  final List<String> blockedTools;

  const FinanceWorkflowState({
    required this.workflowKind,
    required this.assetClass,
    required this.intentMode,
    required this.executionMode,
    required this.safetyBoundary,
    required this.evidenceRefs,
    required this.confirmationState,
    required this.source,
    this.subject,
    this.subjects = const [],
    this.updatedAt,
    this.hasUnsupportedExecutableParts = false,
    this.blockedTools = const [],
  });

  bool get isStrategy =>
      workflowKind == FinanceWorkflowKind.strategyDesign ||
      workflowKind == FinanceWorkflowKind.strategyReview;

  bool get isTradePrep => workflowKind == FinanceWorkflowKind.tradePrep;

  bool get isEvidenceReview =>
      workflowKind == FinanceWorkflowKind.evidenceReview &&
      intentMode == FinanceIntentMode.review;

  Map<String, dynamic> toJson() => {
    'contract': 'finance-workflow-state-v1',
    'workflowKind': workflowKind.name,
    'assetClass': assetClass.name,
    'intentMode': intentMode.name,
    'executionMode': executionMode.name,
    'safetyBoundary': safetyBoundary,
    'evidenceRefs': evidenceRefs,
    'confirmationState': confirmationState.name,
    if (subject != null) 'subject': subject,
    if (subjects.isNotEmpty) 'subjects': subjects,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    'source': source,
    'hasUnsupportedExecutableParts': hasUnsupportedExecutableParts,
    if (blockedTools.isNotEmpty) 'blockedTools': blockedTools,
  };

  factory FinanceWorkflowState.fromJson(Map<String, dynamic> json) {
    return FinanceWorkflowState(
      workflowKind: _enumByName(
        FinanceWorkflowKind.values,
        '${json['workflowKind'] ?? ''}',
        FinanceWorkflowKind.unknown,
      ),
      assetClass: _enumByName(
        FinanceAssetClass.values,
        '${json['assetClass'] ?? ''}',
        FinanceAssetClass.unknown,
      ),
      intentMode: _enumByName(
        FinanceIntentMode.values,
        '${json['intentMode'] ?? ''}',
        FinanceIntentMode.unknown,
      ),
      executionMode: _enumByName(
        FinanceExecutionMode.values,
        '${json['executionMode'] ?? ''}',
        FinanceExecutionMode.unknown,
      ),
      safetyBoundary: '${json['safetyBoundary'] ?? ''}',
      evidenceRefs: [
        for (final value
            in json['evidenceRefs'] is List
                ? json['evidenceRefs'] as List
                : const [])
          '$value',
      ],
      confirmationState: _enumByName(
        FinanceConfirmationState.values,
        '${json['confirmationState'] ?? ''}',
        FinanceConfirmationState.unknown,
      ),
      subject: json['subject'] == null ? null : '${json['subject']}',
      subjects: [
        for (final value
            in json['subjects'] is List ? json['subjects'] as List : const [])
          '$value',
      ],
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
      source: '${json['source'] ?? 'unknown'}',
      hasUnsupportedExecutableParts:
          json['hasUnsupportedExecutableParts'] == true,
      blockedTools: [
        for (final value
            in json['blockedTools'] is List
                ? json['blockedTools'] as List
                : const [])
          '$value',
      ],
    );
  }

  static FinanceWorkflowState? latestFromMessages(
    List<Message> messages, {
    int turnStartIndex = 0,
  }) {
    return _latestWhere(messages, turnStartIndex: turnStartIndex);
  }

  static FinanceWorkflowState? latestTradePrepFromMessages(
    List<Message> messages, {
    int turnStartIndex = 0,
  }) {
    return _latestWhere(
      messages,
      turnStartIndex: turnStartIndex,
      predicate: (state) => state.workflowKind == FinanceWorkflowKind.tradePrep,
    );
  }

  static FinanceWorkflowState? _latestWhere(
    List<Message> messages, {
    int turnStartIndex = 0,
    bool Function(FinanceWorkflowState state)? predicate,
  }) {
    final states = <FinanceWorkflowState>[];
    final start = turnStartIndex.clamp(0, messages.length);
    for (final message in messages.skip(start)) {
      if (message.role == Role.user) {
        final state = fromUserContent(message.content);
        if (state != null && (predicate == null || predicate(state))) {
          states.add(state);
        }
      }
      for (final call in message.toolUses ?? const <ToolUse>[]) {
        final state = fromToolCall(call);
        if (state != null && (predicate == null || predicate(state))) {
          states.add(state);
        }
      }
      final result = message.toolResult;
      if (result != null && !result.isError) {
        final state = fromToolResult(result);
        if (state != null && (predicate == null || predicate(state))) {
          states.add(state);
        }
      }
    }
    return states.isEmpty ? null : states.last;
  }

  static FinanceWorkflowState? fromUserContent(String content) {
    final explicit = _stateFromUnknown(_jsonObject(content)?['workflowState']);
    if (explicit != null) return explicit;
    final marker = content.lastIndexOf('data:');
    if (marker < 0) return null;
    final payload = _jsonObject(content.substring(marker + 'data:'.length));
    if (payload == null) return null;
    final embedded = _stateFromUnknown(payload['workflowState']);
    if (embedded != null) return embedded;
    if (payload['template'] == 'strategy_signal') {
      return FinanceWorkflowState(
        workflowKind: FinanceWorkflowKind.tradePrep,
        assetClass: FinanceAssetClass.stock,
        intentMode: FinanceIntentMode.size,
        executionMode: payload['confirmationRequired'] == true
            ? FinanceExecutionMode.requiresConfirmation
            : FinanceExecutionMode.previewOnly,
        safetyBoundary: payload['confirmationRequired'] == true
            ? 'confirmation required before execution'
            : 'strategy signal sizing evidence',
        evidenceRefs: ['strategy_signal'],
        confirmationState: payload['confirmationRequired'] == true
            ? FinanceConfirmationState.pending
            : FinanceConfirmationState.none,
        subject: _subjectFromPayload(payload),
        updatedAt: DateTime.now(),
        source: 'user-data:strategy_signal',
      );
    }
    return null;
  }

  static FinanceWorkflowState? fromToolCall(ToolUse call) {
    final explicit = _stateFromUnknown(call.input['workflowState']);
    if (explicit != null) return explicit;
    if (call.name != 'MarketData' && call.name != 'Portfolio') return null;
    final action = '${call.input['action'] ?? ''}';
    switch (action) {
      case 'custom_strategy_validate':
        return _strategyCallState(
          call,
          intentMode: FinanceIntentMode.validate,
          executionMode: FinanceExecutionMode.previewOnly,
          safetyBoundary: 'read-only validation',
        );
      case 'custom_strategy_backtest':
      case 'custom_strategy_fund_backtest':
      case 'custom_strategy_rank':
        return _strategyCallState(
          call,
          intentMode: FinanceIntentMode.backtest,
          executionMode: FinanceExecutionMode.previewOnly,
          safetyBoundary: 'read-only backtest evidence',
        );
      case 'custom_strategy_save':
        return _strategyCallState(
          call,
          intentMode: FinanceIntentMode.save,
          executionMode: FinanceExecutionMode.previewOnly,
          safetyBoundary: 'save strategy artifact only',
        );
      case 'custom_strategy_run':
        return _strategyCallState(
          call,
          intentMode: FinanceIntentMode.rerun,
          executionMode: FinanceExecutionMode.previewOnly,
          safetyBoundary: 'reuse saved strategy artifact',
        );
      case 'custom_strategy_observe':
        return _strategyCallState(
          call,
          intentMode: FinanceIntentMode.observe,
          executionMode: FinanceExecutionMode.previewOnly,
          safetyBoundary: 'observation evidence only',
        );
      default:
        return null;
    }
  }

  static FinanceWorkflowState? fromToolResult(ToolResult result) {
    final decoded = _jsonObject(result.content);
    if (decoded == null) return null;
    final explicit = _stateFromUnknown(decoded['workflowState']);
    if (explicit != null) return explicit;
    if (decoded['contract'] == 'trade-prep-v1') {
      return FinanceWorkflowState(
        workflowKind: FinanceWorkflowKind.tradePrep,
        assetClass: FinanceAssetClass.stock,
        intentMode: FinanceIntentMode.size,
        executionMode: FinanceExecutionMode.requiresConfirmation,
        safetyBoundary: 'trade preparation only',
        evidenceRefs: ['trade-prep-v1'],
        confirmationState: FinanceConfirmationState.pending,
        subject: '${decoded['symbol'] ?? decoded['code'] ?? ''}'.isEmpty
            ? null
            : '${decoded['symbol'] ?? decoded['code']}',
        updatedAt: DateTime.now(),
        source: 'tool-result:trade-prep-v1',
      );
    }
    final action = '${decoded['action'] ?? ''}';
    if (!action.startsWith('custom_strategy_')) return null;
    if (action == 'custom_strategy_help' || action == 'custom_strategy_list') {
      return null;
    }
    final status = '${decoded['status'] ?? ''}';
    final unsupported = _hasUnsupportedParts(decoded);
    final intent = switch (action) {
      'custom_strategy_validate' => FinanceIntentMode.validate,
      'custom_strategy_backtest' ||
      'custom_strategy_fund_backtest' ||
      'custom_strategy_rank' => FinanceIntentMode.backtest,
      'custom_strategy_save' => FinanceIntentMode.save,
      'custom_strategy_run' => FinanceIntentMode.rerun,
      'custom_strategy_observe' => FinanceIntentMode.observe,
      _ => FinanceIntentMode.unknown,
    };
    return FinanceWorkflowState(
      workflowKind: FinanceWorkflowKind.strategyReview,
      assetClass: _assetClassFromSpec(
        decoded['spec'] ?? decoded['normalizedSpec'],
      ),
      intentMode: intent,
      executionMode: status == 'rejected'
          ? FinanceExecutionMode.blocked
          : FinanceExecutionMode.previewOnly,
      safetyBoundary: status == 'rejected'
          ? 'unsupported strategy parts'
          : 'strategy evidence only',
      evidenceRefs: [action],
      confirmationState: FinanceConfirmationState.none,
      subject: _subjectFromPayload(decoded),
      updatedAt: DateTime.now(),
      source: 'tool-result:$action',
      hasUnsupportedExecutableParts: unsupported,
    );
  }

  static FinanceWorkflowState _strategyCallState(
    ToolUse call, {
    required FinanceIntentMode intentMode,
    required FinanceExecutionMode executionMode,
    required String safetyBoundary,
  }) {
    final spec = call.input['strategySpec'];
    return FinanceWorkflowState(
      workflowKind: FinanceWorkflowKind.strategyDesign,
      assetClass: _assetClassFromSpec(spec),
      intentMode: intentMode,
      executionMode: executionMode,
      safetyBoundary: safetyBoundary,
      evidenceRefs: ['${call.input['action']}'],
      confirmationState: FinanceConfirmationState.none,
      subject: _subjectFromPayload(call.input),
      updatedAt: DateTime.now(),
      source: 'tool-call:${call.name}.${call.input['action']}',
    );
  }

  static FinanceWorkflowState? _stateFromUnknown(Object? value) {
    if (value is Map) {
      return FinanceWorkflowState.fromJson(Map<String, dynamic>.from(value));
    }
    if (value is String && value.trim().startsWith('{')) {
      final decoded = _jsonObject(value);
      if (decoded != null) return FinanceWorkflowState.fromJson(decoded);
    }
    return null;
  }

  static Map<String, dynamic>? _jsonObject(String content) {
    final text = content.trim();
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      final prefix = _balancedJsonObjectPrefix(text);
      if (prefix == null) return null;
      try {
        final decoded = jsonDecode(prefix);
        return decoded is Map<String, dynamic> ? decoded : null;
      } catch (_) {
        return null;
      }
    }
  }

  static String? _balancedJsonObjectPrefix(String text) {
    if (!text.startsWith('{')) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5c) {
          escaped = true;
        } else if (code == 0x22) {
          inString = false;
        }
        continue;
      }
      if (code == 0x22) {
        inString = true;
      } else if (code == 0x7b) {
        depth++;
      } else if (code == 0x7d) {
        depth--;
        if (depth == 0) return text.substring(0, i + 1);
      }
    }
    return null;
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String name,
    T fallback,
  ) {
    final normalized = _normalizeEnumName(name);
    for (final value in values) {
      if (_normalizeEnumName(value.name) == normalized) return value;
    }
    return fallback;
  }

  static String _normalizeEnumName(String value) =>
      value.replaceAll('_', '').replaceAll('-', '').toLowerCase();

  static FinanceAssetClass _assetClassFromSpec(Object? spec) {
    if (spec is! Map) return FinanceAssetClass.unknown;
    final assetClass = '${spec['assetClass'] ?? spec['market'] ?? ''}'
        .toLowerCase();
    if (assetClass == 'fund') return FinanceAssetClass.fund;
    if (assetClass == 'stock' || assetClass == 'a_share') {
      return FinanceAssetClass.stock;
    }
    return FinanceAssetClass.unknown;
  }

  static String? _subjectFromPayload(Map payload) {
    for (final key in const ['symbol', 'code', 'fundCode', 'strategyId']) {
      final value = '${payload[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    final symbols = payload['symbols'];
    if (symbols is List && symbols.isNotEmpty) return '${symbols.first}';
    return null;
  }

  static bool _hasUnsupportedParts(Map<String, dynamic> payload) {
    for (final key in const ['errors', 'unsupported', 'unsupportedDetails']) {
      final value = payload[key];
      if (value is List && value.isNotEmpty) return true;
      if (value is String && value.trim().isNotEmpty) return true;
    }
    return false;
  }
}
