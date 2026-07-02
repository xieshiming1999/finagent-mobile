---
description: Stock analysis and dashboard workflows for A-shares, HK stocks, and US stocks
when_to_use: Use when the user asks about stock quotes, technical analysis, K-line review, financial data, stock comparison, or wants a stock dashboard / technical panel / heat map
---

# Stock Analysis Skill

## Data sources

### 1. MarketData first

Before quote, kline, backtest, or chart work on a stock, inspect the governed interface first, then check reusable local data:

```json
MarketData(action: "interfaces", category: "stock", limit: 20)
MarketData(action: "interface_describe", interfaceId: "stock.quote")
MarketData(action: "interface_availability", interfaceId: "stock.quote")
MarketData(action: "data_health")
MarketData(action: "coverage", symbols: ["600519"])
MarketData(action: "query_api_calls", source: "eastmoney", minutes: 30)
MarketData(action: "query_quote", symbols: ["600519"])
MarketData(action: "query_kline", symbols: ["600519"], startDate: "2024-01-01")
```

Only fetch fresh data when local data is missing or stale:

```json
MarketData(action: "quote", symbols: ["600519"])
MarketData(action: "kline", symbols: ["600519"], period: "daily", startDate: "2024-01-01")
```

For parameter optimization requests, keep the route short and explicit:

```json
MarketData(action: "coverage", symbols: ["600519"])
MarketData(action: "query_kline", symbols: ["600519"], period: "daily", startDate: "2021-06-28", endDate: "2026-06-28", limit: 1300)
MarketData(action: "optimize_params", symbols: ["600519"], strategy: "rsi", period: "5y", paramGrid: {"period":[10,14,20], "oversold":[25,30,35], "overbought":[65,70,75]})
```

If the local K-line readback already covers the requested window, do not spend
extra live `kline` calls before optimization. Report both requested window and
actual data window in the final answer.

For China A-shares, quote / kline routing is:
local SQLite -> TDX -> EastMoney / Sina / Tencent fallback.

Keep the returned `source` visible in analysis output. Do not use Yahoo / yfinance for China A-shares.
If quote/K-line/sector calls fail, inspect `data_health`, then `query_api_calls` before retrying.
Do not repeat invalid-parameter, quota/rate-limit, or repeated socket-reset
failures; switch to local rows, TDX, or a more targeted EastMoney REST-only
dataset.

### 2. AkShare / WebFetch as supplement

Use AkShare only when `MarketData` does not already cover the needed dataset. Do not bypass local cache and normal provider routing for ordinary quote / kline work.

### 3. TradingView Scanner

Load the `tradingview-scanner` skill when you need live technical indicators such as RSI, MACD, Bollinger Bands, moving averages, ADX, or rating summaries.

### 4. TradingView visualization

Before generating stock dashboards, technical panels, or dynamic market pages, load:

```text
Skill(skill: "tradingview")
```

On mobile, TradingView is an enhancement layer only. Critical prices, K-line data, scoring, alerts, and persistence must still come from `MarketData`, `DataProcess`, and local reusable data.

## Analysis workflow

### Single-stock analysis

1. `interfaces` / `interface_describe` / `interface_availability`
2. `coverage` / `query_quote` / `query_kline` to reuse local data first
3. `quote` / `kline` only when fresh data is needed
4. TradingView Scanner for live technical overlays
5. Answer normal analysis requests in Markdown/text, not fenced or inline HTML.
   If the user asks for a rendered card, dashboard, panel, or page in FinAgent,
   prefer a compact app-native UI surface:
   `Write` a small JSON data file under `memory/data/`, then call
   `UIControl(action:"showChart", params:{dataFile:"memory/data/..."})` for
   K-line evidence and `UIControl(action:"showTable", ...)` for compact
   valuation/flow summaries. Do not generate a large standalone HTML dashboard
   from a template unless the user explicitly asks for a custom page.

When `DataProcess(action:"summary")`, `DataProcess(action:"support_summary")`,
or `DataProcess(action:"volume")` returns `analysisEvidence`, use that
`analysis-evidence-v1` object as the stock-analysis contract. Report
`observedFacts`, `interpretations`, `missingEvidence`, `confidence`, and
`sourceCoverage`. Do not treat `strategyReadiness:"analysis_only"` as a
validated StrategySpec, backtest, monitor, watchlist rule, or trade plan.

When a bounded stock-candidate workflow returns
`analysisEvidence.kind:"candidate_research"` with
`strategyReadiness:"candidate"`, treat it as an observation shortlist only.
Use the listed candidates, missing evidence, and source coverage directly; do
not present it as a buy recommendation, validated StrategySpec, monitor rule,
watchlist mutation, or trade action until the user selects a candidate and a
separate contract validates the next step.

When valuation evidence is part of the analysis, distinguish available metrics
from missing metrics:

- If PE/PB are present, show them with source and data/retrieval time when the
  tool result provides it.
- If PE/PB are absent or shown as `-`, explicitly state a valuation-data gap:
  name the missing fields, the interface/readback where the gap appeared, and
  avoid presenting a precise valuation range from unavailable PE/PB data.
  Use this exact sentence when the basic-fundamental interface shows PE/PB as
  missing: `估值数据缺失：基本面接口中 PE、PB 字段显示为 “-”，本次未获取到有效估值指标。`
  If the gap is from a local readback, also state:
  `本地基本面读回中 PE、PB 字段为空，无法给出精确估值区间。`
  Do not replace that sentence with weaker wording.
- Do not collapse a PE/PB-only gap into a generic "basic fundamentals missing"
  statement when other fundamental rows are available.
- In stock dashboards and dashboard refresh summaries, always state the
  valuation status explicitly: either report PE/PB with source/time, or state
  the PE/PB gap with source/time and consequence.

### Sector analysis

1. fetch sector lists
2. fetch constituents where needed
3. summarize technical condition across the leaders

### Single-stock K-line pattern questions

For single-stock K-line pattern intents, keep the workflow daily and
local-first:

```text
MarketData(action:"query_kline", symbol:"600519", limit:120)
DataProcess(action:"pattern_summary", symbol:"600519", period:"daily")
MarketData(action:"query_quote", symbol:"600519")
```

If `pattern_summary` returns no patterns, say that no code-owned pattern was
detected and explain the limitation. Do not invent candlestick patterns, and do
not add separate `pattern`, `trend`, `indicators`, `support`, broad market, or
live provider calls unless the user asks for a deeper follow-up or local K-line
readback is empty.

For strategy-selection, strategy-candidate scoring, or “which watchlist symbol
fits this strategy” intents, use the `strategy-system` skill and the governed
`MarketData(custom_strategy_rank)` / backtest actions. Single-stock technical
diagnostics are not the evidence source for strategy ranking or portfolio
drafts.

### Market-wide money-flow routing

When the intent is market-wide capital flow rather than analysis of one
specified stock, use the `market-overview` skill. Prefer a compact
local-readback pass:

```text
MarketData(action:"query_flow_rank", limit:20)
MarketData(action:"query_sector_ranking", limit:20)
MarketData(action:"query_northbound_flow", limit:10)
```

Stop after those local readbacks and answer with source/provider, data time,
retrieval time when present, and coverage gaps. Do not add hot rank, limit
pool, screening, dragon tiger, or per-stock `flow` / `query_money_flow` unless
the user asks for deeper follow-up or the core readbacks are empty.

### Market-wide unusual-activity routing

When the intent is market-wide unusual-activity discovery rather than analysis
of one specified stock, use the `market-overview` skill. Prefer a compact
local-readback pass:

```text
MarketData(action:"query_unusual", limit:20)
MarketData(action:"query_limit_pool", limit:30)
MarketData(action:"query_hot_rank", limit:20)
```

Use `MarketData(action:"query_flow_rank", limit:20)` only as one additional
corroborating list. Do not call broad `query_quote`; quote readback requires
explicit symbols. Stop after the above readbacks and answer with source/provider,
data time, retrieval time when present, and coverage gaps.

## Dashboard templates

Templates live in `bundle/dashboards/`.

| Template | Path                                      | Best for                            |
| -------- | ----------------------------------------- | ----------------------------------- |
| chart    | `bundle/dashboards/chart/template.html`   | K-line, moving average, MACD panels |
| table    | `bundle/dashboards/table/template.html`   | watchlists, ranking tables          |
| kpi      | `bundle/dashboards/kpi/template.html`     | market overview KPI cards           |
| monitor  | `bundle/dashboards/monitor/template.html` | price alerts and threshold views    |

### Dashboard creation flow

For FinAgent stock analysis, use the lightweight inline path first:

```text
Write(file_path:"memory/data/maotai_kline.json", content:"{\"columns\":[\"date\",\"open\",\"high\",\"low\",\"close\",\"volume\"],\"data\":[...]}")
UIControl(action:"showChart", params:{"dataFile":"memory/data/maotai_kline.json"})
UIControl(action:"showTable", params:{"title":"估值与资金证据","data":[...]})
```

Keep the JSON compact: latest 60-120 daily bars are enough for a chart. Put
the full analysis, provenance, PE/PB gap, and risk judgment in the final chat
answer instead of embedding a large HTML report.

Use the file-backed HTML page path only for custom standalone pages:

1. `readFile('bundle/dashboards/<type>/template.html')`
2. modify `{{TITLE}}` and `CONFIG`
3. `writeFile('memory/dashboards/xxx.html', content)`
4. `UIControl addPage {file: "memory/dashboards/xxx.html", title: "..."}`
5. `UIControl openPage {file: "memory/dashboards/xxx.html"}`

If the file is already open and you edit it, use `WebView(action: "refresh")`.
Use `WebView(action: "query")` or `UIControl pushData` for runtime-only updates.

### Dashboard data rule

Dashboards should consume data prepared through `MarketData`, `DataProcess`,
local reusable rows, or app bridge routes. Do not embed public provider URLs in
dashboard HTML for normal quote/K-line workflows.

## Presentation rules

- Do not put raw `<div>`, `<table>`, or fenced ```html blocks in a normal chat
  answer. Chat Markdown is not the rendering surface for app dashboards.
- Rendered HTML belongs in `memory/dashboards/` or `memory/pages/` and must be
  opened via the supported UIControl/Dashboard/WebView flow.
- default dark theme: `#131722`
- China market color convention: up `#ef5350`, down `#26a69a`
- write dashboard files into `memory/dashboards/`
- A-share codes are 6 digits, for example `000001`, `600519`
- HK stock codes are 5 digits, for example `00700`
