part of 'reusable_data_store.dart';

extension ReusableDataStoreCoverageSummaryTables on ReusableDataStore {
  Map<String, dynamic> reusableSummary() {
    final db = _db;
    if (db == null) {
      return {'available': false, 'message': 'Reusable data store unavailable'};
    }

    final quote = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(timestamp) AS latest FROM quote_snapshot',
        )
        .first;
    final kline = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MIN(date) AS earliest, MAX(date) AS latest FROM kline_daily',
        )
        .first;
    final tickChart = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(trade_date) AS latest FROM tick_chart_intraday',
        )
        .first;
    final transactions = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(trade_date) AS latest FROM transactions',
        )
        .first;
    final volumeProfile = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(trade_date) AS latest FROM volume_profile',
        )
        .first;
    final tdxCounts = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT scope) AS scopes, MAX(fetched_at) AS latest FROM tdx_security_count',
        )
        .first;
    final tdxSampling = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(fetched_at) AS latest FROM tdx_chart_sampling',
        )
        .first;
    final exTable = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT entry_key) AS entries, MAX(updated_at) AS latest FROM ex_table_entry',
        )
        .first;
    final auction = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(trade_date) AS latest FROM auction_snapshot',
        )
        .first;
    final xdxr = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(event_date) AS latest FROM xdxr_event',
        )
        .first;
    final companyInfo = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(fetched_at) AS latest FROM stock_company_info',
        )
        .first;
    final hotRank = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(trade_date) AS latest FROM hot_rank',
        )
        .first;
    final dragonTiger = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(trade_date) AS latest FROM dragon_tiger',
        )
        .first;
    final limitPool = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(trade_date) AS latest FROM limit_pool',
        )
        .first;
    final northboundFlow = db
        .select(
          'SELECT COUNT(*) AS rows, MAX(trade_date) AS latest FROM northbound_flow',
        )
        .first;
    final northboundHolding = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(trade_date) AS latest FROM northbound_holding',
        )
        .first;
    final unusualActivity = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(event_date) AS latest FROM unusual_activity',
        )
        .first;
    final flowRank = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(trade_date) AS latest FROM flow_rank',
        )
        .first;
    final fundamental = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MIN(report_date) AS earliest, MAX(report_date) AS latest FROM fundamental',
        )
        .first;
    final moneyFlow = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MIN(date) AS earliest, MAX(date) AS latest FROM money_flow',
        )
        .first;
    final fundNav = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MIN(date) AS earliest, MAX(date) AS latest FROM fund_nav',
        )
        .first;
    final fundHolding = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT fund_code) AS funds, COUNT(DISTINCT stock_code) AS stocks, MAX(report_date) AS latest FROM fund_holding',
        )
        .first;
    final fundManager = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT manager_name) AS managers, COUNT(DISTINCT fund_code) AS funds, MAX(updated_at) AS latest FROM fund_manager',
        )
        .first;
    final financeNews = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT source) AS sources, MAX(published_at) AS latest FROM finance_news',
        )
        .first;
    final fundPerformance = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS funds, MAX(metric_date) AS latest FROM fund_performance_metrics',
        )
        .first;
    final indexConstituent = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT index_code) AS indexes, COUNT(DISTINCT stock_code) AS stocks, MAX(as_of_date) AS latest FROM index_constituent',
        )
        .first;
    final stockList = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(updated_at) AS latest FROM stock_list',
        )
        .first;
    final exCategory = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT category) AS categories, MAX(updated_at) AS latest FROM ex_category',
        )
        .first;
    final windDocument = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT COALESCE(entity_code, doc_id)) AS entities, MAX(updated_at) AS latest FROM wind_document',
        )
        .first;
    final windEconomicSeries = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT series_key) AS series, MAX(updated_at) AS latest FROM wind_economic_series',
        )
        .first;
    final windAnalytics = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT COALESCE(entity_code, result_id)) AS entities, MAX(updated_at) AS latest FROM wind_analytics_result',
        )
        .first;
    final fundList = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT code) AS codes, MAX(updated_at) AS latest FROM fund_list',
        )
        .first;
    final marketScreening = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols, MAX(screened_at) AS latest FROM market_screening_snapshot',
        )
        .first;
    final technicalIndicator = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols, COUNT(DISTINCT indicator) AS indicators, MAX(source_date) AS latest FROM technical_indicator_series',
        )
        .first;
    final alphaFactor = db
        .select(
          'SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols, COUNT(DISTINCT factor_name) AS factors, MAX(source_date) AS latest FROM alpha_factor',
        )
        .first;
    return {
      'available': true,
      'quote_snapshot': _rowMap(quote),
      'kline_daily': _rowMap(kline),
      'tick_chart_intraday': _rowMap(tickChart),
      'transactions': _rowMap(transactions),
      'volume_profile': _rowMap(volumeProfile),
      'tdx_security_count': _rowMap(tdxCounts),
      'tdx_chart_sampling': _rowMap(tdxSampling),
      'ex_table_entry': _rowMap(exTable),
      'auction_snapshot': _rowMap(auction),
      'xdxr_event': _rowMap(xdxr),
      'stock_company_info': _rowMap(companyInfo),
      'hot_rank': _rowMap(hotRank),
      'dragon_tiger': _rowMap(dragonTiger),
      'limit_pool': _rowMap(limitPool),
      'northbound_flow': _rowMap(northboundFlow),
      'northbound_holding': _rowMap(northboundHolding),
      'unusual_activity': _rowMap(unusualActivity),
      'flow_rank': _rowMap(flowRank),
      'fundamental': _rowMap(fundamental),
      'money_flow': _rowMap(moneyFlow),
      'fund_nav': _rowMap(fundNav),
      'fund_holding': _rowMap(fundHolding),
      'fund_manager': _rowMap(fundManager),
      'finance_news': _rowMap(financeNews),
      'fund_performance_metrics': _rowMap(fundPerformance),
      'index_constituent': _rowMap(indexConstituent),
      'stock_list': _rowMap(stockList),
      'ex_category': _rowMap(exCategory),
      'wind_document': _rowMap(windDocument),
      'wind_economic_series': _rowMap(windEconomicSeries),
      'wind_analytics_result': _rowMap(windAnalytics),
      'fund_list': _rowMap(fundList),
      'market_screening_snapshot': _rowMap(marketScreening),
      'technical_indicator_series': _rowMap(technicalIndicator),
      'alpha_factor': _rowMap(alphaFactor),
      ...reusableSummaryYfinanceTables(db),
      'sources': _reusableSummarySources(db),
    };
  }
}
