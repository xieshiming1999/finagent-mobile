# Advanced Chart Widget

Prefer the official external embedding script:

`https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js`

Generated dashboard widgets should use daily/weekly/monthly intervals (`D`,
`W`, `M`). If the user needs minute-level charts, use local K-line/minute data
or link out to TradingView instead of generating minute-level dashboard widgets.

For China-market dashboards, use red up / green down overrides:

```json
"overrides": {
  "mainSeriesProperties.candleStyle.upColor": "#ef5350",
  "mainSeriesProperties.candleStyle.downColor": "#26a69a",
  "mainSeriesProperties.candleStyle.borderUpColor": "#ef5350",
  "mainSeriesProperties.candleStyle.borderDownColor": "#26a69a",
  "mainSeriesProperties.candleStyle.wickUpColor": "#ef5350",
  "mainSeriesProperties.candleStyle.wickDownColor": "#26a69a"
}
```

Mobile pages must also render a local Canvas/SVG/HTML fallback from
`MarketData` K-line rows. Do not rely on this widget as the only chart.
