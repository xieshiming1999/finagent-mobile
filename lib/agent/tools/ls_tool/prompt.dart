/// Short description for LLM function calling.
const description = 'Lists files and directories in a directory tree.';

/// Full instructions for the LLM.
const prompt = '''Lists files and directories in a tree structure.

Usage:
- Provide a path to a directory to list its contents.
- Uses breadth-first traversal with indentation to show hierarchy.
- Skips hidden files (names starting with ".") and __pycache__ directories.
- Maximum 1000 entries to prevent overwhelming output.
- Paths must be within the agent's sandbox directory.''';
