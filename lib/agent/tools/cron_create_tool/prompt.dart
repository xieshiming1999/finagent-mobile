const description =
    'Schedule a prompt to run on a recurring or one-shot schedule.';

const prompt =
    '''Schedule a prompt to be executed at a future time or on a recurring schedule.

Usage:
- schedule: Supports multiple formats:
  - Standard 5-field cron: "*/5 * * * *" (every 5 min), "30 9 * * 1-5" (weekdays 9:30am)
  - Interval: "every 1 minute", "every 30 seconds", "every 2 hours"
  - Delay: "after 30 minutes", "in 1 hour"
- recurring: true (default) for repeating, false for one-shot
- durable: true to persist across app restarts, false (default) for session-only
- run_in_background: true (default) to execute without blocking the user

Note: Recurring tasks auto-expire after 7 days. Use durable: true for tasks
that should survive app restarts. Cron times are in the device's local timezone.
Maximum 50 scheduled tasks allowed.''';
