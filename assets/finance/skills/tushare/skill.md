---
description: App-supported Tushare Pro research data for explicit stock list, K-line, daily valuation, trading-calendar, and evidence-gated index constituent requests. Requires `TUSHARE_TOKEN`.
when_to_use: Use when the user explicitly wants Tushare/Tushare Pro and the requested API is one of the supported or credential-gated app surfaces: stock_basic, daily, weekly, monthly, index_daily, daily_basic, trade_cal, or index_weight after live capability evidence confirms permission.
---
# Tushare Data Source

Tushare Pro is a token, points, and permission-gated research source. It is
not part of the default A-share quote/K-line fallback path. For ordinary
A-share market data, prefer local SQLite, TDX, EastMoney, and free quote
sources first.

Use Tushare only for the app-supported APIs:
- `stock_basic`
- `daily`, `weekly`, `monthly`, `index_daily`
- `daily_basic`
- `trade_cal`
- `index_weight` only after `index.constituents / tushare` availability shows
  the current token can access it

Do not call `fina_indicator`, `income`, `balancesheet`, `cashflow`,
`moneyflow`, `fund_basic`, or `fund_nav`. The configured permission set cannot
access those APIs, and the runtime blocks them before any network request.
Treat `index_weight` separately: it is a registered but credential-gated
`index.constituents` capability. Prefer local `query_index_constituents` or an
already supported provider unless current live evidence shows the Tushare
capability is usable.

## Entry Point

Use `MarketData`. Do not have the agent write ad hoc Python with the `tushare`
package:

```json
MarketData(action: "tushare", api_name: "daily", params: {"ts_code": "600519.SH", "start_date": "20250101", "end_date": "20250601"}, fields: "ts_code,trade_date,open,high,low,close,pre_close,change,pct_chg,vol,amount")
```

Use nested `params`. The tool still accepts flat params for compatibility, but
new scripts and templates should use nested `params` so UI helper fields like
`market` or `source` are not passed through to Tushare by mistake.

Registered schemas persist into FinAgent's local reusable SQLite by default.
Only set `persist:false` when you are explicitly debugging the raw upstream
payload. After structured data is fetched, reuse it through local query actions
before spending more Tushare quota:

```json
MarketData(action: "query_kline", symbols: ["600519"], adjust: "none")
MarketData(action: "query_fundamental", symbols: ["600519"])
MarketData(action: "query_stock_list", industry: "liquor")
```

Current structured persistence coverage:
- `stock_basic`
- `daily/weekly/monthly/index_daily`
- `daily_basic`
- `trade_cal`
- `index_weight` only when `tushare.index.constituents` is live-validated for
  the configured token

Unknown Tushare schemas are not normal workflow output. They must be rejected,
routed through an explicit provider diagnostic envelope, or promoted by adding
a code-owned interface, canonical normalizer, and query path before the agent
relies on the response.

## Common APIs

| Task | `api_name` | Key params |
|---|---|---|
| Stock list | `stock_basic` | `list_status:"L"` |
| Trading calendar | `trade_cal` | `exchange:"SSE"`, `start_date`, `end_date`, `is_open:"1"` |
| A-share daily bars | `daily` | `ts_code` or `trade_date` |
| Valuation indicators | `daily_basic` | `ts_code` or `trade_date` |
| Index daily bars | `index_daily` | `ts_code` |
| Index constituents | `index_weight` | `index_code`; check `index.constituents / tushare` availability first |

## Default Time Windows

- "Recent trend": about 20 trading days.
- "Recent period": about 3 months.
- Daily valuation: roughly 20 trading days when a range is needed.

Use `YYYYMMDD` dates consistently. Clamp future dates to the most recent
available date and state that clearly. For long ranges, split by year or
quarter instead of running high-frequency loops. Do not blindly retry
permission failures, rate limits, or parameter errors.

If the tool returns `TUSHARE_RATE_LIMIT` or an equivalent frequency-limit
error, treat it as a tool failure. Query already-persisted local data first or
wait for the endpoint window to reset; do not continue retrying as if it were a
normal conversational response.

## Output Rules

Unless the user explicitly wants the raw table, return:

1. A one-sentence conclusion.
2. Data scope, API name, and field definitions.
3. The key table or summary table.
4. Missing data, permission limits, rate limits, or field limitations.
5. An export path if you generated a file.
