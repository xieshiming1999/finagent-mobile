import 'dart:convert';
import 'dart:io';

import '../../artifact_registry.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

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
        'enum': ['help', 'list', 'get', 'register', 'graph'],
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
        return _register(toolUseId, registry, input, context);
      case 'graph':
        return ToolResult(
          toolUseId: toolUseId,
          content: jsonEncode(_graph(registry, input)),
        );
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
    'actions': ['help', 'list', 'get', 'register', 'graph'],
    'kinds': ArtifactKind.values.map((kind) => kind.wireName).toList(),
    'guidance': [
      'Register artifacts after creating durable workflow outputs; do not rely only on chat text.',
      'Use provenance and freshness to explain where evidence came from and whether it is reusable.',
      'Use get/list before reusing an existing artifact in later turns.',
      'Use graph to inspect claim/evidence/source relationships before citing a prior artifact.',
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
    ToolContext context,
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
    var path = (input['path'] as String?)?.trim() ?? '';
    final title = (input['title'] as String?)?.trim() ?? '';
    final source = (input['source'] as String?)?.trim() ?? '';
    if (title.isEmpty || source.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'ArtifactRegistry(action:"register") requires non-empty title and source. Provide path for an existing artifact, or omit path to let ArtifactRegistry create a managed artifact file.',
        isError: true,
      );
    }
    var managedArtifact = false;
    if (path.isEmpty) {
      path = _writeManagedArtifact(context, kind, input, title, source);
      managedArtifact = true;
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
        'managedArtifact': managedArtifact,
        'artifact': record.toJson(),
      }),
    );
  }

  String _writeManagedArtifact(
    ToolContext context,
    ArtifactKind kind,
    Map<String, dynamic> input,
    String title,
    String source,
  ) {
    final freshness = _mapValue(input['freshness']);
    final provenance = _mapValue(input['provenance']);
    final metadata = _mapValue(input['metadata']);
    final digest = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'kind': kind.wireName,
              'title': title,
              'source': source,
              'freshness': freshness,
              'provenance': provenance,
              'metadata': metadata,
            }),
          ),
        )
        .toString()
        .substring(0, 16);
    final relativePath = p.join(
      'memory',
      'artifacts',
      kind.wireName,
      '$digest.json',
    );
    final file = File(p.join(context.basePath, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${jsonEncode({
            'contract': 'managed-artifact-v1',
            'kind': kind.wireName,
            'title': title,
            'source': source,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'freshness': freshness,
            'provenance': provenance.isEmpty ? {'source': source} : provenance,
            'links': _stringList(input['links']),
            'metadata': metadata,
          })}\n',
    );
    return relativePath;
  }

  Map<String, dynamic> _graph(
    ArtifactRegistry registry,
    Map<String, dynamic> input,
  ) {
    final kind = _kindOrNull(input['kind']);
    final limit = _intValue(input['limit'], defaultValue: 50).clamp(1, 100);
    final records = registry.list(kind: kind).take(limit).toList();
    final nodes = <String, Map<String, dynamic>>{};
    final edges = <Map<String, dynamic>>[];

    void addNode(String id, String type, Map<String, dynamic> data) {
      if (id.trim().isEmpty) return;
      nodes[id] = {'id': id, 'type': type, ...data};
    }

    for (final record in records) {
      final artifact = record.toJson();
      final artifactId = artifact['stableRef'] as String;
      addNode(artifactId, 'artifact', {
        'kind': artifact['kind'],
        'title': artifact['title'],
        'verificationStatus': artifact['verificationStatus'],
        'freshness': artifact['freshness'],
      });
      final sourceId = 'source:${artifact['source']}';
      addNode(sourceId, 'source', {'source': artifact['source']});
      edges.add({
        'from': artifactId,
        'to': sourceId,
        'relation': 'from_source',
      });

      final provenance = artifact['provenance'];
      if (provenance is Map) {
        for (final entry in provenance.entries) {
          final key = '${entry.key}';
          final value = entry.value;
          if (value is String && value.trim().isNotEmpty) {
            final nodeId = '$key:$value';
            addNode(nodeId, key, {'value': value});
            edges.add({
              'from': artifactId,
              'to': nodeId,
              'relation': 'proves_with',
            });
          }
        }
      }
      for (final link in _stringList(artifact['links'])) {
        addNode(
          link,
          link.startsWith('artifact:') ? 'artifact_ref' : 'reference',
          {'value': link},
        );
        edges.add({'from': artifactId, 'to': link, 'relation': 'links_to'});
      }
    }
    return {
      'contract': 'artifact-evidence-graph-v1',
      'artifactCount': records.length,
      'nodeCount': nodes.length,
      'edgeCount': edges.length,
      'nodes': nodes.values.toList(),
      'edges': edges,
      'guidance':
          'Use this graph to connect claims, artifacts, source/provider evidence, freshness, and missing links before reusing prior analysis.',
    };
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
