import 'dart:io';

import '../../message.dart';
import '../../security_scan.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../../file_history.dart';
import '../utils/file_utils.dart';
import 'prompt.dart' as tool_prompt;

/// Creates or overwrites a file with given content.
///
/// Reference: claude-code-best/src/tools/FileWriteTool/FileWriteTool.ts
class FileWriteTool extends Tool {
  @override
  String get name => 'Write';

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
        'description': 'The path to the file to write',
      },
      'content': {
        'type': 'string',
        'description': 'The content to write to the file',
      },
      'overwrite': {
        'type': 'boolean',
        'description':
            'Set true only when intentionally replacing an existing generated memory artifact such as memory/pages/*.html or memory/dashboards/*.html.',
      },
    },
    'required': ['file_path', 'content'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) {
    final filePath = input['file_path'] as String? ?? '';
    return !(filePath == 'memory' ||
        filePath.startsWith('memory/') ||
        filePath.contains('/memory/'));
  }

  @override
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final filePath = input['file_path'] as String?;
    if (filePath == null || filePath.trim().isEmpty) {
      return 'file_path is required.';
    }
    if (!input.containsKey('content')) {
      return 'content is required.';
    }

    String resolved;
    try {
      resolved = normalizePath(filePath, context.basePath);
    } on PathSecurityException catch (e) {
      return e.toString();
    } on ArgumentError catch (e) {
      return e.message as String;
    }

    // Agent can only write under memory/
    final isMemoryPath =
        filePath.startsWith('memory/') ||
        isInMemoryDir(resolved, context.basePath);
    if (!isMemoryPath) {
      return 'Files must be written under memory/. '
          'Example: memory/pages/xxx.html, memory/skills/xxx/skill.md. '
          'Got: $filePath (resolved to: $resolved)';
    }

    // Bundle write protection
    if (isInBundleDir(resolved, context.basePath)) {
      return 'bundle/ is read-only. Write to memory/ instead.';
    }

    final overwrite = input['overwrite'] == true;
    final isGeneratedArtifact =
        filePath.startsWith('memory/pages/') ||
        filePath.startsWith('memory/dashboards/');

    // For existing files: enforce read-before-write and staleness checks unless
    // the caller explicitly declares a complete generated artifact replacement.
    final file = File(resolved);
    if (file.existsSync() && !overwrite && !isGeneratedArtifact) {
      // Read-before-write enforcement
      if (!context.readFileTimestamps.containsKey(resolved)) {
        return 'File has not been read yet. Read it first before writing to it.';
      }

      // Staleness detection
      final readTimestamp = context.readFileTimestamps[resolved]!;
      final currentMtime = file.statSync().modified.millisecondsSinceEpoch;
      if (currentMtime > readTimestamp) {
        return 'File has been modified since it was last read. '
            'Read it again before writing.';
      }
    }
    // New files skip both checks

    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final filePath = input['file_path'] as String;
    final content = input['content'] as String;
    final resolved = normalizePath(filePath, context.basePath);

    try {
      final file = File(resolved);
      final isNewFile = !file.existsSync();

      // Snapshot before overwrite
      if (!isNewFile) {
        snapshotBeforeWrite(resolved, context.basePath);
      }

      // Create parent directories
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }

      // Write file content (UTF-8, LF)
      file.writeAsStringSync(content);

      // Update read timestamp
      context.readFileTimestamps[resolved] = file
          .statSync()
          .modified
          .millisecondsSinceEpoch;

      // Security warning for memory files (write succeeds but warns)
      final securityWarning = resolved.contains('/memory/')
          ? SecurityScan.describeRisk(content)
          : null;
      final warnSuffix = securityWarning != null
          ? '\n\n⚠️ Security warning: $securityWarning'
          : '';

      final bytesWritten = file.lengthSync();
      final lineCount = '\n'.allMatches(content).length + 1;
      final sizeKb = (bytesWritten / 1024).toStringAsFixed(1);

      if (isNewFile) {
        return ToolResult(
          toolUseId: toolUseId,
          content:
              'File created: $filePath ($lineCount lines, ${sizeKb}KB)$warnSuffix',
        );
      }

      return ToolResult(
        toolUseId: toolUseId,
        content:
            'File updated: $filePath ($lineCount lines, ${sizeKb}KB)$warnSuffix',
      );
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Error writing file: $e',
        isError: true,
      );
    }
  }
}
