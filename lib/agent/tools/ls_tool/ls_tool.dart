import 'dart:io';
import 'package:path/path.dart' as p;

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../utils/file_utils.dart';
import 'prompt.dart' as tool_prompt;

bool _isMacroResearchContentPath(String filePath) {
  return filePath.replaceAll('\\', '/').contains('/data/macro_research_content');
}

/// Lists files and directories in a tree structure.
///
/// Claude Code v1.0.3 removed standalone LS (done via Bash).
/// CC Mobile keeps it since there is no Bash on mobile.
class LSTool extends Tool {
  static const int _maxEntries = 1000;

  @override
  String get name => 'LS';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'The path to the directory to list',
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
    final dirPath = input['path'] as String?;
    if (dirPath == null || dirPath.trim().isEmpty) {
      return 'path is required.';
    }

    try {
      final resolved = normalizePath(dirPath, context.basePath);
      if (!Directory(resolved).existsSync()) {
        return 'Directory not found: $dirPath';
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
    final dirPath = input['path'] as String;
    final resolved = normalizePath(dirPath, context.basePath);
    if (_isMacroResearchContentPath(resolved)) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Macro research content artifact directories are diagnostic/source-maintenance storage. '
            'For normal macro analysis, use MarketData(action: "query_macro_research_content") '
            'and answer from contentEvidence instead of listing local artifact files.',
        isError: true,
      );
    }

    try {
      final lines = <String>[];
      var entryCount = 0;

      void listDir(String path, int depth) {
        if (entryCount >= _maxEntries) return;

        final dir = Directory(path);
        List<FileSystemEntity> entries;
        try {
          entries = dir.listSync()
            ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
        } catch (_) {
          return; // Skip unreadable directories
        }

        for (final entity in entries) {
          if (entryCount >= _maxEntries) break;

          final name = p.basename(entity.path);
          // Skip hidden files and __pycache__
          if (name.startsWith('.') || name == '__pycache__') continue;

          final indent = '  ' * depth;
          if (entity is Directory) {
            lines.add('$indent$name/');
            entryCount++;
            listDir(entity.path, depth + 1);
          } else {
            lines.add('$indent$name');
            entryCount++;
          }
        }
      }

      lines.add('${p.basename(resolved)}/');
      entryCount++;
      listDir(resolved, 1);

      if (entryCount >= _maxEntries) {
        lines.add(
          '\n(Showing $_maxEntries of $entryCount+ entries, truncated)',
        );
      } else {
        lines.add('\n($entryCount entries)');
      }

      return ToolResult(toolUseId: toolUseId, content: lines.join('\n'));
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Error listing directory: $e',
        isError: true,
      );
    }
  }
}
