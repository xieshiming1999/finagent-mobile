description: Oil analysis plus a custom HTML dashboard using TradingView charts and free data APIs
when_to_use: User asks to analyze oil, create a dashboard, or build an oil war room
---
# Oil Analysis & Dashboard Skill

## Oil Data Sources

### TradingView charts
TradingView widgets, Advanced Chart examples, dynamic price cards, period limits, and the mobile fallback rules for oil dashboards are maintained in the separate `tradingview` skill. Load it before generating an oil chart page:

```
Skill(skill: "tradingview")
```

On mobile, TradingView is only an enhancement layer. Critical prices, K-lines, and alerts must come from `MarketData`, `DataProcess`, or local persisted data, with a local Canvas/SVG/HTML fallback.

Common symbols:
- Brent: ICEEUR:BRN1! or TVC:UKOIL
- WTI: NYMEX:CL1! or TVC:USOIL
- Shanghai crude: INE:SC1!
- Dubai crude: NYMEX:DC1!

### Data access
Use interface-backed finance tools before raw HTTP:

- **MarketData/DataStore**: cached quote/history and provider-routed data when
  the instrument is supported by the app.
- **Yahoo Finance**: commodity prices through the Yahoo/MarketData workflow
  when the symbol is available (see the `tradingview-scanner` skill)
  - Brent: BZ=F, WTI: CL=F
- **TradingView Scanner**: real-time oil technicals (see the `tradingview-scanner` skill)
  - Brent: market=`cfd`, symbol `TVC:UKOIL`
  - WTI: market=`cfd`, symbol `TVC:USOIL`
  - Use it for RSI, MACD, Bollinger Bands, buy/sell ratings, and similar indicators

## JS Bridge

JavaScript inside the HTML page can call free APIs through the injected `Bridge`. Do not add a custom `window.AgentBridge` wrapper:

```js
async function callAPI(path, params = {}) {
  return await Bridge.fetch(path, params, "GET");
}
```

Raw full URLs are diagnostic fallback only. A reusable finance workflow should
not treat a raw one-off HTTP response as canonical app data unless a matching
data API interface, normalizer, persistence path, and readback query exist.

## Dashboard Design Rules

- **Self-contained**: inline CSS/JS, no external CDN dependency
- **Dark theme**: background `#131722`, text `#d1d4dc`
- **Responsive**: use viewport units plus flexbox/grid
- **File location**: write pages under `memory/pages/`
- After every create/update, refresh the `memory/pages/INDEX.md` index

## Dashboard Template Reference

The skill folder includes `dashboard.html` with a 4-panel TradingView layout. Follow the newer page rules from the `tradingview` skill when they differ.

## Debug Logs

- `memory/.bridge_logs/bridge_<date>.log` - API call log
- `memory/.bridge_logs/js_errors_<date>.log` - JavaScript error log
