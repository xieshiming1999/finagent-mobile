const description =
    'Execute JavaScript code in a sandboxed environment with unified Bridge API.';

const prompt =
    '''Execute JavaScript code in a JS sandbox for data computation, transformation, and analysis.

## Available Bridge API:

### HTTP (all environments)
- Bridge.fetch(url, params?, method?) — HTTP request (sync in Script/Monitor, async in WebView)
- Bridge.get(url, options?) — GET request
- Bridge.post(url, body?) — POST request
- Bridge.put(url, body?) — PUT request
- Bridge.delete(url, options?) — DELETE request

### File System (Script / Monitor only)
- Bridge.readFile(path) — read file content as string
- Bridge.writeFile(path, content) — write string to file
- Bridge.listDir(path?) — list directory contents, returns [{name, type}, ...]
- Bridge.fileExists(path) — check if file/directory exists, returns true/false
- Bridge.fileStat(path) — get file metadata, returns {size, modified, type}

### Data Processing (all environments)
- Bridge.parseCSV(text, separator?) — parse CSV text to 2D array
- Bridge.toCSV(array, separator?) — convert 2D array to CSV string
- Bridge.parseXML(text) — parse XML to JSON tree {tag, attrs?, text?, children?}
- Bridge.base64Encode(text) / Bridge.base64Decode(text)
- Bridge.hexEncode(text) / Bridge.hexDecode(text)
- Bridge.hash(text, algorithm?) — compute hash digest (sha256/sha1/sha512/md5, default sha256)

### Statistics (all environments)
- Bridge.sum(arr), Bridge.avg(arr), Bridge.median(arr)
- Bridge.groupBy(arr, keyOrFn) — group array of objects by key or function
- Bridge.unique(arr) — deduplicate array
- Bridge.sortBy(arr, key, desc?) — sort array of objects by key
- Bridge.flatten(arr) — recursive flatten nested arrays

### Agent Communication (all environments)
- Bridge.sendToAgent(msg, data?) — send message to Agent
- Bridge.notify(msg, severity?) — notify user
- Bridge.alert(msg) — alert notification
- Bridge.getConfig(key) — get app configuration value

### Standard JS
- JSON.parse/stringify, Math, Date, Array, Object, RegExp
- console.log/error/warn (captured and returned)

## Backward compatibility:
Global aliases are available for file/data/stats functions (e.g., `readFile()` works, but `Bridge.readFile()` is preferred).

## Not available in Script (use Monitor or WebView instead):
- `Bridge.ws(...)` — Monitor only (WebSocket registration)
- `Bridge.sendToMonitor(...)` / `Bridge.onPush(...)` — Monitor and WebView only
- `Bridge.getState/setState` — WebView only (per-dashboard state)

## Not available:
- fetch, XMLHttpRequest (use Bridge.fetch instead)
- require, import (no modules)
- DOM, window, document (no browser APIs)

## Output:
The last expression in your code is the return value. Use JSON.stringify() for structured results.

## Example:
```javascript
const raw = Bridge.readFile("memory/stock_data.json");
const data = JSON.parse(raw);
const prices = data.map(d => d.close);
JSON.stringify({
  avg: Bridge.avg(prices),
  median: Bridge.median(prices),
  max: Math.max(...prices),
  count: prices.length
});
```

## Guidelines:
- Use for computations that are too complex for the LLM to do inline.
- File paths are relative to the agent base directory (e.g., "memory/data.json").
- bundle/ directory is read-protected — use Bridge.readFile on memory/ files only.
- Keep scripts focused — one computation per call.
''';
