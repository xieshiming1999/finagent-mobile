---
description: Deep research report workflow for a 5 to 8 page structured equity report covering company profile, industry, financials, valuation, catalysts, and risks.
when_to_use: User asks for deep analysis, a full equity research report, a comprehensive company review, or first-time coverage of a stock.
---

# Deep Research

## Best-fit scenarios

- "Do a deep dive on XXX"
- "Write a research report on XXX"
- "I want a full understanding of this company"
- First-time coverage where the user needs a complete investment picture

## Report structure: seven sections

Before collecting data for any section, use the governed data interface path:

```text
MarketData(action: "interfaces", category: "stock")
MarketData(action: "interface_describe", interfaceId: "stock.quote")
MarketData(action: "interface_availability", interfaceId: "stock.quote", symbols: ["<code>"])
MarketData(action: "coverage", symbols: ["<code>"])
MarketData(action: "query_quote", symbols: ["<code>"])
```

Only call requirement-level refresh routes such as `quote`, `earnings`,
`sector`, or `flow` after the interface/cache/readback check says local data is
missing, stale, or insufficient. Keep provider, cache status, data time, and
fetched-at in the report.

### Part 1: Company profile

```text
MarketData(action: "query_quote", symbols: ["<code>"])
MarketData(action: "query_fundamental", symbols: ["<code>"])
# If cache/readback is missing or stale:
MarketData(action: "quote", symbols: ["<code>"])
MarketData(action: "earnings", symbols: ["<code>"])
Research(action: "search", query: "<company> core business revenue mix")
```

Include:
- one-sentence positioning statement
- key metrics card: market cap, PE, PB, ROE, revenue, net profit
- revenue mix
- competitive advantages or moat

### Part 2: Industry analysis

```text
MarketData(action: "interface_availability", interfaceId: "market.sector_ranking")
MarketData(action: "sector", symbols: ["<code>"])
Research(action: "search", query: "<industry> market size competition growth rate")
```

Include:
- industry size and growth
- competitive structure, such as CR3 or CR5 concentration
- demand, supply, and policy drivers
- company positioning inside the industry
- industry-level risks

### Part 3: Financial analysis, three-year trend

```text
MarketData(action: "query_fundamental", symbols: ["<code>"])
# If cache/readback is missing or stale:
MarketData(action: "earnings", symbols: ["<code>"])
# Pull the latest four reporting periods and analyze the trend
```

| Dimension | Focus | Healthy signal |
|---|---|---|
| Growth | 3Y CAGR for revenue and profit | Consumer >10%, tech >20% |
| Profitability | Gross margin, net margin, ROE trend | ROE >15% and stable |
| Cash quality | Operating cash flow / net profit | Greater than 0.8 |
| Asset quality | Receivables / revenue, inventory / revenue | Stable or improving |
| Financial safety | Leverage and interest coverage | Below 60% leverage outside finance |

Red-flag checks:
- revenue up but cash flow down
- profit up but gross margin down
- inventory rising sharply

### Part 4: Valuation

Load the `valuation` skill and apply its full framework:

```text
Skill(name: "valuation")
```

Include:
- DCF range
- comparable-company range
- current-price position inside the range
- final judgment: undervalued, fair, or expensive

### Part 5: Catalysts and timeline

```text
Research(action: "search", query: "<company> earnings guidance dividend buyback product launch expansion order book")
```

| Time horizon | Catalyst | Likely effect |
|---|---|---|
| Near term, within 1 month | earnings guidance, dividend plan | positive or negative |
| Medium term, 1 to 3 months | product launch, capacity ramp | usually positive |
| Longer term, 3 to 6 months | policy changes, competitor moves | uncertain |

### Part 6: Risk assessment

Review risk from three layers:

1. Company-specific risk
2. Industry risk
3. Market or positioning risk

For each risk, state:
- probability: high, medium, low
- impact: large, medium, small
- response: stop-loss or de-risking condition

### Part 7: Investment conclusion

| Dimension | Score | View |
|---|---|---|
| Fundamentals | X/10 | ... |
| Valuation | X/10 | ... |
| Technicals | X/10 | ... |
| Catalysts | X/10 | ... |
| Risk | X/10 | ... |
| Composite | XX/50 | Rating |

Rating map:
- 40 and above: Buy
- 32 and above: Accumulate
- 24 and above: Hold
- 16 and above: Reduce
- below 16: Sell

Also include:
- preferred entry range
- stop-loss level
- staged target price
- suggested position size
- timing conditions

## Dashboard report output

```text
FileRead(file_path: "bundle/dashboards/report/template.html")
-> build CONFIG sections using the seven-part structure above
-> FileWrite memory/dashboards/reports/research_<code>_<date>.html
-> UIControl addPage {file: "memory/dashboards/reports/research_<code>_<date>.html", title: "..."}
```

## Guardrails

- Cite the data source for every important claim
- End with a disclaimer
- If one section is data-limited, explicitly mark it as limited
- Use more than one valuation method
- The report should take a view, not just list facts
