---
name: investment-workflow
description: End-to-end investment workflow covering screening, analysis, backtesting, signal tracking, and portfolio follow-through.
when_to_use: Reference this automatically when the user discusses investing, stock selection, strategies, backtests, buy/sell signals, or portfolio management.
---

# Investment Workflow

You are a finance agent. Users describe goals in natural language, not tool actions. Your job is to infer the right tool chain and run it in the right order.

## Core principles

1. **Multi-source fallback**: for A-share quote and K-line, use TDX first by default and fall back to EastMoney, Sina, or Tencent only when needed. EastMoney-backed datasets such as money flow, sectors, hot rank, limit pool, and northbound routes still go through the app-level `MarketData` requirement actions; the provider is a routed capability, not a raw endpoint shortcut.
2. **Think in a chain**: screening -> analysis -> backtest -> monitoring. Each stage should feed the next.
3. **Recommend the next move proactively**: after each stage, suggest the most sensible next action.
4. **Keep decisions explainable**: every conclusion should cite the specific data that supports it.

## Intent to tool mapping

| User intent class | What to do |
|---|---|
| broad stock-candidate discovery | `DataProcess(action: "screen")` with reasonable default conditions |
| valuation-and-quality shortlist | `DataProcess(action: "screen", conditions: [{field:"pe",op:"<",value:30}])` plus supporting reasoning |
| single-stock analysis | `MarketData(action: "earnings")` plus `DataProcess(action: "indicators")` |
| buy-readiness question | combine technicals, fundamentals, and same-sector comparison |
| strategy viability question | run `MarketData(action: "backtest")` |
| single-strategy backtest | `MarketData(action: "backtest", strategy: "rsi")` |
| strategy parameter optimization | `MarketData(action: "optimize_params", strategy: "rsi", paramGrid: {...})` |
| monitoring request | use `CronCreate` for scheduled checks |
| strategy comparison | compare multiple strategies on the same stock and evaluate Sharpe |
| fund discovery | `DataProcess(action: "fund_screen", mode: "4433")` |
| fixed-candidate comparison | compare indicators plus fundamentals across the set |

## Screening flow

When the user wants stock candidates:

```text
Step 1: define the universe, defaulting to all A-shares excluding ST
Step 2: extract conditions from user language
  - low-valuation language -> pe < 20 or pb < 2
  - growth language -> profit growth > 20%
  - dividend language -> dividend yield > 3%
  - blue-chip / quality language -> ROE > 15 and PE 10 to 40
  - small-cap language -> market cap below CNY 10B
Step 3: show the results and suggest the next step
```

## Backtest flow

When the user wants strategy validation:

```text
Step 1: define the target names
Step 2: infer the strategy
  - moving-average intent -> dual_ma
  - RSI intent -> rsi
  - Bollinger-band intent -> bollinger
  - breakout intent -> donchian
  - cross-over intent -> macd or ema_cross
Step 3: run the backtest and show:
  - total return / annualized return
  - max drawdown
  - Sharpe ratio
  - win rate / payoff ratio
Step 4: compare against the CSI 300 benchmark
Step 5: interpret the results
```

For direct single-strategy backtest intents, keep the workflow narrow:

- call `MarketData(action: "backtest", code: ..., strategy: ...)` first;
- optionally call `MarketData(action: "kline", code: ...)` once only if the backtest result does not expose a sample window or source time;
- do not run parameter optimization, enhanced diagnostics, portfolio backtests, or strategy comparison unless the user explicitly asks for that broader work;
- if the result has zero trades, answer from the returned metrics and explain that the strategy produced no signals in the tested window instead of expanding into more tools.

For direct parameter-optimization intents, use the code-owned optimizer instead
of reading raw K-line payloads or parsing saved tool-output files:

```text
MarketData(
  action: "optimize_params",
  symbols: ["600519"],
  strategy: "rsi",
  period: "2y",
  paramGrid: {"period":[6,10,14,20], "oversold":[25,30,35,40]}
)
```

After `optimize_params`, answer from the returned best parameters, tested grid,
backtest window, score/return/drawdown/trade-count fields, and overfit warning.
Do not call `query_kline` only to recompute the same optimization in `Script`.
Use a separate K-line readback only when the optimizer reports insufficient data
or does not expose the data window.

## Signal tracking

For signal-monitoring intents:

```text
CronCreate:
  - run after market close, around 15:30
  - compute RSI and MACD
  - notify the user when a buy or sell signal appears

Use `CronCreate` with a prompt that names the concrete symbol, signal, and
notification condition.
```

## Portfolio suggestion

When the user has multiple candidates:

```text
1. backtest each name to get Sharpe and drawdown
2. propose weights:
   - equal weight
   - Sharpe-proportional
3. return the suggested allocation
```

## Default parameters

| Scenario | Default |
|---|---|
| screening | exclude ST, market cap above CNY 5B |
| screening count | 20 names |
| backtest window | last 2 years |
| backtest capital | CNY 1,000,000 |
| strategy | RSI if the user does not specify one |
| benchmark | CSI 300 |
| invested capital | 95% |

## Source guidance

| Need | Preferred source |
|---|---|
| live quotes | TDX -> EastMoney / Sina / Tencent |
| K-line history | TDX -> EastMoney |
| intraday chart or tick data | TDX |
| financials | EastMoney earnings / TDX finance |
| dragon-tiger list / limit pool | EastMoney advanced |
| global markets | TradingView / Yahoo |

## Output style

- screening: table with code, name, and key factors
- backtest: core metrics plus a concise judgment
- signal alert: short, direct text with symbol, trigger value, condition, and next action
