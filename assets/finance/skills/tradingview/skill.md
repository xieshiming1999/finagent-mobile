---
description: Proactively load before generating or modifying any mobile finance dashboard that uses TradingView widgets, live prices, K-line charts, ticker tapes, heatmaps, technical ratings, or TradingView Scanner.
when_to_use: Load this skill whenever the user asks for a dashboard/page/report with charts, K-lines, live quote digits, market overview widgets, heatmaps, ticker tape, technical analysis, stock cards, watchlists, TradingView, or TradingView Scanner on mobile FinAgent.
---
# TradingView Skill

Use this skill proactively for TradingView dashboard visualization and
TradingView Scanner work. On mobile FinAgent, TradingView is a best-effort
visual layer: external scripts can fail in WebView because of network, region,
provider security policy, or mobile WebView limitations.

## Core Rules

- Use TradingView widgets for enhanced display: K-line charts, dynamic price,
  change percentage, technical rating, ticker tape, overview cards, and market
  heatmaps.
- Use `MarketData`, `DataProcess`, Wind, EastMoney, TDX, or local SQLite data
  for calculations, ranking, scoring, alerts, and persisted structured data.
- Do not scrape values from TradingView widget DOM.
- Every important chart/quote area must have a local Canvas/SVG/HTML fallback
  rendered from `MarketData` / `DataProcess` results.
- For A-share quote/K-line, prefer local SQLite and TDX-first MarketData routes.
  Do not use Yahoo/yfinance for China A-shares.
- For China/A-share local fallback tables, cards, and charts, use the China
  market convention: red means up/gain, green means down/loss. Do not copy
  TradingView's default green-up/red-down palette into local A-share fallback
  HTML. TradingView widgets may keep their native colors, but local labels and
  fallback visuals must use China-market colors when rendering China data.

## Load The Right Reference

Read only the reference file needed for the task:

| Task | Read |
|------|------|
| Choose widgets or dashboard layout | `bundle/skills/tradingview/references/widgets.md` |
| Main K-line / candlestick widget | `bundle/skills/tradingview/references/advanced-chart.md` |
| Live price cards, quote digits, technical ratings, ticker tape | `bundle/skills/tradingview/references/dynamic-digits.md` |
| TradingView Scanner fields and examples | `bundle/skills/tradingview/references/scanner.md` |
| Mobile fallback and local data pattern | `bundle/skills/tradingview/references/mobile-fallback.md` |

## Quick Workflow

1. Reuse or fetch structured data first with `MarketData` / `DataProcess`.
2. Render local fallback chart/quote from those results.
3. Add TradingView widgets as visual enhancement.
4. If TradingView fails, keep the local chart/quote visible and show a small
   "TradingView unavailable" status.

## Symbol Format

- A-share: `SSE:600519`, `SZSE:000001`
- China indices: `SSE:000001`, `SZSE:399001`, `SZSE:399006`
- Hong Kong: `HKEX:700`
- US: `NASDAQ:AAPL`, `NYSE:BABA`
- ETFs: `AMEX:SPY`, `NASDAQ:QQQ`
- Commodities/futures: `TVC:USOIL`, `TVC:UKOIL`, `NYMEX:CL1!`,
  `ICEEUR:BRN1!`
