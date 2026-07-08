---
description: Market overview workflow for broad index trends, sector heatmaps, capital-flow questions, unusual-stock questions, technical sentiment, and global market snapshots.
when_to_use: User asks for the overall market picture, index direction, sector strength, market breadth, broad market money flow, unusual-stock discovery, or a global market check.
---
# Market Overview

## Data sources

### A-share market data
Use interface-backed `MarketData` / `DataStore` workflows first. Do not build
new market-overview workflows around raw public AkShare URLs.

| Requirement | Normal workflow |
|---|---|
| Major China indices | `MarketData(action:"quote", symbols:["000001","399001","399006"])` or cached `query_quote` |
| Industry/concept board list | `MarketData(action:"sector", boardType:"industry")` and cached `query_sector` |
| Full A-share spot snapshot | local `stock_list` / quote cache first, then interface-backed quote fetches |

### TradingView Scanner for technical sentiment
Use the dedicated `tradingview-scanner` skill for bulk technical ratings:
- Index sentiment from `Recommend.All` in the `-1` to `+1` range
- Market breadth from full-market RSI distribution
- Sector technical strength from board-level average `Recommend.All`

### Yahoo Finance for the global market snapshot
Use `MarketData(action:"price", symbols:[...])` for live Yahoo/global symbols.
Do not call `MarketData(action:"quote")` for `^GSPC`, `BTC-USD`, US tickers,
HK suffixes, FX symbols, or other global symbols; `quote` is the A-share/local
provider route.

Use the Yahoo section of the `tradingview-scanner` skill:
- Global indices: `^GSPC`, `^DJI`, `^IXIC`, `^VIX`
- Crypto: `BTC-USD`, `ETH-USD`
- FX: `EURUSD=X`, `GBPUSD=X`
- ETFs: `SPY`, `QQQ`, `GLD`

### TradingView charts
TradingView widgets, heatmaps, ticker tape, scanners, and mobile fallback rules are maintained in the separate `tradingview` skill. Load `Skill(skill: "tradingview")` before building a market-overview dashboard. Global symbols commonly used here are `SSE:000001`, `SZSE:399001`, `HSI:HSI`, `NASDAQ:IXIC`, and `SP:SPX`.

### Macro/factor context

For market regime, market-cause, cross-asset, commodity, rates, country, or
index/passive-flow questions, read the governed factor layer before concluding:

```text
MarketData(action: "query_macro_factors", target: "A-shares", limit: 10)
MarketData(action: "query_macro_factors", family: "rates_liquidity", limit: 10)
MarketData(action: "query_macro_factors", regions: "Indonesia", family: "index_classification", limit: 10)
```

Keep this evidence separate from index, sector, flow, and technical evidence.
Use the row source time, fetched time, affected assets, status, and
transmission channel. If the readback returns `status:"missing"`, state that
the current factor layer has no matching macro evidence instead of assuming no
macro driver exists.

When generating a China/A-share market overview dashboard, local fallback
tables, index cards, sector/flow lists, legends, and charts must use the China
market color convention: red for up/gain and green for down/loss. TradingView
embedded widgets may keep their native palette, but local fallback HTML must
not invert China-market colors.

## Workflow

For market-wide money-flow intent, keep the first answer bounded:

1. Use `MarketData(action:"query_flow_rank", limit:20)`.
2. Add at most one rotation check with `MarketData(action:"query_sector_ranking", limit:20)`.
3. Add northbound context only if it is already local with `MarketData(action:"query_northbound_flow", limit:10)`.
4. Do not expand into hot rank, limit pool, screening, dragon tiger, or
   per-stock `flow` / `query_money_flow` unless the user asks for more detail or
   the first two readbacks are empty.
5. Answer immediately after these readbacks. State source/provider, data time,
   retrieval time when present, and coverage gaps.

For market-wide unusual-activity discovery intent, keep the first answer bounded:

1. Use `MarketData(action:"query_unusual", limit:20)`.
2. If that readback is empty, use `MarketData(action:"query_limit_pool", limit:30)`.
3. Add at most one corroborating list with `MarketData(action:"query_hot_rank", limit:20)` or `MarketData(action:"query_flow_rank", limit:20)`.
4. Do not call broad `query_quote`; quote readback requires explicit symbols.
   Do not continue into screening, dragon tiger, or live provider fetches after
   limit-pool / hot-rank / flow-rank evidence is enough for a bounded answer.
5. Answer immediately with source/provider, data time, retrieval time when
   present, and coverage gaps. If `query_unusual` is empty, state that gap and
   use limit-pool or hot-rank as proxy evidence.

For general market-overview intent, keep the first answer bounded:

1. Inspect reusable/local evidence first:
   - `MarketData(action:"interfaces", category:"index")`
   - `MarketData(action:"coverage")`
   - `DataProcess(action:"market_snapshot")` when a current snapshot exists
   - `MarketData(action:"query_index_quote", symbols:["000001","399001","399006"])`
2. If local index rows are missing, use one governed quote refresh:
   - `MarketData(action:"quote", symbols:["000001","399001","399006"])`
   - Do not try alternate raw index code formats such as `999999`, `1A0001`, `s_sh000001`, or Yahoo symbols for A-share market overview unless the user explicitly asks for provider diagnostics.
3. Add breadth/rotation only with bounded governed actions:
   - `MarketData(action:"query_sector_ranking", limit:10)` before live sector refresh.
   - If sector cache is missing, use `MarketData(action:"sector", boardType:"industry", limit:10)` once.
   - `MarketData(action:"query_flow_rank", limit:10)` before `MarketData(action:"flow_rank", limit:10)`.
4. Add exactly one first-pass macro readback when macro/rates/country/
   commodity/index/passive-flow context may explain the move:
   - broad China/A-share market question:
     `MarketData(action:"query_macro_factors", target:"A-shares", limit:10)`
   - explicit commodity/country/rates question: use the user's structured
     exposure as `target`, `regions`, or `family`.
   - Do not repeat macro readbacks with several target/family combinations in
     the first answer. If no rows match, state the macro-evidence gap.
5. Do not call WindMcp for this workflow unless `WIND_API_KEY` is configured and the user explicitly asks for Wind/professional data. If Wind returns `KEY_MISSING`, stop Wind for this turn.
6. For broad "why did the market move" or "technical plus macro" prompts, do
   not add single-symbol technical fallbacks such as
   `MarketData(action:"query_technical_indicator")`,
   `DataProcess(action:"indicators")`, `DataProcess(action:"summary")`,
   `DataProcess(action:"support")`, or `DataProcess(action:"signals")` unless
   the user explicitly asks for RSI/MACD/K-line/support details. Use index
   quote/open/high/low/close/change rows as price-action evidence. If index
   K-line or technical indicators are not already verified, state that gap
   instead of trying provider-format diagnostics for `000300`, `999999`,
   `1A0001`, `s_sh000001`, or other alternate index codes.
7. Stop after the above evidence and produce a final answer. If some evidence
   is missing or a provider fails, state the gap and source/freshness instead
   of continuing broad provider retries. Keep the first pass within roughly ten
   data calls.
8. Present the result in chat first. Create a dashboard only when the user asks for a dashboard or when the workflow explicitly needs one.

When `DataProcess(action:"market_snapshot")` returns `analysisEvidence`, use
that `analysis-evidence-v1` object as the market-analysis contract. Report
observed facts, interpretation, missing evidence, confidence, and source
coverage. Do not treat `strategyReadiness:"analysis_only"` as a validated
StrategySpec, monitor rule, or trade instruction.

When `MarketData(action:"query_sector_ranking")` or
`MarketData(action:"query_flow_rank")` returns `analysisEvidence`, use it as
sector or flow analysis evidence. Keep sector rotation and capital-flow
interpretation separate from strategy rules until a StrategySpec or monitor
contract is explicitly created.
