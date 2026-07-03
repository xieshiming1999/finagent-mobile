part of 'reusable_data_store.dart';

void _migrateReusableDataStoreIndexes(Database db) {
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_quote_snapshot_code_time ON quote_snapshot(code, timestamp)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_quote_snapshot_source_time ON quote_snapshot(source, timestamp)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_kline_daily_code_date ON kline_daily(code, date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_api_result_cache_expiry ON api_result_cache(expires_at)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_raw_api_payload_created ON raw_api_payload(created_at)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_tick_chart_code_date ON tick_chart_intraday(code, trade_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_transactions_code_date ON transactions(code, trade_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_volume_profile_code_date ON volume_profile(code, trade_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_auction_code_date ON auction_snapshot(code, trade_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_xdxr_code_date ON xdxr_event(code, event_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_tdx_index_momentum_code_date ON tdx_index_momentum(code, trade_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_tdx_top_board_date_rank ON tdx_top_board(board_date, category, side, rank)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_hot_rank_date_rank ON hot_rank(trade_date, rank)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_dragon_tiger_date ON dragon_tiger(trade_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_limit_pool_date_type ON limit_pool(trade_date, pool_type)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_northbound_flow_date ON northbound_flow(trade_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_northbound_holding_code_date ON northbound_holding(code, trade_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_unusual_activity_date_time ON unusual_activity(event_date, event_time)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_flow_rank_date_period ON flow_rank(trade_date, period)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sector_rank_date_type ON sector_rank(trade_date, board_type, rank)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_chip_distribution_code_date ON chip_distribution(code, trade_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_fundamental_code_date ON fundamental(code, report_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_money_flow_code_date ON money_flow(code, date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_industry_map_l1 ON industry_map(industry_l1)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_yfinance_statement_symbol_period ON yfinance_statement_items(symbol, period)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_yfinance_news_symbol_time ON yfinance_news(symbol, published_at)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_yfinance_options_symbol_expiry ON yfinance_option_contracts(symbol, expiry_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_yfinance_actions_symbol_date ON yfinance_corporate_actions(symbol, action_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_yfinance_holders_symbol ON yfinance_holders(symbol, holder_type)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_yfinance_insider_symbol_date ON yfinance_insider_transactions(symbol, start_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_wind_document_published ON wind_document(published_at)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_wind_document_entity ON wind_document(entity_code, published_at)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_wind_economic_series_metric_date ON wind_economic_series(metric_query, date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_wind_analytics_question_date ON wind_analytics_result(question, value_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_tdx_block_member_code ON tdx_block_member(code)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_tdx_block_member_block ON tdx_block_member(block_code)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_fund_nav_code_date ON fund_nav(code, date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_fund_money_yield_code_date ON fund_money_yield(code, date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_fund_dividend_factor_code_date ON fund_dividend_factor(code, event_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_intraday_ohlcv_code_time ON intraday_ohlcv_bars(code, bar_time)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_fund_holding_fund_date ON fund_holding(fund_code, report_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_fund_manager_name_company ON fund_manager(manager_name, company)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_fund_manager_fund ON fund_manager(fund_code)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_news_time ON finance_news(published_at, fetched_at)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_finance_news_source ON finance_news(source, published_at)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_fund_performance_code_date ON fund_performance_metrics(code, metric_date, provider)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_index_constituent_index_date ON index_constituent(index_code, as_of_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_index_constituent_stock_date ON index_constituent(stock_code, as_of_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_technical_indicator_series_symbol ON technical_indicator_series(symbol, indicator, source_date)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_technical_indicator_series_latest ON technical_indicator_series(fetched_at, provider, indicator)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_alpha_factor_symbol ON alpha_factor(symbol, source_date, factor_name)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_alpha_factor_latest ON alpha_factor(fetched_at, provider, source_action)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_stock_list_name ON stock_list(name)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_ex_category_name ON ex_category(name)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_market_screening_latest ON market_screening_snapshot(screened_at, provider)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_market_screening_symbol ON market_screening_snapshot(symbol, screened_at)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_tdx_security_count_scope_market ON tdx_security_count(scope, market, fetched_at)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_tdx_chart_sampling_scope_code ON tdx_chart_sampling(scope, code, fetched_at)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_ex_table_entry_code ON ex_table_entry(code, category, updated_at)',
  );
}
