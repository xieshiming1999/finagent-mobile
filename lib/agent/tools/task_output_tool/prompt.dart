const description =
    'Retrieve output from a running or completed background task.';

const prompt = '''Retrieves output from a background sub-agent task.

Usage:
- Use block: true (default) to wait for the task to complete.
- Use block: false to check current status without waiting.
- timeout defaults to 600 seconds (max 600 seconds).
- Returns the task's status, result, and progress information.''';
