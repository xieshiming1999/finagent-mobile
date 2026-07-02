---
description: Monitor creation templates with built-in JavaScript scripts. Normal finance monitors use interface-backed MarketData/DataStore workflows and local finance routes instead of raw provider URLs.
when_to_use: User asks to create price alerts, change alerts, RSI/trend monitoring, fund NAV monitoring, or volume anomaly monitoring.
---
# Monitor Templates

When creating a Monitor, prefer these interface-backed workflows:

- collect quote, K-line, fund NAV, sector, flow, and limit-pool data with
  `MarketData` or reusable `query_*` actions;
- keep provider choice as a routing constraint, not as a raw provider URL;
- show provenance in the monitor description when data was seeded from a
  provider-backed fetch.

The JavaScript templates in this folder call local `/api/finance/...` routes.
They must not call public provider URLs directly. Provider choice should remain
a routing constraint on a requirement-level request, not a raw endpoint in the
monitor script.

## How `callService` works

FinAgent monitor scripts use local requirement-level paths:

```js
var quote = callService('/api/finance/quote', {ts_code: '600519.SH', market: 'CN'});
```

## Script authoring rules

For RSI or trend monitors, prefer an app-owned technical route or local
MarketData-derived technical payload instead of recomputing indicators from
raw K-line rows when the runtime exposes one. If a script uses a local K-line
route, treat the response as an object with data/provenance fields unless the
tool result explicitly documents a bare array. Read rows from `resp.data`, and
do not run separate diagnostic scripts after monitor readback; if the monitor
readback exposes a data-shape gap, report it as a monitor defect or update the
monitor through the monitor tool.

For strategy-to-monitor requests, keep the first pass bounded. Use
`strategy_signal` for validated stock StrategySpec signals based on daily
SMA/volume confirmation; pass the saved strategyId and structured
strategyRules to `MonitorCreate`, then call `MonitorList` once to confirm
readback. Use `price_alert` only when the strategy can be reduced to numeric
upper/lower price levels. Do not call broker, Xueqiu buy/sell, transfer,
simulated trade, Script, Bash, Read, LS, Glob, or Grep.
For one-sided price alerts, omit the unused bound. Do not use fake sentinel
values such as `upper: 1000`, `lower: 0`, or an already-triggered opposite
bound to represent a one-sided condition.
If prior analysis context is needed, use the session/search tool; do not inspect
session directories through filesystem listing.
If the user already asks to set up/create the monitor, do not stop with a
TaskCreate, todo item, or "shall I continue?" message. State the condition in
the monitor description, call `MonitorCreate`, then call `MonitorList`.

When the monitor is derived from a validated or backtested custom strategy,
include `strategyId` and structured `strategyRules` in `MonitorCreate` if the
tool schema exposes them. Use validated thresholds or signal names from the
StrategySpec/backtest evidence. Do not translate an unsupported rule into a
different indicator unless the user explicitly asks for a new proxy strategy.
For fund observation monitors, use `template:"fund_rule_monitor"` and pass
`monitorDraft` and `dcaObservation` directly when `custom_strategy_observe`
returned them; they remain structured monitor provenance instead of display-only
prose.
For portfolio ranking monitors, use `template:"portfolio_rebalance_monitor"`
and pass `strategyId`, `portfolioEvidence`, and `rebalanceDraft` from
`custom_strategy_rank`. It is review-only: no rebalance, Portfolio order,
XueqiuTrade action, broker action, or local trade mutation is authorized by
this monitor.
When the runtime output includes `strategyReview:` with
`contract:"strategy-review-v1"`, treat that object as the authoritative
strategy-review boundary. Use its `reviewKind`, `strategyId`, `signal`,
`subjects`, `evidence`, `draft`, `boundaries`, and `confirmation` fields
instead of parsing prose, and do not treat it as `analysis-evidence-v1` or a
trade execution result.

### `price_alert` - price breakout alert

Monitor a stock price and alert when it breaks above or below a
threshold.

Parameters:
- `ts_code` - stock code, for example `"600519.SH"`
- `name` - display name, for example `"Moutai"`
- `upper` - upper trigger price (optional)
- `lower` - lower trigger price (optional)
- `market` - market, default `"CN"`; optional `"HK"` or `"US"`

Example:

```json
{
  "name": "Moutai price",
  "template": "price_alert",
  "params": {"ts_code": "600519.SH", "name": "Moutai", "lower": 1800, "upper": 2000},
  "interval": "5m",
  "display": "value_card"
}
```

### `change_alert` - daily percent-change alert

Monitor daily percentage change and alert when it exceeds a threshold.

Parameters:
- `ts_code` - stock code
- `name` - display name
- `threshold` - percentage-change threshold, for example `5` for +/-5%
- `market` - market, default `"CN"`

Example:

```json
{
  "name": "Moutai change",
  "template": "change_alert",
  "params": {"ts_code": "600519.SH", "name": "Moutai", "threshold": 3},
  "interval": "5m",
  "display": "value_card"
}
```

### `strategy_signal` - validated StrategySpec signal monitor

Monitor a saved stock StrategySpec signal using local quote and K-line rows.
The template is alert-only and returns `data_missing` instead of throwing when
local quote/K-line rows are unavailable.

When the entry condition actually triggers, the template sends a structured
`Bridge.sendToAgent(...)` event with `strategyId`, symbol, price, indicator
evidence, and `confirmationRequired:true`. Treat that event as a sizing/risk
preflight request only. Do not write Portfolio or XueqiuTrade state until a
later explicit user confirmation approves the action.

Parameters:
- `ts_code` - stock code, for example `"600519.SH"`
- `name` - display name
- `market` - market, default `"CN"`
- `sma_period` - moving-average period, default `20`
- `volume_period` - volume average period, default `20`
- `min_bars` - minimum local bars, default `120`

Example:

```json
{
  "name": "custom_20_v1 signal",
  "template": "strategy_signal",
  "params": {"ts_code": "600519.SH", "name": "贵州茅台", "market": "CN", "sma_period": 20, "volume_period": 20, "min_bars": 120},
  "interval": "30m",
  "display": "value_card",
  "strategyId": "custom_20_v1",
  "strategyRules": {"id": "custom_20_v1", "entry": {"all": []}}
}
```

### `fund_rule_monitor` - fund StrategySpec observation monitor

Use this template when `custom_strategy_observe` returned `monitorDraft` and
`dcaObservation`. It reads local interface-backed fund NAV rows, evaluates
fund-specific observation rules such as NAV trend, drawdown, volatility, or
rolling return, and sends a structured `Bridge.sendToAgent(...)` event only
when the fund observation state needs review. It is observation-only: no fund
subscription, redemption, Portfolio trade, XueqiuTrade action, or broker action
is authorized by this monitor.

Parameters:
- `fund_code`, `code`, or `symbol` - fund code, for example `"110011.OF"`
- `name` - display name
- `min_rows` - minimum local fund rows, default `30`
- `monitorDraft` - structured draft from `custom_strategy_observe`
- `dcaObservation` - structured DCA observation from `custom_strategy_observe`

Example:

```json
{
  "name": "fund_dca_nav_guard_v1 observation",
  "template": "fund_rule_monitor",
  "params": {"fund_code": "110011.OF", "name": "E Fund", "min_rows": 30},
  "interval": "1d",
  "display": "value_card",
  "strategyId": "fund_dca_nav_guard_v1",
  "monitorDraft": {"mode": "fund_rule_monitor", "entryRules": []},
  "dcaObservation": {"mode": "fund_observation_only"}
}
```

### `portfolio_rebalance_monitor` - portfolio ranking review monitor

Use this template when a saved `custom_strategy_rank` artifact has
`status:"ranked"`. The monitor preserves `portfolioEvidence` and
`rebalanceDraft`, then asks the event agent to review the saved ranking and
rebalance boundary. It is evidence-only and must not rebalance or place orders.

Parameters:
- `strategyId` - saved strategy artifact id
- `portfolioEvidence` - structured evidence returned by `custom_strategy_rank`
- `rebalanceDraft` - structured rebalance draft returned by `custom_strategy_rank`

Example:

```json
{
  "name": "ranked_portfolio_v1 review",
  "template": "portfolio_rebalance_monitor",
  "interval": "1d",
  "display": "status_row",
  "strategyId": "ranked_portfolio_v1",
  "portfolioEvidence": {"mode": "equal_weight_selected_metrics"},
  "rebalanceDraft": {
    "rebalanceInterval": "monthly",
    "positions": [
      {"symbol": "300059", "targetWeight": 0.4},
      {"symbol": "600519", "targetWeight": 0.4}
    ]
  }
}
```

### `fund_nav` - fund NAV monitor

Currently disabled until the runtime exposes an interface-backed
`fund.nav_history` monitor service. Query reusable fund NAV data with
`MarketData(action:"query_fund_nav")` instead of creating this monitor.

Parameters:
- `ts_code` - fund code, for example `"110011.OF"`
- `name` - display name
- `lower` - lower NAV bound (optional)
- `upper` - upper NAV bound (optional)

Do not create this template as a normal monitor until the service is available.
Example parameters for the future supported route:

```json
{
  "name": "E Fund Mid Cap",
  "template": "fund_nav",
  "params": {"ts_code": "110011.OF", "name": "E Fund Mid Cap", "lower": 5.0},
  "interval": "30m",
  "display": "value_card"
}
```

### `volume_surge` - volume anomaly

Monitor stock volume and alert when today's volume expands beyond a
multiple of the previous day.

Parameters:
- `ts_code` - stock code
- `name` - display name
- `multiplier` - volume multiple, for example `2` means volume is more
  than 2x the previous day
- `market` - market, default `"CN"`

Example:

```json
{
  "name": "Moutai volume",
  "template": "volume_surge",
  "params": {"ts_code": "600519.SH", "name": "Moutai", "multiplier": 2},
  "interval": "5m",
  "display": "value_card"
}
```

### `watchlist` - batch watchlist monitor

Monitor multiple stocks or funds at once and return a watchlist table.

Parameters:
- `items` - watch list, for example
  `[{"ts_code":"600519.SH","name":"Moutai"}, ...]`
- `market` - market, default `"CN"`
- `change_threshold` - percent-change alert threshold, optional,
  default `5`

Example:

```json
{
  "name": "Watchlist monitor",
  "template": "watchlist",
  "params": {
    "items": [
      {"ts_code": "600519.SH", "name": "Moutai"},
      {"ts_code": "000858.SZ", "name": "Wuliangye"},
      {"ts_code": "600036.SH", "name": "China Merchants Bank"}
    ],
    "change_threshold": 3
  },
  "interval": "5m",
  "display": "watchlist"
}
```

## Usage guide

1. First decide which template best matches the user request.
2. Use the `template` + `params` fields of `MonitorCreate`. Do not
   write raw `script` when a template already fits.
3. If no template fits, then write custom JavaScript using `script`.
4. Templates already handle errors, state persistence, and alert
   triggers, so no extra condition block is needed.
