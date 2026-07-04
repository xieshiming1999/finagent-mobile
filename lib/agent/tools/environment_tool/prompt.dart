const description =
    'Query runtime environment, UI state, screen info, or config values.';

const prompt = '''
Query runtime environment information.

Parameters (all optional):
- **key**: If provided, returns the API config value for this key (from Settings → API Keys).
  Omit to get full environment info.

Returns (when no key specified):
- **time**: Current date and time (ISO 8601)
- **platform**: Operating system (android, ios, macos, linux)
- **basePath**: Agent workspace root directory
- **ui**: Current UI state
  - orientation: portrait / landscape (actual current direction)
  - orientationMode: auto / portrait / landscape (lock mode set by user or agent)
  - screenWidth / screenHeight: viewport dimensions in logical pixels
  - webViewMode: hidden / split / fullscreen
  - activeDashboard: title of currently displayed dashboard (null if none)
  - activeDashboardFile: file path of current dashboard HTML
  - dashboardCount: number of dashboard items
  - backgroundTasks: number of running background WebView tasks
- **configKeys**: list of available API config key names

Use this to:
- Check screen orientation and size before generating HTML layout (single-column vs multi-column)
- Know which dashboard is displayed before modifying it
- Check available config keys before using Bridge.getConfig in scripts
- Understand UI state before making UIControl calls
''';
