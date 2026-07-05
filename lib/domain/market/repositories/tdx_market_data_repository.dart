import 'dart:convert';

import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/models.dart';

class TdxMarketDataRepository {
  final DataManager _dataManager;

  TdxMarketDataRepository(this._dataManager);

  void saveTickChart(
    String symbol,
    List<Map<String, dynamic>> rows, {
    String? tradeDate,
  }) {
    _dataManager.saveTickChart(
      symbol,
      rows,
      source: '通达信',
      tradeDate: tradeDate,
    );
  }

  void saveTransactions(
    String symbol,
    List<Map<String, dynamic>> rows, {
    String? tradeDate,
  }) {
    _dataManager.saveTransactions(
      symbol,
      rows,
      source: '通达信',
      tradeDate: tradeDate,
    );
  }

  void saveFinance(String symbol, Map<String, dynamic> payload) {
    _dataManager.saveCompanyInfo(symbol, 'tdx_finance', payload, source: '通达信');
    final row = _financeToFundamental(symbol, payload);
    if (row != null) {
      _dataManager.saveFundamentalRows([row], source: '通达信');
    }
  }

  void saveXdxr(String symbol, List<Map<String, dynamic>> rows) {
    _dataManager.saveXdxrEvents(symbol, rows, source: '通达信');
  }

  void saveUnusualActivity(List<Map<String, dynamic>> rows) {
    _dataManager.saveUnusualActivity(rows, source: '通达信');
    _dataManager.saveStockListRows(
      rows
          .where(
            (row) =>
                ('${row['code'] ?? ''}'.trim().isNotEmpty) &&
                ('${row['name'] ?? row['Name'] ?? ''}'.trim().isNotEmpty),
          )
          .map(
            (row) => {
              'code': row['code'],
              'name': row['name'] ?? row['Name'],
              'market': _normalizeCnMarket('${row['code'] ?? ''}', row['market']),
              'stock_type': 'stock',
            },
          )
          .toList(),
      source: '通达信',
    );
  }

  void saveIndexInfo(String symbol, Map<String, dynamic> payload) {
    if (!payload.containsKey('error')) {
      _dataManager.saveQuoteSnapshots([
        _indexInfoToQuote(symbol, payload),
      ], source: '通达信:index_quote');
      _dataManager.saveStockListRows([
        {
          'code': symbol,
          'name': payload['name'] ?? payload['Name'] ?? symbol,
          'market': symbol.startsWith('0') ? 'SH' : 'SZ',
          'stock_type': 'index',
        },
      ], source: '通达信:index_quote');
    }
  }

  void saveStockList(List<Map<String, dynamic>> rows, int market) {
    _dataManager.saveStockListRows(
      rows,
      source: '通达信',
      market: market == 1 ? 'SH' : 'SZ',
    );
  }

  void saveSecurityCount(int market, int count) {
    _dataManager.saveTdxSecurityCounts([
      {'scope': 'main', 'market': '$market', 'count': count},
    ], source: '通达信');
  }

  void saveSampling(String symbol, Map<String, dynamic> payload) {
    final prices = (payload['prices'] as List?)?.cast<num>() ?? const <num>[];
    final preClose = (payload['preClose'] as num?)?.toDouble();
    final market = '${payload['market'] ?? ''}';
    _dataManager.saveTdxChartSampling([
      for (var i = 0; i < prices.length; i++)
        {
          'scope': 'main',
          'code': symbol,
          'sequence': i,
          'market': market,
          'pre_close': preClose,
          'price': prices[i].toDouble(),
          'change': preClose == null ? null : prices[i].toDouble() - preClose,
        },
    ], source: '通达信');
  }

  void saveVolumeProfile(String symbol, Map<String, dynamic> payload) {
    _dataManager.saveVolumeProfile(symbol, payload, source: '通达信');
  }

  void saveAuction(
    String symbol,
    List<Map<String, dynamic>> rows, {
    String? tradeDate,
  }) {
    _dataManager.saveAuction(
      symbol,
      rows,
      source: '通达信',
      tradeDate: tradeDate,
    );
  }

  void saveMomentum(
    String symbol,
    Map<String, dynamic> payload, {
    String? tradeDate,
  }) {
    _dataManager.saveIndexMomentum(
      symbol,
      payload,
      source: '通达信',
      tradeDate: tradeDate,
    );
  }

  void saveTopBoard(
    Map<String, dynamic> payload, {
    required int category,
  }) {
    _dataManager.saveTopBoard(
      payload,
      source: '通达信',
      category: category.toString(),
    );
  }

  void saveQuotesList(List<Map<String, dynamic>> rows) {
    _dataManager.saveQuoteSnapshots(_rowsToQuotes(rows), source: '通达信');
    _dataManager.saveStockListRows(
      rows
          .where(
            (row) =>
                (row['code']?.toString().trim().isNotEmpty ?? false) &&
                (row['name']?.toString().trim().isNotEmpty ?? false),
          )
          .map(
            (row) => {
              'code': row['code'],
              'name': row['name'],
              'market': _normalizeTdxStockListMarket(
                row['code']?.toString() ?? '',
                row['market'],
              ),
              'stock_type': 'stock',
            },
          )
          .toList(),
      source: '通达信',
    );
  }

  void saveIndexBars(String symbol, List<Map<String, dynamic>> rows) {
    _dataManager.saveKlineRows(
      symbol,
      _rowsToKline(rows),
      source: '通达信',
      adjust: 'none',
    );
  }

  void saveCompanyInfo(String symbol, Map<String, dynamic> result) {
    _dataManager.saveCompanyInfo(
      symbol,
      'tdx_company_info',
      result,
      source: '通达信',
    );
  }

  void saveCompanyCategoryPreview(
    String symbol,
    String title,
    Map<String, dynamic> entry,
  ) {
    _dataManager.saveCompanyInfo(
      symbol,
      'tdx_company_categories:$title',
      {
        'title': title,
        'first_content': entry['filename'] as String?,
        'entry': entry,
      },
      source: '通达信',
    );
  }

  void saveCompanyContent(
    String symbol,
    String title,
    Map<String, dynamic> entry,
    String content,
  ) {
    _dataManager.saveCompanyInfo(
      symbol,
      'tdx_company_content:$title',
      {
        'title': title,
        'first_content': content.length > 2000 ? content.substring(0, 2000) : content,
        'entry': entry,
      },
      source: '通达信',
    );
  }

  void saveBlockMembers(List<Map<String, dynamic>> rows) {
    _dataManager.saveTdxBlockMembers(rows, source: '通达信');
  }

  List<Map<String, dynamic>> normalizeBlockRows(
    String filename,
    List<Map<String, dynamic>> rows,
  ) {
    return rows.map((row) => {
      ...row,
      'blockCode':
          '${row['blockCode'] ?? row['BlockCode'] ?? '$filename:${row['blockName'] ?? row['BlockName'] ?? ''}'}',
      'blockName': '${row['blockName'] ?? row['BlockName'] ?? ''}',
      'type': '${row['type'] ?? row['Type'] ?? row['blockType'] ?? row['BlockType'] ?? ''}',
      'code': '${row['code'] ?? row['Code'] ?? ''}',
    }).where((row) => ('${row['code'] ?? ''}').isNotEmpty).toList();
  }

  Map<String, dynamic>? _financeToFundamental(
    String code,
    Map<String, dynamic> data,
  ) {
    final reportDate = _normalizeFinanceDate(data['updatedDate']);
    if (reportDate == null) return null;
    final totalAssets = _financeNum(data['totalAssets']);
    final currentLiabilities = _financeNum(data['currentLiabilities']);
    final longTermLiabilities = _financeNum(data['longTermLiabilities']);
    final totalLiabilities =
        (currentLiabilities == null && longTermLiabilities == null)
        ? null
        : (currentLiabilities ?? 0) + (longTermLiabilities ?? 0);
    return {
      'code': code,
      'report_date': reportDate,
      'eps': _financeNum(data['eps']),
      'revenue': _financeNum(data['operatingRevenue']),
      'net_profit': _financeNum(data['netProfit']),
      'total_assets': totalAssets,
      'total_liabilities': totalLiabilities,
      'debt_ratio': _financePercent(totalLiabilities, totalAssets),
      'raw_json': jsonEncode(data),
      'source': '通达信',
    };
  }

  String? _normalizeFinanceDate(dynamic value) {
    final digits = '$value'.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) return null;
    return '${digits.substring(0, 4)}-${digits.substring(4, 6)}-${digits.substring(6, 8)}';
  }

  double? _financeNum(dynamic value) {
    if (value == null) return null;
    final n = value is num ? value.toDouble() : double.tryParse('$value');
    return n != null && n.isFinite ? n : null;
  }

  double? _financePercent(double? numerator, double? denominator) {
    if (numerator == null || denominator == null || denominator == 0) return null;
    return numerator / denominator * 100;
  }

  List<StockQuote> _rowsToQuotes(List<Map<String, dynamic>> rows) {
    return rows
        .map((row) {
          final code = '${row['code'] ?? ''}';
          final price = _toDouble(row['price']);
          final changePct = _toDouble(row['changePct']);
          final prevClose = changePct == -100 ? price : price / (1 + changePct / 100);
          return StockQuote(
            code: code,
            name: '${row['name'] ?? code}',
            price: price,
            change: price - prevClose,
            changePct: changePct,
            open: price,
            high: price,
            low: price,
            prevClose: prevClose.isFinite ? prevClose : price,
            volume: _toDouble(row['volume']),
            amount: _toDouble(row['amount']),
            source: '通达信',
          );
        })
        .where((quote) => quote.code.isNotEmpty)
        .toList();
  }

  StockQuote _indexInfoToQuote(String symbol, Map<String, dynamic> data) {
    final price = _toDouble(data['close']);
    final prevClose = _toDouble(data['preClose']);
    return StockQuote(
      code: 'INDEX:$symbol',
      name: symbol,
      price: price,
      change: _toDouble(data['change']),
      changePct: _toDouble(data['changePct']),
      open: _toDouble(data['open']),
      high: _toDouble(data['high']),
      low: _toDouble(data['low']),
      prevClose: prevClose == 0 ? price : prevClose,
      volume: _toDouble(data['volume']),
      amount: _toDouble(data['amount']),
      source: '通达信',
    );
  }

  List<KlineBar> _rowsToKline(List<Map<String, dynamic>> rows) {
    return rows
        .map((row) => KlineBar(
              date: '${row['date'] ?? ''}',
              open: _toDouble(row['open']),
              high: _toDouble(row['high']),
              low: _toDouble(row['low']),
              close: _toDouble(row['close']),
              volume: _toDouble(row['volume']),
              amount: _toDouble(row['amount']),
            ))
        .where((bar) => bar.date.isNotEmpty)
        .toList();
  }

  String _normalizeTdxStockListMarket(String code, Object? market) {
    final value = '${market ?? ''}'.trim().toLowerCase();
    if (value == '1' || value == 'sh') return 'SH';
    if (value == '2' || value == 'bj') return 'BJ';
    if (value == '0' || value == 'sz') return 'SZ';
    final clean = code.trim();
    if (clean.startsWith('6')) return 'SH';
    if (clean.startsWith('4') || clean.startsWith('8') || clean.startsWith('9')) {
      return 'BJ';
    }
    return 'SZ';
  }

  String _normalizeCnMarket(String code, Object? market) {
    final value = '${market ?? ''}'.trim().toLowerCase();
    if (value == 'sh') return 'SH';
    if (value == 'sz') return 'SZ';
    if (value == 'bj') return 'BJ';
    return _normalizeTdxStockListMarket(code, null);
  }

  double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
