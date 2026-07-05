import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../../../agent/tool_context.dart';

class EastmoneyAdvancedRepository {
  ReusableDataStore? _store;
  String? _storeBasePath;
  final DataManager _dataManager;

  EastmoneyAdvancedRepository(this._dataManager);

  ReusableDataStore? _storeForContext(ToolContext context) {
    final basePath = context.basePath;
    if (basePath.isEmpty) return null;
    if (_store == null || _storeBasePath != basePath) {
      _storeBasePath = basePath;
      _store = ReusableDataStore(basePath)..cleanup();
    }
    return _store;
  }

  void saveLimitPool(
    String poolType,
    List<Map<String, dynamic>> rows, {
    String? tradeDate,
  }) {
    _dataManager.saveLimitPool(poolType, rows, source: '东方财富', tradeDate: tradeDate);
  }

  void saveHotRank(List<Map<String, dynamic>> rows, {String? tradeDate}) {
    _dataManager.saveHotRank(rows, source: '东方财富', tradeDate: tradeDate);
  }

  void saveDragonTiger(List<Map<String, dynamic>> rows, {String? tradeDate}) {
    _dataManager.saveDragonTiger(rows, source: '东方财富', tradeDate: tradeDate);
  }

  void saveNorthboundFlow(List<Map<String, dynamic>> rows) {
    _dataManager.saveNorthboundFlow(rows, source: '东方财富');
  }

  void saveNorthboundHolding(
    List<Map<String, dynamic>> rows, {
    required String code,
  }) {
    _dataManager.saveNorthboundHolding(rows, source: '东方财富', code: code);
  }

  void saveUnusualActivity(List<Map<String, dynamic>> rows, {String? eventDate}) {
    _dataManager.saveUnusualActivity(
      rows,
      source: '东方财富',
      eventDate: eventDate,
    );
  }

  void saveFlowRank(
    String period,
    List<Map<String, dynamic>> rows, {
    String? tradeDate,
  }) {
    _dataManager.saveFlowRank(
      period,
      rows,
      source: '东方财富',
      tradeDate: tradeDate,
    );
  }

  void saveStockListRows(List<Map<String, dynamic>> rows) {
    _dataManager.saveStockListRows(rows, source: '东方财富');
  }

  List<Map<String, dynamic>> queryHotRank(
    ToolContext context, {
    String? code,
    String? tradeDate,
    int limit = 50,
  }) {
    return _storeForContext(context)?.queryHotRank(
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        _dataManager.queryHotRank(code: code, tradeDate: tradeDate, limit: limit);
  }

  List<Map<String, dynamic>> queryDragonTiger(
    ToolContext context, {
    String? code,
    String? tradeDate,
    int limit = 50,
  }) {
    return _storeForContext(context)?.queryDragonTiger(
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        _dataManager.queryDragonTiger(
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryLimitPool(
    ToolContext context, {
    String? poolType,
    String? code,
    String? tradeDate,
    int limit = 50,
  }) {
    return _storeForContext(context)?.queryLimitPool(
          poolType: poolType,
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        _dataManager.queryLimitPool(
          poolType: poolType,
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryNorthboundFlow(
    ToolContext context, {
    String? tradeDate,
    int limit = 50,
  }) {
    return _storeForContext(context)?.queryNorthboundFlow(
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        _dataManager.queryNorthboundFlow(tradeDate: tradeDate, limit: limit);
  }

  List<Map<String, dynamic>> queryNorthboundHolding(
    ToolContext context, {
    String? code,
    String? tradeDate,
    int limit = 50,
  }) {
    return _storeForContext(context)?.queryNorthboundHolding(
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        _dataManager.queryNorthboundHolding(
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryUnusualActivity(
    ToolContext context, {
    String? code,
    String? eventDate,
    int limit = 50,
  }) {
    return _storeForContext(context)?.queryUnusualActivity(
          code: code,
          eventDate: eventDate,
          limit: limit,
        ) ??
        _dataManager.queryUnusualActivity(
          code: code,
          eventDate: eventDate,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryFlowRank(
    ToolContext context, {
    String? period,
    String? code,
    String? tradeDate,
    int limit = 50,
  }) {
    return _storeForContext(context)?.queryFlowRank(
          period: period,
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        ) ??
        _dataManager.queryFlowRank(
          period: period,
          code: code,
          tradeDate: tradeDate,
          limit: limit,
        );
  }

  String normalizeCnMarket(String code, Object? market) {
    final value = '${market ?? ''}'.trim().toLowerCase();
    if (value == 'sh') return 'SH';
    if (value == 'sz') return 'SZ';
    if (value == 'bj') return 'BJ';
    final clean = code.trim();
    if (clean.startsWith('6')) return 'SH';
    if (clean.startsWith('4') || clean.startsWith('8') || clean.startsWith('9')) {
      return 'BJ';
    }
    return 'SZ';
  }
}
