import '../../../agent/data_fetcher/eastmoney_advanced_fetcher.dart';

abstract class EastmoneyAdvancedProvider {
  Future<List<Map<String, dynamic>>> readLimitUp({String? date});
  Future<List<Map<String, dynamic>>> readLimitDown({String? date});
  Future<List<Map<String, dynamic>>> readHotRank({required int pageSize});
  Future<List<Map<String, dynamic>>> readDragonTiger({
    String? date,
    required int pageSize,
  });
  Future<List<Map<String, dynamic>>> readNorthboundHolding({
    required String code,
  });
  Future<List<Map<String, dynamic>>> readNorthboundFlow({required int days});
  Future<List<Map<String, dynamic>>> readUnusual({required int pageSize});
  Future<List<Map<String, dynamic>>> readFlowRank({
    required String period,
    required int pageSize,
  });
}

class FetcherEastmoneyAdvancedProvider implements EastmoneyAdvancedProvider {
  final EastMoneyAdvancedFetcher _fetcher;

  FetcherEastmoneyAdvancedProvider(this._fetcher);

  @override
  Future<List<Map<String, dynamic>>> readLimitUp({String? date}) {
    return _fetcher.getLimitUpPool(date: date);
  }

  @override
  Future<List<Map<String, dynamic>>> readLimitDown({String? date}) {
    return _fetcher.getLimitDownPool(date: date);
  }

  @override
  Future<List<Map<String, dynamic>>> readHotRank({required int pageSize}) {
    return _fetcher.getHotRank(pageSize: pageSize);
  }

  @override
  Future<List<Map<String, dynamic>>> readDragonTiger({
    String? date,
    required int pageSize,
  }) {
    return _fetcher.getDragonTiger(date: date, pageSize: pageSize);
  }

  @override
  Future<List<Map<String, dynamic>>> readNorthboundHolding({
    required String code,
  }) {
    return _fetcher.getNorthboundHolding(code: code);
  }

  @override
  Future<List<Map<String, dynamic>>> readNorthboundFlow({required int days}) {
    return _fetcher.getNorthboundFlow(days: days);
  }

  @override
  Future<List<Map<String, dynamic>>> readUnusual({required int pageSize}) {
    return _fetcher.getUnusualActivity(pageSize: pageSize);
  }

  @override
  Future<List<Map<String, dynamic>>> readFlowRank({
    required String period,
    required int pageSize,
  }) {
    return _fetcher.getFlowRanking(period: period, pageSize: pageSize);
  }
}
