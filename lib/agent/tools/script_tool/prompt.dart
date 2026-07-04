const description =
    'Execute JavaScript code in a sandboxed QuickJS runtime with unified Bridge API.';

const prompt = '''Execute JavaScript in a sandboxed QuickJS runtime.

IMPORTANT: Do NOT use XMLHttpRequest, fetch(), or any async HTTP — they will NOT work.
Use Bridge.fetch/get/post for ALL HTTP requests (they support both internal and external URLs).

## Available Bridge API:

### HTTP
- Bridge.fetch(url, params?, method?) — HTTP request (sync, pre-fetched before execution)
- Bridge.get(url, options?) — GET request
- Bridge.post(url, body?) — POST request
- Bridge.put(url, body?) — PUT request
- Bridge.delete(url, options?) — DELETE request
- Bridge.getConfig(key) — read API key from user config

### File System
- Bridge.readFile(path) — read file content as string
- Bridge.writeFile(path, content) — write string to file
- Bridge.listDir(path?) — list directory [{name, type}]
- Bridge.fileExists(path) — check if file/dir exists
- Bridge.fileStat(path) — get {size, modified, type}

### Data Processing
- Bridge.parseCSV(text, sep?) / Bridge.toCSV(arr, sep?)
- Bridge.base64Encode/Decode(text)
- Bridge.hexEncode/Decode(text)
- Bridge.hash(text, algo?) — sha256 (default) / sha1 / sha512 / md5

### Statistics
- Bridge.sum(arr), Bridge.avg(arr), Bridge.median(arr)
- Bridge.groupBy(arr, key), Bridge.unique(arr), Bridge.sortBy(arr, key, desc?)
- Bridge.flatten(arr)

### Agent Communication
- Bridge.sendToAgent(msg, data?) — send message to Agent
- Bridge.notify(msg, severity?) — notify user
- Bridge.alert(msg) — alert notification

## Not available in Script (use Monitor or WebView):
- Bridge.ws(...) — Monitor only (WebSocket)
- Bridge.sendToMonitor / Bridge.onPush — Monitor and WebView only
- Bridge.getState / Bridge.setState — WebView only

All HTTP calls are synchronous (pre-fetched before execution). Both literal URLs and variable URLs work:
  const data = Bridge.get('https://api.example.com/quote?code=600519');
  const url = 'https://api.example.com/quote?code=600519';
  const data = Bridge.fetch(url);

Backward-compatible global aliases are available (e.g., `callService()`, `readFile()`, `sum()`).
Return a value from your script — it will be JSON-serialized and returned to you.

Use this tool to:
- Fetch and process data from any HTTP API
- Read/write files in the agent's workspace
- Test API endpoints before writing Monitor/Dashboard scripts
- Prototype data processing logic
- Validate Bridge.getConfig keys''';
