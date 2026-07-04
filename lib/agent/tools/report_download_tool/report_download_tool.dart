import 'dart:io';

import 'package:http/http.dart' as http;

import '../../artifact_registry.dart';
import '../../data_fetcher/http_utils.dart';
import '../../tool.dart';
import '../../message.dart';
import '../../tool_context.dart';
import '../utils/file_utils.dart';

class ReportDownloadTool extends Tool {
  @override
  String get name => 'ReportDownload';

  @override
  String get description =>
      'Download a financial report PDF from a URL and save to local disk.';

  @override
  String get prompt =>
      'Download a financial report PDF from a given URL.\n'
      'Validates that the downloaded file is a real PDF (magic bytes check).\n'
      'Retries up to 3 times with backoff on failure.\n'
      'Parameters:\n'
      '- url (required): Direct PDF URL (e.g. from stockn.xueqiu.com or notice.10jqka.com.cn)\n'
      '- outputPath (required): Where to save the PDF file (relative to basePath)';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'url': {'type': 'string', 'description': 'Direct PDF URL'},
      'outputPath': {'type': 'string', 'description': 'Local save path'},
    },
    'required': ['url', 'outputPath'],
  };

  @override
  bool get isReadOnly => false;

  static const _maxRetries = 3;
  static const _pdfMagic = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-

  Map<String, String> _headers(String url) {
    final headers = {
      'User-Agent': configuredHttpUserAgent(),
      'Accept': 'application/pdf,application/octet-stream,*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };
    if (url.contains('10jqka.com.cn')) {
      headers['Referer'] = 'https://10jqka.com.cn/';
    } else {
      headers['Referer'] = 'https://xueqiu.com/';
    }
    return headers;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final url = input['url'] as String? ?? '';
    final outputPath = input['outputPath'] as String? ?? '';

    if (url.isEmpty || outputPath.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'url and outputPath are required',
        isError: true,
      );
    }

    if (!url.toLowerCase().endsWith('.pdf')) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'URL does not end with .pdf',
        isError: true,
      );
    }

    final resolvedOutput = normalizePath(outputPath, context.basePath);

    String? lastError;
    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        final response = await http.get(Uri.parse(url), headers: _headers(url));

        if (response.statusCode != 200) {
          lastError = 'HTTP ${response.statusCode}';
          if (attempt < _maxRetries) {
            await Future.delayed(Duration(seconds: 3 * attempt));
            continue;
          }
          break;
        }

        final bytes = response.bodyBytes;

        if (bytes.length < 5) {
          return ToolResult(
            toolUseId: toolUseId,
            content: 'response too small (${bytes.length} bytes)',
            isError: true,
          );
        }
        for (var i = 0; i < _pdfMagic.length; i++) {
          if (bytes[i] != _pdfMagic[i]) {
            return ToolResult(
              toolUseId: toolUseId,
              content:
                  'downloaded file is not a valid PDF (magic bytes mismatch)',
              isError: true,
            );
          }
        }

        final outFile = File(resolvedOutput);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(bytes);
        ArtifactRegistry(context.basePath).register(
          kind: ArtifactKind.report,
          path: resolvedOutput,
          title: 'Financial report PDF',
          source: 'ReportDownload',
          id: 'report:$resolvedOutput',
          ownerTask: 'report-download',
          verificationStatus: ArtifactVerificationStatus.verified,
          freshness: {
            'fetchedAt': DateTime.now().toUtc().toIso8601String(),
            'status': 'fresh',
          },
          provenance: {'source': 'ReportDownload', 'url': url},
          metadata: {
            'url': url,
            'sizeBytes': bytes.length,
            'outputPath': outputPath,
          },
        );

        final sizeMb = (bytes.length / 1024 / 1024).toStringAsFixed(1);
        return ToolResult(
          toolUseId: toolUseId,
          content: 'Downloaded $outputPath ($sizeMb MB, ${bytes.length} bytes)',
        );
      } catch (e) {
        lastError = e.toString();
        if (attempt < _maxRetries) {
          await Future.delayed(Duration(seconds: 3 * attempt));
        }
      }
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: 'Download failed after $_maxRetries attempts: $lastError',
      isError: true,
    );
  }
}
