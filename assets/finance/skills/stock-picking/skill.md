---
description: Stock-picking framework for candidate discovery, valuation/ROE screening, scoring, ranking, and actionable recommendations
when_to_use: Use when the user asks for stock ideas, shortlist generation, opportunity discovery, valuation/quality screens, PE/PB/ROE filters, or “what is worth watching / buying”
---
# Stock Picking

Load `analysis-standards` before producing a shortlist. Its Finance Output Standard governs the final answer: separate facts, calculations, inferences, recommendations, assumptions, and unverified items, and retain source/as-of time, fetch/ingest time, fields used, method/tool action, quality/confidence note, and readback status.

## Core idea

Stock picking has three layers:
1. discover candidates
2. score and rank them
3. output actionable recommendations

The goal is not to find *matching* stocks. The goal is to find stocks with the best risk-adjusted opportunity.

For broad shortlist prompts, do not start with code-specific technical
analysis. Discover candidates through governed MarketData readback/screening
first, then run technical analysis only after candidate codes are selected or
the user asks for one-stock validation.

For broad prompts without explicit stock codes, do **not** call
`DataProcess(action:"screen")` first. `DataProcess(screen)` requires a concrete
`codes` list. First get candidate codes from governed `MarketData` readbacks
such as `query_hot_rank`, `query_sector_ranking`, `query_flow_rank`, or a
provider-specific candidate interface, then optionally use `DataProcess(screen,
codes:[...])` on that bounded candidate set.

When the user asks to make an observation dashboard, treat the dashboard as the
output surface and put candidate reasons, source time, retrieved time,
observation conditions, risks, and data gaps into the dashboard content.
Do not mutate Watchlist in the same turn unless the user explicitly asks to add
the candidates to a watchlist, observation pool, or self-selected list.

## Provenance gate

Before live discovery or validation, check the governed interface and local
readback state for the data family you plan to use. Normal mobile stock-picking
workflow is:

```json
MarketData(action: "interfaces", category: "stock")
MarketData(action: "interface_describe", interfaceId: "market.hot_rank")
MarketData(action: "interface_availability", interfaceId: "market.hot_rank")
MarketData(action: "query_hot_rank", limit: 20)
MarketData(action: "query_quote", symbols: ["600519"])
MarketData(action: "query_kline", symbols: ["600519"], limit: 120)
MarketData(action: "data_health", section: "failures", limit: 5)
```

Use live `MarketData` refresh actions only when the relevant interface is
missing, stale, or explicitly requested. If `data_health` or
`interface_availability` says a provider is gated, disabled, unsupported, or
temporarily blocked, do not route around it with a provider-direct example.

## Layer 1: candidate discovery

Use 1-3 sources depending on the user’s intent. Do not run everything by default.

### 1. Sector rotation
Good for: “what is hot recently?”

```json
MarketData(action: "query_sector_ranking", limit: 20)
MarketData(action: "query_index_quote", symbols: ["000001"])
MarketData(action: "sector", boardType: "industry")
MarketData(action: "sector", boardType: "concept")
```

For broad market context, use local/readback index quote actions with explicit
index codes such as `000001`, `399001`, `399006`, or `000300`. Do not call a
broad index refresh without a code; replace it with local index quote readback
or an explicit index-specific refresh.

If `query_sector_ranking` or an equivalent board-ranking readback says cached
rows look like non-sector instruments, treat sector/board evidence as
unavailable. Do not reuse option, IPO, bond, or single-stock rows as sector
rotation evidence.

### 2. Unusual movers
Good for: “what is moving today?”

Use screening / technical summaries on liquid movers with strong price, turnover, and volume behavior.

### 3. Money-flow signal
Good for: “what is smart money buying?”

```json
MarketData(action: "query_money_flow", symbols: ["<leader>"])
MarketData(action: "flow", symbols: ["<leader>"])
```

### 4. Technical breakout scan

Check candidates for:
- breakout above recent highs
- bullish moving-average alignment
- volume-confirmed strength
- high relative strength

### 5. Fundamental quality
Good for: “what are the better value / quality names?”

Typical checks:
- reasonable PE / PB
- ROE strength
- revenue and profit growth
- no obvious accounting / audit warning

For PE/ROE or valuation screens, read governed local evidence first and keep
the workflow bounded. If the local daily-valuation / fundamental readback is
empty, or the screening result says PE, PB, ROE, or similar fields are `0/N`,
`no-values`, or `-`, stop and disclose it as a valuation data coverage gap.
Do not call a selected-code fundamental refresh as if it were a full-market
valuation refresh.
Do not use raw Tushare, code-specific `query_fundamental`, quote-only data, or
`DataProcess(screen)` without candidate codes to recover from a full-market
valuation coverage gap.

When PE/PB valuation fields are missing or shown as `-`, state a clear
valuation-data gap: name the missing fields, the interface/readback where the
gap appeared, and avoid presenting a precise valuation range from unavailable
PE/PB data.
Use this exact sentence when the basic-fundamental interface shows PE/PB as
missing: `估值数据缺失：基本面接口中 PE、PB 字段显示为 “-”，本次未获取到有效估值指标。`
If the gap is from a local readback, also state:
`本地基本面读回中 PE、PB 字段为空，无法给出精确估值区间。`
Do not replace that sentence with weaker wording.
When ROE or other screening fields are also missing, add that broader limitation
after the PE/PB gap instead of replacing it.

### 6. Event-driven ideas
Good for: “any news-driven opportunities?”

```json
Research(action: "news", query: "earnings beat increase holding institutional research")
```

### 7. Historical learning

Use prior reflections and validation results as a correction layer:
- reward setups that historically worked
- downgrade setups that repeatedly failed in similar conditions

## Layer 2: scoring

Before scoring each candidate, prefer local reusable evidence:

```json
MarketData(action: "interface_availability", interfaceId: "stock.quote")
MarketData(action: "query_quote", symbols: ["600519"])
MarketData(action: "query_kline", symbols: ["600519"], limit: 120)
MarketData(action: "query_money_flow", symbols: ["600519"], limit: 20)
MarketData(action: "query_fundamental", symbols: ["600519"], limit: 8)
```

For a strategy-selection shortlist, do not add single-stock technical
diagnostics as a second ranking layer. Use the `strategy-system` skill and
`MarketData(custom_strategy_rank)` so the selected candidate, score, portfolio
evidence, and trade boundary come from one governed strategy contract.

A typical 100-point structure:

### Technical (40)
- trend
- volume/price behavior
- momentum
- pattern quality

### Fundamentals (30)
- profitability
- valuation
- growth

### Money flow (20)
- sustained inflow
- chip / holder structure where available

### Catalyst (10)
- recent positive news
- sentiment / market attention

## Layer 3: actionable output

For each top pick, include:
- why it made the list
- current setup quality
- buy zone
- stop / invalidation
- target
- suggested position size
- whether it is buy-now or watchlist-first

Example shape:

```text
1. 000858 Wuliangye — Buy | score 82
- Why: strong trend, solid fundamentals, stable inflow
- Buy zone: 158-162
- Stop: 148
- Target: 185
- Size: 15%
- Status: buyable now on pullback support
```

If entry is not ready yet, say so clearly and put it into watchlist mode rather than pretending it is ready.

## Workflow expectation

1. discover 10-30 candidates
2. score them consistently
3. keep the final recommendation list short
4. provide execution-ready guidance, not just ratings
5. if appropriate, add the best names to `Watchlist`

## Anti-patterns

- do not recommend a long list with no execution guidance
- do not call something “undervalued” from PE alone
- do not skip `interface_availability` / `data_health` when a provider has recent failure, gated, or unsupported evidence
- do not skip `MarketData(query_*)` and re-fetch blindly
- do not call a selected-code fundamental refresh as an all-market PE/ROE refresh
- do not spend extra tool calls confirming a valuation coverage gap after the screening/readback result already proves it
- do not run code-specific technical analysis before candidate codes are selected
- do not recommend overextended momentum names without checking pullback risk
- do not ignore existing portfolio concentration
- do not present a candidate as high-conviction if you skipped technical or fundamental validation
