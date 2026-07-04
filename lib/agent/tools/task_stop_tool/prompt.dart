const description = 'Stop a running background task.';

const prompt = '''Stops a running background sub-agent task by its ID.

Usage:
- Provide the task_id of a running background task.
- The task must be in "running" status.
- The sub-agent will be cancelled and its status set to "killed".''';
