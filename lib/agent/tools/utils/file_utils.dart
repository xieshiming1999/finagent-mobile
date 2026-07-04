import 'dart:io';
import 'package:path/path.dart' as p;

/// Shared utility functions for file tools.
/// Reference: claude-code-best/src/utils/file.ts, readFileInRange.ts, path.ts

/// Max file size for read operations (256 KB).
const int maxReadSizeBytes = 256 * 1024;

/// Default max lines for a read without explicit limit.
const int defaultMaxLines = 2000;

/// Max file size for edit operations (1 GiB).
const int maxEditFileSize = 1024 * 1024 * 1024;

/// Result of reading a file range.
class FileReadResult {
  final String content;
  final int lineCount;
  final int totalLines;
  final int totalBytes;
  final int mtimeMs;

  const FileReadResult({
    required this.content,
    required this.lineCount,
    required this.totalLines,
    required this.totalBytes,
    required this.mtimeMs,
  });
}

/// Add line numbers to content, matching Claude Code's addLineNumbers().
///
/// Format: "     1\tline content" (6-char right-padded number + tab).
/// Reference: claude-code-best/src/utils/file.ts addLineNumbers()
String addLineNumbers(String content, {int startLine = 1}) {
  if (content.isEmpty) return '';
  final lines = content.split('\n');
  return lines
      .asMap()
      .entries
      .map((entry) {
        final lineNum = entry.key + startLine;
        final numStr = lineNum.toString();
        final padded = numStr.length >= 6 ? numStr : numStr.padLeft(6);
        return '$padded\t${entry.value}';
      })
      .join('\n');
}

/// Read a file in a specified line range.
///
/// [offset] is 0-indexed start line.
/// [limit] is max number of lines to read (null = read up to [defaultMaxLines]).
/// [maxBytes] is max file size in bytes (null = no limit).
///
/// Reference: claude-code-best/src/utils/readFileInRange.ts
FileReadResult readFileInRange(
  String path,
  int offset, [
  int? limit,
  int? maxBytes,
]) {
  final file = File(path);
  final stat = file.statSync();
  final totalBytes = stat.size;
  final mtimeMs = stat.modified.millisecondsSinceEpoch;

  if (maxBytes != null && totalBytes > maxBytes) {
    throw FileTooLargeException(path, totalBytes, maxBytes);
  }

  final raw = file.readAsStringSync();
  // Strip BOM and normalize line endings
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final content = normalized.startsWith('\uFEFF')
      ? normalized.substring(1)
      : normalized;

  final allLines = content.split('\n');
  // Remove trailing empty line from split if file ends with newline
  final totalLines = content.endsWith('\n') && allLines.last.isEmpty
      ? allLines.length - 1
      : allLines.length;

  final effectiveLimit = limit ?? defaultMaxLines;
  final startIdx = offset.clamp(0, allLines.length);
  final endIdx = (startIdx + effectiveLimit).clamp(0, allLines.length);
  final selectedLines = allLines.sublist(startIdx, endIdx);

  return FileReadResult(
    content: selectedLines.join('\n'),
    lineCount: selectedLines.length,
    totalLines: totalLines,
    totalBytes: totalBytes,
    mtimeMs: mtimeMs,
  );
}

/// Normalize a file path, resolving relative paths against basePath.
///
/// Security: ensures the resolved path is within basePath (sandbox enforcement).
/// Reference: claude-code-best/src/utils/path.ts expandPath()
String normalizePath(String filePath, String basePath) {
  final trimmed = filePath.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('file_path cannot be empty');
  }

  String resolved;
  if (p.isAbsolute(trimmed)) {
    resolved = p.normalize(trimmed);
  } else {
    resolved = p.normalize(p.join(basePath, trimmed));
  }

  // Sandbox enforcement: path must be within basePath
  final normalizedBase = p.normalize(basePath);
  if (!_isSameOrInside(resolved, normalizedBase)) {
    throw PathSecurityException(resolved, normalizedBase);
  }

  return resolved;
}

/// Check if a path is in the bundle/ directory (read-only, writes rejected).
bool isInBundleDir(String path, String basePath) {
  final bundleDir = p.normalize(p.join(basePath, 'bundle'));
  return _isSameOrInside(path, bundleDir);
}

/// Check if a path is in the memory/ directory (writes skip permission).
bool isInMemoryDir(String path, String basePath) {
  final memoryDir = p.normalize(p.join(basePath, 'memory'));
  return _isSameOrInside(path, memoryDir);
}

bool _isSameOrInside(String candidate, String parent) {
  final normalizedCandidate = p.normalize(candidate);
  final normalizedParent = p.normalize(parent);
  return p.equals(normalizedCandidate, normalizedParent) ||
      p.isWithin(normalizedParent, normalizedCandidate);
}

/// Find a similar file in the same directory (different extension).
///
/// Reference: claude-code-best/src/utils/file.ts findSimilarFile()
String? findSimilarFile(String path) {
  final dir = Directory(p.dirname(path));
  if (!dir.existsSync()) return null;

  final baseName = p.basenameWithoutExtension(path);
  try {
    for (final entity in dir.listSync()) {
      if (entity is File) {
        final name = p.basenameWithoutExtension(entity.path);
        if (name == baseName && entity.path != path) {
          return entity.path;
        }
      }
    }
  } catch (_) {
    // Directory not readable
  }
  return null;
}

/// Get the modification time of a file in milliseconds since epoch.
int getFileModificationTime(String path) {
  return File(path).statSync().modified.millisecondsSinceEpoch;
}

/// Convert an absolute path to a path relative to basePath.
String toRelativePath(String absolutePath, String basePath) {
  final relativePath = p.relative(absolutePath, from: basePath);
  return relativePath.startsWith('..') ? absolutePath : relativePath;
}

/// Exception for files exceeding the size limit.
class FileTooLargeException implements Exception {
  final String path;
  final int actualSize;
  final int maxSize;

  FileTooLargeException(this.path, this.actualSize, this.maxSize);

  @override
  String toString() =>
      'File $path is too large ($actualSize bytes, max $maxSize bytes). '
      'Use offset and limit to read a portion.';
}

/// Exception for path security violations (escaping sandbox).
class PathSecurityException implements Exception {
  final String path;
  final String basePath;

  PathSecurityException(this.path, this.basePath);

  @override
  String toString() =>
      'Path "$path" is outside the allowed directory "$basePath".';
}
