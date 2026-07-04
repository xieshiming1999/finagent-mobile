/// WebFetchTool — fetch web content or download files from URLs.
///
/// Automatically handles different content types:
/// - HTML → strips tags, returns text content for LLM
/// - PDF/binary → saves to file, returns file path
/// - JSON/text → returns raw content
library;

import 'dart:io';

import 'package:http/http.dart' as http;

import '../../data_fetcher/http_utils.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../utils/file_utils.dart';

class WebFetchTool extends Tool {
  @override
  String get name => 'WebFetch';

  @override
  String get description => 'Fetch web content or download files from a URL.';

  @override
  String get prompt =>
      '''Fetch content from a URL. Supports GET and POST requests with custom headers.

Parameters:
- url (required): The URL to fetch
- method: HTTP method, "GET" (default) or "POST"
- headers: Custom HTTP headers as key-value map (merged with default User-Agent)
- body: Request body string for POST requests (typically JSON)
- outputPath: For binary files (PDF, images), where to save. Auto-generated if not provided.
- maxLength: Max content length to return (default 50000 chars, to avoid flooding context)

Examples:
- GET: WebFetch url="https://api.example.com/data"
- POST with JSON: WebFetch url="https://api.example.com/scan" method="POST" headers={"Content-Type":"application/json"} body='{"query":"test"}'
- POST with browser headers: WebFetch url="https://scanner.tradingview.com/crypto/scan" method="POST" headers={"Content-Type":"application/json","Origin":"https://www.tradingview.com","Referer":"https://www.tradingview.com/"} body='{"symbols":{"tickers":["BINANCE:BTCUSDT"]},"columns":["RSI","MACD.macd","close"]}'

''';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'url': {'type': 'string', 'description': 'URL to fetch'},
      'method': {
        'type': 'string',
        'description': 'HTTP method: GET (default) or POST',
        'enum': ['GET', 'POST'],
      },
      'headers': {
        'type': 'object',
        'description': 'Custom HTTP headers (key-value pairs)',
        'additionalProperties': {'type': 'string'},
      },
      'body': {
        'type': 'string',
        'description': 'Request body for POST (typically JSON string)',
      },
      'outputPath': {
        'type': 'string',
        'description': 'Output path for binary files (optional)',
      },
      'maxLength': {
        'type': 'integer',
        'description': 'Max content length (default 50000)',
      },
    },
    'required': ['url'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool get canParallel => true;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final url = input['url'] as String? ?? '';
    if (url.isEmpty) return 'url is required.';
    final outputPath = input['outputPath'] as String?;
    if (outputPath != null && outputPath.trim().isNotEmpty) {
      try {
        normalizePath(outputPath, context.basePath);
      } catch (e) {
        return e.toString();
      }
    }
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final url = input['url'] as String? ?? '';
    if (url.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'url is required',
        isError: true,
      );
    }

    final maxLength = (input['maxLength'] as int?) ?? 50000;
    final method = ((input['method'] as String?) ?? 'GET').toUpperCase();
    final customHeaders =
        (input['headers'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        ) ??
        {};
    final body = input['body'] as String?;

    try {
      final headers = {
        'User-Agent': configuredHttpUserAgent(),
        ...customHeaders,
      };
      final uri = Uri.parse(url);

      final http.Response response;
      if (method == 'POST') {
        response = await http.post(uri, headers: headers, body: body);
      } else {
        response = await http.get(uri, headers: headers);
      }

      if (response.statusCode != 200) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          isError: true,
        );
      }

      final contentType = response.headers['content-type'] ?? '';

      // Binary content (PDF, images, etc.) → save to file
      if (_isBinaryContent(contentType, url)) {
        final rawPath =
            input['outputPath'] as String? ?? _defaultOutputPath(url, context);
        final outputPath = normalizePath(rawPath, context.basePath);
        final file = File(outputPath);
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(response.bodyBytes);
        return ToolResult(
          toolUseId: toolUseId,
          content:
              'Downloaded to $outputPath (${response.bodyBytes.length} bytes, $contentType)',
        );
      }

      // Text content
      var text = response.body;

      // HTML → strip tags
      if (contentType.contains('html')) {
        text = _htmlToText(text);
      }

      // Truncate if too long
      if (text.length > maxLength) {
        text =
            '${text.substring(0, maxLength)}\n\n[Truncated: ${text.length} total chars, showing first $maxLength]';
      }

      final lineCount = '\n'.allMatches(text).length + 1;
      final sizeKb = (text.length / 1024).toStringAsFixed(1);
      return ToolResult(
        toolUseId: toolUseId,
        content:
            '$text\n\n(${sizeKb}KB, $lineCount lines, content-type: $contentType)',
      );
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Fetch failed: $e',
        isError: true,
      );
    }
  }

  bool _isBinaryContent(String contentType, String url) {
    if (contentType.contains('pdf') ||
        contentType.contains('octet-stream') ||
        contentType.contains('image/')) {
      return true;
    }
    // URL heuristic
    final lower = url.toLowerCase();
    return lower.endsWith('.pdf') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg');
  }

  String _defaultOutputPath(String url, ToolContext context) {
    final uri = Uri.parse(url);
    var filename = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : 'download';
    if (!filename.contains('.')) filename += '.pdf';
    return '${context.basePath}/tmp/$filename';
  }

  /// Simple HTML to text conversion — strips tags, decodes common entities.
  String _htmlToText(String html) {
    // Remove script/style blocks
    var text = html.replaceAll(
      RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
      '',
    );

    // Convert common block elements to newlines
    text = text.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    text = text.replaceAll(
      RegExp(r'</(p|div|h[1-6]|li|tr)>', caseSensitive: false),
      '\n',
    );
    text = text.replaceAll(
      RegExp(r'<(p|div|h[1-6])[\s>]', caseSensitive: false),
      '\n',
    );

    // Strip remaining tags
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');

    // Decode common HTML entities
    text = text.replaceAll('&amp;', '&');
    text = text.replaceAll('&lt;', '<');
    text = text.replaceAll('&gt;', '>');
    text = text.replaceAll('&quot;', '"');
    text = text.replaceAll('&#39;', "'");
    text = text.replaceAll('&nbsp;', ' ');

    // Collapse whitespace
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }
}
