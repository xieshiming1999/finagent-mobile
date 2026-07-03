part of 'reusable_data_store.dart';

extension ReusableDataStoreYfinanceMarketDatasets on ReusableDataStore {
  void saveYfinanceNews(List<Map<String, dynamic>> rows) {
    _saveYfinanceRows(this, 'yfinance_news', [
      'symbol',
      'news_id',
      'title',
      'publisher',
      'published_at',
      'link',
      'summary',
      'source',
      'updated_at',
      'raw_json',
    ], rows);
  }

  void saveYfinanceOptionExpiries(List<Map<String, dynamic>> rows) {
    _saveYfinanceRows(this, 'yfinance_option_expiries', [
      'symbol',
      'expiry_date',
      'source',
      'updated_at',
    ], rows);
  }

  void saveYfinanceOptionContracts(List<Map<String, dynamic>> rows) {
    _saveYfinanceRows(
      this,
      'yfinance_option_contracts',
      [
        'symbol',
        'expiry_date',
        'option_type',
        'contract_symbol',
        'strike',
        'last_price',
        'bid',
        'ask',
        'change',
        'percent_change',
        'volume',
        'open_interest',
        'implied_volatility',
        'in_the_money',
        'currency',
        'last_trade_date',
        'source',
        'updated_at',
        'raw_json',
      ],
      rows,
      numericColumns: const {
        'strike',
        'last_price',
        'bid',
        'ask',
        'change',
        'percent_change',
        'volume',
        'open_interest',
        'implied_volatility',
      },
      intColumns: const {'in_the_money'},
    );
  }

  void saveYfinanceCorporateActions(List<Map<String, dynamic>> rows) {
    _saveYfinanceRows(
      this,
      'yfinance_corporate_actions',
      [
        'symbol',
        'action_type',
        'action_date',
        'value',
        'source',
        'updated_at',
        'raw_json',
      ],
      rows,
      numericColumns: const {'value'},
    );
  }
}
