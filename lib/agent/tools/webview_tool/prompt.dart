const webViewToolPrompt =
    '''Interact with a WebView browser embedded in the app.

Actions:
- query: Execute JavaScript and return the result. Use `javascript` for custom JS code.
  If `selector` is also given, the selected element is available as `el` in your JS.
  Example: {"action":"query", "javascript":"document.title"}
  Example: {"action":"query", "selector":".price", "javascript":"el.textContent"}

- click: Click an element by CSS selector. {"action":"click", "selector":"button.submit"}

- input: Type text into an input field. The field is focused, cleared, then filled.
  {"action":"input", "selector":"input[name=search]", "text":"crude oil"}

- screenshot: Capture the current WebView as a PNG image for visual analysis.
  For generated HTML dashboards/pages, verify readable content with query,
  get_info, get_html, selectors, and page text first. Use screenshots for
  visual-only questions such as chart pixels, canvas rendering, layout overlap,
  or image/crop inspection.
  {"action":"screenshot"}

- navigate: Load a URL or local file. Local paths (starting with / or memory/)
  are loaded via loadHtmlString. {"action":"navigate", "url":"https://example.com"}
  {"action":"navigate", "url":"memory/dashboard.html"}

- back / forward / reload: Browser navigation controls. `reload` refreshes the
  current WebView document and may reuse the loaded data/html snapshot.
  {"action":"back"}
  {"action":"reload"}

- refresh: Re-read the active file-backed dashboard/page from disk when the
  feature supports it. Use this after editing `memory/pages/*.html` or
  `memory/dashboards/*.html`. For URL/search pages, use reload instead.
  {"action":"refresh"}

- get_info: Return current URL, page title, and viewport dimensions.
  {"action":"get_info"}

- get_html: Capture the full page HTML and cleaned text, save to files.
  Returns metadata (URL, title, file paths, sizes) + first 500 chars preview.
  Use this to read page content instead of screenshot when text is sufficient.
  {"action":"get_html"}

- scroll: Scroll the page. Use `absolute:true` to scroll to a position, or omit for relative scroll.
  {"action":"scroll", "x":0, "y":500}

- wait_for: Wait for a CSS selector to appear in the DOM (polls every 500ms).
  {"action":"wait_for", "selector":".chart-loaded", "timeout":10000}

Parameters:
- target (optional): WebView name. Omit to use the active WebView.
  Available targets depend on the feature. Common ones:
  - "design": Main preview WebView for design output.
  - "search": Hidden browser for web search. Navigate to a search engine
    (e.g. bing.com/search?q=...), wait for results, then query to extract
    titles/links/snippets.
- selector: CSS selector for click/input/query/wait_for.
- javascript: JS code for query action.
- text: Text to type for input action.
- url: URL for navigate action.
- x, y: Scroll coordinates (integers).
- absolute: If true, scroll to position; if false, scroll by offset (default false).
- timeout: Milliseconds for wait_for (default 5000).

This tool provides generic WebView interaction. For site-specific workflows,
load the relevant skill first to get selectors and navigation patterns.

JS Bridge: HTML pages loaded in the WebView have a Bridge object for
communicating with the agent. See AGENTS.md Bridge API section for details.
Common: Bridge.sendToAgent(msg), Bridge.notify(msg), Bridge.fetch(url).''';
