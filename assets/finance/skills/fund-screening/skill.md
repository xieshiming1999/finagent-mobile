---
description: Fund screening workflow using the 4433 rule, manager evaluation, and risk-aware shortlist filters.
when_to_use: User asks which funds look strong, how to screen funds, or asks for a shortlist of candidate funds.
---

# Fund Screening

Load `analysis-standards` before producing a shortlist. Its Finance Output Standard governs the final answer: separate facts, calculations, inferences, recommendations, assumptions, and unverified items, and retain source/as-of time, fetch/ingest time, fields used, method/tool action, quality/confidence note, and readback status.

## 4433 rule

Use this classic screening rule:
1. Top quarter for trailing 1-year return
2. Top quarter for trailing 2-year, 3-year, 5-year, and year-to-date return
3. Top third for trailing 6-month return
4. Top third for trailing 3-month return

Only include funds that satisfy all four checks.

## Additional filters

| Dimension | Condition | Why it matters |
|---|---|---|
| AUM | 2B to 200B | Too small is unstable, too large can reduce flexibility |
| Manager tenure | More than 3 years | Prefer managers tested through multiple market regimes |
| Max drawdown | Less than 25% | Basic risk-control screen |
| Sharpe ratio | Greater than 1.0 | Better risk-adjusted return |
| Top-10 concentration | Less than 60% | Avoid over-concentrated portfolios |

## Execution path

Fund data should come from local reusable rows first, then the configured
EastMoney/AkShare, Wind, or research path. Do not use Tushare `fund_basic` or
`fund_nav`; those API names are blocked by the runtime for this app.

```text
DataProcess(action: "fund_screen", mode: "4433", limit: 3)
```

For broad prompts such as “最近有哪些基金值得关注”, use `DataProcess(action:
"fund_screen")` first. It reads governed local `fund_performance_metrics` rows
and returns a compact shortlist with source time, fetched-at, cache status, and
limitations. If it returns `cacheStatus:"miss"`, run one bounded refresh:

```text
MarketData(action: "fund_performance", limit: 50)
DataProcess(action: "fund_screen", mode: "4433", limit: 3)
```

Use `MarketData(action:"query_fund_nav", symbols:[...])` only for selected
ordinary funds after a shortlist exists. Money funds require money-yield data,
not ordinary NAV. Do not use `Grep`, `Read`, or `Script` to inspect tool-output
files for this workflow; if a tool output is too large, call a narrower
query/summary action or answer from the compact `fund_screen` result.

For research-only prompts such as choosing, ranking, or recommending funds for
long-term observation, do not call `Watchlist`, monitor tools, or
`MarketData(action:"custom_strategy_observe")`. In fund-selection language,
"长期观察" means an analysis shortlist unless the user also asks to save,
monitor, set trigger conditions, create a定投 plan, or write to an observation
pool. For prompts that explicitly ask to design a定投/观察 condition and write a
watchlist item, do not broaden the workflow into custom statistics, holdings,
manager research, or script-based NAV calculations. Use only fund identity,
performance, and NAV/money-yield readbacks, then `Watchlist(add)` with the
selected fund's real `name` from the fund identity readback and
`Watchlist(list)` readback.

For broad "choose 3 funds" research prompts, keep the first pass bounded:
fund identity, performance/screening, one selected money-fund money-yield
readback, and targeted NAV/holding readbacks for at most two ordinary funds. Do
not repeat the same code/interface query in the same turn. If a broad
money-yield readback already contains enough money-fund candidates, do not query
those same codes again. Do not call manager, `custom_strategy_observe`, or live
holding refresh paths unless the user explicitly asks for manager due
diligence, a validated observation strategy, or the final answer cannot
honestly disclose the holding/manager gap.

If the user says this is research-only, says not to live fetch, or says to stop
after local/readback evidence, treat that as a hard boundary for the turn. Use
only `DataProcess(fund_screen)` and `MarketData` `query_*` readbacks such as
`query_fund_money_yield`, `query_fund_nav`, and `query_fund_holding`. Do not
call live refresh actions such as `fund_money_yield`, `fund_holding`,
`fund_nav`, provider diagnostics, manager fetches, or broad provider refreshes.
If a local readback is missing, state the missing coverage instead of fetching.

For ETF/listed-fund rotation, do not answer from fund-screening concepts alone.
Make one bounded listed-price evidence read before giving a concrete rotation
design. Use `MarketData(action:"etf")`, `MarketData(action:"quote")` for a
small ETF basket, or local `MarketData(query_quote/query_kline)` when rows are
already available. In the final answer, explicitly separate:

If the user has not supplied ETF codes yet, use a single mobile-safe default
quote sample before the design:

```text
MarketData(action: "quote", symbols: ["510300.SH"])
```

Label it as sample listed-market evidence only. Do not claim NAV/IOPV,
premium-discount, or underlying-index confirmation unless those rows were
also retrieved. Do not run `custom_strategy_rank`, `custom_strategy_backtest`,
or broad `Research(search)` after ETF K-line evidence is unavailable; state the
data gap and keep the answer at design/observation level.

- observed listed market price / quote / K-line evidence;
- missing or not retrieved NAV / IOPV evidence;
- missing or not retrieved underlying-index evidence.

Use NAV / IOPV only for premium-discount checks and use underlying-index rows
only for tracking or trend confirmation. If those rows were not retrieved,
state the gap rather than presenting the checks as verified.

## Output format

```text
| Rank | Fund | Code | 1Y | 3Y | Drawdown | Sharpe | Manager |
|------|------|------|----|----|----------|--------|---------|
| 1 | Example Theme Select | 001234 | +32% | +85% | -18% | 1.5 | Zhang San (5y) |
```

## With Watchlist

Use this only when the user explicitly asks to save, observe, monitor, or add
selected funds to a watchlist:

```text
Watchlist(
  action: "add",
  groupId: "<fund-group>",
  symbol: "001234",
  name: "Example Theme Select",
  type: "fund",
  source: "fund-screening",
  tags: ["4433", "growth"]
)
```

After adding, read back the same symbol/id before claiming success. `tag` /
`tags` are labels, not a replacement for the fund name. If the user did not ask
for a dashboard or custom statistics, stop after the watchlist readback and
final evidence summary.
