part of 'reusable_data_store.dart';

String normalizeFundCategory(Map<String, dynamic> row) {
  final existing = '${row['fund_category'] ?? row['fundCategory'] ?? ''}'
      .trim()
      .toLowerCase();
  if (_fundCategories.contains(existing)) return existing;
  final text = [
    row['fund_type'],
    row['type'],
    row['name'],
    row['fund_name'],
  ].map((value) => '${value ?? ''}'.toLowerCase()).join(' ');
  if (text.trim().isEmpty) return 'unknown';
  if (text.contains('后端') || text.contains('backend')) return 'backend';
  if (text.contains('货币') ||
      text.contains('money') ||
      text.contains('monetary') ||
      text.contains('现金')) {
    return 'money';
  }
  if (text.contains('债') || text.contains('bond')) return 'bond';
  if (text.contains('etf')) return 'etf';
  if (text.contains('指数') || text.contains('index')) return 'index';
  if (text.contains('fof')) return 'fof';
  if (text.contains('qdii')) return 'qdii';
  if (text.contains('reit')) return 'reits';
  return 'ordinary';
}

bool supportsOrdinaryFundNavCategory(Object? category) {
  final value = '${category ?? 'unknown'}';
  return value != 'money' && value != 'backend' && value != 'unknown';
}

bool supportsMoneyFundYieldCategory(Object? category) =>
    '${category ?? ''}' == 'money';

const _fundCategories = {
  'money',
  'backend',
  'bond',
  'etf',
  'index',
  'fof',
  'qdii',
  'reits',
  'ordinary',
  'unknown',
};

