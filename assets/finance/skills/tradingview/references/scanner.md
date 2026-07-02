# TradingView Scanner

TradingView Scanner can provide global technical snapshots: RSI, MACD,
oscillator/MA ratings, volatility, relative volume, and recommendation summary.

Use the existing `tradingview-scanner` skill for detailed scanner fields,
headers, market names, and raw POST examples.

Typical market names:

- A-share: `china`, symbols like `SSE:600519`, `SZSE:000001`
- Hong Kong: `hongkong`, symbols like `HKEX:700`
- US: `america`, symbols like `NASDAQ:AAPL`, `NYSE:BABA`
- Crypto: `crypto`

Scanner output is useful for technical summary tables. It is not a replacement
for persisted quote/K-line data or local alert calculations.
