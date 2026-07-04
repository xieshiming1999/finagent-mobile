const description = 'Update a task status, details, or dependencies.';

const prompt = '''Update a task's status, details, or dependencies.

Usage:
- Set status to "in_progress" when starting work on a task.
- Set status to "completed" when done.
- Set status to "deleted" to permanently remove a task.
- Use addBlocks/addBlockedBy to set up task dependencies.
- Only mark a task as completed when you have FULLY accomplished it.''';
