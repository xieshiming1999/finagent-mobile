import '../../../agent/data_fetcher/data_manager.dart';
import '../providers/tdx_market_provider.dart';
import '../repositories/tdx_market_data_repository.dart';
import 'tdx_market_data_persistence_service.dart';

class TdxMarketDataService {
  final TdxMarketProvider _provider;
  final TdxMarketDataRepository _repository;
  final TdxMarketDataPersistenceService _persistence;

  TdxMarketDataService({DataManager? dataManager, TdxMarketProvider? provider})
    : this._internal(dataManager ?? DataManager(), provider);

  TdxMarketDataService._internal(
    DataManager dataManager,
    TdxMarketProvider? provider,
  ) : _provider = provider ?? FetcherTdxMarketProvider(dataManager),
      _repository = TdxMarketDataRepository(dataManager),
      _persistence = TdxMarketDataPersistenceService(
        TdxMarketDataRepository(dataManager),
      );

  Future<Map<String, dynamic>> tickChart(String symbol) async {
    final data = await _provider.readTickChart(symbol);
    _persistence.saveTickChart(symbol, data);
    final latest = data.length > 10 ? data.sublist(data.length - 10) : data;
    return {
      'action': 'tdx_tick_chart',
      'source': '通达信',
      'symbol': symbol,
      'points': data.length,
      'latest10': latest,
      if (data.length > 10)
        'note':
            '${data.length} points total, showing latest 10. Full data available for chart rendering.',
    };
  }

  Future<Map<String, dynamic>> transactions(
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final count = input['limit'] as int? ?? 50;
    final data = await _provider.readTransactions(symbol, count: count);
    _persistence.saveTransactions(symbol, data);
    return {
      'action': 'tdx_transactions',
      'source': '通达信',
      'symbol': symbol,
      'count': data.length,
      'data': data.take(30).toList(),
      if (data.length > 30)
        'note': '${data.length} transactions, showing latest 30',
    };
  }

  Future<Map<String, dynamic>> finance(String symbol) async {
    final data = await _provider.readFinance(symbol);
    _persistence.saveFinance(symbol, data);
    return {
      'action': 'tdx_finance',
      'source': '通达信',
      'symbol': symbol,
      ...data,
    };
  }

  Future<Map<String, dynamic>> xdxr(String symbol) async {
    final data = await _provider.readXdxr(symbol);
    _persistence.saveXdxr(symbol, data);
    return {
      'action': 'tdx_xdxr',
      'source': '通达信',
      'symbol': symbol,
      'count': data.length,
      'data': data.take(20).toList(),
      if (data.length > 20)
        'note': '${data.length} events total, showing latest 20',
    };
  }

  Future<Map<String, dynamic>> unusual(Map<String, dynamic> input) async {
    final market = input['params'] is Map
        ? ((input['params'] as Map)['market'] as int? ?? 0)
        : 0;
    final data = await _provider.readUnusual(market: market, count: 50);
    _persistence.saveUnusualActivity(data);
    return {
      'action': 'tdx_unusual',
      'source': '通达信',
      'count': data.length,
      'data': data.take(30).toList(),
      if (data.length > 30) 'note': '${data.length} events, showing latest 30',
    };
  }

  Future<Map<String, dynamic>> indexInfo(String symbol) async {
    final data = await _provider.readIndexInfo(symbol);
    _persistence.saveIndexInfo(symbol, data);
    return {
      'action': 'tdx_index_info',
      'source': '通达信',
      'symbol': symbol,
      ...data,
    };
  }

  Future<Map<String, dynamic>> stockList(Map<String, dynamic> input) async {
    final market = input['params'] is Map
        ? ((input['params'] as Map)['market'] as int? ?? 0)
        : 0;
    final data = await _provider.readStockList(market: market, count: 100);
    _persistence.saveStockList(data, market);
    return {
      'action': 'tdx_stock_list',
      'source': '通达信',
      'market': market,
      'count': data.length,
      'data': data.take(50).toList(),
      if (data.length > 50)
        'note': '${data.length} securities, showing first 50',
    };
  }

  Future<Map<String, dynamic>> count(Map<String, dynamic> input) async {
    final market = input['params'] is Map
        ? ((input['params'] as Map)['market'] as int? ?? 0)
        : ((input['market'] as num?)?.toInt() ?? 0);
    final count = await _provider.readCount(market: market);
    _persistence.saveSecurityCount(market, count);
    return {
      'action': 'tdx_count',
      'source': '通达信',
      'scope': 'main',
      'market': market,
      'count': count,
    };
  }

  Future<Map<String, dynamic>> sampling(String symbol) async {
    final data = await _provider.readSampling(symbol);
    _persistence.saveSampling(symbol, data);
    final prices = (data['prices'] as List?)?.cast<num>() ?? const <num>[];
    return {
      'action': 'tdx_sampling',
      'source': '通达信',
      'symbol': symbol,
      'market': data['market'],
      'preClose': data['preClose'],
      'count': prices.length,
      'prices': prices,
    };
  }

  Future<Map<String, dynamic>> volumeProfile(String symbol) async {
    final data = await _provider.readVolumeProfile(symbol);
    _persistence.saveVolumeProfile(symbol, data);
    return {
      'action': 'tdx_volume_profile',
      'source': '通达信',
      'symbol': symbol,
      ...data,
    };
  }

  Future<Map<String, dynamic>> auction(String symbol) async {
    final data = await _provider.readAuction(symbol);
    _persistence.saveAuction(symbol, data);
    return {
      'action': 'tdx_auction',
      'source': '通达信',
      'symbol': symbol,
      'count': data.length,
      'data': data,
    };
  }

  Future<Map<String, dynamic>> historyTick(
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final dateStr = input['date'] as String? ?? '';
    final date = int.tryParse(dateStr) ?? 0;
    if (date == 0) {
      throw ArgumentError(
        'date required (YYYYMMDD). Example: MarketData(action:"tdx_history_tick", symbols:["600519"], date:"20250519")',
      );
    }
    final data = await _provider.readHistoryTick(symbol, date);
    _persistence.saveTickChart(symbol, data, tradeDate: _inputDate(input));
    return {
      'action': 'tdx_history_tick',
      'source': '通达信',
      'symbol': symbol,
      'date': date,
      'count': data.length,
      'data': data.length > 50 ? data.sublist(0, 50) : data,
    };
  }

  Future<Map<String, dynamic>> momentum(String symbol) async {
    final data = await _provider.readMomentum(symbol);
    _persistence.saveMomentum(symbol, data);
    return {'action': 'tdx_momentum', 'source': '通达信', ...data};
  }

  Future<Map<String, dynamic>> historyTrans(
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final date = int.tryParse(input['date']?.toString() ?? '') ?? 0;
    if (date == 0) throw ArgumentError('date required (YYYYMMDD)');
    final data = await _provider.readHistoryTransactions(symbol, date);
    _persistence.saveTransactions(symbol, data, tradeDate: _inputDate(input));
    return {
      'action': 'tdx_history_trans',
      'source': '通达信',
      'symbol': symbol,
      'date': date,
      'count': data.length,
      'data': data.length > 50 ? data.sublist(0, 50) : data,
    };
  }

  Future<Map<String, dynamic>> topBoard(Map<String, dynamic> input) async {
    final category = (input['category'] as num?)?.toInt() ?? 0;
    final size = (input['size'] as num?)?.toInt() ?? 10;
    final data = await _provider.readTopBoard(category: category, size: size);
    _persistence.saveTopBoard(data, category: category);
    return {'action': 'tdx_top_board', 'source': '通达信', ...data};
  }

  Future<Map<String, dynamic>> quotesList(Map<String, dynamic> input) async {
    final count = (input['count'] as num?)?.toInt() ?? 80;
    final sortType = (input['sortType'] as num?)?.toInt() ?? 0;
    final data = await _provider.readQuotesList(
      count: count,
      sortType: sortType,
    );
    _persistence.saveQuotesList(data);
    return {
      'action': 'tdx_quotes_list',
      'source': '通达信',
      'count': data.length,
      'data': data,
    };
  }

  Future<Map<String, dynamic>> indexBars(
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final count = (input['count'] as num?)?.toInt() ?? 100;
    final data = await _provider.readIndexBars(symbol, count: count);
    _persistence.saveIndexBars(symbol, data);
    return {
      'action': 'tdx_index_bars',
      'source': '通达信',
      'symbol': symbol,
      'count': data.length,
      'data': data.length > 30 ? data.sublist(data.length - 30) : data,
    };
  }

  Future<Map<String, dynamic>> companyInfo(
    String symbol, [
    Map<String, dynamic> input = const {},
  ]) async {
    final categories = await _provider.readCompanyCategories(symbol);
    final maxContentFiles = (input['maxContentFiles'] as num?)?.toInt() ?? 1;
    final result = <String, dynamic>{
      'action': 'tdx_company_info',
      'source': '通达信',
      'symbol': symbol,
      'categories': categories,
      'max_content_files': maxContentFiles,
    };
    if (categories.isNotEmpty) {
      final contentErrors = <Map<String, dynamic>>[];
      var attemptedContentFiles = 0;
      var fetchedContentFiles = 0;
      for (final category in categories) {
        final title = '${category['name'] ?? ''}'.trim();
        if (title.isEmpty) continue;
        _persistence.saveCompanyCategoryPreview(symbol, title, category);
        final filename = '${category['filename'] ?? ''}'.trim();
        if (filename.isEmpty) continue;
        if (attemptedContentFiles >= maxContentFiles) continue;
        attemptedContentFiles++;
        try {
          final content = await _provider.readCompanyContent(symbol, filename);
          fetchedContentFiles++;
          if (result['first_content'] == null) {
            result['first_content'] = content.length > 2000
                ? content.substring(0, 2000)
                : content;
          }
          _persistence.saveCompanyContent(symbol, title, category, content);
        } catch (e) {
          contentErrors.add({
            'title': title,
            'filename': filename,
            'error': '$e',
          });
        }
      }
      result['content_files_attempted'] = attemptedContentFiles;
      result['content_files_fetched'] = fetchedContentFiles;
      if (contentErrors.isNotEmpty) result['content_errors'] = contentErrors;
    }
    _persistence.saveCompanyInfo(symbol, result);
    return result;
  }

  Future<Map<String, dynamic>> block(
    List<String> symbols,
    Map<String, dynamic> input,
  ) async {
    final filename = input['filename']?.toString() ?? 'block_gn.dat';
    final blockName = input['blockName']?.toString();
    var rows = await _provider.readBlockMembers(
      filename: filename,
      blockName: blockName,
    );
    if (symbols.isNotEmpty) {
      final target = symbols.first;
      rows = rows.where((row) => '${row['code'] ?? ''}' == target).toList();
    }
    final normalized = _repository.normalizeBlockRows(filename, rows);
    _persistence.saveBlockMembers(normalized);
    return {
      'action': 'tdx_block',
      'source': '通达信',
      'filename': filename,
      if (blockName != null && blockName.isNotEmpty) 'blockName': blockName,
      if (symbols.isNotEmpty) 'symbol': symbols.first,
      'count': normalized.length,
      'note':
          'TDX block files expose filename + block name/type + member code. block_code is persisted as "<filename>:<block_name>".',
      'data': normalized,
    };
  }

  String? _inputDate(Map<String, dynamic> input) {
    final value = input['date'] ?? input['startDate'];
    if (value == null) return null;
    final text = '$value'.replaceAll('/', '-');
    if (text.length == 8 && !text.contains('-')) {
      return '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6, 8)}';
    }
    return text.isEmpty ? null : text;
  }
}
