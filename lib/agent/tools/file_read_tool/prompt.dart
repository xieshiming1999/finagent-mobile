/// Short description for LLM function calling.
const description = 'Reads a file from the filesystem.';

/// Full instructions for the LLM.
const prompt = '''Reads a file from the local filesystem.

Usage:
- The file_path can be absolute or relative to the agent's base directory.
- By default, it reads up to 2000 lines starting from the beginning of the file.
- You can optionally specify an offset (1-indexed line number) and limit to read a specific range.
- Results are returned with line numbers in the format: "     1\\tline content".
- **Image files** (.png, .jpg, .jpeg, .gif, .webp): Returns the image content directly for visual analysis. You can use this to view rendered PDF pages, extracted figures, or any image file.
- Files must be within the agent's sandbox directory.''';
