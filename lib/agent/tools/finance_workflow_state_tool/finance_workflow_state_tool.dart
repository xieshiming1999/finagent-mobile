import 'dart:convert';
import 'dart:io';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

const _workflowKinds = [
  'market_analysis',
  'stock_research',
  'stock_selection',
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
        'enum': [
          'help',
          'create',
          'validate',
          'save',
          'list',
          'get',
          'current',
        ],
        'description':
            'help, create/validate a finance-workflow-state-v1 object, or save/list/get/current durable workflow state',
      },
      'id': {'type': 'string'},
      'status': {
        'type': 'string',
        'enum': ['active', 'blocked', 'complete', 'cancelled'],
      },
      'blocker': {'type': 'string'},
      'pendingUserQuestion': {'type': 'object'},
      'pendingApproval': {'type': 'object'},
      'generatedArtifacts': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'completedSteps': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'requiredEvidence': {
        'type': 'array',
        'items': {'type': 'string'},
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
      'requiredArtifacts': {
        'type': 'array',
        'items': {'type': 'object'},
        'description':
            'Structured output artifact requirements, for example kindAnyOf/report/dashboard and fields that must be included.',
      },
      'requiredVerifier': {
        'type': 'object',
        'description':
            'Structured verifier requirement, for example {"tool":"WorkflowVerifier","action":"check","workflow":"macro_factor_lookup"}.',
      },
      'workflowState': {
        'type': 'object',
        'description':
            'Existing finance-workflow-state-v1 object for validation',
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
    if (action == 'list') {
      return ToolResult(
        toolUseId: toolUseId,
        content: jsonEncode(_list(context, input)),
      );
    }
    if (action == 'get' || action == 'current') {
      return _get(toolUseId, context, input, current: action == 'current');
    }
    if (action != 'create' && action != 'validate' && action != 'save') {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid FinanceWorkflowState action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }
    final rawState = input['workflowState'] is Map
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
    if (action == 'save') {
      return _save(toolUseId, context, input, out);
    }
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
    'actions': ['create', 'validate', 'save', 'list', 'get', 'current'],
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
        'The agent must choose these typed fields explicitly. Save active workflow state when later turns, recovery, verification, or UI evidence need it. Do not infer workflow behavior by matching user prompt text in runtime code.',
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
      if (_objectList(input['requiredArtifacts']).isNotEmpty)
        'requiredArtifacts': _objectList(input['requiredArtifacts']),
      if (_mapOrNull(input['requiredVerifier']) != null)
        'requiredVerifier': _mapOrNull(input['requiredVerifier']),
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

  List<Map<String, dynamic>> _objectList(Object? value) {
    if (value is! List) return [];
    return [
      for (final item in value)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  ToolResult _save(
    String toolUseId,
    ToolContext context,
    Map<String, dynamic> input,
    Map<String, dynamic> state,
  ) {
    final store = _readStore(context);
    final now = DateTime.now().toIso8601String();
    final id = _optionalString(input['id']) ?? _stateId(state, now);
    final record = {
      'id': id,
      'contract': 'workflow-state-record-v1',
      'status': _status(input['status']),
      'workflowState': state,
      'requiredEvidence': _stringList(input['requiredEvidence']),
      'completedSteps': _stringList(input['completedSteps']),
      'generatedArtifacts': _stringList(input['generatedArtifacts']),
      if (_mapOrNull(input['pendingUserQuestion']) != null)
        'pendingUserQuestion': _mapOrNull(input['pendingUserQuestion']),
      if (_mapOrNull(input['pendingApproval']) != null)
        'pendingApproval': _mapOrNull(input['pendingApproval']),
      if (_optionalString(input['blocker']) != null)
        'blocker': _optionalString(input['blocker']),
      'updatedAt': now,
    };
    final records = _records(store)
      ..removeWhere((item) => item['id'] == id)
      ..insert(0, record);
    _writeStore(context, {
      'contract': 'workflow-state-store-v1',
      'records': records,
    });
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'contract': 'workflow-state-record-v1',
        'record': record,
        'usage':
            'Use FinanceWorkflowState(action:"current") or action:"get" to resume typed workflow state in later turns.',
      }),
    );
  }

  Map<String, dynamic> _list(ToolContext context, Map<String, dynamic> input) {
    final limit = _intValue(input['limit'], defaultValue: 20).clamp(1, 100);
    final kind = _optionalString(input['workflowKind']);
    final records = _records(_readStore(context))
        .where((record) {
          if (kind == null) return true;
          final state = record['workflowState'];
          return state is Map && state['workflowKind'] == kind;
        })
        .take(limit)
        .toList();
    return {
      'contract': 'workflow-state-list-v1',
      'count': records.length,
      'workflowKind': kind,
      'records': records,
    };
  }

  ToolResult _get(
    String toolUseId,
    ToolContext context,
    Map<String, dynamic> input, {
    required bool current,
  }) {
    final records = _records(_readStore(context));
    final id = _optionalString(input['id']);
    final record = current
        ? records.cast<Map<String, dynamic>?>().firstWhere(
            (item) => item?['status'] == 'active',
            orElse: () => records.isEmpty ? null : records.first,
          )
        : records.cast<Map<String, dynamic>?>().firstWhere(
            (item) => item?['id'] == id,
            orElse: () => null,
          );
    if (record == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: current
            ? 'No saved workflow state. Use FinanceWorkflowState(action:"save") after creating typed state.'
            : 'FinanceWorkflowState(action:"get") requires an existing id. Use action="list" first.',
        isError: true,
      );
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'contract': 'workflow-state-record-v1',
        'record': record,
      }),
    );
  }

  Map<String, dynamic> _readStore(ToolContext context) {
    final file = _storeFile(context);
    if (!file.existsSync())
      return {'contract': 'workflow-state-store-v1', 'records': []};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic>
          ? decoded
          : {'contract': 'workflow-state-store-v1', 'records': []};
    } catch (_) {
      return {'contract': 'workflow-state-store-v1', 'records': []};
    }
  }

  void _writeStore(ToolContext context, Map<String, dynamic> store) {
    final file = _storeFile(context);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(store));
  }

  File _storeFile(ToolContext context) =>
      File('${context.memoryDir}/workflows/state.json');

  List<Map<String, dynamic>> _records(Map<String, dynamic> store) {
    final records = store['records'];
    if (records is! List) return [];
    return records
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _stateId(Map<String, dynamic> state, String now) {
    final subject =
        _optionalString(state['subject']) ??
        _stringList(state['subjects']).join('-');
    final suffix = now.replaceAll(RegExp(r'[^0-9]'), '');
    return [
      'workflow',
      state['workflowKind'],
      state['intentMode'],
      if (subject.isNotEmpty) subject,
      suffix,
    ].where((part) => '$part'.trim().isNotEmpty).join('-');
  }

  String _status(Object? value) {
    final text = '${value ?? 'active'}'.trim();
    const allowed = {'active', 'blocked', 'complete', 'cancelled'};
    return allowed.contains(text) ? text : 'active';
  }

  int _intValue(Object? value, {required int defaultValue}) {
    if (value is int) return value;
    return int.tryParse('${value ?? ''}') ?? defaultValue;
  }

  Map<String, dynamic>? _mapOrNull(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}
