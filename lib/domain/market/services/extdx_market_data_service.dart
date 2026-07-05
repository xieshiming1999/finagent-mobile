import '../../../agent/data_fetcher/data_manager.dart';
import '../providers/extdx_market_provider.dart';
import '../repositories/extdx_market_data_repository.dart';
import 'extdx_market_data_persistence_service.dart';

class ExTdxMarketDataService {
  final ExTdxMarketProvider _provider;
  final ExTdxMarketDataPersistenceService _persistence;

  ExTdxMarketDataService({
    DataManager? dataManager,
    ExTdxMarketProvider? provider,
  }) : this._internal(dataManager ?? DataManager(), provider);

  ExTdxMarketDataService._internal(
    DataManager dataManager,
    ExTdxMarketProvider? provider,
  ) : _provider = provider ?? FetcherExTdxMarketProvider(dataManager),
      _persistence = ExTdxMarketDataPersistenceService(
        ExTdxMarketDataRepository(dataManager),
      );

  Future<Map<String, dynamic>> categories() async {
    final data = await _provider.readCategories();
    _persistence.saveCategories(data);
    return {
      'action': 'ex_categories',
      'source': '通达信扩展',
      'count': data.length,
      'data': data.map((item) => item.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> count() async {
    final count = await _provider.readCount();
    _persistence.saveCount(count);
    return {
      'action': 'ex_count',
      'source': '通达信扩展',
      'scope': 'ex',
      'market': 'all',
      'count': count,
    };
  }

  Future<Map<String, dynamic>> table(Map<String, dynamic> input) async {
    final detail = input['detail'] == true;
    final data = await _provider.readTable(detail: detail);
    if (!detail) _persistence.saveTableEntries(_parseTableEntries(data));
    return {
      'action': 'ex_table',
      'source': '通达信扩展',
      'detail': detail,
      'data': data,
    };
  }

  Future<Map<String, dynamic>> sampling(Map<String, dynamic> input) async {
    final params = input['params'] as Map<String, dynamic>? ?? {};
    final category = params['category'] as int? ?? 30;
    final code = params['code'] as String? ?? '';
    if (code.isEmpty) {
      throw ArgumentError(
        'params.code required. Example: MarketData(action:"ex_sampling", params:{category:30, code:"RBL8"})',
      );
    }
    final data = await _provider.readSampling(category: category, code: code);
    _persistence.saveSampling(category, code, data);
    final prices = (data['prices'] as List?)?.cast<num>() ?? const <num>[];
    return {
      'action': 'ex_sampling',
      'source': '通达信扩展',
      'category': category,
      'code': code,
      'count': prices.length,
      'prices': prices,
    };
  }

  Future<Map<String, dynamic>> kline(Map<String, dynamic> input) async {
    final params = input['params'] as Map<String, dynamic>? ?? {};
    final category = params['category'] as int? ?? 30;
    final code = params['code'] as String? ?? '';
    if (code.isEmpty) {
      throw ArgumentError(
        'params.code required. Example: MarketData(action:"ex_kline", params:{category:30, code:"RBL8"})',
      );
    }
    final period = switch (params['period'] as String? ?? 'daily') {
      'weekly' => 5,
      'monthly' => 6,
      '1min' => 0,
      '5min' => 1,
      '15min' => 2,
      '30min' => 3,
      '60min' => 4,
      _ => 9,
    };
    final count = params['count'] as int? ?? 100;
    final data = await _provider.readKline(
      category: category,
      code: code,
      period: period,
      count: count,
    );
    _persistence.saveKline(category, code, data);
    return {
      'action': 'ex_kline',
      'source': '通达信扩展',
      'category': category,
      'code': code,
      'count': data.length,
      'data': data.map((bar) => bar.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> quote(Map<String, dynamic> input) async {
    final params = input['params'] as Map<String, dynamic>? ?? {};
    final category = params['category'] as int? ?? 30;
    final code = params['code'] as String? ?? '';
    if (code.isEmpty) {
      throw ArgumentError(
        'params.code required. Example: MarketData(action:"ex_quote", params:{category:30, code:"RBL8"})',
      );
    }
    final data = await _provider.readQuote(category: category, code: code);
    _persistence.saveQuote(data);
    return {'action': 'ex_quote', 'source': '通达信扩展', ...data.toJson()};
  }

  Future<Map<String, dynamic>> list(Map<String, dynamic> input) async {
    final params = input['params'] as Map<String, dynamic>? ?? {};
    final start = params['start'] as int? ?? 0;
    final count = params['count'] as int? ?? 50;
    final data = await _provider.readList(start: start, count: count);
    _persistence.saveList(data);
    return {
      'action': 'ex_list',
      'source': '通达信扩展',
      'start': start,
      'count': data.length,
      'data': data.map((item) => item.toJson()).toList(),
    };
  }

  List<Map<String, dynamic>> _parseTableEntries(String raw) {
    final rows = <Map<String, dynamic>>[];
    for (final segment in raw.split(',')) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split('|');
      if (parts.length < 2) continue;
      final key = parts[0].trim();
      final name = parts[1].trim();
      if (key.isEmpty || name.isEmpty) continue;
      final match = RegExp(r'^(\d+)#(.+)$').firstMatch(key);
      rows.add({
        'entry_key': key,
        'category': match?.group(1),
        'code': match?.group(2) ?? key,
        'name': name,
      });
    }
    return rows;
  }
}
