/// Short description for LLM function calling.
const description = 'Creates or overwrites a file with the given content.';

/// Full instructions for the LLM.
const prompt = '''Creates or overwrites a file with the given content.

Usage:
- For existing files, you MUST use the Read tool first before writing. This tool will fail if you have not read the file first.
- For complete replacement of a generated memory artifact such as `memory/pages/*.html` or `memory/dashboards/*.html`, pass `overwrite:true` instead of first probing with a failing write.
- Prefer the Edit tool for modifying existing files — it only sends the diff.
- Only use this tool for creating new files or complete rewrites.
- Files in bundle/ are read-only and cannot be written. Write to memory/ instead.
- Parent directories will be created automatically if they don't exist.''';
