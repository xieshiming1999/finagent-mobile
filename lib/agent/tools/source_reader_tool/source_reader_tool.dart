import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class SourceReaderTool extends Tool {
  @override
  String get name => 'SourceReader';

  @override
  String get description =>
      'Read a source URL or local file, extract basic text metadata, hash the content, and persist source evidence.';

  @override
  String get prompt =>
      'Use SourceReader(action:"help") before source ingestion. Use read with url or path to persist source evidence before citing macro/news/research content.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'read'],
      },
      'url': {'type': 'string'},
      'path': {'type': 'string'},
      'source': {'type': 'string'},
      'topic': {'type': 'string'},
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
    final action = '${input['action'] ?? 'help'}'.trim();
    if (action == 'help') {
      return ToolResult(toolUseId: toolUseId, content: jsonEncode(_help()));
    }
    if (action != 'read') {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid SourceReader action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }
    final url = _optionalString(input['url']);
    final path = _optionalString(input['path']);
    if ((url == null && path == null) || (url != null && path != null)) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'SourceReader(action:"read") requires exactly one of url or path.',
        isError: true,
      );
    }
    try {
      final content = path != null
          ? await _readPath(path)
          : await _readUrl(url!);
      final hash = sha256.convert(utf8.encode(content.body)).toString();
      final record = {
        'contract': 'source-evidence-record-v1',
        'id': 'source:$hash',
        'url': url,
        'path': path,
        'source': _optionalString(input['source']) ?? _sourceFrom(url, path),
        'topic': _optionalString(input['topic']) ?? 'unknown',
        'title': _title(content.body),
        'publishedAt': _date(content.body),
        'contentType': content.contentType,
        'hash': hash,
        'bytes': utf8.encode(content.body).length,
        'excerpt': _truncate(_plainText(content.body), 800),
        'storedAt': DateTime.now().toUtc().toIso8601String(),
      };
      final file = File('${context.memoryDir}/source_evidence/$hash.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(record),
      );
      return ToolResult(
        toolUseId: toolUseId,
        content: jsonEncode({
          'contract': 'source-reader-result-v1',
          'record': record,
          'artifactHint': {
            'kind': 'research',
            'path': file.path,
            'title': record['title'],
            'source': record['source'],
            'provenance': {
              'sourceHash': hash,
              'url': url,
              'path': path,
              'topic': record['topic'],
            },
          },
        }),
      );
    } catch (error) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'SourceReader failed: $error',
        isError: true,
      );
    }
  }

  Map<String, dynamic> _help() => {
    'contract': 'source-reader-help-v1',
    'actions': ['read'],
    'required': 'Exactly one of url or path.',
    'stores': 'memory/source_evidence/<sha256>.json',
    'guidance':
        'SourceReader records title/date/hash/excerpt as evidence. Use ArtifactRegistry to register reusable source evidence before citing it in analysis.',
  };

  Future<_SourceContent> _readPath(String path) async {
    final file = File(path);
    if (!file.existsSync()) throw 'file not found: $path';
    return _SourceContent(await file.readAsString(), 'text/plain');
  }

  Future<_SourceContent> _readUrl(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw 'HTTP ${response.statusCode} for $url';
      }
      final body = await response.transform(utf8.decoder).join();
      return _SourceContent(
        body,
        response.headers.contentType?.mimeType ?? 'text/plain',
      );
    } finally {
      client.close(force: true);
    }
  }

  String _sourceFrom(String? url, String? path) {
    if (url != null) return Uri.tryParse(url)?.host ?? 'web';
    return path ?? 'local-file';
  }

  String _title(String body) {
    final html = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(body)?.group(1);
    if (html != null && html.trim().isNotEmpty) return _plainText(html).trim();
    return _plainText(body)
        .split('\n')
        .firstWhere(
          (line) => line.trim().isNotEmpty,
          orElse: () => 'Untitled source',
        )
        .trim();
  }

  String? _date(String body) {
    return RegExp(r'\b20\d{2}-\d{2}-\d{2}\b').firstMatch(body)?.group(0);
  }

  String _plainText(String value) => value
      .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), ' ')
      .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _truncate(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}...';

  String? _optionalString(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }
}

class _SourceContent {
  final String body;
  final String contentType;

  const _SourceContent(this.body, this.contentType);
}
