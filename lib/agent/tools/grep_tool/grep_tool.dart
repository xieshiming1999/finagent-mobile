import 'dart:io';
import 'dart:math' show min, max;
import 'package:glob/glob.dart' as globpkg;
import 'package:path/path.dart' as p;

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../utils/file_utils.dart';
import 'prompt.dart' as tool_prompt;

/// Content search tool using Dart regular expressions.
///
/// Pure Dart implementation replacing ripgrep.
/// Reference: claude-code-best/src/tools/GrepTool/GrepTool.ts
class GrepTool extends Tool {
  static const int _defaultHeadLimit = 250;

  /// Directories to always skip.
  static const _skipDirs = {'.git', '.svn', '.hg', '.bzr', '__pycache__'};

  @override
  String get name => 'Grep';

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
        'description': 'The regular expression pattern to search for',
      },
      'path': {
        'type': 'string',
        'description':
            'File or directory to search in. Defaults to the agent\'s base directory.',
      },
      'glob': {
        'type': 'string',
        'description': 'Glob pattern to filter files (e.g. "*.dart")',
      },
      'output_mode': {
        'type': 'string',
        'enum': ['content', 'files_with_matches', 'count'],
        'description': 'Output mode (default: "files_with_matches")',
      },
      '-i': {'type': 'boolean', 'description': 'Case insensitive search'},
      '-n': {
        'type': 'boolean',
        'description':
            'Show line numbers in output (default true, content mode only)',
      },
      '-B': {
        'type': 'integer',
        'description': 'Number of lines to show before each match',
      },
      '-A': {
        'type': 'integer',
        'description': 'Number of lines to show after each match',
      },
      '-C': {
        'type': 'integer',
        'description': 'Number of context lines before and after each match',
      },
      'head_limit': {
        'type': 'integer',
        'description':
            'Limit output entries (default 250, pass 0 for unlimited)',
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

    // Validate regex
    try {
      RegExp(pattern);
    } on FormatException catch (e) {
      return 'Invalid regex pattern: ${e.message}';
    }

    final searchPath = input['path'] as String?;
    if (searchPath != null) {
      try {
        normalizePath(searchPath, context.basePath);
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
    final globFilter = input['glob'] as String?;
    final outputMode = input['output_mode'] as String? ?? 'files_with_matches';
    final caseInsensitive = input['-i'] as bool? ?? false;
    final showLineNumbers = input['-n'] as bool? ?? true;
    final beforeContext = input['-B'] as int?;
    final afterContext = input['-A'] as int?;
    final contextLines = input['-C'] as int?;
    final headLimit = input['head_limit'] as int? ?? _defaultHeadLimit;

    final searchDir = searchPath != null
        ? normalizePath(searchPath, context.basePath)
        : context.basePath;

    try {
      final regex = RegExp(pattern, caseSensitive: !caseInsensitive);

      // Determine context line counts
      final ctxBefore = contextLines ?? beforeContext ?? 0;
      final ctxAfter = contextLines ?? afterContext ?? 0;

      // Collect files to search
      final files = await _collectFiles(searchDir, globFilter);

      switch (outputMode) {
        case 'content':
          return _searchContent(
            toolUseId,
            files,
            regex,
            context.basePath,
            showLineNumbers: showLineNumbers,
            beforeCtx: ctxBefore,
            afterCtx: ctxAfter,
            headLimit: headLimit,
          );
        case 'count':
          return _searchCount(
            toolUseId,
            files,
            regex,
            context.basePath,
            headLimit: headLimit,
          );
        case 'files_with_matches':
        default:
          return _searchFilesWithMatches(
            toolUseId,
            files,
            regex,
            context.basePath,
            headLimit: headLimit,
          );
      }
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Error searching: $e',
        isError: true,
      );
    }
  }

  /// Collect all files to search, applying glob filter and skipping hidden dirs.
  Future<List<File>> _collectFiles(String searchDir, String? globFilter) async {
    final entity = FileSystemEntity.typeSync(searchDir);
    if (entity == FileSystemEntityType.file) {
      return [File(searchDir)];
    }

    final dir = Directory(searchDir);
    final files = <File>[];
    final globMatcher = globFilter != null ? globpkg.Glob(globFilter) : null;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;

      // Skip hidden directories and known skip dirs
      final parts = p.relative(entity.path, from: searchDir).split(p.separator);
      if (parts.any((s) => s.startsWith('.') || _skipDirs.contains(s))) {
        continue;
      }

      // Apply glob filter
      if (globMatcher != null) {
        final relativePath = p.relative(entity.path, from: searchDir);
        if (!globMatcher.matches(relativePath)) continue;
      }

      // Skip binary files (simple heuristic: check first 512 bytes for null)
      try {
        final raf = entity.openSync();
        try {
          final bytes = raf.readSync(512);
          if (bytes.contains(0)) continue; // likely binary
        } finally {
          raf.closeSync();
        }
      } catch (_) {
        continue;
      }

      files.add(entity);
    }

    return files;
  }

  /// files_with_matches mode: return list of matching file paths sorted by mtime.
  ToolResult _searchFilesWithMatches(
    String toolUseId,
    List<File> files,
    RegExp regex,
    String basePath, {
    required int headLimit,
  }) {
    final matches = <_FileWithMtime>[];

    for (final file in files) {
      try {
        final content = file.readAsStringSync();
        if (regex.hasMatch(content)) {
          final stat = file.statSync();
          matches.add(
            _FileWithMtime(
              path: file.path,
              mtimeMs: stat.modified.millisecondsSinceEpoch,
            ),
          );
        }
      } catch (_) {
        // Skip unreadable files
      }
    }

    if (matches.isEmpty) {
      return ToolResult(toolUseId: toolUseId, content: 'No matches found');
    }

    // Sort by mtime descending (most recent first)
    matches.sort((a, b) => b.mtimeMs.compareTo(a.mtimeMs));

    final effectiveLimit = headLimit == 0 ? matches.length : headLimit;
    final truncated = matches.length > effectiveLimit;
    final results = matches.take(effectiveLimit).toList();

    final filenames = results
        .map((m) => toRelativePath(m.path, basePath))
        .toList();

    var output = 'Found ${matches.length} file(s)\n${filenames.join('\n')}';
    if (truncated) {
      output +=
          '\n\n(Showing $effectiveLimit of ${matches.length} matching files)';
    }

    return ToolResult(toolUseId: toolUseId, content: output);
  }

  /// content mode: return matching lines with optional context.
  ToolResult _searchContent(
    String toolUseId,
    List<File> files,
    RegExp regex,
    String basePath, {
    required bool showLineNumbers,
    required int beforeCtx,
    required int afterCtx,
    required int headLimit,
  }) {
    final outputLines = <String>[];
    var lineCount = 0;
    var matchCount = 0;
    var fileMatchCount = 0;
    final effectiveLimit = headLimit == 0 ? -1 : headLimit;

    for (final file in files) {
      if (effectiveLimit > 0 && lineCount >= effectiveLimit) break;

      try {
        final content = file.readAsStringSync();
        final lines = content.split('\n');
        final relativePath = toRelativePath(file.path, basePath);

        // Find matching line indices
        final matchingIndices = <int>[];
        for (var i = 0; i < lines.length; i++) {
          if (regex.hasMatch(lines[i])) {
            matchingIndices.add(i);
          }
        }

        if (matchingIndices.isEmpty) continue;

        matchCount += matchingIndices.length;
        fileMatchCount++;

        // Build set of lines to show (including context)
        final linesToShow = <int>{};
        for (final idx in matchingIndices) {
          final start = max(0, idx - beforeCtx);
          final end = min(lines.length - 1, idx + afterCtx);
          for (var i = start; i <= end; i++) {
            linesToShow.add(i);
          }
        }

        final sortedLines = linesToShow.toList()..sort();

        // Output file header and matching lines
        var prevLine = -2;
        for (final idx in sortedLines) {
          if (effectiveLimit > 0 && lineCount >= effectiveLimit) break;

          // Add separator for non-contiguous blocks
          if (prevLine >= 0 && idx > prevLine + 1) {
            outputLines.add('--');
            lineCount++;
          }

          final lineNum = idx + 1;
          if (showLineNumbers) {
            outputLines.add('$relativePath:$lineNum:${lines[idx]}');
          } else {
            outputLines.add('$relativePath:${lines[idx]}');
          }
          lineCount++;
          prevLine = idx;
        }
      } catch (_) {
        // Skip unreadable files
      }
    }

    if (outputLines.isEmpty) {
      return ToolResult(toolUseId: toolUseId, content: 'No matches found');
    }

    final truncated = effectiveLimit > 0 && lineCount >= effectiveLimit;
    var output = outputLines.join('\n');
    output +=
        '\n\n($matchCount matches across $fileMatchCount files'
        '${truncated ? ', output truncated at $effectiveLimit lines' : ''})';

    return ToolResult(toolUseId: toolUseId, content: output);
  }

  /// count mode: return match counts per file.
  ToolResult _searchCount(
    String toolUseId,
    List<File> files,
    RegExp regex,
    String basePath, {
    required int headLimit,
  }) {
    final counts = <String>[];
    var totalMatches = 0;
    var fileCount = 0;
    final effectiveLimit = headLimit == 0 ? -1 : headLimit;

    for (final file in files) {
      if (effectiveLimit > 0 && counts.length >= effectiveLimit) break;

      try {
        final content = file.readAsStringSync();
        final matches = regex.allMatches(content).length;
        if (matches > 0) {
          final relativePath = toRelativePath(file.path, basePath);
          counts.add('$relativePath:$matches');
          totalMatches += matches;
          fileCount++;
        }
      } catch (_) {
        // Skip unreadable files
      }
    }

    if (counts.isEmpty) {
      return ToolResult(toolUseId: toolUseId, content: 'No matches found');
    }

    final output =
        '${counts.join('\n')}\n\nFound $totalMatches total match(es) across $fileCount file(s).';

    return ToolResult(toolUseId: toolUseId, content: output);
  }
}

class _FileWithMtime {
  final String path;
  final int mtimeMs;

  _FileWithMtime({required this.path, required this.mtimeMs});
}
