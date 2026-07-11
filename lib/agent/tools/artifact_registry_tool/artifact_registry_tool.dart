import 'dart:convert';

import '../../artifact_registry.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class ArtifactRegistryTool extends Tool {
  @override
  String get name => 'ArtifactRegistry';

  @override
  String get description =>
      'Create and inspect durable workflow artifacts such as analyses, dashboards, strategies, backtests, reports, and data evidence.';

  @override
  String get prompt =>
      'Use ArtifactRegistry(action:"help") to discover artifact kinds. Use list/get to inspect durable outputs and register to save an artifact record after creating a file, dashboard, strategy, backtest, macro evidence, or trade-preparation note.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'list', 'get', 'register'],
      },
      'kind': {
        'type': 'string',
        'enum': ArtifactKind.values.map((kind) => kind.wireName).toList(),
        'description': 'Optional for list; required for register.',
      },
      'id': {'type': 'string', 'description': 'Artifact id or stable id.'},
      'path': {'type': 'string', 'description': 'Runtime artifact path.'},
      'title': {'type': 'string'},
      'source': {'type': 'string'},
      'ownerTask': {'type': 'string'},
      'verificationStatus': {
        'type': 'string',
        'enum': ArtifactVerificationStatus.values
            .map((status) => status.wireName)
            .toList(),
      },
      'freshness': {'type': 'object'},
      'provenance': {'type': 'object'},
      'links': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'metadata': {'type': 'object'},
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100},
    },
  };

  @override
  bool get isReadOnly => false;

  @override
  bool canRunInParallel(Map<String, dynamic> input) =>
      (input['action'] as String?) != 'register';

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = (input['action'] as String?)?.trim() ?? 'list';
    final registry = ArtifactRegistry(context.basePath);
    switch (action) {
      case 'help':
        return ToolResult(toolUseId: toolUseId, content: jsonEncode(_help()));
      case 'list':
        return ToolResult(
          toolUseId: toolUseId,
          content: jsonEncode(_list(registry, input)),
        );
      case 'get':
        return _get(toolUseId, registry, input);
      case 'register':
        return _register(toolUseId, registry, input);
      default:
        return ToolResult(
          toolUseId: toolUseId,
          content:
              'Invalid ArtifactRegistry action "$action". Use action="help" for supported actions.',
          isError: true,
        );
    }
  }

  Map<String, dynamic> _help() => {
    'contract': 'artifact-registry-help-v1',
    'actions': ['help', 'list', 'get', 'register'],
    'kinds': ArtifactKind.values.map((kind) => kind.wireName).toList(),
    'guidance': [
      'Register artifacts after creating durable workflow outputs; do not rely only on chat text.',
      'Use provenance and freshness to explain where evidence came from and whether it is reusable.',
      'Use get/list before reusing an existing artifact in later turns.',
    ],
  };

  Map<String, dynamic> _list(
    ArtifactRegistry registry,
    Map<String, dynamic> input,
  ) {
    final kind = _kindOrNull(input['kind']);
    final limit = _intValue(input['limit'], defaultValue: 20).clamp(1, 100);
    final records = registry.list(kind: kind).take(limit).toList();
    return {
      'contract': 'artifact-registry-list-v1',
      'count': records.length,
      'kind': kind?.wireName,
      'artifacts': records.map((record) => record.toJson()).toList(),
    };
  }

  ToolResult _get(
    String toolUseId,
    ArtifactRegistry registry,
    Map<String, dynamic> input,
  ) {
    final id = (input['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'ArtifactRegistry(action:"get") requires id.',
        isError: true,
      );
    }
    final normalizedId = id.startsWith('artifact:') ? id.substring(9) : id;
    for (final record in registry.list()) {
      if (record.id == normalizedId || record.stableRef == id) {
        return ToolResult(
          toolUseId: toolUseId,
          content: jsonEncode({
            'contract': 'artifact-registry-record-v1',
            'artifact': record.toJson(),
          }),
        );
      }
    }
    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Artifact "$id" was not found. Use ArtifactRegistry(action:"list") to inspect available artifacts.',
      isError: true,
    );
  }

  ToolResult _register(
    String toolUseId,
    ArtifactRegistry registry,
    Map<String, dynamic> input,
  ) {
    final kind = _kindOrNull(input['kind']);
    if (kind == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'ArtifactRegistry(action:"register") requires a supported kind. Use action="help" to inspect kinds.',
        isError: true,
      );
    }
    final path = (input['path'] as String?)?.trim() ?? '';
    final title = (input['title'] as String?)?.trim() ?? '';
    final source = (input['source'] as String?)?.trim() ?? '';
    if (path.isEmpty || title.isEmpty || source.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'ArtifactRegistry(action:"register") requires non-empty path, title, and source.',
        isError: true,
      );
    }
    final record = registry.register(
      kind: kind,
      path: path,
      title: title,
      source: source,
      id: (input['id'] as String?)?.trim().ifEmptyNull,
      ownerTask: (input['ownerTask'] as String?)?.trim().ifEmptyNull,
      verificationStatus: ArtifactVerificationStatusWire.parse(
        input['verificationStatus'] as String?,
      ),
      freshness: _mapValue(input['freshness']),
      provenance: _mapValue(input['provenance']),
      links: _stringList(input['links']),
      metadata: _mapValue(input['metadata']),
    );
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'contract': 'artifact-registry-record-v1',
        'artifact': record.toJson(),
      }),
    );
  }
}

ArtifactKind? _kindOrNull(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return ArtifactKindWire.parse(text);
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList();
}

int _intValue(Object? value, {required int defaultValue}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? defaultValue;
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
