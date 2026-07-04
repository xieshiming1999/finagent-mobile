import 'dart:io';

import '../../message.dart';
import '../../security_scan.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../../file_history.dart';
import '../utils/file_utils.dart';
import 'prompt.dart' as tool_prompt;
import 'utils.dart' as edit_utils;

/// Search-and-replace edit tool.
///
/// Reference: claude-code-best/src/tools/FileEditTool/FileEditTool.ts
class FileEditTool extends Tool {
  @override
  String get name => 'Edit';

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
        'description': 'The path to the file to modify',
      },
      'old_string': {
        'type': 'string',
        'description':
            'The text to replace (must match exactly once, '
            'unless replace_all is true)',
      },
      'new_string': {'type': 'string', 'description': 'The replacement text'},
      'replace_all': {
        'type': 'boolean',
        'description': 'Replace all occurrences of old_string (default false)',
      },
    },
    'required': ['file_path', 'old_string', 'new_string'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) {
    final filePath = input['file_path'] as String? ?? '';
    // Will be checked properly in validateInput, but we can do a quick check
    // This method is called before validateInput so we use a simple heuristic
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
    final oldString = input['old_string'] as String? ?? '';
    final newString = input['new_string'] as String? ?? '';
    final replaceAll = input['replace_all'] as bool? ?? false;

    if (filePath == null || filePath.trim().isEmpty) {
      return 'file_path is required.';
    }

    // 1. No-op check
    if (oldString == newString) {
      return 'old_string and new_string are identical. No changes to make.';
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
      return 'Files must be edited under memory/. '
          'Example: memory/pages/xxx.html, memory/skills/xxx/skill.md. '
          'Got: $filePath (resolved to: $resolved)';
    }

    // Bundle write protection
    if (isInBundleDir(resolved, context.basePath)) {
      return 'bundle/ is read-only. Write to memory/ instead.';
    }

    final file = File(resolved);
    final fileExists = file.existsSync();

    // 2 & 3. Empty old_string = file creation
    if (oldString.isEmpty) {
      if (fileExists) {
        // Only allow if file is empty
        final content = file.readAsStringSync();
        if (content.trim().isNotEmpty) {
          return 'Cannot create new file — file already exists at $filePath. '
              'To edit, provide old_string to match existing content.';
        }
      }
      // File doesn't exist or is empty — creation OK
      return null;
    }

    // 4. File doesn't exist but old_string is non-empty
    if (!fileExists) {
      final similar = findSimilarFile(resolved);
      final suggestion = similar != null ? ' Did you mean: $similar?' : '';
      return 'File not found: $filePath.$suggestion';
    }

    // 5. (skip .ipynb check on mobile)

    // Check file size
    final stat = file.statSync();
    if (stat.size > maxEditFileSize) {
      return 'File is too large to edit (${stat.size} bytes, max $maxEditFileSize bytes).';
    }

    // 6. Read-before-write enforcement
    if (!context.readFileTimestamps.containsKey(resolved)) {
      return 'File has not been read yet. Read it first before editing.';
    }

    // 7. Staleness detection
    final readTimestamp = context.readFileTimestamps[resolved]!;
    final currentMtime = stat.modified.millisecondsSinceEpoch;
    if (currentMtime > readTimestamp) {
      return 'File has been modified since it was last read. '
          'Read it again before editing.';
    }

    // Read file content for string matching
    final fileContent = file.readAsStringSync();

    // 8. String not found (with quote normalization fallback)
    final actualString = edit_utils.findActualString(fileContent, oldString);
    if (actualString == null) {
      return 'old_string not found in file. '
          'Make sure it matches the file content exactly.';
    }

    // 9. Multiple matches without replace_all
    if (!replaceAll) {
      final occurrences = edit_utils.countOccurrences(
        fileContent,
        actualString,
      );
      if (occurrences > 1) {
        return 'old_string appears $occurrences times in the file. '
            'Add more surrounding context to make it unique, '
            'or set replace_all to true.';
      }
    }

    // 10. All checks passed
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final filePath = input['file_path'] as String;
    final oldString = input['old_string'] as String? ?? '';
    final newString = input['new_string'] as String? ?? '';
    final replaceAll = input['replace_all'] as bool? ?? false;
    final resolved = normalizePath(filePath, context.basePath);

    try {
      final file = File(resolved);

      // Handle file creation (empty old_string)
      if (oldString.isEmpty) {
        final parent = file.parent;
        if (!parent.existsSync()) {
          parent.createSync(recursive: true);
        }
        file.writeAsStringSync(newString);
        context.readFileTimestamps[resolved] = file
            .statSync()
            .modified
            .millisecondsSinceEpoch;
        final lineCount = '\n'.allMatches(newString).length + 1;
        final sizeKb = (file.lengthSync() / 1024).toStringAsFixed(1);
        return ToolResult(
          toolUseId: toolUseId,
          content: 'File created: $filePath ($lineCount lines, ${sizeKb}KB)',
        );
      }

      // Read current content
      final originalContent = file.readAsStringSync();

      // Snapshot before edit
      snapshotBeforeWrite(resolved, context.basePath);

      // Find actual string (may differ due to quote normalization)
      final actualOldString =
          edit_utils.findActualString(originalContent, oldString) ?? oldString;

      // Build snippet before applying edit (for result display)
      final snippetResult = edit_utils.getSnippet(
        originalContent,
        actualOldString,
        newString,
      );

      // Apply the edit
      final updatedContent = edit_utils.applyEdit(
        originalContent,
        actualOldString,
        newString,
        replaceAll: replaceAll,
      );

      // Write updated content
      file.writeAsStringSync(updatedContent);
      context.readFileTimestamps[resolved] = file
          .statSync()
          .modified
          .millisecondsSinceEpoch;

      // Format result with line numbers
      final numberedSnippet = addLineNumbers(
        snippetResult.snippet,
        startLine: snippetResult.startLine,
      );

      final replaceCount = replaceAll
          ? edit_utils.countOccurrences(originalContent, actualOldString)
          : 1;
      final replaceAllNote = replaceAll
          ? ' (replaced $replaceCount occurrences)'
          : '';

      // Security warning for memory files
      final securityWarning = resolved.contains('/memory/')
          ? SecurityScan.describeRisk(newString)
          : null;
      final warnSuffix = securityWarning != null
          ? '\n\n⚠️ Security warning: $securityWarning'
          : '';

      final totalLines = '\n'.allMatches(updatedContent).length + 1;
      final lineDelta =
          '\n'.allMatches(newString).length -
          '\n'.allMatches(actualOldString).length;
      final deltaStr = lineDelta > 0 ? '+$lineDelta' : '$lineDelta';

      return ToolResult(
        toolUseId: toolUseId,
        content:
            'File updated: $filePath$replaceAllNote '
            '($totalLines lines, $deltaStr lines changed). '
            "Snippet:\n$numberedSnippet$warnSuffix",
      );
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Error editing file: $e',
        isError: true,
      );
    }
  }
}
