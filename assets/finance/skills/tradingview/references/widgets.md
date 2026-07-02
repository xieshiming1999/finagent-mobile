# TradingView Widget Selection

TradingView widgets are display components. On mobile, they are best-effort
enhancements and must not be the only visible chart/quote content.

| Need | TradingView widget | Use |
|------|--------------------|-----|
| Main K-line | Advanced Chart | Stock/index/commodity detail page |
| Live price card | Single Ticker | Price + change percentage |
| Symbol summary | Symbol Info | Quote and basic symbol info |
| Mini chart card | Symbol Overview | Watchlist tiles and compact stock cards |
| Technical rating | Technical Analysis | Buy/sell rating, MA and oscillator summary |
| Top market strip | Ticker Tape | Dashboard header with indices/watchlist |
| Market groups | Market Overview / Market Data | Index/sector/commodity/FX overview |
| Market breadth | Stock Heatmap / ETF Heatmap / Crypto Heatmap | Risk/breadth visual |
| Interactive exploration | Screener | User-facing discovery panel |
| Company facts | Company Profile / Fundamental Data / Financials | Display-only fact panels |
| Events | Economic Calendar | Macro/event dashboard |

## Mobile Layout Guidance

- Keep pages lightweight: one main chart plus a small number of live widgets.
- Use local tables for long watchlists.
- Put local fallback content before or beside the TradingView container so the
  page is useful even when external scripts fail.
- Do not use widget DOM values for alerts, ranking, or score calculations.
