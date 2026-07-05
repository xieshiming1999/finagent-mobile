import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/models.dart';
import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../../../agent/tool_context.dart';

class EastmoneyMarketDataRepository {
  ReusableDataStore? _store;
  String? _storeBasePath;
  final DataManager _dataManager;

  EastmoneyMarketDataRepository(this._dataManager);

  void saveMoneyFlow(
    String symbol,
    List<MoneyFlow> rows, {
    required String source,
  }) {
    _dataManager.saveMoneyFlowRows(symbol, rows, source: source);
  }

  void saveEtfQuotes(List<StockQuote> quotes, {required String source}) {
    _dataManager.saveQuoteSnapshots(quotes, source: source);
    _dataManager.saveStockListRows(
      quotes
          .map(
            (quote) => {
              'code': quote.code,
              'name': quote.name,
              'market': 'ETF',
              'stock_type': 'etf',
            },
          )
          .toList(),
      source: source,
      market: 'ETF',
    );
  }

  void saveListedFundQuotes(List<StockQuote> quotes, {required String source}) {
    _dataManager.saveQuoteSnapshots(quotes, source: source);
    _dataManager.saveStockListRows(
      quotes
          .map(
            (quote) => {
              'code': quote.code,
              'name': quote.name,
              'market': 'LISTED_FUND',
              'stock_type': 'listed_fund',
            },
          )
          .toList(),
      source: source,
      market: 'LISTED_FUND',
    );
  }

  void saveStockListRows(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _dataManager.saveStockListRows(rows, source: source);
  }

  void saveSectorRanking(
    String boardType,
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _dataManager.saveSectorRanking(boardType, rows, source: source);
  }

  void saveSectorStocks(
    List<StockQuote> quotes, {
    required String source,
    required String sectorCode,
    String? sectorName,
  }) {
    _dataManager.saveQuoteSnapshots(quotes, source: source);
    final label = (sectorName ?? sectorCode).trim();
    _dataManager.saveStockListRows(
      quotes
          .map(
            (quote) => {
              'code': quote.code,
              'name': quote.name,
              'market': _marketFromCode(quote.code),
              if (label.isNotEmpty) 'industry': label,
              'stock_type': 'stock',
            },
          )
          .toList(),
      source: source,
    );
    if (label.isNotEmpty) {
      _dataManager.saveIndustryMap(
        quotes.map((quote) => {'code': quote.code}).toList(),
        industry: label,
      );
    }
  }

  void saveChipDistribution(
    String symbol,
    Map<String, dynamic> payload, {
    required String source,
  }) {
    _dataManager.saveChipDistribution(symbol, payload, source: source);
  }

  void saveFundManagers(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _dataManager.saveFundManagerRows(rows, source: source);
  }

  void saveFundList(List<Map<String, dynamic>> rows, {required String source}) {
    _dataManager.saveFundList(rows, source: source);
  }

  void saveFundNav(List<Map<String, dynamic>> rows, {required String source}) {
    _dataManager.saveFundNav(rows, source: source);
  }

  void saveFundMoneyYield(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _dataManager.saveFundMoneyYield(rows, source: source);
  }

  void saveFundHolding(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _dataManager.saveFundHolding(rows, source: source);
    final stockRows = rows
        .map((row) {
          final code = '${row['stock_code'] ?? ''}'.trim();
          if (code.isEmpty) return null;
          return {
            'code': code,
            'name': '${row['stock_name'] ?? ''}'.trim(),
            'market': _marketFromCode(code),
            'stock_type': 'stock',
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    if (stockRows.isNotEmpty) {
      _dataManager.saveStockListRows(stockRows, source: source);
    }
  }

  void saveFundPerformance(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _dataManager.saveFundPerformanceMetrics(rows, source: source);
  }

  void saveStockShareholders(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _dataManager.saveStockShareholders(rows, source: source);
  }

  void saveStockCompanyInfo(
    String code,
    Map<String, dynamic> row, {
    required String source,
  }) {
    _dataManager.saveCompanyInfo(
      code,
      '${row['info_type'] ?? 'eastmoney_company_info'}',
      row,
      source: source,
    );
  }

  ReusableDataStore? _storeForContext(ToolContext context) {
    final basePath = context.basePath;
    if (basePath.isEmpty) return null;
    if (_store == null || _storeBasePath != basePath) {
      _storeBasePath = basePath;
      _store = ReusableDataStore(basePath)..cleanup();
    }
    return _store;
  }

  List<Map<String, dynamic>> querySectorRanking(
    ToolContext context, {
    String? boardType,
    String? tradeDate,
    String? source,
    int limit = 50,
  }) {
    return _storeForContext(context)?.querySectorRanking(
          boardType: boardType,
          tradeDate: tradeDate,
          source: source,
          limit: limit,
        ) ??
        _dataManager.querySectorRanking(
          boardType: boardType,
          tradeDate: tradeDate,
          source: source,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryIndustryMap(
    ToolContext context, {
    String? code,
    String? industry,
    int limit = 50,
  }) {
    return _storeForContext(
          context,
        )?.queryIndustryMap(code: code, industry: industry, limit: limit) ??
        _dataManager.queryIndustryMap(
          code: code,
          industry: industry,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryChipDistribution(
    ToolContext context,
    String symbol, {
    String? tradeDate,
    String? source,
    int limit = 20,
  }) {
    return _storeForContext(context)?.queryChipDistribution(
          symbol,
          tradeDate: tradeDate,
          source: source,
          limit: limit,
        ) ??
        _dataManager.queryChipDistribution(
          symbol,
          tradeDate: tradeDate,
          source: source,
          limit: limit,
        );
  }

  String _marketFromCode(String code) {
    final clean = code.trim();
    if (clean.startsWith('6')) return 'SH';
    if (clean.startsWith('4') ||
        clean.startsWith('8') ||
        clean.startsWith('9')) {
      return 'BJ';
    }
    return 'SZ';
  }
}
