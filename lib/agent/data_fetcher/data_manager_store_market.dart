part of 'data_manager.dart';

extension DataManagerMarketStoreAccess on DataManager {
  StockQuote? getRecentQuote(String code, Duration maxAge, {String? source}) {
    return _store?.getRecentQuote(code, maxAge, source: source);
  }

  List<StockQuote> queryQuotes(String code, {int limit = 20, String? source}) {
    return _store?.queryQuotes(code, limit: limit, source: source) ?? const [];
  }

  void saveQuoteSnapshots(List<StockQuote> quotes, {String source = '通达信'}) {
    _store?.saveQuoteSnapshots(quotes, source);
  }

  void saveKlineRows(
    String code,
    List<KlineBar> bars, {
    String source = '通达信',
    String adjust = 'none',
  }) {
    _store?.saveKline(code, bars, source: source, adjust: adjust);
  }

  List<KlineBar> queryKline(
    String code, {
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
    String? source,
    int? limit,
  }) {
    return _store?.queryKline(
          code,
          startDate: startDate,
          endDate: endDate,
          adjust: adjust,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  void saveTickChart(
    String code,
    List<Map<String, dynamic>> rows, {
    String source = '通达信',
    String? tradeDate,
  }) {
    _store?.saveTickChart(code, rows, source: source, tradeDate: tradeDate);
  }

  List<Map<String, dynamic>> queryTickChart(
    String code, {
    String? tradeDate,
    int limit = 240,
  }) {
    return _store?.queryTickChart(code, tradeDate: tradeDate, limit: limit) ??
        const [];
  }

  void saveTransactions(
    String code,
    List<Map<String, dynamic>> rows, {
    String source = '通达信',
    String? tradeDate,
  }) {
    _store?.saveTransactions(code, rows, source: source, tradeDate: tradeDate);
  }

  List<Map<String, dynamic>> queryTransactions(
    String code, {
    String? tradeDate,
    int limit = 100,
  }) {
    return _store?.queryTransactions(
          code,
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        const [];
  }

  void saveVolumeProfile(
    String code,
    Map<String, dynamic> payload, {
    String source = '通达信',
    String? tradeDate,
  }) {
    _store?.saveVolumeProfile(
      code,
      payload,
      source: source,
      tradeDate: tradeDate,
    );
  }

  List<Map<String, dynamic>> queryVolumeProfile(
    String code, {
    String? tradeDate,
    int limit = 200,
  }) {
    return _store?.queryVolumeProfile(
          code,
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        const [];
  }

  void saveAuction(
    String code,
    List<Map<String, dynamic>> rows, {
    String source = '通达信',
    String? tradeDate,
  }) {
    _store?.saveAuction(code, rows, source: source, tradeDate: tradeDate);
  }

  List<Map<String, dynamic>> queryAuction(
    String code, {
    String? tradeDate,
    int limit = 100,
  }) {
    return _store?.queryAuction(code, tradeDate: tradeDate, limit: limit) ??
        const [];
  }

  void saveXdxrEvents(
    String code,
    List<Map<String, dynamic>> rows, {
    String source = '通达信',
  }) {
    _store?.saveXdxrEvents(code, rows, source: source);
  }

  List<Map<String, dynamic>> queryXdxrEvents(String code, {int limit = 50}) {
    return _store?.queryXdxrEvents(code, limit: limit) ?? const [];
  }

  void saveIndexMomentum(
    String code,
    Map<String, dynamic> payload, {
    String source = '通达信',
    String? tradeDate,
  }) {
    _store?.saveIndexMomentum(
      code,
      payload,
      source: source,
      tradeDate: tradeDate,
    );
  }

  List<Map<String, dynamic>> queryIndexMomentum(
    String code, {
    String? tradeDate,
    int limit = 200,
  }) {
    return _store?.queryIndexMomentum(
          code,
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        const [];
  }

  void saveTopBoard(
    Map<String, dynamic> payload, {
    String source = '通达信',
    String category = '0',
    String? boardDate,
  }) {
    _store?.saveTopBoard(
      payload,
      source: source,
      category: category,
      boardDate: boardDate,
    );
  }

  List<Map<String, dynamic>> queryTopBoard({
    String? code,
    String? category,
    String? side,
    String? boardDate,
    int limit = 100,
  }) {
    return _store?.queryTopBoard(
          code: code,
          category: category,
          side: side,
          boardDate: boardDate,
          limit: limit,
        ) ??
        const [];
  }

  void saveTdxBlockMembers(
    List<Map<String, dynamic>> rows, {
    String source = '通达信',
  }) {
    _store?.saveTdxBlockMembers(rows, source: source);
  }

  List<Map<String, dynamic>> queryTdxBlockMembers({
    String? code,
    String? blockCode,
    int limit = 50,
  }) {
    return _store?.queryTdxBlockMembers(
          code: code,
          blockCode: blockCode,
          limit: limit,
        ) ??
        const [];
  }

  void saveCompanyInfo(
    String code,
    String infoType,
    Map<String, dynamic> payload, {
    String source = '通达信',
  }) {
    _store?.saveCompanyInfo(code, infoType, payload, source: source);
  }

  List<Map<String, dynamic>> queryCompanyInfo(
    String code, {
    String? infoType,
    int limit = 20,
  }) {
    return _store?.queryCompanyInfo(code, infoType: infoType, limit: limit) ??
        const [];
  }

  void saveStockShareholders(
    List<Map<String, dynamic>> rows, {
    String source = 'akshare',
  }) {
    _store?.saveStockShareholders(rows, source: source);
  }

  List<Map<String, dynamic>> queryStockShareholders({
    String? code,
    String? holderName,
    String? reportDate,
    String? source,
    int limit = 100,
  }) {
    return _store?.queryStockShareholders(
          code: code,
          holderName: holderName,
          reportDate: reportDate,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  void saveHotRank(
    List<Map<String, dynamic>> rows, {
    String source = '东方财富',
    String? tradeDate,
  }) {
    _store?.saveHotRank(rows, source: source, tradeDate: tradeDate);
  }

  List<Map<String, dynamic>> queryHotRank({
    String? code,
    String? tradeDate,
    int limit = 50,
  }) {
    return _store?.queryHotRank(
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        const [];
  }

  void saveDragonTiger(
    List<Map<String, dynamic>> rows, {
    String source = '东方财富',
    String? tradeDate,
  }) {
    _store?.saveDragonTiger(rows, source: source, tradeDate: tradeDate);
  }

  List<Map<String, dynamic>> queryDragonTiger({
    String? code,
    String? tradeDate,
    int limit = 50,
  }) {
    return _store?.queryDragonTiger(
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        const [];
  }

  void saveLimitPool(
    String poolType,
    List<Map<String, dynamic>> rows, {
    String source = '东方财富',
    String? tradeDate,
  }) {
    _store?.saveLimitPool(poolType, rows, source: source, tradeDate: tradeDate);
  }

  List<Map<String, dynamic>> queryLimitPool({
    String? poolType,
    String? code,
    String? tradeDate,
    int limit = 50,
  }) {
    return _store?.queryLimitPool(
          poolType: poolType,
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        const [];
  }

  void saveNorthboundFlow(
    List<Map<String, dynamic>> rows, {
    String source = '东方财富',
  }) {
    _store?.saveNorthboundFlow(rows, source: source);
  }

  List<Map<String, dynamic>> queryNorthboundFlow({
    String? tradeDate,
    int limit = 50,
  }) {
    return _store?.queryNorthboundFlow(tradeDate: tradeDate, limit: limit) ??
        const [];
  }

  void saveNorthboundHolding(
    List<Map<String, dynamic>> rows, {
    String source = '东方财富',
    String? code,
  }) {
    _store?.saveNorthboundHolding(rows, source: source, code: code);
  }

  List<Map<String, dynamic>> queryNorthboundHolding({
    String? code,
    String? tradeDate,
    int limit = 50,
  }) {
    return _store?.queryNorthboundHolding(
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        const [];
  }

  void saveUnusualActivity(
    List<Map<String, dynamic>> rows, {
    String source = '东方财富',
    String? eventDate,
  }) {
    _store?.saveUnusualActivity(rows, source: source, eventDate: eventDate);
  }

  List<Map<String, dynamic>> queryUnusualActivity({
    String? code,
    String? eventDate,
    int limit = 50,
  }) {
    return _store?.queryUnusualActivity(
          code: code,
          eventDate: eventDate,
          limit: limit,
        ) ??
        const [];
  }

  void saveFlowRank(
    String period,
    List<Map<String, dynamic>> rows, {
    String source = '东方财富',
    String? tradeDate,
  }) {
    _store?.saveFlowRank(period, rows, source: source, tradeDate: tradeDate);
  }

  List<Map<String, dynamic>> queryFlowRank({
    String? period,
    String? code,
    String? tradeDate,
    int limit = 50,
  }) {
    return _store?.queryFlowRank(
          period: period,
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        const [];
  }

  void saveSectorRanking(
    String boardType,
    List<Map<String, dynamic>> rows, {
    String source = '东方财富',
    String? tradeDate,
  }) {
    _store?.saveSectorRanking(
      boardType,
      rows,
      source: source,
      tradeDate: tradeDate,
    );
  }

  List<Map<String, dynamic>> querySectorRanking({
    String? boardType,
    String? tradeDate,
    String? source,
    int limit = 50,
  }) {
    return _store?.querySectorRanking(
          boardType: boardType,
          tradeDate: tradeDate,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  void saveChipDistribution(
    String code,
    Map<String, dynamic> payload, {
    String source = '东方财富',
    String? tradeDate,
  }) {
    _store?.saveChipDistribution(
      code,
      payload,
      source: source,
      tradeDate: tradeDate,
    );
  }

  List<Map<String, dynamic>> queryChipDistribution(
    String code, {
    String? tradeDate,
    String? source,
    int limit = 20,
  }) {
    return _store?.queryChipDistribution(
          code,
          tradeDate: tradeDate,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  Map<String, dynamic>? saveIndustryMap(
    List<Map<String, dynamic>> rows, {
    required String industry,
  }) {
    return _store?.saveIndustryMap(rows, industry: industry);
  }

  List<Map<String, dynamic>> queryIndustryMap({
    String? code,
    String? industry,
    int limit = 50,
  }) {
    return _store?.queryIndustryMap(
          code: code,
          industry: industry,
          limit: limit,
        ) ??
        const [];
  }
}
