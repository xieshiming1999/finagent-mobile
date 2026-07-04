/// Short description for LLM function calling.
const description = 'Searches file contents using regular expressions.';

/// Full instructions for the LLM.
const prompt = '''Searches file contents using regular expressions.

Usage:
- Supports full Dart regex syntax (e.g., "log.*Error", "function\\s+\\w+").
- Filter files with the glob parameter (e.g., "*.dart", "**/*.md").
- Output modes:
  - "files_with_matches" (default): shows only file paths of matching files.
  - "content": shows matching lines with line numbers.
  - "count": shows match counts per file.
- Use -i for case-insensitive search.
- Use -B, -A, -C for context lines around matches (content mode only).
- Default limit is 250 results. Pass head_limit: 0 for unlimited.
- Paths must be within the agent's sandbox directory.''';
