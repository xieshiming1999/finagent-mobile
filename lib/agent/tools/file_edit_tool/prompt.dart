/// Short description for LLM function calling.
const description = 'Performs exact string replacements in files.';

/// Full instructions for the LLM.
const prompt = '''Performs exact string replacements in files.

Usage:
- You must use the Read tool at least once before editing a file.
- The old_string must match exactly once in the file (unless replace_all is true).
- If old_string is empty and the file does not exist, a new file will be created with new_string as content.
- If new_string is empty, the matched text will be deleted.
- The edit will FAIL if old_string is not unique in the file. Provide more surrounding context to make it unique, or use replace_all.
- Use replace_all for renaming variables or replacing repeated strings across the file.
- Files in bundle/ are read-only and cannot be edited. Write to memory/ instead.''';
