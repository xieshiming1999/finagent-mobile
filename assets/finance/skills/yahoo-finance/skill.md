---
description: "Use for FinAgent/mobile Yahoo Finance data: US/HK/global quotes, history for backtests, earnings summaries, ETFs, indices, FX, and crypto. Do not use for China A-shares."
when_to_use: "Load when the user asks for Yahoo/yfinance, US stocks, HK stocks, global indices, ETFs, crypto, FX, non-A-share prices/history/earnings, or global-market fallback data in FinAgent/mobile."
---

# Yahoo Finance / yfinance on FinAgent

FinAgent/mobile does not run the Python yfinance sidecar. Use the native
`MarketData` tool, which calls Yahoo Finance REST directly for non-A-share
global instruments.

## Core Rules

- Use Yahoo only for non-A-share instruments: US stocks, HK stocks, ETFs,
  global indices, FX, and crypto.
- Do not use Yahoo/yfinance for China A-share symbols such as `600519`,
  `000001`, `600519.SH`, or `000001.SZ`.
- Prefer `MarketData` over direct `WebFetch`; use direct Yahoo URLs only when
  the tool lacks the needed route.
- Disclose source and freshness/delay when using Yahoo data.

## Preferred Calls

```text
MarketData(action: "interfaces", category: "global_market")
MarketData(action: "interface_describe", interfaceId: "stock.quote")
MarketData(action: "interface_availability", interfaceId: "stock.quote", provider: "yfinance", providerMode: "strict")
MarketData(action: "data_health")
MarketData(action: "coverage", symbols: ["AAPL"])
MarketData(action: "query_quote", symbols: ["AAPL"])
MarketData(action: "query_kline", symbols: ["AAPL"], adjust: "none")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "profile")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "statements")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "earnings_calendar")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "earnings_history")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "earnings_estimates")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "eps_revisions")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "eps_trend")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "quarterly_financial_statements")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "recommendations")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "upgrade_downgrade_events")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "news")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "option_expiries")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "options")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "option_open_interest")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "option_volume")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "option_implied_volatility")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "option_moneyness")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "option_bid_ask_spread")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "option_price_change")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "option_trade_recency")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "actions")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "dividends")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "splits")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "holders")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "institutional_holders")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "mutual_fund_holders")
MarketData(action: "query_yfinance", symbols: ["AAPL"], dataset: "insiders")
MarketData(action: "price", symbols: ["AAPL", "0700.HK", "BTC-USD", "^GSPC"])
MarketData(action: "backtest", symbols: ["AAPL"], strategy: "compare", period: "1y")
MarketData(action: "earnings", symbols: ["AAPL"])
MarketData(action: "yahoo_news", symbols: ["AAPL"], limit: 10)
MarketData(action: "yahoo_options", symbols: ["AAPL"], expiry: "2026-06-19")
MarketData(action: "yahoo_actions", symbols: ["AAPL"], period: "5y")
```

Run the local readback calls first. `cacheStatus:local-hit` means canonical rows
were reused; `cacheStatus:local-miss` means the local store has no reusable row
for that dataset/symbol and a governed Yahoo fetch may be needed. A local miss
is not proof that the instrument has no data.

Successful Yahoo `price` calls persist quote snapshots. Successful non-A-share
backtest/history calls persist daily K-line rows with `source:"yahoo"` and
`adjust:"none"`. Successful Yahoo `earnings` calls persist
`defaultKeyStatistics` to `yfinance_profile_fields` and income/balance/EPS
statement items to `yfinance_statement_items`, plus recommendations,
upgrade/downgrade views, holders, and insider transactions. `yahoo_news`,
`yahoo_options`, and `yahoo_actions` persist typed news, option expiry/contract,
open interest, implied volatility, and corporate action rows. Unknown Yahoo
endpoints are output-only until a code normalizer is added.

## Symbol Formats

| Market         | Format           | Examples                     |
| -------------- | ---------------- | ---------------------------- |
| US stock / ETF | plain ticker     | `AAPL`, `MSFT`, `SPY`, `QQQ` |
| Hong Kong      | 4 digits + `.HK` | `0700.HK`, `9988.HK`         |
| Global index   | `^` prefix       | `^GSPC`, `^IXIC`, `^VIX`     |
| Crypto         | `XXX-USD`        | `BTC-USD`, `ETH-USD`         |
| FX             | `XXXYYY=X`       | `EURUSD=X`, `USDJPY=X`       |

## URL Families

Use these only when `MarketData` cannot cover the task:

| Purpose              | URL family                                                                                                         |
| -------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Chart quote/history  | `https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?interval=1d&range=2d`                                  |
| CSV history download | `https://query1.finance.yahoo.com/v7/finance/download/{symbol}?period1=...&period2=...&interval=1d&events=history` |
| Multi-symbol quote   | `https://query1.finance.yahoo.com/v7/finance/quote?symbols=AAPL,MSFT`                                              |
| Quote summary        | `https://query1.finance.yahoo.com/v10/finance/quoteSummary/{symbol}?modules=...`                                   |
| Search               | `https://query1.finance.yahoo.com/v1/finance/search?q=AAPL`                                                        |
| Options              | `https://query1.finance.yahoo.com/v7/finance/options/{symbol}`                                                     |
| Trending             | `https://query1.finance.yahoo.com/v1/finance/trending/{region}`                                                    |
| News RSS             | `https://feeds.finance.yahoo.com/rss/2.0/headline?s={symbol}&region=US&lang=en-US`                                 |

`query2.finance.yahoo.com` often mirrors the same endpoint families.
