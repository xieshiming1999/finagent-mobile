import 'dart:io';
import 'package:glob/glob.dart' as globpkg;
import 'package:path/path.dart' as p;

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../utils/file_utils.dart';
import 'prompt.dart' as tool_prompt;

/// File pattern matching tool using glob patterns.
///
/// Pure Dart implementation using the `glob` package.
/// Reference: claude-code-best/src/tools/GlobTool/GlobTool.ts
class GlobTool extends Tool {
  static const int _maxResults = 100;

  @override
  String get name => 'Glob';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'pattern': {
        'type': 'string',
        'description': 'The glob pattern to match files against',
      },
      'path': {
        'type': 'string',
        'description':
            'The directory to search in. Defaults to the agent\'s base directory.',
      },
    },
    'required': ['pattern'],
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
    final pattern = input['pattern'] as String?;
    if (pattern == null || pattern.trim().isEmpty) {
      return 'pattern is required.';
    }

    final searchPath = input['path'] as String?;
    if (searchPath != null) {
      try {
        final resolved = normalizePath(searchPath, context.basePath);
        if (!Directory(resolved).existsSync()) {
          return 'Directory not found: $searchPath';
        }
      } on PathSecurityException catch (e) {
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
    final pattern = input['pattern'] as String;
    final searchPath = input['path'] as String?;
    final searchDir = searchPath != null
        ? normalizePath(searchPath, context.basePath)
        : context.basePath;

    try {
      final glob = globpkg.Glob(pattern);
      // The Dart glob package's ** doesn't match at root level,
      // so we also create a root-only pattern when pattern starts with **/
      final rootGlob = pattern.startsWith('**/')
          ? globpkg.Glob(pattern.substring(3))
          : null;
      final matches = <_FileWithMtime>[];

      // List all files recursively and match against glob pattern
      final dir = Directory(searchDir);
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;

        final relativePath = p.relative(entity.path, from: searchDir);
        // Skip hidden directories
        if (relativePath.split(p.separator).any((s) => s.startsWith('.'))) {
          continue;
        }

        if (glob.matches(relativePath) ||
            (rootGlob != null && rootGlob.matches(relativePath))) {
          try {
            final stat = entity.statSync();
            matches.add(
              _FileWithMtime(
                path: entity.path,
                mtimeMs: stat.modified.millisecondsSinceEpoch,
              ),
            );
          } catch (_) {
            // Skip files we can't stat
          }
        }
      }

      if (matches.isEmpty) {
        return ToolResult(toolUseId: toolUseId, content: 'No files found');
      }

      // Sort by modification time, most recent first
      matches.sort((a, b) => b.mtimeMs.compareTo(a.mtimeMs));

      final truncated = matches.length > _maxResults;
      final results = matches.take(_maxResults).toList();

      // Convert to relative paths
      final filenames = results
          .map((m) => toRelativePath(m.path, context.basePath))
          .toList();

      var output = filenames.join('\n');
      if (truncated) {
        output +=
            '\n\n(Showing $_maxResults of ${matches.length} matches. '
            'Consider using a more specific path or pattern.)';
      } else {
        output += '\n\n(${matches.length} matches)';
      }

      return ToolResult(toolUseId: toolUseId, content: output);
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Error searching files: $e',
        isError: true,
      );
    }
  }
}

class _FileWithMtime {
  final String path;
  final int mtimeMs;

  _FileWithMtime({required this.path, required this.mtimeMs});
}
