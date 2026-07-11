import 'dart:convert';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

const _workflowKinds = [
  'market_analysis',
  'stock_research',
  'fund_research',
  'strategy_design',
  'strategy_review',
  'trade_prep',
  'monitor_review',
  'evidence_review',
  'unknown',
];
const _assetClasses = ['stock', 'fund', 'portfolio', 'mixed', 'unknown'];
const _intentModes = [
  'analysis',
  'validate',
  'backtest',
  'save',
  'rerun',
  'observe',
  'size',
  'confirm',
  'review',
  'unknown',
];
const _executionModes = [
  'none',
  'preview_only',
  'requires_confirmation',
  'paper_allowed_after_confirmation',
  'blocked',
  'unknown',
];
const _confirmationStates = [
  'none',
  'pending',
  'answered',
  'denied',
  'accepted',
  'unknown',
];

class FinanceWorkflowStateTool extends Tool {
  @override
  String get name => 'FinanceWorkflowState';

  @override
  String get description =>
      'Create or validate typed finance workflow state. Use this instead of relying on prompt-text parsing.';

  @override
  String get prompt =>
      'Use FinanceWorkflowState when a finance workflow needs explicit intent/state. '
      'Call action="help" for allowed enum values; call action="create" with typed fields before using workflow summaries, trade preflight, or strategy workflow state.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'create', 'validate'],
        'description':
            'help, create a finance-workflow-state-v1 object, or validate an existing state',
      },
      'workflowKind': {'type': 'string', 'enum': _workflowKinds},
      'assetClass': {'type': 'string', 'enum': _assetClasses},
      'intentMode': {'type': 'string', 'enum': _intentModes},
      'executionMode': {'type': 'string', 'enum': _executionModes},
      'confirmationState': {'type': 'string', 'enum': _confirmationStates},
      'safetyBoundary': {'type': 'string'},
      'evidenceRefs': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'subject': {'type': 'string'},
      'subjects': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'source': {'type': 'string'},
      'hasUnsupportedExecutableParts': {'type': 'boolean'},
      'blockedTools': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'workflowState': {
        'type': 'object',
        'description': 'Existing finance-workflow-state-v1 object for validation',
      },
    },
  };

  @override
  bool get isReadOnly => true;

  @override
  bool get canParallel => true;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = '${input['action'] ?? 'help'}';
    if (action == 'help') {
      return ToolResult(toolUseId: toolUseId, content: jsonEncode(_help()));
    }
    if (action != 'create' && action != 'validate') {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid FinanceWorkflowState action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }
    final rawState = action == 'validate'
        ? input['workflowState']
        : input;
    final state = _normalizeState(rawState);
    final errors = _validateState(state);
    if (errors.isNotEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid finance workflow state: ${errors.join('; ')}. Use FinanceWorkflowState(action:"help") for allowed enum values.',
        isError: true,
      );
    }
    final out = {
      ...state,
      'updatedAt': state['updatedAt'] ?? DateTime.now().toIso8601String(),
    };
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'contract': 'finance-workflow-state-result-v1',
        'action': action,
        'workflowState': out,
        'usage':
            'Pass this workflowState as a structured tool parameter or embed it as data.workflowState only when a workflow entry point requires user-message state.',
      }),
    );
  }

  Map<String, dynamic> _help() => {
    'contract': 'finance-workflow-state-help-v1',
    'actions': ['create', 'validate'],
    'enums': {
      'workflowKind': _workflowKinds,
      'assetClass': _assetClasses,
      'intentMode': _intentModes,
      'executionMode': _executionModes,
      'confirmationState': _confirmationStates,
    },
    'requiredForCreate': [
      'workflowKind',
      'assetClass',
      'intentMode',
      'executionMode',
      'confirmationState',
      'safetyBoundary',
      'evidenceRefs',
    ],
    'guidance':
        'The agent must choose these typed fields explicitly. Do not infer workflow behavior by matching user prompt text in runtime code.',
  };

  Map<String, dynamic> _normalizeState(Object? raw) {
    if (raw is! Map) return {};
    final input = Map<String, dynamic>.from(raw);
    return {
      'contract': 'finance-workflow-state-v1',
      'workflowKind': _normalizeEnum(input['workflowKind']),
      'assetClass': _normalizeEnum(input['assetClass']),
      'intentMode': _normalizeEnum(input['intentMode']),
      'executionMode': _normalizeEnum(input['executionMode']),
      'safetyBoundary': '${input['safetyBoundary'] ?? ''}'.trim(),
      'evidenceRefs': _stringList(input['evidenceRefs']),
      'confirmationState': _normalizeEnum(input['confirmationState']),
      if (_optionalString(input['subject']) != null)
        'subject': _optionalString(input['subject']),
      'subjects': _stringList(input['subjects']),
      'source': _optionalString(input['source']) ?? 'agent-structured-intent',
      if (_optionalString(input['updatedAt']) != null)
        'updatedAt': _optionalString(input['updatedAt']),
      'hasUnsupportedExecutableParts':
          input['hasUnsupportedExecutableParts'] == true,
      'blockedTools': _stringList(input['blockedTools']),
    };
  }

  List<String> _validateState(Map<String, dynamic> state) {
    final errors = <String>[];
    if (state['contract'] != 'finance-workflow-state-v1') {
      errors.add('contract must be finance-workflow-state-v1');
    }
    _requireEnum(errors, state, 'workflowKind', _workflowKinds);
    _requireEnum(errors, state, 'assetClass', _assetClasses);
    _requireEnum(errors, state, 'intentMode', _intentModes);
    _requireEnum(errors, state, 'executionMode', _executionModes);
    _requireEnum(errors, state, 'confirmationState', _confirmationStates);
    if ('${state['safetyBoundary'] ?? ''}'.trim().isEmpty) {
      errors.add('safetyBoundary is required');
    }
    final refs = state['evidenceRefs'];
    if (refs is! List || refs.isEmpty) {
      errors.add('evidenceRefs must contain at least one evidence key');
    }
    return errors;
  }

  void _requireEnum(
    List<String> errors,
    Map<String, dynamic> state,
    String key,
    List<String> allowed,
  ) {
    if (!allowed.contains(state[key])) {
      errors.add('$key must be one of ${allowed.join(', ')}');
    }
  }

  String _normalizeEnum(Object? value) {
    return '${value ?? ''}'
        .trim()
        .replaceAllMapped(
          RegExp(r'[A-Z]'),
          (match) => '_${match.group(0)!.toLowerCase()}',
        )
        .replaceFirst(RegExp(r'^_'), '');
  }

  String? _optionalString(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return [];
    return {
      for (final item in value)
        if ('$item'.trim().isNotEmpty) '$item'.trim(),
    }.toList();
  }
}
