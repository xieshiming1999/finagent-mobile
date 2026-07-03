part of 'reusable_data_store.dart';

extension ReusableDataStoreCoverageSymbolMarket on ReusableDataStore {
  Map<String, dynamic> coverage({String? code}) {
    final db = _db;
    if (db == null) {
      return {'available': false, 'message': 'Reusable data store unavailable'};
    }
    if (code == null || code.trim().isEmpty) {
      return reusableSummary();
    }

    final clean = _cleanCode(code);
    final symbol = code.trim().toUpperCase();
    final quotes = db.select(
      'SELECT COUNT(*) AS count, MAX(timestamp) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM quote_snapshot WHERE code = ?',
      [clean],
    ).first;
    final klines = db.select(
      'SELECT COUNT(*) AS count, MIN(date) AS earliest, MAX(date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM kline_daily WHERE code = ?',
      [clean],
    ).first;
    final tickChart = db.select(
      'SELECT COUNT(*) AS count, MAX(trade_date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM tick_chart_intraday WHERE code = ?',
      [clean],
    ).first;
    final transactions = db.select(
      'SELECT COUNT(*) AS count, MAX(trade_date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM transactions WHERE code = ?',
      [clean],
    ).first;
    final volumeProfile = db.select(
      'SELECT COUNT(*) AS count, MAX(trade_date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM volume_profile WHERE code = ?',
      [clean],
    ).first;
    final auction = db.select(
      'SELECT COUNT(*) AS count, MAX(trade_date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM auction_snapshot WHERE code = ?',
      [clean],
    ).first;
    final xdxr = db.select(
      'SELECT COUNT(*) AS count, MAX(event_date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM xdxr_event WHERE code = ?',
      [clean],
    ).first;
    final companyInfo = db.select(
      'SELECT COUNT(*) AS count, MAX(fetched_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM stock_company_info WHERE code = ?',
      [clean],
    ).first;
    final hotRank = db.select(
      'SELECT COUNT(*) AS count, MAX(trade_date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM hot_rank WHERE code = ?',
      [clean],
    ).first;
    final dragonTiger = db.select(
      'SELECT COUNT(*) AS count, MAX(trade_date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM dragon_tiger WHERE code = ?',
      [clean],
    ).first;
    final limitPool = db.select(
      'SELECT COUNT(*) AS count, MAX(trade_date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM limit_pool WHERE code = ?',
      [clean],
    ).first;
    final northboundHolding = db.select(
      'SELECT COUNT(*) AS count, MAX(trade_date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM northbound_holding WHERE code = ?',
      [clean],
    ).first;
    final unusualActivity = db.select(
      'SELECT COUNT(*) AS count, MAX(event_date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM unusual_activity WHERE code = ?',
      [clean],
    ).first;
    final flowRank = db.select(
      'SELECT COUNT(*) AS count, MAX(trade_date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM flow_rank WHERE code = ?',
      [clean],
    ).first;
    final fundamental = db.select(
      'SELECT COUNT(*) AS count, MIN(report_date) AS earliest, MAX(report_date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM fundamental WHERE code = ?',
      [clean],
    ).first;
    final moneyFlow = db.select(
      'SELECT COUNT(*) AS count, MIN(date) AS earliest, MAX(date) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM money_flow WHERE code = ?',
      [clean],
    ).first;
    final tdxSampling = db.select(
      'SELECT COUNT(*) AS count, MAX(fetched_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM tdx_chart_sampling WHERE code = ?',
      [clean],
    ).first;
    final exTable = db.select(
      'SELECT COUNT(*) AS count, MAX(updated_at) AS latest, GROUP_CONCAT(DISTINCT source) AS sources FROM ex_table_entry WHERE code = ?',
      [clean],
    ).first;
    return {
      'available': true,
      'code': clean,
      'symbol': symbol,
      'quote_snapshot': _rowMap(quotes),
      'kline_daily': _rowMap(klines),
      'tick_chart_intraday': _rowMap(tickChart),
      'transactions': _rowMap(transactions),
      'volume_profile': _rowMap(volumeProfile),
      'auction_snapshot': _rowMap(auction),
      'xdxr_event': _rowMap(xdxr),
      'stock_company_info': _rowMap(companyInfo),
      'hot_rank': _rowMap(hotRank),
      'dragon_tiger': _rowMap(dragonTiger),
      'limit_pool': _rowMap(limitPool),
      'northbound_holding': _rowMap(northboundHolding),
      'unusual_activity': _rowMap(unusualActivity),
      'flow_rank': _rowMap(flowRank),
      'fundamental': _rowMap(fundamental),
      'money_flow': _rowMap(moneyFlow),
      'tdx_chart_sampling': _rowMap(tdxSampling),
      'ex_table_entry': _rowMap(exTable),
      ..._coverageResearchRows(db, clean, symbol),
    };
  }
}
