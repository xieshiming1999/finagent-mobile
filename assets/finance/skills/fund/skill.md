---
description: Fund NAV, ranking, holdings analysis, and dashboard workflows
when_to_use: Use when the user asks about fund NAV, ranking, holdings, performance comparison, or wants a fund dashboard / NAV comparison / holdings view
---

# Fund Analysis Skill

## Data Sources

Use the governed interface path first, then local reusable rows. Fund data that has been persisted by
Wind/Yahoo/EastMoney/AkShare paths should be queried before spending another
provider call:

```json
MarketData(action: "interfaces", category: "fund_etf", limit: 20)
MarketData(action: "interface_describe", interfaceId: "fund.nav_history")
MarketData(action: "interface_availability", interfaceId: "fund.nav_history")
MarketData(action: "data_health")
MarketData(action: "coverage")
MarketData(action: "query_fund_list", limit: 50)
MarketData(action: "query_fund_nav", symbols: ["110011.OF"], limit: 60)
MarketData(action: "query_fund_money_yield", symbols: ["000009"], limit: 60)
MarketData(action: "fund_money_yield", symbols: ["000009"])
MarketData(action: "query_api_calls", source: "eastmoney", minutes: 30)
```

If recent API errors show rate-limit, invalid parameter, or repeated transport
failure, do not retry blindly. Use cached fund rows, switch only to a configured
provider path such as Wind or EastMoney/AkShare, or ask for permission to run a
targeted refresh.

For ordinary fund selection, comparison,定投观察, or watchlist creation, stay on
the governed fund interfaces and local readbacks unless the user explicitly
asks for Wind/professional fund data or local fund evidence is insufficient. If
Wind returns a parameter, quote, credential, quota, or application error, stop
Wind for the turn and keep that failure visible rather than retrying with
guessed fields.

### Provider adapters

Fund provider endpoints are implementation details behind app-level
requirements such as fund identity, fund NAV, fund holdings, fund performance
metrics, and ETF quotes.
Use raw provider URLs only for explicit diagnostics or provider validation. For
normal analysis, use `MarketData` local queries and provider-routed app actions.
If a governed fund interface exists, prefer `interfaces`,
`interface_describe`, `interface_availability`, then `data_health`,
`coverage`, `query_*`, and requirement-level `MarketData(action: ...)`
routes before provider-direct thinking.

`fund.performance_metrics` is a governed interface on the shared contract, but
mobile/FinAgent should not advertise provider-direct performance fetches until a
native canonical writer and `query_fund_performance` readback path are present.

## Analysis Workflow

Fund Pulse and fund readback workflows are analysis surfaces. When the prompt
or tool output refers to `analysis-evidence-v1`, preserve that boundary:
report observed facts, interpretation, missing evidence, confidence, and source
coverage. Do not present fund analysis as a validated strategy, monitor rule,
定投 rule, or trade plan until a StrategySpec/watchlist/monitor contract is
created separately.

When a bounded fund-candidate workflow returns
`analysisEvidence.kind:"candidate_research"` with
`strategyReadiness:"candidate"`, treat it as an observation shortlist only.
Use the listed funds, missing evidence, and source coverage directly; do not
present it as a buy/定投 recommendation, validated StrategySpec, monitor rule,
watchlist mutation, or trade action until the user selects a fund and a
separate contract validates the next step.

### Fund screening

1. Check `interfaces` / `interface_describe` / `interface_availability` first.
2. Check `query_fund_list` and `coverage`.
3. If local rows are missing/stale, use a configured provider path
   (Wind only when its key is available, EastMoney/AkShare, or a targeted
   research bridge). Do not call
   Tushare `fund_basic` or `fund_nav`; those API names are blocked by the
   runtime for this app.
4. Sort by 1-year / 3-year return.
5. Filter for scale > 100M and age > 3 years.

### Fund comparison

1. Resolve requested fund codes with `query_fund_list`.
2. Read `query_fund_performance` when available, then read `query_fund_nav`
   for each ordinary open fund. Use the `seriesSummary` returned by
   `query_fund_nav` for bounded return and drawdown comparison before trying
   any external calculation.
3. For money funds, use `query_fund_money_yield`; they expose per-10k income
   and seven-day annualized yield, not ordinary NAV trend. If the money-yield
   cache is empty and the user asks for the fund's actual yield values, use the
   targeted `fund_money_yield` refresh for that fund only, then read it back with
   `query_fund_money_yield`. Do not retry ordinary `fund_nav` for a confirmed
   money fund just because NAV rows are empty.
4. Use `query_fund_holding` with `code`, `fundCode`, or `symbols` for each
   fund when holdings are needed. `stockCode` means a constituent-stock filter.
5. Fetch missing NAV or holding data only for funds not covered locally. If
   local NAV, performance, or holding rows already provide source time and
   fetched time for the requested funds, do not refetch them just to confirm the
   same data.
6. Once the requested funds have enough local evidence to compare category,
   NAV trend, performance, and available holdings, answer directly and state
   missing coverage instead of spending more calls on optional data.
7. Normalize and plot NAV curves only when the user asks for a chart or
   dashboard; otherwise summarize return, drawdown, style, risk, source time,
   fetched time, and coverage limits in text.
8. Do not call optional Wind-backed fund company or financial document routes
   merely to enrich a text comparison when Wind is not configured. Treat
   `KEY_MISSING` as a stop signal for Wind in the current turn.
9. For fund watchlist writes, verify the same symbol/id with the watchlist
   readback action before claiming the write succeeded.
10. For fund watchlist signal checks, do not run `Script` and do not interpret
    free-text `entryCondition` yourself. Use:
    `Watchlist(action:"list", type:"fund", status:"watching")`, then
    `DataProcess(action:"watch_signal_check", type:"fund", status:"watching")`.
    Answer from the returned JSON `results`: `triggered`, `status`, `checks`,
    `unsupportedRules`, and `provenance`.
    Do not call `DataProcess(action:"signals"|"score_technical"|"summary"|
    "support"|"indicators"|"ai_record")` for fund or ETF codes; those are
    stock/K-line technical analysis or stock prediction-log actions and should
    return a tool error for known fund codes.
    If the user only asked to check fund observation signals, stop at signal
    status and missing evidence. Do not offer `Portfolio` paper-trade or
    `XueqiuTrade` execution as the immediate next step unless the user
    explicitly asks to prepare or execute a trade.

For a text fund comparison, the normal bounded path is Skill plus local
`MarketData` readbacks. Tool results are already in the conversation context;
do not inspect `memory/.tool_outputs` or use `LS`, `Read`, `Grep`, `Glob`,
`Bash`, `Script`, file-system probing, raw provider diagnostics, or broad extra
fetches to recompute metrics unless the user explicitly asks for a generated
artifact or local fund readbacks are insufficient. If NAV history is already
returned with daily returns, use the returned summary fields or estimate
return/drawdown from the visible rows; otherwise state that exact deeper
statistics were not computed.

For ordinary fund comparison or selection, do not use broad `Research(search)`
to classify fund type, fill generic fund metadata, or compensate for optional
context. Fund type, NAV semantics, money-yield semantics, performance,
holdings, source time, fetched time, and gaps should come from structured
`MarketData` fund actions and local readbacks. Use `Research` only when the
user explicitly asks for current news, manager events, product announcements,
or other external context that is not part of the governed fund data contract.
If optional external context is unavailable, classify it as unavailable and
answer from the structured fund evidence instead of retrying search.

## Dashboard Creation

Use the app-level dashboard tool for generated fund dashboards. Do not read
bundled template files, write dashboard HTML manually, or open panels with
`UIControl` unless the user explicitly asks for custom HTML. Template mode and
custom HTML mode are separate: when using a report template, pass structured
JSON config and do not pass `html`.

For a fund comparison dashboard, create a compact structured report config that
contains the fund rows, comparison table, data source/time, fetched time,
category caveat, and risk warning. Then verify once with WebView `get_info` or
`screenshot` against the created dashboard id or observed `dash-...` panel id.
For money funds such as `000009`, use `query_fund_money_yield` and label the
metric as per-10k income / 7-day annualized yield. Do not fetch or retry
ordinary fund NAV after the fund identity shows it is a money fund.

If live WebView verification times out but the tool reports a static dashboard
artifact fallback, disclose that live DOM evidence should be retried later if
visual proof is required; do not pretend the live panel was verified.

When continuing or refreshing an existing report dashboard, reuse the same
dashboard id with the dashboard report template and structured config, then
verify with WebView. Do not recommend `UIControl.pushData` for report-template
refreshes; it is for runtime-only panel updates, not the normal persisted
dashboard artifact path.

### Dashboard types

- **NAV comparison**: chart template with multiple line series, normalized to 1.0
- **Holdings analysis**: chart template + ECharts pie/sunburst (sector -> stock)
- **Manager scorecard**: KPI template (Sharpe, drawdown, ranking, scale, tenure)

### Dashboard data rule

Dashboards should consume data prepared through `MarketData`, `DataProcess`,
local reusable rows, or app bridge routes. Do not embed public provider URLs in
dashboard HTML.

## Notes

- Fund codes are 6 digits, for example `110011`
- ETF codes are 6 digits, for example `510300`
- Use dark theme `#131722` for consistency
