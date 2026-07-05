import 'dart:convert';

import '../../../agent/data_fetcher/data_manager.dart';

class EarningsMarketDataRepository {
  final DataManager _dataManager;

  EarningsMarketDataRepository(this._dataManager);

  Map<String, dynamic>? saveEastmoneyFundamentals(
    String code,
    List<dynamic> rows,
  ) {
    return _dataManager.saveFundamentalRows(
      rows
          .whereType<Map>()
          .map((row) {
            final m = row.cast<String, dynamic>();
            return <String, dynamic>{
              'code': code,
              'report_date': (m['REPORT_DATE'] as String?)?.substring(0, 10),
              'revenue': _toNullableDouble(m['TOTALOPERATEREVE']),
              'revenue_yoy': _toNullableDouble(m['TOTALOPERATEREVETZ']),
              'net_profit': _toNullableDouble(m['PARENTNETPROFIT']),
              'profit_yoy': _toNullableDouble(m['PARENTNETPROFITTZ']),
              'gross_margin': _toNullableDouble(m['XSMLL']),
              'net_margin': _toNullableDouble(m['XSJLL']),
              'roe': _toNullableDouble(m['ROEJQ']),
              'debt_ratio': _toNullableDouble(m['ZCFZL']),
              'source': '东方财富:earnings',
              'raw_json': jsonEncode(m),
            };
          })
          .toList(),
      source: '东方财富:earnings',
    );
  }

  double? _toNullableDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }
}
