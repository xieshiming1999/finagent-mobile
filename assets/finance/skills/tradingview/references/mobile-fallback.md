# Mobile Fallback Pattern

Mobile FinAgent dashboards must remain useful when TradingView scripts fail.

## Data Flow

1. Query reusable local data first:

```json
MarketData(action: "coverage", symbols: ["600519"])
MarketData(action: "query_quote", symbols: ["600519"])
MarketData(action: "query_kline", symbols: ["600519"], startDate: "2024-01-01")
```

2. Fetch missing data through MarketData:

```json
MarketData(action: "quote", symbols: ["600519"])
MarketData(action: "kline", symbols: ["600519"], period: "daily", startDate: "2024-01-01")
```

3. Render local quote and chart from those results.
4. Add TradingView widgets only as enhancement.

## Requirements

- Local fallback should be visible before or beside external widgets.
- If a widget fails, show "TradingView unavailable" plus the local quote/chart
  snapshot, not an empty frame.
- China/A-share local fallback visuals must use red for up/gain and green for
  down/loss. This applies to CSS variables, table classes, quote cards,
  sparklines, canvas charts, and generated legends. Do not use TradingView's
  default green-up/red-down colors for local China-market fallback content.
- Do not depend on widget load events to decide whether an alert fires.
- Long watchlists should be local tables with optional expanded TradingView
  widgets for selected symbols.
