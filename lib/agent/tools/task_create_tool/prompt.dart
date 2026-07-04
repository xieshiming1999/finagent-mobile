const description = 'Create a new task to track work progress.';

const prompt = '''Create a task to track your work progress.

Usage:
- Use this to break down complex work into discrete steps.
- Provide a brief subject and a description of what needs to be done.
- Optionally set activeForm (present continuous, e.g. "Analyzing AAPL") for status display.
- Tasks start with status "pending".
- Mark tasks as in_progress when you start working, completed when done (via TaskUpdate).''';
