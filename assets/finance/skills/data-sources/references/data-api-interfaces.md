# Data API Interfaces

Generated from the code-owned shared_mobile_finagent finance data API contract. Use this table to choose requirement-level workflows before raw provider diagnostics.

Contract version: 2026-06-25

| Interface | Canonical schema | Query/readback | Cache lookup | Supported providers | Blocked/output-only providers |
|---|---|---|---|---|---|
| `stock.identity_list` | `stock_list` | `query_stock_list` | readback-declared<br>`query_stock_list` | tdx:supported, eastmoneyDirect:supported, sina:supported, tencent:supported | tushare:credential-gated, wind:credential-gated |
| `stock.quote` | `quote_snapshot` | `query_quote` | readback-declared<br>`query_quote` | tdx:supported, eastmoneyDirect:supported, sina:supported, tencent:supported, tencent:global-only, yfinance:global-only | wind:credential-gated, tushare:not-supported |
| `index.quote` | `quote_snapshot` | `query_index_quote`, `query_quote` | readback-declared<br>`query_index_quote,query_quote` | tdx:supported, sina:supported, eastmoneyDirect:supported, tencent:supported | wind:credential-gated |
| `index.daily_kline` | `kline_daily` | `query_kline` | readback-declared<br>`query_kline` | tdx:supported, eastmoneyDirect:supported, tencent:supported | tushare:credential-gated, wind:credential-gated |
| `stock.daily_kline` | `kline_daily` | `query_kline` | readback-declared<br>`query_kline` | tdx:supported, eastmoneyDirect:supported, sina:supported, tencent:supported, tushare:supported, yfinance:global-only | akshare:not-supported, wind:credential-gated |
| `market.intraday_ohlcv_bars` | `intraday_ohlcv_bars` | `query_intraday_ohlcv_bars` | readback-declared<br>`query_intraday_ohlcv_bars` | sina:supported/origin:sina | tdx:not-supported, eastmoneyDirect:not-supported, tencent:not-supported |
| `index.constituents` | `index_constituent` | `query_index_constituents` | readback-declared<br>`query_index_constituents` | - | akshare:not-supported, eastmoneyDirect:not-supported, tdx:not-supported, wind:not-supported, tushare:credential-gated |
| `fund.identity_list` | `fund_list` | `query_fund_list` | readback-declared<br>`query_fund_list` | eastmoneyDirect:supported | akshare:not-supported/origin:eastmoney, tushare:disabled, wind:credential-gated |
| `fund.performance_metrics` | `fund_performance_metrics` | `query_fund_performance` | readback-declared<br>`query_fund_performance` | eastmoneyDirect:supported | akshare:not-supported, wind:credential-gated |
| `fund.holding` | `fund_holding` | `query_fund_holding` | readback-declared<br>`query_fund_holding` | eastmoneyDirect:supported | akshare:not-supported, wind:credential-gated |
| `fund.company_info` | `stock_company_info` | `query_fund_company_info`, `query_company_info` | readback-declared<br>`query_fund_company_info,query_company_info` | - | wind:credential-gated |
| `fund.financials` | `fundamental` | `query_fund_financials`, `query_fundamental` | readback-declared<br>`query_fund_financials,query_fundamental` | - | wind:credential-gated |
| `fund.investor_holders` | `stock_company_info` | `query_fund_investor_holders`, `query_company_info` | readback-declared<br>`query_fund_investor_holders,query_company_info` | - | wind:credential-gated |
| `stock.money_flow` | `money_flow` | `query_money_flow` | readback-declared<br>`query_money_flow` | eastmoneyDirect:supported | akshare:not-supported, tushare:disabled, tdx:not-supported, wind:credential-gated |
| `stock.daily_valuation` | `fundamental` | `query_stock_daily_valuation`, `query_fundamental` | readback-declared<br>`query_stock_daily_valuation,query_fundamental` | tushare:supported, eastmoneyDirect:supported, tdx:supported | wind:credential-gated, akshare:not-supported |
| `fund.etf_quote` | `quote_snapshot` | `query_etf_quote`, `query_quote`, `query_stock_list` | readback-declared<br>`query_etf_quote,query_quote,query_stock_list` | eastmoneyDirect:supported, sina:supported, tencent:supported | akshare:not-supported, wind:credential-gated |
| `fund.listed_fund_quote` | `quote_snapshot` | `query_listed_fund_quote`, `query_quote`, `query_stock_list` | readback-declared<br>`query_listed_fund_quote,query_quote,query_stock_list` | tencent:supported | eastmoneyDirect:not-supported, akshare:not-supported, sina:not-supported, wind:not-supported |
| `fund.etf_daily_ohlcv_bars` | `kline_daily` | `query_kline` | readback-declared<br>`query_kline` | tencent:supported | eastmoneyDirect:not-supported, akshare:not-supported/origin:sina, sina:not-supported, wind:not-supported |
| `fund.etf_transactions` | `transactions` | `query_transactions` | readback-declared<br>`query_transactions` | tencent:supported | tdx:not-supported, sina:not-supported, eastmoneyDirect:not-supported, akshare:not-supported, wind:not-supported |
| `fund.manager` | `fund_manager` | `query_fund_manager` | readback-declared<br>`query_fund_manager` | eastmoneyDirect:supported | akshare:not-supported, wind:credential-gated |
| `fund.nav_history` | `fund_nav` | `query_fund_nav` | readback-declared<br>`query_fund_nav` | eastmoneyDirect:supported | akshare:not-supported/origin:eastmoney, tushare:disabled, wind:credential-gated |
| `fund.money_yield_history` | `fund_money_yield` | `query_fund_money_yield` | readback-declared<br>`query_fund_money_yield` | eastmoneyDirect:supported | akshare:not-supported/origin:eastmoney, tushare:disabled, wind:not-supported |
| `fund.dividend_factor` | `fund_dividend_factor` | `query_fund_dividend_factor` | readback-declared<br>`query_fund_dividend_factor` | sina:supported/origin:sina | eastmoneyDirect:not-supported, wind:not-supported |
| `stock.chip_distribution` | `chip_distribution` | `query_chip` | readback-declared<br>`query_chip` | eastmoneyDirect:supported | akshare:not-supported, tdx:not-supported, wind:not-supported |
| `market.sector_ranking` | `sector_rank` | `query_sector_ranking`, `query_sector` | readback-declared<br>`query_sector_ranking,query_sector` | eastmoneyDirect:supported, sina:supported | akshare:not-supported, tdx:not-supported, tushare:not-supported, wind:not-supported |
| `market.sector_constituents` | `industry_map` | `query_sector_constituents`, `query_industry_map`, `query_quote`, `query_stock_list` | readback-declared<br>`query_sector_constituents,query_industry_map,query_quote,query_stock_list` | eastmoneyDirect:supported, sina:supported | akshare:not-supported, tdx:not-supported, wind:not-supported |
| `market.board_ranking` | `sector_rank` | `query_board_ranking`, `query_sector` | readback-declared<br>`query_board_ranking,query_sector` | eastmoneyDirect:supported, sina:supported | akshare:not-supported, tdx:not-supported, wind:not-supported |
| `market.board_members` | `industry_map` | `query_board_members`, `query_industry_map`, `query_quote` | readback-declared<br>`query_board_members,query_industry_map,query_quote` | eastmoneyDirect:supported, sina:supported | akshare:not-supported, tdx:not-supported, wind:not-supported |
| `market.northbound_flow` | `northbound_flow` | `query_northbound_flow`, `query_northbound` | readback-declared<br>`query_northbound_flow,query_northbound` | eastmoneyDirect:supported | akshare:not-supported, tdx:not-supported, tushare:not-supported, wind:not-supported |
| `market.northbound_holding` | `northbound_holding` | `query_northbound_holding`, `query_northbound` | readback-declared<br>`query_northbound_holding,query_northbound` | eastmoneyDirect:supported | akshare:not-supported, tdx:not-supported, wind:not-supported |
| `market.hot_rank` | `hot_rank` | `query_hot_rank` | readback-declared<br>`query_hot_rank` | eastmoneyDirect:supported | akshare:not-supported, tdx:not-supported, tushare:not-supported, wind:not-supported |
| `market.dragon_tiger` | `dragon_tiger` | `query_dragon_tiger` | readback-declared<br>`query_dragon_tiger` | eastmoneyDirect:supported | akshare:not-supported, tdx:not-supported, tushare:not-supported, wind:not-supported |
| `market.unusual_activity` | `unusual_activity` | `query_unusual` | readback-declared<br>`query_unusual` | eastmoneyDirect:supported, tdx:supported | akshare:not-supported, tushare:not-supported, wind:not-supported |
| `market.flow_rank` | `flow_rank` | `query_flow_rank` | readback-declared<br>`query_flow_rank` | eastmoneyDirect:supported | akshare:not-supported, tdx:not-supported, tushare:not-supported, wind:not-supported |
| `calendar.trade_days` | `trade_calendar` | `query_trade_calendar` | readback-declared<br>`query_trade_calendar` | szse:supported, tushare:supported | akshare:not-supported/origin:sina, eastmoneyDirect:not-supported, tdx:not-supported |
| `market.limit_pool` | `limit_pool` | `query_limit_pool` | readback-declared<br>`query_limit_pool` | eastmoneyDirect:supported | akshare:not-supported, tushare:not-supported, tdx:not-supported, wind:not-supported |
| `stock.tick_chart_intraday` | `tick_chart_intraday` | `query_tick_chart` | readback-declared<br>`query_tick_chart` | tdx:supported | eastmoneyDirect:not-supported, wind:not-supported |
| `stock.transactions` | `transactions` | `query_transactions` | readback-declared<br>`query_transactions` | tdx:supported, sina:supported, tencent:supported | eastmoneyDirect:not-supported, wind:not-supported |
| `stock.volume_profile` | `volume_profile` | `query_volume_profile` | readback-declared<br>`query_volume_profile` | tdx:supported | eastmoneyDirect:not-supported, wind:not-supported |
| `stock.xdxr_events` | `xdxr_event` | `query_xdxr` | readback-declared<br>`query_xdxr` | tdx:supported | eastmoneyDirect:not-supported, wind:credential-gated |
| `stock.auction_snapshot` | `auction_snapshot` | `query_auction` | readback-declared<br>`query_auction` | tdx:supported | eastmoneyDirect:not-supported, wind:not-supported |
| `stock.company_info` | `stock_company_info` | `query_stock_company_info`, `query_company_info` | readback-declared<br>`query_stock_company_info,query_company_info` | tdx:supported, eastmoneyDirect:supported | wind:credential-gated |
| `stock.shareholders` | `stock_shareholder` | `query_stock_shareholders` | readback-declared<br>`query_stock_shareholders` | eastmoneyDirect:supported | akshare:not-supported, wind:credential-gated, tdx:not-supported |
| `stock.risk_metrics` | `stock_company_info` | `query_stock_risk_metrics`, `query_company_info` | readback-declared<br>`query_stock_risk_metrics,query_company_info` | - | wind:credential-gated |
| `provider.api_call_log` | `api_call_log` | `query_api_calls`, `query_api_errors` | readback-declared<br>`query_api_calls,query_api_errors` | local:supported | eastmoneyDirect:not-supported, tdx:not-supported, yfinance:not-supported, wind:not-supported |
| `provider.fetch_task_queue` | `fetch_task_queue` | `fetch_status` | readback-declared<br>`fetch_status` | local:supported | eastmoneyDirect:not-supported, tdx:not-supported, yfinance:not-supported, wind:not-supported |
| `provider.coverage` | `provider_coverage` | `query_tdx_count`, `query_tdx_sampling` | readback-declared<br>`query_tdx_count,query_tdx_sampling` | tdx:supported | eastmoneyDirect:not-supported, akshare:not-supported |
| `provider.table_metadata` | `provider_table_metadata` | `query_ex_categories`, `query_ex_table` | readback-declared<br>`query_ex_categories,query_ex_table` | tdx:supported | eastmoneyDirect:not-supported, akshare:not-supported |
| `market.tdx_block_member` | `tdx_block_member` | `query_tdx_block_member` | readback-declared<br>`query_tdx_block_member` | tdx:supported | eastmoneyDirect:not-supported |
| `market.tdx_top_board` | `tdx_top_board` | `query_top_board` | readback-declared<br>`query_top_board` | tdx:supported | eastmoneyDirect:not-supported |
| `index.momentum` | `tdx_index_momentum` | `query_momentum` | readback-declared<br>`query_momentum` | tdx:supported | eastmoneyDirect:not-supported, wind:credential-gated |
| `index.profile` | `stock_company_info` | `query_index_profile`, `query_company_info` | readback-declared<br>`query_index_profile,query_company_info` | - | wind:credential-gated |
| `index.fundamentals` | `fundamental` | `query_index_fundamentals`, `query_fundamental` | readback-declared<br>`query_index_fundamentals,query_fundamental` | - | wind:credential-gated |
| `wind.financial_document` | `wind_document` | `query_wind_document` | readback-declared<br>`query_wind_document` | - | wind:credential-gated |
| `wind.economic_series` | `wind_economic_series` | `query_wind_economic` | readback-declared<br>`query_wind_economic` | - | wind:credential-gated |
| `wind.analytics_result` | `wind_analytics_result` | `query_wind_analytics` | readback-declared<br>`query_wind_analytics` | - | wind:credential-gated |
| `news.finance_feed` | `finance_news` | `query_finance_news` | readback-declared<br>`query_finance_news` | eastmoneyDirect:supported, sina:supported | tushare:credential-gated, wind:credential-gated, yfinance:not-supported |
| `global.company_profile` | `yfinance_profile_fields` | `query_global_company_profile`, `query_yfinance` | readback-declared<br>`query_global_company_profile,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.financial_statements` | `yfinance_statement_items` | `query_global_financial_statements`, `query_yfinance` | readback-declared<br>`query_global_financial_statements,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.income_statement` | `yfinance_statement_items` | `query_global_income_statement`, `query_yfinance` | readback-declared<br>`query_global_income_statement,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.balance_sheet` | `yfinance_statement_items` | `query_global_balance_sheet`, `query_yfinance` | readback-declared<br>`query_global_balance_sheet,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.cash_flow` | `yfinance_statement_items` | `query_global_cash_flow`, `query_yfinance` | readback-declared<br>`query_global_cash_flow,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.earnings_calendar` | `yfinance_statement_items` | `query_global_earnings_calendar`, `query_yfinance` | readback-declared<br>`query_global_earnings_calendar,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.earnings_history` | `yfinance_statement_items` | `query_global_earnings_history`, `query_yfinance` | readback-declared<br>`query_global_earnings_history,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.earnings_estimates` | `yfinance_statement_items` | `query_global_earnings_estimates`, `query_yfinance` | readback-declared<br>`query_global_earnings_estimates,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.eps_revisions` | `yfinance_statement_items` | `query_global_eps_revisions`, `query_yfinance` | readback-declared<br>`query_global_eps_revisions,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.eps_trend` | `yfinance_statement_items` | `query_global_eps_trend`, `query_yfinance` | readback-declared<br>`query_global_eps_trend,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.quarterly_financial_statements` | `yfinance_statement_items` | `query_global_quarterly_financial_statements`, `query_yfinance` | readback-declared<br>`query_global_quarterly_financial_statements,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.quarterly_income_statement` | `yfinance_statement_items` | `query_global_quarterly_income_statement`, `query_yfinance` | readback-declared<br>`query_global_quarterly_income_statement,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.quarterly_balance_sheet` | `yfinance_statement_items` | `query_global_quarterly_balance_sheet`, `query_yfinance` | readback-declared<br>`query_global_quarterly_balance_sheet,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.quarterly_cash_flow` | `yfinance_statement_items` | `query_global_quarterly_cash_flow`, `query_yfinance` | readback-declared<br>`query_global_quarterly_cash_flow,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.recommendations` | `yfinance_recommendations` | `query_global_recommendations`, `query_yfinance` | readback-declared<br>`query_global_recommendations,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.upgrade_downgrade_events` | `yfinance_recommendations` | `query_global_upgrade_downgrade_events`, `query_yfinance` | readback-declared<br>`query_global_upgrade_downgrade_events,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.holders` | `yfinance_holders` | `query_global_holders`, `query_yfinance` | readback-declared<br>`query_global_holders,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.major_holders` | `yfinance_holders` | `query_global_major_holders`, `query_yfinance` | readback-declared<br>`query_global_major_holders,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.institutional_holders` | `yfinance_holders` | `query_global_institutional_holders`, `query_yfinance` | readback-declared<br>`query_global_institutional_holders,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.mutual_fund_holders` | `yfinance_holders` | `query_global_mutual_fund_holders`, `query_yfinance` | readback-declared<br>`query_global_mutual_fund_holders,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.insider_transactions` | `yfinance_insider_transactions` | `query_global_insider_transactions`, `query_yfinance` | readback-declared<br>`query_global_insider_transactions,query_yfinance` | yfinance:global-only | wind:not-supported |
| `option.expiry_calendar` | `yfinance_option_expiries` | `query_option_expiry_calendar`, `query_yfinance` | readback-declared<br>`query_option_expiry_calendar,query_yfinance` | yfinance:global-only | wind:not-supported |
| `option.contract_list` | `yfinance_option_contracts` | `query_option_contract_list`, `query_yfinance` | readback-declared<br>`query_option_contract_list,query_yfinance` | yfinance:global-only | wind:not-supported |
| `option.quote` | `yfinance_option_contracts` | `query_option_quote`, `query_yfinance` | readback-declared<br>`query_option_quote,query_yfinance` | yfinance:global-only | wind:not-supported |
| `option.daily_kline` | `kline_daily` | `query_option_daily_kline`, `query_kline` | readback-declared<br>`query_option_daily_kline,query_kline` | yfinance:global-only | wind:not-supported |
| `option.open_interest` | `yfinance_option_contracts` | `query_option_open_interest`, `query_yfinance` | readback-declared<br>`query_option_open_interest,query_yfinance` | yfinance:global-only | wind:not-supported |
| `option.volume` | `yfinance_option_contracts` | `query_option_volume`, `query_yfinance` | readback-declared<br>`query_option_volume,query_yfinance` | yfinance:global-only | wind:not-supported |
| `option.implied_volatility` | `yfinance_option_contracts` | `query_option_implied_volatility`, `query_yfinance` | readback-declared<br>`query_option_implied_volatility,query_yfinance` | yfinance:global-only | wind:not-supported |
| `option.moneyness` | `yfinance_option_contracts` | `query_option_moneyness`, `query_yfinance` | readback-declared<br>`query_option_moneyness,query_yfinance` | yfinance:global-only | wind:not-supported |
| `option.bid_ask_spread` | `yfinance_option_contracts` | `query_option_bid_ask_spread`, `query_yfinance` | readback-declared<br>`query_option_bid_ask_spread,query_yfinance` | yfinance:global-only | wind:not-supported |
| `option.price_change` | `yfinance_option_contracts` | `query_option_price_change`, `query_yfinance` | readback-declared<br>`query_option_price_change,query_yfinance` | yfinance:global-only | wind:not-supported |
| `option.trade_recency` | `yfinance_option_contracts` | `query_option_trade_recency`, `query_yfinance` | readback-declared<br>`query_option_trade_recency,query_yfinance` | yfinance:global-only | wind:not-supported |
| `option.chain_snapshot` | `yfinance_options` | `query_option_chain_snapshot`, `query_yfinance` | readback-declared<br>`query_option_chain_snapshot,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.options_chain` | `yfinance_options` | `query_global_options_chain`, `query_yfinance` | readback-declared<br>`query_global_options_chain,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.corporate_actions` | `yfinance_corporate_actions` | `query_global_corporate_actions`, `query_yfinance` | readback-declared<br>`query_global_corporate_actions,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.dividends` | `yfinance_corporate_actions` | `query_global_dividends`, `query_yfinance` | readback-declared<br>`query_global_dividends,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.capital_gains` | `yfinance_corporate_actions` | `query_global_capital_gains`, `query_yfinance` | readback-declared<br>`query_global_capital_gains,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.stock_splits` | `yfinance_corporate_actions` | `query_global_stock_splits`, `query_yfinance` | readback-declared<br>`query_global_stock_splits,query_yfinance` | yfinance:global-only | wind:not-supported |
| `global.finance_news` | `yfinance_news` | `query_global_finance_news`, `query_yfinance` | readback-declared<br>`query_global_finance_news,query_yfinance` | yfinance:global-only | wind:not-supported |
| `market.screening` | `screening_result` | `query_market_screening` | readback-declared<br>`query_market_screening` | tradingview:supported | wind:credential-gated |
| `market.margin_trading` | `margin_trading` | `query_margin_trading` | readback-declared<br>`query_margin_trading` | szse:supported | akshare:not-supported |
| `data.coverage` | `data_coverage` | `coverage`, `reusable_summary` | readback-declared<br>`coverage,reusable_summary` | local:supported | eastmoneyDirect:not-supported, akshare:not-supported, tdx:not-supported, tushare:not-supported, yfinance:not-supported, wind:not-supported |
| `data.store_stats` | `data_store_stats` | `stats` | readback-declared<br>`stats` | local:supported | eastmoneyDirect:not-supported, akshare:not-supported, tdx:not-supported, tushare:not-supported, yfinance:not-supported, wind:not-supported |
| `provider.source_status` | `provider_source_status` | `sources` | readback-declared<br>`sources` | local:supported | eastmoneyDirect:not-supported, akshare:not-supported, tdx:not-supported, tushare:not-supported, yfinance:not-supported, wind:not-supported |
| `data.health` | `data_health_report` | `data_health` | readback-declared<br>`data_health` | local:supported | eastmoneyDirect:not-supported, akshare:not-supported, tdx:not-supported, tushare:not-supported, yfinance:not-supported, wind:not-supported |
| `data.runtime_probe` | `runtime_probe_status` | `runtime_probe` | readback-declared<br>`runtime_probe` | local:supported | eastmoneyDirect:not-supported, akshare:not-supported, tdx:not-supported, tushare:not-supported, yfinance:not-supported, wind:not-supported |
| `data.feed_status` | `data_feed_config` | - | not-implemented | - | local:not-supported, eastmoneyDirect:not-supported, akshare:not-supported, tdx:not-supported, tushare:not-supported, yfinance:not-supported, wind:not-supported |
| `bond.convertible_quote` | `quote_snapshot` | `query_bond_quote`, `query_quote` | readback-declared<br>`query_bond_quote,query_quote` | tencent:supported | wind:not-supported, eastmoneyDirect:not-supported, akshare:not-supported, sina:not-supported |
| `bond.convertible_daily_kline` | `kline_daily` | `query_bond_kline`, `query_kline` | readback-declared<br>`query_bond_kline,query_kline` | tencent:supported | wind:not-supported, eastmoneyDirect:not-supported, akshare:not-supported, sina:not-supported |
| `bond.profile` | `stock_company_info` | `query_bond_profile`, `query_company_info` | readback-declared<br>`query_bond_profile,query_company_info` | - | wind:credential-gated |
| `bond.market_data` | `stock_company_info` | `query_bond_market_data`, `query_company_info` | readback-declared<br>`query_bond_market_data,query_company_info` | - | wind:credential-gated |
| `bond.issuer_financials` | `fundamental` | `query_bond_issuer_financials`, `query_fundamental` | readback-declared<br>`query_bond_issuer_financials,query_fundamental` | - | wind:credential-gated |
| `technical.indicator_series` | `technical_indicator_series` | `query_technical_indicator` | readback-declared<br>`query_technical_indicator` | local:supported | tradingview:not-supported, wind:credential-gated |
| `stock.alpha_factors` | `alpha_factor` | `query_alpha_factors` | readback-declared<br>`query_alpha_factors` | local:supported | akshare:not-supported, wind:not-supported |

Provider parameters are routing constraints for these interfaces. They are not permission to bypass local cache/readback, canonical normalizers, persistence, or API health policy.

Cache reuse rule: default `cache-first` reads canonical local rows before provider
routing and reuses them only when the interface-specific source data timestamp,
date window, or coverage rule satisfies the request. Local `fetched_at` records
ingest time and must not be used as market freshness. `live-only` bypasses
local rows, `cache-only` refuses provider calls after a miss, and
`providerMode: strict` requires any cache hit to carry matching provider/source
evidence before reuse; otherwise the cache is treated as a miss and only the
requested provider route is eligible. Use `live-only` when explicit provider
validation must force a live provider call.
