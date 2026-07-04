import 'dart:convert';
import 'dart:io';

import '../../tool.dart';
import '../../message.dart';
import '../../tool_context.dart';
import '../utils/file_utils.dart';
import 'report_pdf_parser.dart';

class ReportParseTool extends Tool {
  @override
  String get name => 'ReportParse';

  @override
  String get description =>
      'Parse a financial report PDF and extract structured content.';

  @override
  String get prompt =>
      'Parse a local financial report PDF file (A-share/HK annual/quarterly report).\n'
      'Returns structured JSON with company name, report period, sections, and figures.\n'
      'Parameters:\n'
      '- filePath (required): Absolute path to the PDF file';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'filePath': {
        'type': 'string',
        'description': 'Absolute path to the PDF file',
      },
    },
    'required': ['filePath'],
  };

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final filePath = input['filePath'] as String? ?? '';
    if (filePath.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'filePath is required',
        isError: true,
      );
    }

    final resolvedPath = normalizePath(filePath, context.basePath);
    if (!File(resolvedPath).existsSync()) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'file not found: $filePath',
        isError: true,
      );
    }

    try {
      final parsed = await parseFinancialReport(resolvedPath);

      final result = parsed.toJson();
      result.remove('rawText');

      // Truncate large section content to keep response manageable
      final sections = result['sections'] as List;
      for (final s in sections) {
        final map = s as Map<String, dynamic>;
        final content = map['content'] as String;
        if (content.length > 2000) {
          map['content'] =
              '${content.substring(0, 2000)}... [truncated, ${content.length} chars total]';
        }
      }

      return ToolResult(
        toolUseId: toolUseId,
        content: const JsonEncoder.withIndent('  ').convert(result),
      );
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Parse failed: $e',
        isError: true,
      );
    }
  }
}
