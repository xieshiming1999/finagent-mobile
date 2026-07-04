/// Short description for LLM function calling.
const description = 'Fast file pattern matching using glob patterns.';

/// Full instructions for the LLM.
const prompt =
    '''Fast file pattern matching tool that finds files by name patterns.

Usage:
- Supports glob patterns like "**/*.md" or "skills/**/*.dart".
- Returns matching file paths sorted by modification time (most recent first).
- Results are capped at 100 files. Use a more specific pattern if truncated.
- The path parameter specifies the directory to search in (defaults to the agent's base directory).
- Paths must be within the agent's sandbox directory.''';
