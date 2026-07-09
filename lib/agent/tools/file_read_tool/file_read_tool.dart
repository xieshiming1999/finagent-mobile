import 'dart:io';
import 'dart:typed_data';

import '../../instruction.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../utils/file_utils.dart';
import 'prompt.dart' as tool_prompt;

bool _isMacroResearchContentPath(String filePath) {
  return filePath.replaceAll('\\', '/').contains('/data/macro_research_content/');
}

/// Reads a file from the filesystem with line numbers.
///
/// Reference: claude-code-best/src/tools/FileReadTool/FileReadTool.ts
class FileReadTool extends Tool {
  /// Optional listener called after each successful file read.
  /// Used by Magic Docs to detect MAGIC DOC headers.
  static void Function(String filePath, String content)? onFileRead;

  @override
  String get name => 'Read';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'file_path': {
        'type': 'string',
        'description': 'The path to the file to read',
      },
      'offset': {
        'type': 'integer',
        'description':
            'The 1-indexed line number to start reading from. '
            'Only provide if the file is too large to read at once.',
      },
      'limit': {
        'type': 'integer',
        'description':
            'The number of lines to read. '
            'Only provide if the file is too large to read at once.',
      },
    },
    'required': ['file_path'],
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
    final filePath = input['file_path'] as String?;
    if (filePath == null || filePath.trim().isEmpty) {
      return 'file_path is required.';
    }

    try {
      final resolved = normalizePath(filePath, context.basePath);
      if (!File(resolved).existsSync()) {
        final similar = findSimilarFile(resolved);
        final suggestion = similar != null ? ' Did you mean: $similar?' : '';
        return 'File not found: $filePath (resolved to: $resolved).$suggestion';
      }
    } on PathSecurityException catch (e) {
      return e.toString();
    } on ArgumentError catch (e) {
      return e.message as String;
    }

    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final filePath = input['file_path'] as String;
    final offset = (input['offset'] as num?)?.toInt() ?? 1;
    final limit = (input['limit'] as num?)?.toInt();
    final resolved = normalizePath(filePath, context.basePath);
    if (_isMacroResearchContentPath(resolved)) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Macro research content artifacts are diagnostic/source-maintenance files. '
            'For normal macro analysis, use MarketData(action: "query_macro_research_content") '
            'and answer from contentEvidence, keyClaims, sourceDataTime, fetchedAt, and contentHash '
            'instead of reading local artifact files.',
        isError: true,
      );
    }

    // Image files: return as image content block for LLM vision
    final lower = resolved.toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      try {
        final bytes = File(resolved).readAsBytesSync();
        final sizeKb = (bytes.length / 1024).toStringAsFixed(1);
        String dims = '';
        if (bytes.length > 24 && bytes[0] == 0x89 && bytes[1] == 0x50) {
          // PNG: width at offset 16, height at offset 20 (4 bytes big-endian)
          final w =
              (bytes[16] << 24) |
              (bytes[17] << 16) |
              (bytes[18] << 8) |
              bytes[19];
          final h =
              (bytes[20] << 24) |
              (bytes[21] << 16) |
              (bytes[22] << 8) |
              bytes[23];
          dims = ', ${w}x${h}px';
        } else if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
          // JPEG: scan for SOF0/SOF2 marker (0xFFC0/0xFFC2) to find dimensions
          for (var i = 2; i < bytes.length - 9;) {
            if (bytes[i] != 0xFF) break;
            final marker = bytes[i + 1];
            if (marker == 0xC0 || marker == 0xC2) {
              final h = (bytes[i + 5] << 8) | bytes[i + 6];
              final w = (bytes[i + 7] << 8) | bytes[i + 8];
              dims = ', ${w}x${h}px';
              break;
            }
            final segLen = (bytes[i + 2] << 8) | bytes[i + 3];
            i += 2 + segLen;
          }
        }
        return ToolResult(
          toolUseId: toolUseId,
          content: 'Image file: $filePath (${sizeKb}KB$dims)',
          images: [Uint8List.fromList(bytes)],
          imagePaths: [resolved],
        );
      } catch (e) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'Error reading image: $e',
          isError: true,
        );
      }
    }

    try {
      final result = readFileInRange(
        resolved,
        offset <= 0 ? 0 : offset - 1, // convert 1-indexed to 0-indexed
        limit,
        limit == null ? maxReadSizeBytes : null, // byte cap only for full reads
      );

      // Track read timestamp for read-before-write safety
      context.readFileTimestamps[resolved] = result.mtimeMs;

      // Notify listeners (Magic Docs detection)
      if (onFileRead != null) {
        onFileRead!(resolved, result.content);
      }

      if (result.content.isEmpty) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'File is empty: $filePath',
        );
      }

      // Check if offset is beyond file length
      if (offset > result.totalLines) {
        return ToolResult(
          toolUseId: toolUseId,
          content:
              'Warning: offset $offset is beyond the end of the file '
              '(file has ${result.totalLines} lines). '
              'No content to display.',
        );
      }

      final numbered = addLineNumbers(
        result.content,
        startLine: offset <= 0 ? 1 : offset,
      );

      // Add truncation hint if applicable
      final endLine = (offset <= 0 ? 1 : offset) + result.lineCount - 1;
      final sizeKb = (result.totalBytes / 1024).toStringAsFixed(1);

      // Attach hierarchical instructions if found near this file
      final instructions =
          getInstructionsForFile(resolved, context.basePath) ?? '';

      if (endLine < result.totalLines) {
        return ToolResult(
          toolUseId: toolUseId,
          content:
              '$numbered\n\n'
              '(Showing lines ${offset <= 0 ? 1 : offset}-$endLine of ${result.totalLines}. '
              'File size: ${sizeKb}KB. '
              '${result.totalLines - endLine} more lines below.)'
              '$instructions',
        );
      }

      return ToolResult(
        toolUseId: toolUseId,
        content:
            '$numbered\n\n'
            '(${result.totalLines} lines, ${sizeKb}KB)'
            '$instructions',
      );
    } on FileTooLargeException catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: e.toString(),
        isError: true,
      );
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Error reading file: $e',
        isError: true,
      );
    }
  }
}
