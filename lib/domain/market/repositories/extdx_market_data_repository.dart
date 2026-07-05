import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/models.dart';

class ExTdxMarketDataRepository {
  final DataManager _dataManager;

  ExTdxMarketDataRepository(this._dataManager);

  void saveCategories(List<ExCategoryItem> data) {
    _dataManager.saveExCategories(
      data.map((item) => item.toJson()).toList(),
      source: '通达信扩展',
    );
  }

  void saveCount(int count) {
    _dataManager.saveTdxSecurityCounts([
      {'scope': 'ex', 'market': 'all', 'count': count},
    ], source: '通达信扩展');
  }

  void saveTableEntries(List<Map<String, dynamic>> rows) {
    _dataManager.saveExTableEntries(rows);
  }

  void saveSampling(int category, String code, Map<String, dynamic> payload) {
    final prices = (payload['prices'] as List?)?.cast<num>() ?? const <num>[];
    _dataManager.saveTdxChartSampling([
      for (var i = 0; i < prices.length; i++)
        {
          'scope': 'ex',
          'code': code,
          'sequence': i,
          'category': '$category',
          'price': prices[i].toDouble(),
        },
    ], source: '通达信扩展');
  }

  void saveKline(int category, String code, List<ExKlineBar> rows) {
    _dataManager.saveKlineRows(
      code,
      rows
          .map(
            (row) => KlineBar(
              date: row.date,
              open: row.open,
              high: row.high,
              low: row.low,
              close: row.close,
              volume: row.volume.toDouble(),
              amount: row.amount,
            ),
          )
          .where((bar) => bar.date.isNotEmpty)
          .toList(),
      source: '通达信扩展:$category',
      adjust: 'none',
    );
  }

  void saveQuote(ExQuoteData data) {
    final change = data.close - data.preClose;
    final changePct = data.preClose == 0 ? 0.0 : change / data.preClose * 100;
    _dataManager.saveQuoteSnapshots([
      StockQuote(
        code: data.code,
        name: data.name.isEmpty ? data.code : data.name,
        price: data.close,
        change: change,
        changePct: changePct,
        open: data.open,
        high: data.high,
        low: data.low,
        prevClose: data.preClose == 0 ? data.close : data.preClose,
        volume: data.vol.toDouble(),
        amount: data.amount,
        source: '通达信扩展:${data.category}',
      ),
    ], source: '通达信扩展:${data.category}');
  }

  void saveList(List<ExListItem> data) {
    _dataManager.saveStockListRows(
      data
          .map(
            (item) => {
              ...item.toJson(),
              'market': 'EXT:${item.category}',
              'stock_type': 'extended',
            },
          )
          .toList(),
      source: '通达信扩展',
    );
  }
}
