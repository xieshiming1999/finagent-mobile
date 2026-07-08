import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'models.dart';

part 'fund_category.dart';
part 'reusable_data_store_core_market.dart';
part 'reusable_data_store_core_reference.dart';
part 'reusable_data_store_fund_reference.dart';
part 'reusable_data_store_finance_news.dart';
part 'reusable_data_store_macro_factor.dart';
part 'reusable_data_store_fund_holding.dart';
part 'reusable_data_store_fund_performance.dart';
part 'reusable_data_store_index_constituent.dart';
part 'reusable_data_store_raw_payload.dart';
part 'reusable_data_store_technical_indicator.dart';
part 'reusable_data_store_alpha_factor.dart';
part 'reusable_data_store_coverage_symbol_market.dart';
part 'reusable_data_store_coverage_symbol_research.dart';
part 'reusable_data_store_coverage_summary_tables.dart';
part 'reusable_data_store_coverage_summary_yfinance.dart';
part 'reusable_data_store_coverage_summary_sources.dart';
part 'reusable_data_store_stats.dart';
part 'reusable_data_store_eastmoney_market_dragon_tiger.dart';
part 'reusable_data_store_eastmoney_market_hot_rank.dart';
part 'reusable_data_store_eastmoney_market_pool.dart';
part 'reusable_data_store_eastmoney_market_flow_rank.dart';
part 'reusable_data_store_eastmoney_market_unusual.dart';
part 'reusable_data_store_eastmoney_northbound_flow.dart';
part 'reusable_data_store_eastmoney_northbound_holding.dart';
part 'reusable_data_store_eastmoney_sector_market.dart';
part 'reusable_data_store_eastmoney_sector_identity.dart';
part 'reusable_data_store_market_screening.dart';
part 'reusable_data_store_margin_trading.dart';
part 'reusable_data_store_migrations.dart';
part 'reusable_data_store_migration_core_base.dart';
part 'reusable_data_store_migration_core_market_board.dart';
part 'reusable_data_store_migration_core_market_event.dart';
part 'reusable_data_store_migration_core_tdx_intraday.dart';
part 'reusable_data_store_migration_core_tdx_reference.dart';
part 'reusable_data_store_migration_core_identity.dart';
part 'reusable_data_store_migration_indexes.dart';
part 'reusable_data_store_migration_provider_research.dart';
part 'reusable_data_store_migration_provider_yfinance_core.dart';
part 'reusable_data_store_migration_provider_yfinance_market.dart';
part 'reusable_data_store_migration_provider_yfinance_ownership.dart';
part 'reusable_data_store_migration_provider_wind.dart';
part 'reusable_data_store_tdx_intraday.dart';
part 'reusable_data_store_tdx_auction.dart';
part 'reusable_data_store_tdx_distribution.dart';
part 'reusable_data_store_tdx_market_momentum.dart';
part 'reusable_data_store_tdx_market_top_board.dart';
part 'reusable_data_store_tdx_market_reference.dart';
part 'reusable_data_store_tdx_reference_corporate.dart';
part 'reusable_data_store_tdx_reference_sampling.dart';
part 'reusable_data_store_tushare_market_equity.dart';
part 'reusable_data_store_tushare_market_money_flow.dart';
part 'reusable_data_store_tushare_reference.dart';
part 'reusable_data_store_tushare_fundamental.dart';
part 'reusable_data_store_tushare_fundamental_api.dart';
part 'reusable_data_store_tushare_query_market.dart';
part 'reusable_data_store_tushare_query_reference.dart';
part 'reusable_data_store_wind.dart';
part 'reusable_data_store_wind_query.dart';
part 'reusable_data_store_yfinance_core.dart';
part 'reusable_data_store_yfinance_market_datasets.dart';
part 'reusable_data_store_yfinance_ownership_datasets.dart';
part 'reusable_data_store_yfinance_query.dart';

class ReusableDataStore {
  final String basePath;
  Database? _db;

  ReusableDataStore(this.basePath) {
    _open();
  }

  bool get available => _db != null;

  void _open() {
    try {
      final dir = Directory('$basePath/data');
      dir.createSync(recursive: true);
      _db = sqlite3.open('${dir.path}/market_data.db');
      _migrate();
    } catch (e) {
      _db = null;
      developer.log('init failed: $e', name: 'ReusableDataStore');
    }
  }

  void _migrate() {
    final db = _db;
    if (db == null) return;
    _migrateReusableDataStore(this, db);
  }

  StockQuote _quoteFromRow(Row row) {
    return StockQuote(
      code: row['code'] as String,
      timestamp: row['timestamp'] as String?,
      fetchedAt: row['fetched_at'] as String?,
      name: row['name'] as String? ?? row['code'] as String,
      price: _num(row['price']),
      change: _num(row['change']),
      changePct: _num(row['change_pct']),
      open: _num(row['open']),
      high: _num(row['high']),
      low: _num(row['low']),
      prevClose: _num(row['prev_close']),
      volume: _num(row['volume']),
      amount: _num(row['amount']),
      pe: _nullableNum(row['pe']),
      pb: _nullableNum(row['pb']),
      marketCap: _nullableNum(row['market_cap']),
      turnoverRate: _nullableNum(row['turnover_rate']),
      source: row['source'] as String,
    );
  }

  void _ensureColumn(String table, String column, String definition) {
    final db = _db;
    if (db == null) return;
    final rows = db.select('PRAGMA table_info($table)');
    final hasColumn = rows.any((row) => row['name'] == column);
    if (!hasColumn) {
      db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  KlineBar _klineFromRow(Row row) {
    return KlineBar(
      date: row['date'] as String,
      open: _num(row['open']),
      high: _num(row['high']),
      low: _num(row['low']),
      close: _num(row['close']),
      volume: _num(row['volume']),
      amount: _num(row['amount']),
      changePct: _nullableNum(row['change_pct']),
      turnoverRate: _nullableNum(row['turnover_rate']),
    );
  }

  Map<String, dynamic> _rowMap(Row row) {
    final result = <String, dynamic>{};
    for (final key in row.keys) {
      result[key] = row[key];
    }
    return result;
  }

  double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  double? _nullableNum(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  int? _int(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  String _cleanCode(String code) {
    final trimmed = code.trim();
    if (RegExp(r'^hk\d{5}$', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed.toLowerCase();
    }
    if (RegExp(r'^us[A-Za-z0-9.]+$', caseSensitive: false).hasMatch(trimmed)) {
      return 'us${trimmed.substring(2).toUpperCase()}';
    }
    final s = trimmed.replaceAll(
      RegExp(r'\.(SH|SZ|BJ|CSI|OF|IB)$', caseSensitive: false),
      '',
    );
    return s.replaceAll(RegExp(r'^(SH|SZ|BJ|CSI)', caseSensitive: false), '');
  }

  String _today() => DateTime.now().toIso8601String().substring(0, 10);

  String? _dateOnly(Object? value) {
    if (value == null) return null;
    final text = '$value';
    if (text.length >= 10) return text.substring(0, 10);
    return text.isEmpty ? null : text;
  }

  String? _normalizeDate(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    if (text.isEmpty) return null;
    final slash = text.replaceAll('/', '-');
    final first10 = slash.length >= 10 ? slash.substring(0, 10) : slash;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(first10)) {
      return first10;
    }
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 8) {
      return '${digits.substring(0, 4)}-${digits.substring(4, 6)}-${digits.substring(6, 8)}';
    }
    return null;
  }

  String? _stripTsCode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return raw
        .split('.')
        .first
        .replaceAll(RegExp(r'^(SH|SZ|BJ)', caseSensitive: false), '');
  }

  String? _tsSuffix(String? raw) {
    if (raw == null || !raw.contains('.')) return null;
    return raw.split('.').last.toUpperCase();
  }

  Map<String, double?> _flowRankValues(
    String period,
    Map<String, dynamic> row,
  ) {
    final keys = switch (period) {
      '3day' => const ['f267', 'f268', 'f269', 'f270', 'f271', 'f272'],
      '5day' => const ['f164', 'f165', 'f166', 'f167', 'f168', 'f169'],
      '10day' => const ['f174', 'f175', 'f176', 'f177', 'f178', 'f179'],
      _ => const ['f62', 'f184', 'f66', 'f69', 'f72', 'f75', 'f78', 'f81'],
    };
    return {
      'main_net': _nullableNum(row[keys[0]]),
      'main_pct': keys.length > 1 ? _nullableNum(row[keys[1]]) : null,
      'super_large_net': keys.length > 2 ? _nullableNum(row[keys[2]]) : null,
      'super_large_pct': keys.length > 3 ? _nullableNum(row[keys[3]]) : null,
      'large_net': keys.length > 4 ? _nullableNum(row[keys[4]]) : null,
      'large_pct': keys.length > 5 ? _nullableNum(row[keys[5]]) : null,
      'medium_net': keys.length > 6 ? _nullableNum(row[keys[6]]) : null,
      'medium_pct': keys.length > 7 ? _nullableNum(row[keys[7]]) : null,
    };
  }

  Map<String, dynamic> _ingestion(
    String schema,
    String table,
    int rows, {
    String provider = 'tushare',
  }) {
    return {
      'ingestion': 'structured',
      'provider': provider,
      'schema': schema,
      'table': table,
      'rows': rows,
      'persisted': rows > 0,
    };
  }

  Object? _firstValue(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      if (row.containsKey(key) && row[key] != null) return row[key];
    }
    return null;
  }

  String? _first(Map<String, dynamic> row, List<String> keys) {
    final value = _firstValue(row, keys);
    if (value == null) return null;
    final text = '$value';
    return text.isEmpty ? null : text;
  }

  String? _safeJson(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return jsonEncode('$value');
    }
  }
}
