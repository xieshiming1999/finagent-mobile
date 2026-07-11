import 'dart:convert';
import 'dart:io';

import '../../interaction_evidence.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

const _evidence = <String>[
  'agent_discovery',
  'tool_calls',
  'no_tool_errors',
  'ui_artifacts',
  'no_pending_interactions',
];

class CapabilityStatusTool extends Tool {
  final List<Tool> Function() toolsProvider;

  CapabilityStatusTool({required this.toolsProvider});

  @override
  String get name => 'CapabilityStatus';

  @override
  String get description =>
      'Inspect runtime capability health and evaluate whether workflow evidence is sufficient before final claims.';

  @override
  String get prompt =>
      'Use CapabilityStatus to inspect live tool availability, pending user input, recent tool failures, and UI artifacts. '
      'Call action="summary" before broad tool use and action="evaluate" before final workflow claims.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'summary', 'evaluate'],
        'description': 'help, summary, or evaluate',
      },
      'workflow': {
        'type': 'string',
        'description':
            'Short workflow name for evaluate results, for example market_overview or stock_research',
      },
      'requiredEvidence': {
        'type': 'array',
        'items': {'type': 'string', 'enum': _evidence},
        'description':
            'Evidence classes that must be present for evaluate. Omit for the default evaluator set.',
      },
      'limit': {
        'type': 'integer',
        'description': 'Maximum recent rows to inspect, default 20',
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
    final action = (input['action'] as String?)?.trim() ?? 'summary';
    if (action == 'help') {
      return ToolResult(toolUseId: toolUseId, content: jsonEncode(_help()));
    }
    if (action != 'summary' && action != 'evaluate') {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid CapabilityStatus action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }

    final rawLimit = input['limit'];
    final limit = rawLimit is int ? rawLimit.clamp(1, 100) : 20;
    final summary = _buildSummary(context, toolsProvider(), limit);
    if (action == 'summary') {
      return ToolResult(toolUseId: toolUseId, content: jsonEncode(summary));
    }

    final requiredEvidence = _parseRequiredEvidence(input['requiredEvidence']);
    if (requiredEvidence.error != null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: requiredEvidence.error!,
        isError: true,
      );
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode(
        _evaluateWorkflow(
          summary,
          workflow: (input['workflow'] as String?)?.trim().isNotEmpty == true
              ? (input['workflow'] as String).trim()
              : 'general_workflow',
          requiredEvidence: requiredEvidence.values,
        ),
      ),
    );
  }

  Map<String, dynamic> _help() => {
    'contract': 'capability-status-help-v1',
    'actions': ['summary', 'evaluate'],
    'requiredEvidence': _evidence,
    'guidance': [
      'Call summary before broad, risky, or unfamiliar tool use.',
      'Call evaluate before final workflow claims to check tool calls, errors, pending user input, and UI artifacts.',
      'CapabilityStatus is evidence-focused and does not decide domain-specific finance logic.',
    ],
  };

  Map<String, dynamic> _buildSummary(
    ToolContext context,
    List<Tool> tools,
    int limit,
  ) {
    final capabilities = tools.map(summarizeToolCapability).toList();
    final session = _readCurrentSession(context, limit);
    final artifacts = _listArtifacts(context, limit);
    final pending = readPendingInteractionState(context);
    final broadDiscoveryTools = capabilities
        .where(
          (capability) =>
              capability.actionValues.contains('help') ||
              capability.name == 'ToolCatalog' ||
              capability.name == 'WorkflowEvidence',
        )
        .map(
          (capability) => {
            'name': capability.name,
            'actions': capability.actionValues,
          },
        )
        .toList()
      ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));

    final uiArtifactCount =
        ((artifacts['pages'] as Map)['count'] as int) +
        ((artifacts['dashboards'] as Map)['count'] as int);
    return {
      'contract': 'capability-status-summary-v1',
      'runtime': 'finagent-mobile',
      'capabilitySummary': {
        'count': capabilities.length,
        'readOnly': capabilities.where((c) => c.readOnly).length,
        'writeOrSideEffect': capabilities
            .where((c) => c.permission == 'write-or-side-effect')
            .length,
        'inputDependentPermission': capabilities
            .where((c) => c.permission == 'input-dependent')
            .length,
        'trustedRuntime': capabilities
            .where((c) => c.permission == 'trusted-runtime')
            .length,
        'userInteraction': capabilities
            .where((c) => c.requiresUserInteraction)
            .length,
        'broadDiscoveryTools': broadDiscoveryTools,
      },
      'health': {
        'pendingInteractionCount': pending.length,
        'toolErrorCount': session['toolErrorCount'],
        'toolCallCount': session['toolCallCount'],
        'uiArtifactCount': uiArtifactCount,
        'repeatedFailureCount': session['repeatedFailureCount'],
      },
      'pendingInteractions': pending,
      'session': session,
      'artifacts': artifacts,
      'guidance':
          'Use evaluate to check whether selected evidence classes are present before final workflow claims.',
    };
  }

  Map<String, dynamic> _evaluateWorkflow(
    Map<String, dynamic> summary, {
    required String workflow,
    required List<String> requiredEvidence,
  }) {
    final checks = requiredEvidence.map((evidence) {
      final passed = _evidencePassed(evidence, summary);
      return {
        'evidence': evidence,
        'passed': passed,
        'message': _evidenceMessage(evidence, passed, summary),
      };
    }).toList();
    final missing = checks
        .where((check) => check['passed'] != true)
        .map((check) => check['evidence'])
        .toList();
    return {
      'contract': 'capability-status-evaluation-v1',
      'workflow': workflow,
      'passed': missing.isEmpty,
      'checks': checks,
      'missing': missing,
      'nextAction': missing.isEmpty
          ? 'Proceed with the final answer and cite the evidence already collected.'
          : 'Collect or repair missing evidence before finalizing: ${missing.join(', ')}.',
    };
  }

  bool _evidencePassed(String evidence, Map<String, dynamic> summary) {
    final health = summary['health'] as Map<String, dynamic>;
    final capabilities = summary['capabilitySummary'] as Map<String, dynamic>;
    switch (evidence) {
      case 'agent_discovery':
        return (capabilities['count'] as int) > 0;
      case 'tool_calls':
        return (health['toolCallCount'] as int) > 0;
      case 'no_tool_errors':
        return (health['toolErrorCount'] as int) == 0;
      case 'ui_artifacts':
        return (health['uiArtifactCount'] as int) > 0;
      case 'no_pending_interactions':
        return (health['pendingInteractionCount'] as int) == 0;
    }
    return false;
  }

  String _evidenceMessage(
    String evidence,
    bool passed,
    Map<String, dynamic> summary,
  ) {
    final health = summary['health'] as Map<String, dynamic>;
    switch (evidence) {
      case 'tool_calls':
        return passed
            ? 'At least one tool call is present.'
            : 'No tool calls are visible in the current session evidence.';
      case 'no_tool_errors':
        return passed
            ? 'No failed tool result is visible.'
            : '${health['toolErrorCount']} failed tool result(s) are visible.';
      case 'ui_artifacts':
        return passed
            ? 'At least one page or dashboard artifact exists.'
            : 'No page/dashboard artifact is visible.';
      case 'no_pending_interactions':
        return passed
            ? 'No pending user question or approval is visible.'
            : '${health['pendingInteractionCount']} pending interaction(s) require resolution.';
    }
    return passed
        ? 'Capability discovery is available.'
        : 'Capability discovery did not return registered capabilities.';
  }

  _EvidenceParseResult _parseRequiredEvidence(Object? value) {
    if (value == null) {
      return _EvidenceParseResult([
        'agent_discovery',
        'tool_calls',
        'no_tool_errors',
        'no_pending_interactions',
      ]);
    }
    if (value is! List) {
      return _EvidenceParseResult.error(
        'CapabilityStatus evaluate requires requiredEvidence to be an array of supported evidence names. Use action="help" for allowed values.',
      );
    }
    final out = <String>[];
    for (final item in value) {
      final text = '$item';
      if (!_evidence.contains(text)) {
        return _EvidenceParseResult.error(
          'Unsupported requiredEvidence "$text". Use one of: ${_evidence.join(', ')}.',
        );
      }
      out.add(text);
    }
    return _EvidenceParseResult(
      out.isEmpty
          ? [
              'agent_discovery',
              'tool_calls',
              'no_tool_errors',
              'no_pending_interactions',
            ]
          : out,
    );
  }

  Map<String, dynamic> _readCurrentSession(ToolContext context, int limit) {
    final file = File('${context.basePath}/sessions/current.jsonl');
    if (!file.existsSync()) {
      return {
        'exists': false,
        'toolCallCount': 0,
        'toolErrorCount': 0,
        'recentFailedTools': <Map<String, dynamic>>[],
      };
    }

    final recentFailedTools = <Map<String, dynamic>>[];
    final toolUsesById = <String, Map<String, dynamic>>{};
    final repeatedFailuresBySignature = <String, Map<String, dynamic>>{};
    var toolCallCount = 0;
    var toolErrorCount = 0;
    for (final line in file.readAsLinesSync()) {
      final text = line.trim();
      if (text.isEmpty) continue;
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic> || decoded['type'] != 'message') {
          continue;
        }
        final toolUses = decoded['toolUses'];
        if (toolUses is List) {
          toolCallCount += toolUses.length;
          for (final item in toolUses) {
            if (item is Map) {
              final id = '${item['id'] ?? ''}';
              if (id.isNotEmpty) {
                toolUsesById[id] = {
                  'name': item['name'],
                  'input': item['input'],
                };
              }
            }
          }
        }
        final result = decoded['toolResult'] ?? decoded['tool_result'];
        if (result is Map && result['isError'] == true) {
          toolErrorCount++;
          final toolUseId = '${result['toolUseId'] ?? ''}';
          final toolUse = toolUsesById[toolUseId];
          final signature = _toolFailureSignature(toolUse);
          if (signature != null) {
            final existing = repeatedFailuresBySignature.putIfAbsent(
              signature,
              () => {
                'toolName': toolUse?['name'],
                'input': toolUse?['input'],
                'count': 0,
                'latestToolUseId': toolUseId,
              },
            );
            existing['count'] = (existing['count'] as int) + 1;
            existing['latestToolUseId'] = toolUseId;
          }
          recentFailedTools.add({
            'toolUseId': result['toolUseId'],
            if (toolUse?['name'] != null) 'toolName': toolUse?['name'],
            'content': _truncate('${result['content'] ?? ''}', 240),
          });
          if (recentFailedTools.length > limit) recentFailedTools.removeAt(0);
        }
      } catch (_) {}
    }
    return {
      'exists': true,
      'toolCallCount': toolCallCount,
      'toolErrorCount': toolErrorCount,
      'recentFailedTools': recentFailedTools,
      'repeatedFailureCount': repeatedFailuresBySignature.values
          .where((row) => (row['count'] as int) >= 3)
          .length,
      'repeatedFailedToolCalls': repeatedFailuresBySignature.values
          .where((row) => (row['count'] as int) >= 3)
          .map(
            (row) => {
              ...row,
              'warning':
                  'Same tool/input failed ${row['count']} times. Stop repeating this call; inspect help/status or change arguments before retrying.',
            },
          )
          .toList(),
    };
  }

  String? _toolFailureSignature(Map<String, dynamic>? toolUse) {
    final name = '${toolUse?['name'] ?? ''}';
    if (name.isEmpty) return null;
    Object? input = toolUse?['input'];
    try {
      input = jsonEncode(input ?? const {});
    } catch (_) {
      input = '$input';
    }
    return '$name::$input';
  }

  Map<String, dynamic> _listArtifacts(ToolContext context, int limit) => {
    'pages': _listHtmlFiles(Directory('${context.basePath}/memory/pages'), limit),
    'dashboards': _listHtmlFiles(
      Directory('${context.basePath}/memory/dashboards'),
      limit,
    ),
  };

  Map<String, dynamic> _listHtmlFiles(Directory dir, int limit) {
    if (!dir.existsSync()) return {'exists': false, 'count': 0, 'recent': []};
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.html'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return {
      'exists': true,
      'count': files.length,
      'recent': files
          .take(limit)
          .map(
            (file) => {
              'path': file.path,
              'updatedAt': file.lastModifiedSync().toIso8601String(),
              'sizeBytes': file.lengthSync(),
            },
          )
          .toList(),
    };
  }

  String _truncate(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}...';
}

class _EvidenceParseResult {
  final List<String> values;
  final String? error;

  _EvidenceParseResult(this.values) : error = null;
  _EvidenceParseResult.error(this.error) : values = const [];
}
