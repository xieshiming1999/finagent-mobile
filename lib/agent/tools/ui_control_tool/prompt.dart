const description = 'Control the app UI: pages, tiles, inline widgets.';

const prompt =
    '''Control the app UI to display data, manage pages/tiles, or show inline widgets.

## Page actions (HTML pages rendered in WebView panel)
- addPage: Register an HTML file in the page list (does NOT open it).
  params: {file: "memory/pages/xxx.html", title?, tag?}
- openPage: Open a page in the WebView panel. If not registered yet, auto-registers it.
  params: {file: "memory/pages/xxx.html", title: "页面标题"} (always pass title)
  Returns: {ok, id, title, webViewMode: "split", fileExists, fileSize}
- closePage: Close the WebView panel (hide it). params: {}
- removePage: Remove a page from the list. params: {id}

EXAMPLE — create and show a K-line chart:
```json
// Step 1: Agent writes HTML file via FileWrite to memory/pages/maotai_kline.html
// Step 2: Open it in WebView
{"action": "openPage", "params": {"title": "茅台K线", "file": "memory/pages/maotai_kline.html"}}
```

## Tile actions (persistent UI elements in the tile grid)
- createTile: Create a new tile with an optional auto-update task.
  params: {id?, title, type (quote|chart|table|monitor|custom), data?, prompt?, schedule?}
  - type: MUST be "quote" for stock quotes, "monitor" for monitoring, "chart" for charts.
  - prompt: The instruction to refresh this tile. MUST include the tile ID and updateTile call.
  - schedule: Auto-update interval: "30s", "1m", "5m", "1h". Required for monitoring.
  - data: Initial data to display immediately.

- updateTile: Update a tile's data. params: {id, data?, title?, type?}
- removeTile: Remove a tile and stop its auto-update. params: {id}

## Inline actions (rendered inside the chat flow)
- showQuote: Show a stock quote card inline. params: {data: {ts_code, name, close, pct_change, ...}}
- showTable: Show a data table inline. params: {title, columns, rows}
- showChart: Show a K-line candlestick chart inline. params: {dataFile: "path/to/kline.json"}
  The dataFile must be a JSON file in Tushare format: {"columns": [...], "data": [[...], ...]}
  Agent writes the data file via FileWrite first, then calls showChart.
- showHtml: Show HTML content inline. params: {html: "<div>...</div>"}

## Guidelines
- **Prefer inline actions** (showChart/showTable/showQuote/showHtml) — they display directly in chat without switching screens.
- Only use openPage when user explicitly requests a standalone page, or when complex multi-chart interaction is needed.
- For K-line charts: FileWrite JSON → showChart (inline, no screen switch). dataFile must be JSON, NOT HTML.
- For complex HTML visualizations (multi-chart interaction, custom dashboards): FileWrite HTML → openPage
- For persistent data displays: use tiles (createTile with schedule for auto-update)
- For one-off quick answers: use inline actions (showQuote/showTable)
- NEVER draw charts in markdown/ASCII — always use showChart or openPage
- Page file path is relative to basePath (e.g. "memory/pages/xxx.html")
- Common mistake: writing HTML + openPage to display a simple K-line chart. Use showChart instead.
- **HTML must be self-contained**: All JS/CSS must be inlined in the HTML file (inside <script>/<style> tags). NEVER reference external CDN URLs — the device may not have internet access. Write chart rendering logic directly in the HTML using Canvas/SVG or inline a charting library.''';
