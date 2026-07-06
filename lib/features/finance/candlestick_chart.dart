import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:k_chart/flutter_k_chart.dart';

import '../../shared/i18n/app_localizations.dart';

/// Candlestick chart displayed inline in chat.
///
/// Takes Tushare-format data ({columns, data}) and renders via k_chart.
class CandlestickChart extends StatelessWidget {
  final String title;
  final Map<String, dynamic> fileData;

  const CandlestickChart({
    super.key,
    required this.title,
    required this.fileData,
  });

  @override
  Widget build(BuildContext context) {
    final datas = _parseData(fileData);
    if (datas.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(AppLocalizations.of(context).noChartDataAvailable),
      );
    }

    DataUtil.calculate(datas);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xff18191d),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            SizedBox(
              height: 350,
              child: KChartWidget(
                datas,
                ChartStyle()
                  ..pointWidth = 7.0
                  ..candleWidth = 5.0
                  ..candleLineWidth = 1.0
                  ..volWidth = 5.0,
                ChartColors(),
                isTrendLine: false,
                mainState: MainState.MA,
                secondaryState: SecondaryState.MACD,
                volHidden: false,
                isLine: false,
                isTapShowInfoDialog: true,
                showNowPrice: true,
                fixedLength: 2,
                maDayList: const [5, 10, 20],
                timeFormat: TimeFormat.YEAR_MONTH_DAY,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Parse Tushare {columns, data} format into KLineEntity list.
  /// Handles nested formats: {data: {data: "json_string"}} from ServiceCall.
  List<KLineEntity> _parseData(Map<String, dynamic> raw) {
    var table = raw;
    if (!table.containsKey('columns') && table.containsKey('data')) {
      final inner = table['data'];
      if (inner is Map<String, dynamic>) {
        table = inner;
      }
      if (table.containsKey('data') &&
          table['data'] is String &&
          !table.containsKey('columns')) {
        try {
          table = json.decode(table['data'] as String) as Map<String, dynamic>;
        } catch (_) {
          return [];
        }
      }
    }

    final columns = (table['columns'] as List?)?.cast<String>() ?? [];
    final data = table['data'] as List? ?? [];
    if (columns.isEmpty || data.isEmpty) return [];

    final iDate = columns.indexOf('trade_date');
    final iOpen = columns.indexOf('open');
    final iHigh = columns.indexOf('high');
    final iLow = columns.indexOf('low');
    final iClose = columns.indexOf('close');
    final iVol = columns.indexOf('vol');
    final iAmount = columns.indexOf('amount');

    if (iOpen < 0 || iHigh < 0 || iLow < 0 || iClose < 0) return [];

    final entities = <KLineEntity>[];
    for (final row in data) {
      final r = row as List;
      final dateStr = iDate >= 0 ? '${r[iDate]}' : '';
      entities.add(KLineEntity.fromCustom(
        open: _toDouble(r[iOpen]),
        high: _toDouble(r[iHigh]),
        low: _toDouble(r[iLow]),
        close: _toDouble(r[iClose]),
        vol: iVol >= 0 ? _toDouble(r[iVol]) : 0,
        amount: iAmount >= 0 ? _toDouble(r[iAmount]) : null,
        time: _parseDate(dateStr),
      ));
    }

    entities.sort((a, b) => (a.time ?? 0).compareTo(b.time ?? 0));
    return entities;
  }

  int _parseDate(String s) {
    if (s.length == 8) {
      final y = int.tryParse(s.substring(0, 4)) ?? 2000;
      final m = int.tryParse(s.substring(4, 6)) ?? 1;
      final d = int.tryParse(s.substring(6, 8)) ?? 1;
      return DateTime(y, m, d).millisecondsSinceEpoch;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
