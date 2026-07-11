---
description: Data-source guide for built-in finance providers and extension patterns
when_to_use: Use when you need to choose the right data source, understand provider differences, fetch deep market datasets, or extend the app with new external finance APIs
---

# Data Sources

`MarketData` supports multiple providers with code-owned routing and fallback. Use this skill to decide **which source should answer which question**.

For the current code-owned requirement surface, consult
`references/data-api-interfaces.md`. For useful non-persisted workflows and
diagnostics, consult `references/output-only-api-interfaces.md`. Use those
interface IDs as the normal workflow vocabulary. Provider parameters are
routing constraints for an interface; they are not raw endpoint shortcuts.

If a requirement-level interface already exists, use that interface and its
`query_*` / governed fetch path first. Do not switch to provider-direct calls
as the normal workflow when the code already has an interface, normalizer,
canonical table, and readback path.

## Local reusable data comes first

Before spending another provider call for quote, kline, backtest, screening, or deep market reads, discover the governed interface first, then check local persisted data:

```json
MarketData(action: "interfaces", category: "stock", limit: 20)
MarketData(action: "interface_describe", interfaceId: "stock.quote")
MarketData(action: "interface_availability", interfaceId: "stock.quote")
MarketData(action: "data_health")
MarketData(action: "finance_doctor")
MarketData(action: "coverage")
MarketData(action: "coverage", symbols: ["600519"])
MarketData(action: "query_api_calls", source: "eastmoney", minutes: 30)
MarketData(action: "query_quote", symbols: ["600519"])
MarketData(action: "query_kline", symbols: ["600519"], startDate: "2024-01-01")
MarketData(action: "query_tick_chart", symbols: ["600519"])
MarketData(action: "query_transactions", symbols: ["600519"], limit: 50)
MarketData(action: "query_volume_profile", symbols: ["600519"])
MarketData(action: "query_company_info", symbols: ["600519"])
MarketData(action: "query_hot_rank", limit: 50)
MarketData(action: "query_dragon_tiger", limit: 50)
MarketData(action: "query_raw_payload", source: "eastmoney")
```

Treat `interfaces -> interface_describe -> interface_availability -> query/fetch`
as the normal progressive-disclosure path. Use `data_health` when you need the
broader provider/dataset backlog, credential state, or classified failure
queues.
Use `finance_doctor` when the workflow may be blocked by local runtime,
session/history, API/task logs, reusable-store, or service readiness. It is a
local diagnostic/readiness report under `data.health`, not a provider refresh
and not a replacement for `interface_availability`.

When the user asks how to recover from a行情, macro, data-source, or provider
failure, do not answer only from this static guidance. Inspect current runtime
evidence first:

```json
MarketData(action: "data_health", section: "failures", limit: 10)
MarketData(action: "query_api_calls", minutes: 120, limit: 10)
```

Then summarize the actual failure classes, missing evidence, cache/readback
fallback, and next bounded retry or no-retry decision. If there are no recent
failures, state that the recovery policy is being described from contract
evidence rather than a live failure row.
For provider failure recovery, answer from the health and API-call evidence
directly. Do not inspect or rewrite dashboard/page files unless the user asks
for a dashboard, report artifact, or file update.

Treat provider results as reusable only when code has a registered canonical schema and a working query path.
If a provider just failed, inspect `data_health`, then `query_api_calls` before retrying. `query_api_calls` is the shared mobile / FinAgent `provider.api_call_log` readback over local `api_requests`. Use `MarketData(action: "data_health", section: "gaps")` and the returned `providerGapQueue` for provider normalizer/readback backlog, `credentialActivationQueue` for gated provider activation or permission/quota work still needing action, `credentialValidatedQueue` for credential-gated capabilities that already have live valid-schema evidence, and `policyDisabledQueue` for capabilities that must remain blocked; use `section: "failures"` and the returned `failureActionQueue` for classified recent failure actions. Use `MarketData(action: "finance_doctor")` when local runtime/session/API/task/reusable-store readiness could explain a workflow failure before attempting provider retries. Stop immediate retries for invalid parameters, permissions, quota/rate limits, disabled provider policy, or repeated transport resets; switch source or use local reusable rows instead.
Use `MarketData(action: "runtime_probe", probeAction: "status")` to inspect current durable runtime-probe evidence before running probes. Read `recommendedTargets`, `blockedTargets`, `providerProbePacks`, and `guidance`: `probeMode:"failures"` and `probeMode:"all"` only auto-run retryable transport, timeout, provider-error, runtime-unavailable, or transport-unstable targets. Credential/permission, quota/rate-limit, unsupported-route, runtime-blocked, schema-contract, schema-mismatch, and explicit do-not-retry rows stay in `blockedTargets` until the root cause changes or the user deliberately passes bounded `probeIds`. `runtime_probe` is the governed probe entry; it writes durable evidence under `data/runtime-probes` and should be preferred over ad hoc provider validation loops.

`MarketData(action: "query_raw_payload")` is local
`provider.raw_payload_audit` diagnostic readback with
`normalWorkflowAllowed:false`. It is useful for inspecting legacy or explicit
diagnostic evidence, but it is not a structured scoring source and not reusable
finance data.

The shared mobile finance surface contract is:

```text
local cache/query -> provider route -> code normalizer -> canonical persist -> same-runtime readback
```

Keep cache/read policy outside provider adapters. Provider adapters fetch and
parse source data; services and repositories decide freshness, canonical writes,
query/readback, and failure logging. Do not treat a one-off provider response as
reusable structured data until the code registers the normalizer, table,
readback action, and no-persist failure behavior.

Provider fallback order is code-owned by `ProviderPolicy`. When a route must
prefer a source, pass a scoped preferred provider order through policy-supported
routing; policy still filters disabled, unconfigured, quota/permission-limited,
runtime/API-health temporarily blocked, or unsupported providers. Do not rewrite
fallback order in prompts or UI logic, and do not model local cache as a provider.

Cache reuse is an explicit interface/service rule, not a provider concern. The
default `cache-first` mode reads canonical local rows first and reuses them only
when source data time, trade-date coverage, or row coverage satisfies the
request. `fetched_at` is local ingest provenance and does not prove market or
news freshness. Use `live-only` to force provider fetch and `cache-only` to
forbid external calls after a miss. `providerMode: strict` still uses
cache-first rules, but a cache hit must carry matching provider/source evidence
for the requested provider; mismatched local rows are treated as a miss and only
the requested provider route remains eligible. Use `live-only` with strict mode
when validation must actually call the requested provider.

Readback actions must distinguish `cacheStatus:local-hit` from
`cacheStatus:local-miss`. A local miss means no canonical row matched the
request; it should drive a governed fetch or health check, not a conclusion
that the market instrument has no data.

## Source priority

Default priority is code-owned. Do not rewrite fallback order in prose unless the user explicitly forces a source.

### A-share quote / kline

1. local SQLite reusable data
2. TDX
3. EastMoney
4. Sina governed provider routes through `stock.identity_list`, `stock.quote`, `index.quote`, `stock.daily_kline`, `stock.transactions`, `fund.etf_quote`, `market.sector_ranking`, `market.sector_constituents`, `market.board_ranking`, `market.board_members`, and `news.finance_feed`
5. Tencent governed routes where shared-mobile registers `provider:"tencent"`:
   `stock.identity_list`, `stock.quote`, `index.quote`, unadjusted
   `stock.daily_kline`, unadjusted `index.daily_kline`, `stock.transactions`,
   bounded `fund.etf_quote`, bounded `fund.etf_daily_ohlcv_bars`, bounded `fund.listed_fund_quote`,
   `bond.convertible_quote`, unadjusted `bond.convertible_daily_kline`, and
   `fund.etf_transactions`.
   Tencent adjusted stock/index/ETF/convertible-bond daily K-line, HK/AH, and other broad routes remain explicit
   `not-supported`, output-only, or deferred on
   FinAgent/shared-mobile until native adapters, normalizers, persistence,
   readback, provenance, skill guidance, and tests are implemented.

Sina is available only through registered interface/provider routing. When the
task explicitly needs Sina validation, keep the call on the matching interface
with `provider:"sina"` and use `runtime_probe` / `data_health` for current
provider truth. Sina daily K-line is unadjusted only; request `adjust:"none"`
or use another provider for qfq/hfq bars. ETF quote/list refresh can use
`MarketData(action: "etf", provider: "sina")` when Sina validation is needed;
sector ranking and concept board ranking can use `provider:"sina"` through the
governed `market.sector_ranking` / `market.board_ranking` routes. Sina sector
constituents can use `market.sector_constituents`, and concept-board members can
use `market.board_members`, when the caller has a Sina node-style `sectorCode`
or `boardCode`, such as `gn_gfgn`. Sina transaction validation can use
`MarketData(action: "transactions", provider: "sina")` through the governed
`stock.transactions` route.
Do not call or invent Sina endpoints
directly from agent prose; new Sina datasets must first be classified as
governed interface, typed output-only surface, diagnostic, or unsupported.

Sina `fund.dividend_factor` is a governed reusable interface. Use
`MarketData(action: "fund_dividend_factor", provider: "sina")` for bounded live
refresh and `query_fund_dividend_factor` for readback; successful rows write the
dedicated `fund_dividend_factor` table. Do not write ETF dividend/factor rows
into `fund_nav`, `fund_holding`, or unrelated canonical tables.

Tencent is available on shared-mobile / FinAgent only through registered
interface routes. Use `provider:"tencent"` on `stock.identity_list`,
`stock.quote`, `index.quote`,
`fund.etf_quote`, `fund.etf_daily_ohlcv_bars`, `fund.listed_fund_quote`,
`bond.convertible_quote`, or `bond.convertible_daily_kline` when strict
Tencent validation or fallback is useful. `stock.identity_list` uses the
bounded Tencent rank-list route and persists canonical `stock_list` rows.
`fund.etf_quote` uses a bounded ETF symbol universe,
`fund.etf_daily_ohlcv_bars` supports only unadjusted `adjust:"none"` daily ETF bars,
`fund.listed_fund_quote` uses a bounded exchange-listed fund / money-market
fund universe, `bond.convertible_quote` uses SH/SZ convertible-bond symbols
such as `110059` / `123xxx`, and `bond.convertible_daily_kline` supports only
unadjusted `adjust:"none"` daily bars. These routes persist `quote_snapshot` or
`kline_daily` rows and read back through `query_etf_quote`,
`query_listed_fund_quote`, `query_bond_quote`, `query_bond_kline`,
`query_transactions`, `query_kline`, or `query_quote`. Do not ask mobile Tencent for adjusted
ETF daily OHLCV, adjusted convertible-bond daily K-line,
HK/AH, or other broad routes unless a future
contract marks that route supported.

### REST-only market lists

Registered EastMoney capabilities cover:

- sector ranking and constituents
- hot rank
- limit pools
- northbound flow / holdings
- dragon-tiger
- money flow ranking

Index membership uses the requirement-level `index.constituents` concept. In
FinAgent/shared mobile this interface has canonical `index_constituent`
storage/readback through `query_index_constituents` and a governed workflow
route for `MarketData(action:"index_constituents")` through the constrained
Tushare capability. Keep that interface-first path. Do not advertise raw
AkShare `index_stock_cons` or arbitrary provider-direct calls as the normal
workflow.

### Research / normalized datasets

Use Tushare only when:

- the user explicitly wants Tushare
- or a standardized research dataset is a better fit than quote fallback

Tushare is not part of normal quote / kline fallback even when configured.

## Provider strengths

### TDX

Best for A-share market structure and deep exchange-style data:

- quote / kline
- intraday tick chart
- transactions; Sina is also available for `stock.transactions` when strict Sina validation or fallback is useful
- auction
- unusual activity
- volume profile
- company / finance / xdxr
- index info / stock lists / ranking-type data

### EastMoney

Best for free REST market lists and board data:

- sector / concept / area ranking
- hot rank
- northbound
- limit-up / limit-down pools
- dragon-tiger
- money flow / flow rank
- ETF / chip / board views

Diagnostic/recovery note: maintained FinAgent/shared-mobile EastMoney quote and list-style calls avoid numbered `xx.push2.eastmoney.com` shard hosts. If recent errors show socket resets or proxy failures, do not retry broad EastMoney calls concurrently; use local reusable rows, TDX for quote/K-line, or a targeted REST-only call.

### Yahoo

Use for non-A-share global assets:

- US stocks / ETFs
- HK stocks
- global indices
- crypto / FX

Do not use Yahoo for China A-shares.

### TradingView

Use `MarketData(action: "scan", symbols: ["EXCHANGE:SYMBOL"])` as the
requirement-level `market.screening` data API interface. The result has a known
`screening_result` schema with interface id, status, failure class, provider,
rows, and provenance. When a runtime `ToolContext` is available it is persisted
to `market_screening_snapshot` and can be reused through
`query_market_screening`.

Direct `WebFetch` POST calls to TradingView Scanner are advanced diagnostics or
custom experiments only. They should not replace the `market.screening`
interface for normal agent workflows.

### Wind

Use first for professional data when configured and quota is available:

- quote / kline
- fundamentals
- company info
- macro
- documents / analytics

### Tushare

Use only for currently registered structured research datasets:

- stock list
- daily / weekly / monthly / index daily K-line
- daily valuation / `daily_basic`
- trade calendar

Do not call Tushare `moneyflow`, `fund_basic`, `fund_nav`,
`fina_indicator`, `income`, `balancesheet`, or `cashflow`; those interfaces are
disabled under the current app/provider contract and should not be advertised as
normal workflows.

## Common provider actions

Use these only when the user explicitly wants a provider-specific path or when
you are validating provider behavior. Normal analysis should stay on governed
interface/query routes first.

### TDX-specific

- `tdx_tick_chart`
- `tdx_transactions`
- `tdx_finance`
- `tdx_xdxr`
- `tdx_unusual`
- `tdx_index_info`
- `tdx_stock_list`
- `tdx_volume_profile`
- `tdx_company_info`

### EastMoney-specific

- `flow`
- `flow_rank`
- `sector`
- `chip`
- `etf`
- `hot_rank`
- `dragon_tiger`
- `northbound`
- `unusual`
- `limit_up`
- `limit_down`

### Yahoo / typed reuse

- `price`
- `backtest*`
- `earnings`
- `yahoo_news`
- `yahoo_options`
- `yahoo_actions`
- `query_yfinance` with typed datasets such as `profile`, `statements`,
  `earnings_calendar`, `earnings_history`, `earnings_estimates`,
  `eps_revisions`, `eps_trend`, `quarterly_financial_statements`,
  `recommendations`, `upgrade_downgrade_events`, `news`, `option_expiries`, `options`,
  `option_open_interest`, `option_volume`, `option_implied_volatility`, `option_moneyness`, `option_bid_ask_spread`, `option_price_change`, `option_trade_recency`, `actions`, `dividends`, `splits`, `holders`,
  and `insiders`

### Tushare

Use persisted `query_fundamental` first for valuation/fundamental reuse. Load
the `tushare` skill only when the user explicitly asks for Tushare/provider
validation, then use nested `params`:

```json
MarketData(action:"tushare", api_name:"daily_basic", params:{ ts_code:"600519.SH" }, fields:"ts_code,trade_date,pe,pb")
```

## When to use which source

| Need                                   | Best source  | Why                                             |
| -------------------------------------- | ------------ | ----------------------------------------------- |
| A-share real-time quote                | local -> TDX | fastest and most aligned with local persistence |
| A-share daily kline                    | local -> TDX | canonical read path first                       |
| intraday chart                         | TDX          | unique deep-market coverage                     |
| transactions                           | TDX / Sina   | governed `stock.transactions` interface         |
| sector / hot / northbound / limit pool | EastMoney    | REST-only datasets                              |
| US / HK / global assets                | Yahoo        | typed global path already exists                |
| professional fundamentals / macro      | Wind         | best covered professional dataset               |
| normalized research tables             | Tushare      | structured research interfaces                  |

## Extension guidance

If the user wants a new external finance API:

1. first see whether an existing provider already covers it
2. if not, document the endpoint in a skill
3. test it with `WebFetch` or the appropriate tool path
4. only treat it as reusable structured data after parser/normalizer, canonical persistence, same-runtime query/readback, and failure logging exist in code

Do not pretend a raw one-off HTTP response is part of the reusable local market-data layer.
