---
description: Multi-agent collaboration workflow for building a specialist research team that works in parallel and produces one synthesized decision.
when_to_use: User asks for comprehensive analysis, team-based analysis, multi-angle research, or a deep structured report.
---

# Multi-Agent Team

## Team roles

| Role | Responsibility | Main data dependency |
|---|---|---|
| Data collector | Pull all required raw inputs | `MarketData` + `Research` |
| Technical analyst | Read trend, indicators, and chart structure | `DataProcess` |
| Fundamental analyst | Review financials, valuation, and growth | `earnings` + scoring logic |
| Risk analyst | Review risk, ST flags, and validation stress | `st-risk` + `backtest` |
| Decision manager | Combine all outputs into one final recommendation | all of the above |

## Execution flow

### Step 1: Create the team

```text
TeamCreate(name: "research_team", agents: [
  {role: "data", description: "data collection"},
  {role: "tech", description: "technical analysis"},
  {role: "fundamental", description: "fundamental analysis"},
  {role: "risk", description: "risk control"}
])
```

### Step 2: Shared data collection

The data collector should use the governed data interface path first, then
perform requirement-level refreshes only for missing, stale, or insufficient
local evidence.

```text
MarketData(action: "interfaces", category: "stock")
MarketData(action: "interface_describe", interfaceId: "stock.quote")
MarketData(action: "interface_availability", interfaceId: "stock.quote", symbols: ["600519"])
MarketData(action: "coverage", symbols: ["600519"])
MarketData(action: "query_quote", symbols: ["600519"])
MarketData(action: "query_kline", symbols: ["600519"])
MarketData(action: "query_fundamental", symbols: ["600519"])
# If cache/readback is missing or stale:
MarketData(action: "quote", symbols: ["600519"])
MarketData(action: "kline", symbols: ["600519"])
MarketData(action: "earnings", symbols: ["600519"])
MarketData(action: "flow", symbols: ["600519"])
Research(action: "news", query: "Moutai")
```

### Step 3: Parallel specialist analysis

```text
Agent(description: "technical analyst",
  prompt: "You are the technical analyst. Score the chart setup, trend, key levels, pattern structure, price-volume behavior, and give a 100-point technical score. Data:\n<data>")

Agent(description: "fundamental analyst",
  prompt: "You are the fundamental analyst. Review profitability, growth, valuation, ROE, PEG, and assign an investment rating. Data:\n<data>")

Agent(description: "risk analyst",
  prompt: "You are the risk analyst. Review ST risk, industry risk, valuation risk, technical risk signals, and propose a stop-loss level. Data:\n<data>")
```

### Step 4: Final synthesis

After all specialist outputs are available:
1. extract scores and key findings
2. combine them with weights, for example technical 40%, fundamental 35%, risk 25%
3. produce the final rating and concrete action plan
4. generate a report if needed

## Difference from Alpha Arena

| Dimension | Multi-Agent Team | Alpha Arena |
|---|---|---|
| Goal | division of labor | competitive comparison |
| Angles | different domains such as technical, fundamental, and risk | similar problem, different frameworks or personas |
| Output | one synthesized conclusion | multiple independent conclusions plus a comparison table |
| Best use | deep work on one symbol | quick multi-view challenge or cross-check |

## Lightweight version

If you do not need a formal team object, run a few parallel agents directly:

```text
Agent(description:"technical", prompt:"...")
Agent(description:"fundamental", prompt:"...")
Agent(description:"risk", prompt:"...")
```

The `Agent` tool supports parallel execution in this simplified path as well.
