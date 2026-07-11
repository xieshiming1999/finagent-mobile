import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum ArtifactKind {
  analysis,
  goal,
  planSnapshot,
  workPacket,
  contextPack,
  apiError,
  dataSnapshot,
  research,
  macroEvidence,
  dashboard,
  strategy,
  backtest,
  report,
  tradePreparation,
}

enum ArtifactVerificationStatus {
  unverified,
  verified,
  stale,
  failed,
  unsupported,
}

extension ArtifactVerificationStatusWire on ArtifactVerificationStatus {
  String get wireName => switch (this) {
    ArtifactVerificationStatus.unverified => 'unverified',
    ArtifactVerificationStatus.verified => 'verified',
    ArtifactVerificationStatus.stale => 'stale',
    ArtifactVerificationStatus.failed => 'failed',
    ArtifactVerificationStatus.unsupported => 'unsupported',
  };

  static ArtifactVerificationStatus parse(String? value) {
    for (final status in ArtifactVerificationStatus.values) {
      if (status.wireName == value) return status;
    }
    return ArtifactVerificationStatus.unverified;
  }
}

extension ArtifactKindWire on ArtifactKind {
  String get wireName => switch (this) {
    ArtifactKind.analysis => 'analysis',
    ArtifactKind.goal => 'goal',
    ArtifactKind.planSnapshot => 'plan_snapshot',
    ArtifactKind.workPacket => 'work_packet',
    ArtifactKind.contextPack => 'context_pack',
    ArtifactKind.apiError => 'api_error',
    ArtifactKind.dataSnapshot => 'data_snapshot',
    ArtifactKind.research => 'research',
    ArtifactKind.macroEvidence => 'macro_evidence',
    ArtifactKind.dashboard => 'dashboard',
    ArtifactKind.strategy => 'strategy',
    ArtifactKind.backtest => 'backtest',
    ArtifactKind.report => 'report',
    ArtifactKind.tradePreparation => 'trade_preparation',
  };

  static ArtifactKind? parse(String value) {
    for (final kind in ArtifactKind.values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }
}

class ArtifactRecord {
  final String id;
  final ArtifactKind kind;
  final String stableRef;
  final String path;
  final String title;
  final String source;
  final String? ownerTask;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  final ArtifactVerificationStatus verificationStatus;
  final Map<String, dynamic> freshness;
  final Map<String, dynamic> provenance;
  final List<String> links;
  final Map<String, dynamic> metadata;

  const ArtifactRecord({
    required this.id,
    required this.kind,
    required this.stableRef,
    required this.path,
    required this.title,
    required this.source,
    this.ownerTask,
    required this.createdAt,
    required this.updatedAt,
    this.expiresAt,
    this.verificationStatus = ArtifactVerificationStatus.unverified,
    this.freshness = const {'status': 'unknown'},
    this.provenance = const {},
    this.links = const [],
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.wireName,
    'stableRef': stableRef,
    'path': path,
    'title': title,
    'source': source,
    'ownerTask': ownerTask,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'verificationStatus': verificationStatus.wireName,
    'freshness': freshness,
    'provenance': provenance.isEmpty ? {'source': source} : provenance,
    'links': links.isEmpty ? [stableRef, path] : links,
    'metadata': metadata,
  };

  factory ArtifactRecord.fromJson(Map<String, dynamic> json) {
    final kind = ArtifactKindWire.parse(json['kind'] as String? ?? '');
    if (kind == null) throw const FormatException('Unknown artifact kind');
    return ArtifactRecord(
      id: json['id'] as String? ?? '',
      kind: kind,
      stableRef: json['stableRef'] as String? ?? 'artifact:${json['id'] ?? ''}',
      path: json['path'] as String? ?? '',
      title: json['title'] as String? ?? '',
      source: json['source'] as String? ?? '',
      ownerTask:
          json['ownerTask'] as String? ??
          _inferOwnerTask(
            Map<String, dynamic>.from(
              json['metadata'] as Map<dynamic, dynamic>? ?? const {},
            ),
          ),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
      verificationStatus: ArtifactVerificationStatusWire.parse(
        json['verificationStatus'] as String?,
      ),
      freshness: Map<String, dynamic>.from(
        json['freshness'] as Map<dynamic, dynamic>? ??
            const {'status': 'unknown'},
      ),
      provenance: Map<String, dynamic>.from(
        json['provenance'] as Map<dynamic, dynamic>? ??
            {'source': json['source'] as String? ?? ''},
      ),
      links:
          (json['links'] as List<dynamic>?)?.whereType<String>().toList() ??
          ['artifact:${json['id'] ?? ''}', json['path'] as String? ?? ''],
      metadata: Map<String, dynamic>.from(
        json['metadata'] as Map<dynamic, dynamic>? ?? const {},
      ),
    );
  }
}

class ArtifactRegistry {
  final String basePath;
  late final String filePath = p.join(
    basePath,
    'memory',
    'artifacts',
    'registry.json',
  );

  ArtifactRegistry(this.basePath);

  ArtifactRecord register({
    required ArtifactKind kind,
    required String path,
    required String title,
    required String source,
    String? id,
    String? ownerTask,
    DateTime? expiresAt,
    ArtifactVerificationStatus verificationStatus =
        ArtifactVerificationStatus.unverified,
    Map<String, dynamic> freshness = const {'status': 'unknown'},
    Map<String, dynamic> provenance = const {},
    List<String> links = const [],
    Map<String, dynamic> metadata = const {},
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final recordId = id ?? '${kind.wireName}:$path';
    final records = list();
    ArtifactRecord? previous;
    for (final record in records) {
      if (record.id == recordId) {
        previous = record;
        break;
      }
    }
    final record = ArtifactRecord(
      id: recordId,
      kind: kind,
      stableRef: 'artifact:$recordId',
      path: path,
      title: title,
      source: source,
      ownerTask: ownerTask ?? _inferOwnerTask(metadata) ?? previous?.ownerTask,
      createdAt: previous?.createdAt ?? timestamp,
      updatedAt: timestamp,
      expiresAt: expiresAt ?? previous?.expiresAt,
      verificationStatus:
          verificationStatus == ArtifactVerificationStatus.unverified
          ? previous?.verificationStatus ?? verificationStatus
          : verificationStatus,
      freshness: freshness.isEmpty
          ? previous?.freshness ?? const {'status': 'unknown'}
          : freshness,
      provenance: provenance.isEmpty
          ? previous?.provenance ?? {'source': source}
          : provenance,
      links: _uniqueStrings([
        'artifact:$recordId',
        path,
        ...links,
        ...?previous?.links,
      ]),
      metadata: metadata,
    );
    _write([record, ...records.where((item) => item.id != recordId)]);
    return record;
  }

  List<ArtifactRecord> list({ArtifactKind? kind}) {
    final file = File(filePath);
    if (!file.existsSync()) return [];
    try {
      final parsed = jsonDecode(file.readAsStringSync());
      if (parsed is! List) return [];
      final records = parsed
          .whereType<Map<dynamic, dynamic>>()
          .map((row) => ArtifactRecord.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      return kind == null
          ? records
          : records.where((record) => record.kind == kind).toList();
    } catch (_) {
      return [];
    }
  }

  void _write(List<ArtifactRecord> records) {
    final file = File(filePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(records.map((record) => record.toJson()).toList()),
    );
  }
}

String? _inferOwnerTask(Map<String, dynamic> metadata) {
  final value =
      metadata['templateId'] ??
      metadata['goalArtifactId'] ??
      metadata['dashboardId'] ??
      metadata['reportType'];
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<String> _uniqueStrings(List<String?> values) {
  final out = <String>[];
  for (final value in values) {
    final text = value?.trim();
    if (text == null || text.isEmpty || out.contains(text)) continue;
    out.add(text);
  }
  return out;
}
