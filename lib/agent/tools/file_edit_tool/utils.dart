// Edit utility functions.
// Reference: claude-code-best/src/tools/FileEditTool/utils.ts

/// Apply an edit to file content by replacing old_string with new_string.
///
/// When [newString] is empty (deletion), if [oldString] doesn't end with '\n'
/// but oldString + '\n' exists in the file, strips the trailing newline too.
/// This prevents leaving blank lines when deleting a line.
///
/// Uses a function replacement `() => replace` to prevent $ backreference
/// interpretation in the replacement string.
///
/// Reference: claude-code-best applyEditToFile()
String applyEdit(
  String originalContent,
  String oldString,
  String newString, {
  bool replaceAll = false,
}) {
  if (replaceAll) {
    if (newString.isNotEmpty) {
      return originalContent.replaceAll(oldString, newString);
    }
    // Deletion with replaceAll
    final withTrailingNewline = '$oldString\n';
    if (!oldString.endsWith('\n') &&
        originalContent.contains(withTrailingNewline)) {
      return originalContent.replaceAll(withTrailingNewline, newString);
    }
    return originalContent.replaceAll(oldString, newString);
  }

  // Single replacement
  if (newString.isNotEmpty) {
    return _replaceFirst(originalContent, oldString, newString);
  }

  // Deletion: strip trailing newline when deleting
  final withTrailingNewline = '$oldString\n';
  if (!oldString.endsWith('\n') &&
      originalContent.contains(withTrailingNewline)) {
    return _replaceFirst(originalContent, withTrailingNewline, newString);
  }
  return _replaceFirst(originalContent, oldString, newString);
}

/// Replace first occurrence without $ backreference interpretation.
String _replaceFirst(String content, String search, String replace) {
  final idx = content.indexOf(search);
  if (idx == -1) return content;
  return content.substring(0, idx) +
      replace +
      content.substring(idx + search.length);
}

/// Build a snippet showing context around the edit.
///
/// Returns the snippet with [contextLines] lines before and after the edit,
/// along with the 1-indexed start line number.
///
/// Reference: claude-code-best getSnippet()
({String snippet, int startLine}) getSnippet(
  String originalFile,
  String oldString,
  String newString, {
  int contextLines = 4,
}) {
  final before = originalFile.split(oldString)[0];
  final replacementLine = before.split('\n').length - 1;

  final newFile = applyEdit(originalFile, oldString, newString);
  final newFileLines = newFile.split('\n');

  final startLine = (replacementLine - contextLines).clamp(
    0,
    newFileLines.length,
  );
  final endLine =
      (replacementLine + contextLines + newString.split('\n').length).clamp(
        0,
        newFileLines.length,
      );

  final snippetLines = newFileLines.sublist(startLine, endLine);
  return (snippet: snippetLines.join('\n'), startLine: startLine + 1);
}

/// Find the actual string in the file, trying exact match first,
/// then falling back to curly-to-straight quote normalization.
///
/// Returns the actual substring from [fileContent] that matches, or null.
///
/// Reference: claude-code-best findActualString()
String? findActualString(String fileContent, String searchString) {
  // 1. Exact match
  if (fileContent.contains(searchString)) {
    return searchString;
  }

  // 2. Quote normalization: curly → straight
  final normalizedFile = _normalizeQuotes(fileContent);
  final normalizedSearch = _normalizeQuotes(searchString);

  final idx = normalizedFile.indexOf(normalizedSearch);
  if (idx != -1) {
    // Extract the actual string from the original file at the same index
    return fileContent.substring(idx, idx + searchString.length);
  }

  return null;
}

/// Normalize curly quotes to straight quotes.
String _normalizeQuotes(String s) {
  return s
      .replaceAll('\u2018', "'") // left single curly
      .replaceAll('\u2019', "'") // right single curly
      .replaceAll('\u201C', '"') // left double curly
      .replaceAll('\u201D', '"'); // right double curly
}

/// Count occurrences of a substring in a string.
int countOccurrences(String content, String substring) {
  if (substring.isEmpty) return 0;
  int count = 0;
  int index = 0;
  while (true) {
    index = content.indexOf(substring, index);
    if (index == -1) break;
    count++;
    index += substring.length;
  }
  return count;
}
