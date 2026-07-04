import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../http_bridge.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Calls a REST API endpoint on the service server.
///
/// Large responses are automatically saved to file with a summary returned
/// to avoid bloating LLM context.
class ServiceCallTool extends Tool {
  /// Threshold: if response has more rows than this, save to file.
  static const int _largeDataThreshold = 50;

  @override
  String get name => 'ServiceCall';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'method': {
        'type': 'string',
        'enum': ['GET', 'POST', 'PUT', 'DELETE'],
        'description': 'HTTP method (default GET)',
      },
      'path': {
        'type': 'string',
        'description':
            'API path (relative like /api/finance/bars, or absolute URL like https://api.example.com/data)',
      },
      'params': {
        'type': 'object',
        'description':
            'Parameters: query params for GET/DELETE, JSON body for POST/PUT',
      },
      'headers': {
        'type': 'object',
        'description':
            'Custom HTTP headers (e.g., {"Authorization": "Bearer xxx"})',
      },
    },
    'required': ['path'],
  };

  @override
  bool get isReadOnly => true;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final path = input['path'] as String?;
    if (path == null || path.trim().isEmpty) {
      return 'path is required.';
    }
    if (!path.startsWith('/') && !path.startsWith('http')) {
      return 'path must start with / or http.';
    }
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final method = (input['method'] as String? ?? 'GET').toUpperCase();
    final path = input['path'] as String;
    final params = input['params'] as Map<String, dynamic>? ?? {};
    final headers = (input['headers'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, v.toString()),
    );

    try {
      final response = await bridgeHttp(
        url: path,
        method: method,
        params: method == 'GET' || method == 'DELETE' ? params : null,
        body: method == 'POST' || method == 'PUT' ? params : null,
        headers: headers,
        serviceBaseUrl: context.serviceBaseUrl,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'API error (${response.statusCode}): ${response.body}',
          isError: true,
        );
      }

      final bodyStr = response.body;

      // Try to parse as JSON to check if it's large tabular data
      try {
        final json = jsonDecode(bodyStr);
        if (_isLargeData(json)) {
          return await _handleLargeData(toolUseId, json, path, params, context);
        }
      } catch (_) {
        // Not JSON or parse error — return as-is
      }

      // Small data — return directly
      if (bodyStr.length > 10000) {
        // Still large text — truncate and save to file
        return await _saveAndSummarize(
          toolUseId,
          bodyStr,
          path,
          params,
          context,
        );
      }

      final sizeKb = (bodyStr.length / 1024).toStringAsFixed(1);
      return ToolResult(
        toolUseId: toolUseId,
        content: '$bodyStr\n\n(${sizeKb}KB)',
      );
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'ServiceCall error: $e',
        isError: true,
      );
    }
  }

  /// Check if the data is large tabular data (has columns + data array).
  bool _isLargeData(dynamic json) {
    if (json is! Map) return false;
    final data = json['data'];
    if (data is List && data.length > _largeDataThreshold) return true;
    return false;
  }

  /// Handle large data: save to JSONL file (one row per line), return summary.
  Future<ToolResult> _handleLargeData(
    String toolUseId,
    Map<String, dynamic> json,
    String path,
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final data = json['data'] as List;
    final columns = json['columns'] as List?;
    final colList = columns?.cast<String>();

    // Generate file name from path and params
    final fileName = _generateFileName(path, params);
    final filePath = p.join(context.basePath, 'memory', 'data', fileName);

    // Ensure directory exists
    Directory(p.dirname(filePath)).createSync(recursive: true);

    // Save as JSONL: first line = meta, then one JSON object per row.
    // This makes Grep effective — each line is a searchable record.
    final buf = StringBuffer();
    buf.writeln(jsonEncode({'columns': columns, 'total': data.length}));
    for (final row in data) {
      if (colList != null && row is List) {
        // Convert [col1, col2, ...] + [val1, val2, ...] → {col1: val1, ...}
        final obj = <String, dynamic>{};
        for (var i = 0; i < colList.length && i < row.length; i++) {
          obj[colList[i]] = row[i];
        }
        buf.writeln(jsonEncode(obj));
      } else {
        buf.writeln(jsonEncode(row));
      }
    }
    File(filePath).writeAsStringSync(buf.toString());

    // Build summary
    final summary = StringBuffer();
    summary.writeln(
      'Data saved to memory/data/$fileName (${data.length} rows).',
    );
    if (columns != null) {
      summary.writeln('Columns: ${columns.join(', ')}');
    }
    summary.writeln('Rows: ${data.length}');

    // Add first few rows as preview
    final previewCount = 5.clamp(0, data.length);
    if (previewCount > 0) {
      summary.writeln('Preview (first $previewCount rows):');
      for (var i = 0; i < previewCount; i++) {
        summary.writeln('  ${jsonEncode(data[i])}');
      }
    }

    // Add basic stats if numeric data
    if (data.isNotEmpty && columns != null) {
      summary.writeln(_buildDataStats(columns, data));
    }

    summary.writeln(
      '\nFile format: JSONL (one JSON object per line, first line is meta). '
      'Use Grep to search, e.g. Grep("半导体", path: "memory/data/$fileName").',
    );

    return ToolResult(toolUseId: toolUseId, content: summary.toString());
  }

  /// Save large text response to file.
  Future<ToolResult> _saveAndSummarize(
    String toolUseId,
    String body,
    String path,
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final fileName = _generateFileName(path, params);
    final filePath = p.join(context.basePath, 'memory', 'data', fileName);
    Directory(p.dirname(filePath)).createSync(recursive: true);
    File(filePath).writeAsStringSync(body);

    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Response saved to memory/data/$fileName '
          '(${body.length} chars). Use Read tool to inspect.',
    );
  }

  /// Generate a descriptive file name.
  String _generateFileName(String path, Map<String, dynamic> params) {
    final pathPart = path
        .replaceAll('/api/', '')
        .replaceAll('/', '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');

    final paramParts = <String>[];
    if (params.containsKey('ts_code')) paramParts.add('${params['ts_code']}');
    if (params.containsKey('start_date')) {
      paramParts.add('${params['start_date']}');
    }

    final suffix = paramParts.isNotEmpty ? '_${paramParts.join('_')}' : '';
    return '$pathPart$suffix.json';
  }

  /// Build basic stats string for numeric columns.
  String _buildDataStats(List columns, List data) {
    if (data.isEmpty) return '';

    final buf = StringBuffer('Stats: ');
    // Try to find common numeric fields
    final colList = columns.cast<String>();
    for (final field in ['close', 'high', 'low', 'vol', 'pe', 'pb']) {
      final idx = colList.indexOf(field);
      if (idx == -1) continue;

      final values = data
          .map((row) {
            if (row is List && idx < row.length) {
              final v = row[idx];
              if (v is num) return v.toDouble();
              if (v is String) return double.tryParse(v);
            }
            return null;
          })
          .whereType<double>()
          .toList();

      if (values.isEmpty) continue;
      values.sort();
      buf.write(
        '$field: ${values.first.toStringAsFixed(2)}'
        '~${values.last.toStringAsFixed(2)} ',
      );
    }
    return buf.toString();
  }
}
