import 'dart:convert';

import 'models.dart';

String normalizeSecurityCode(String code) {
  final s = code.replaceAll(RegExp(r'\.[A-Z]+$', caseSensitive: false), '');
  return s.replaceAll(RegExp(r'^(SH|SZ|BJ|HK)', caseSensitive: false), '');
}

StockQuote normalizeQuote(StockQuote quote, String source) {
  return StockQuote(
    code: normalizeSecurityCode(quote.code),
    timestamp: quote.timestamp,
    fetchedAt: quote.fetchedAt,
    name: quote.name,
    price: quote.price,
    change: quote.change,
    changePct: quote.changePct,
    open: quote.open,
    high: quote.high,
    low: quote.low,
    prevClose: quote.prevClose,
    volume: quote.volume,
    amount: quote.amount,
    pe: quote.pe,
    pb: quote.pb,
    marketCap: quote.marketCap,
    turnoverRate: quote.turnoverRate,
    source: source,
  );
}

List<StockQuote> normalizeQuotes(List<StockQuote> quotes, String source) {
  return quotes.map((quote) => normalizeQuote(quote, source)).toList();
}

List<KlineBar> normalizeKlineBars(List<KlineBar> bars) {
  return bars
      .where((bar) => bar.date.isNotEmpty && bar.close > 0)
      .toList(growable: false);
}

List<Map<String, dynamic>> tryNormalizeWindDocumentPayload(
  String content, {
  required String tool,
  String? query,
}) {
  try {
    final parsed = jsonDecode(content);
    final rows = _extractWindRows(parsed);
    if (rows.isEmpty) return const [];
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    return List.generate(rows.length, (index) {
      final row = rows[index];
      final entityCode = normalizeSecurityCode(
        _string(row, ['Wind代码', 'windcode', '证券代码', '股票代码', '代码', 'code']) ??
            '',
      );
      final title =
          _string(row, ['标题', 'title', '公告标题', '新闻标题', '名称', '摘要标题']) ??
          '$tool-${index + 1}';
      final publishedAt =
          _normalizeWindDateTime(
            _string(row, ['发布时间', '发布日期', '日期', '时间', 'publish_time']),
          ) ??
          updatedAt;
      return {
        'doc_id': '${tool}_${query ?? ''}_${entityCode}_${publishedAt}_$title',
        'tool': tool,
        'query': query,
        'title': title,
        'publisher': _string(row, ['媒体', '来源', '发布机构', 'publisher', 'source']),
        'published_at': publishedAt,
        'url': _string(row, ['链接', 'url', 'URL', '公告链接', '新闻链接']),
        'summary':
            _string(row, ['摘要', 'summary', '内容摘要', '内容']) ??
            _previewWindRow(row),
        'entity_code': entityCode.isEmpty ? null : entityCode,
        'entity_name': _string(row, [
          '证券简称',
          '中文简称',
          '公司名称',
          '发行人',
          'entity_name',
        ]),
        'source': 'Wind',
        'updated_at': updatedAt,
        'raw_json': jsonEncode(row),
      };
    });
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> tryNormalizeWindGlobalNewsPayload(
  String content, {
  required String code,
}) {
  try {
    final parsed = jsonDecode(content);
    final rows = _extractWindRows(parsed);
    if (rows.isEmpty) return const [];
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    return List.generate(rows.length, (index) {
      final row = rows[index];
      final symbol = normalizeSecurityCode(
        _string(row, ['Wind代码', 'windcode', '证券代码', '股票代码', '代码', 'code']) ??
            code,
      ).toUpperCase();
      if (symbol.isEmpty) return null;
      final title =
          _string(row, ['标题', 'title', '公告标题', '新闻标题', '名称', '摘要标题']) ??
          'get_financial_news-${index + 1}';
      final publishedAt =
          _normalizeWindDateTime(
            _string(row, ['发布时间', '发布日期', '日期', '时间', 'publish_time']),
          ) ??
          updatedAt;
      return {
        'symbol': symbol,
        'news_id': 'wind_${symbol}_${publishedAt}_$title',
        'title': title,
        'publisher': _string(row, ['媒体', '来源', '发布机构', 'publisher', 'source']),
        'published_at': publishedAt,
        'link': _string(row, ['链接', 'url', 'URL', '公告链接', '新闻链接']),
        'summary':
            _string(row, ['摘要', 'summary', '内容摘要', '内容']) ??
            _previewWindRow(row),
        'source': 'Wind',
        'updated_at': updatedAt,
        'raw_json': jsonEncode(row),
      };
    }).whereType<Map<String, dynamic>>().toList(growable: false);
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> tryNormalizeWindFinanceNewsPayload(
  String content, {
  String? query,
}) {
  try {
    final parsed = jsonDecode(content);
    final rows = _extractWindRows(parsed);
    if (rows.isEmpty) return const [];
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    return List.generate(rows.length, (index) {
      final row = rows[index];
      final title =
          _string(row, ['标题', 'title', '公告标题', '新闻标题', '名称', '摘要标题']) ??
          'get_financial_news-${index + 1}';
      final publishedAt =
          _normalizeWindDateTime(
            _string(row, ['发布时间', '发布日期', '日期', '时间', 'publish_time']),
          ) ??
          fetchedAt;
      return {
        'news_id': 'wind_${query ?? ''}_${publishedAt}_$title',
        'title': title,
        'summary':
            _string(row, ['摘要', 'summary', '内容摘要']) ?? _previewWindRow(row),
        'content': _string(row, ['内容', 'content', '正文', 'body']),
        'publisher': _string(row, ['媒体', '来源', '发布机构', 'publisher', 'source']),
        'published_at': publishedAt,
        'url': _string(row, ['链接', 'url', 'URL', '公告链接', '新闻链接']),
        'source': 'wind',
        'fetched_at': fetchedAt,
        'raw_json': jsonEncode(row),
      };
    });
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> tryNormalizeWindEconomicPayload(
  String content, {
  required String metricQuery,
}) {
  try {
    final parsed = jsonDecode(content);
    final rows = _extractWindRows(parsed);
    if (rows.isEmpty) return const [];
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    return rows
        .map((row) {
          final metricName =
              _string(row, ['指标名称', '指标', '名称', 'metric_name', 'name']) ??
              metricQuery;
          final date = _normalizeWindDate(
            _string(row, ['日期', '交易日期', '时间', '报告期', 'date']) ??
                updatedAt.substring(0, 10),
          );
          final valueNum = _number(row, ['值', '数值', 'value', '最新值', '指标值']);
          final valueText =
              valueNum?.toString() ??
              _string(row, ['值', '数值', 'value', '最新值', '指标值']) ??
              _previewWindRow(row);
          return {
            'series_key': '${metricQuery}_$metricName',
            'metric_query': metricQuery,
            'metric_name': metricName,
            'metric_code': _string(row, [
              '指标代码',
              'metric_id',
              'metric_code',
              'Wind代码',
            ]),
            'date': date,
            'value_num': valueNum,
            'value_text': valueText,
            'unit': _string(row, ['单位', 'unit']),
            'frequency': _string(row, ['频率', 'freq', 'frequency']),
            'currency': _string(row, ['币种', 'currency']),
            'source': 'Wind',
            'updated_at': updatedAt,
            'raw_json': jsonEncode(row),
          };
        })
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> tryNormalizeWindAnalyticsPayload(
  String content, {
  required String question,
}) {
  try {
    final parsed = jsonDecode(content);
    final rows = _extractWindRows(parsed);
    if (rows.isEmpty) return const [];
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    return List.generate(rows.length, (index) {
      final row = rows[index];
      final entityCode = normalizeSecurityCode(
        _string(row, ['Wind代码', 'windcode', '证券代码', '代码', 'code']) ?? '',
      );
      return {
        'result_id': '${question}_${entityCode}_${index + 1}',
        'question': question,
        'entity_code': entityCode.isEmpty ? null : entityCode,
        'entity_name': _string(row, ['证券简称', '中文简称', '名称', 'name', '公司名称']),
        'value_date': _normalizeWindDate(
          _string(row, ['日期', '交易日期', '时间', '报告期', 'date']) ??
              updatedAt.substring(0, 10),
        ),
        'title':
            _string(row, ['标题', 'title', '名称', 'name', '指标名称']) ?? question,
        'content': _previewWindRow(row),
        'value_num': _number(row, ['值', '数值', 'value', '最新值', '收盘价', '最新价']),
        'value_text':
            _string(row, ['值', '数值', 'value', '最新值', '收盘价', '最新价']) ??
            _previewWindRow(row),
        'unit': _string(row, ['单位', 'unit']),
        'source': 'Wind',
        'updated_at': updatedAt,
        'raw_json': jsonEncode(row),
      };
    });
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> tryNormalizeWindFundHoldingPayload(
  String content, {
  String? fundCode,
}) {
  try {
    final parsed = jsonDecode(content);
    final rows = _extractWindRows(parsed);
    if (rows.isEmpty) return const [];
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final normalized = <Map<String, dynamic>>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final normalizedFundCode = normalizeSecurityCode(
        _string(row, ['基金代码', '基金Wind代码', 'fund_code', 'Wind代码']) ??
            fundCode ??
            '',
      );
      final stockCode = normalizeSecurityCode(
        _string(row, ['股票代码', '持仓证券代码', '证券代码', 'stock_code', 'code']) ?? '',
      );
      final reportDate = _normalizeWindDate(
        _string(row, ['报告期', '截止日期', '持仓日期', '日期', 'report_date']) ?? '',
      );
      if (normalizedFundCode.isEmpty ||
          stockCode.isEmpty ||
          reportDate.isEmpty) {
        continue;
      }
      normalized.add({
        'fund_code': normalizedFundCode,
        'report_date': reportDate,
        'stock_code': stockCode,
        'stock_name': _string(row, [
          '股票名称',
          '持仓证券简称',
          '证券简称',
          '中文简称',
          'stock_name',
          'name',
        ]),
        'hold_shares': _number(row, ['持股数', '持仓数量', '持有股数', 'hold_shares']),
        'hold_value': _number(row, ['持仓市值', '持有市值', '市值', 'hold_value']),
        'hold_pct': _number(row, [
          '占净值比例',
          '占基金净值比例',
          '持仓占比',
          '占净值',
          'hold_pct',
        ]),
        'rank': _int(row, ['序号', '排名', 'rank']) ?? i + 1,
        'source': 'Wind',
        'fetched_at': fetchedAt,
        'raw_json': jsonEncode(row),
      });
    }
    return normalized;
  } catch (_) {
    return const [];
  }
}

({String code, List<MoneyFlow> rows})? tryNormalizeWindMoneyFlowPayload(
  String content, {
  String? code,
}) {
  try {
    final parsed = jsonDecode(content);
    final windRows = _extractWindRows(parsed);
    if (windRows.isEmpty) return null;
    final normalizedCode = normalizeSecurityCode(code ?? '');
    final flows = <MoneyFlow>[];
    String? rowCode;
    for (final row in windRows) {
      final currentCode = normalizeSecurityCode(
        _string(row, ['Wind代码', 'windcode', '证券代码', '股票代码', 'code']) ??
            normalizedCode,
      );
      final date = _normalizeWindDate(
        _string(row, ['交易时间', '交易日期', '日期', '时间', 'date']) ?? '',
      );
      if (currentCode.isEmpty || date.isEmpty) continue;
      rowCode ??= currentCode;
      if (currentCode != rowCode) continue;

      final superLarge = _number(row, [
        '超大单净流入额(万元)',
        '超大单净流入-净额',
        '今日超大单净流入-净额',
        'super_large_net',
      ]);
      final large = _number(row, [
        '大单净流入额(万元)',
        '大单净流入-净额',
        '今日大单净流入-净额',
        'large_net',
      ]);
      final medium = _number(row, [
        '中单净流入额(万元)',
        '中单净流入-净额',
        '今日中单净流入-净额',
        'medium_net',
      ]);
      final small = _number(row, [
        '小单净流入额(万元)',
        '小单净流入-净额',
        '今日小单净流入-净额',
        'small_net',
      ]);
      final main =
          _number(row, ['当日主力净流入额', '今日主力净流入-净额', '主力净流入-净额', 'main_net']) ??
          ((superLarge != null || large != null)
              ? (superLarge ?? 0) + (large ?? 0)
              : null);
      if (main == null &&
          small == null &&
          medium == null &&
          large == null &&
          superLarge == null) {
        continue;
      }
      flows.add(
        MoneyFlow(
          date: date,
          mainNetInflow: main ?? 0,
          smallNetInflow: small ?? 0,
          mediumNetInflow: medium ?? 0,
          largeNetInflow: large ?? 0,
          superLargeNetInflow: superLarge ?? 0,
          closePrice: _number(row, ['收盘价', '最新成交价', '最新价', 'close_price']),
          changePct: _number(row, ['涨跌幅', 'change_pct', 'pct_chg']),
        ),
      );
    }
    if (rowCode == null || flows.isEmpty) return null;
    flows.sort((a, b) => a.date.compareTo(b.date));
    return (code: rowCode, rows: flows);
  } catch (_) {
    return null;
  }
}

({String code, List<Map<String, dynamic>> rows})? tryNormalizeWindXdxrPayload(
  String content, {
  String? code,
}) {
  try {
    final parsed = jsonDecode(content);
    final windRows = _extractWindRows(parsed);
    if (windRows.isEmpty) return null;
    final fallbackCode = normalizeSecurityCode(code ?? '');
    final normalized = <Map<String, dynamic>>[];
    String? rowCode;
    for (final row in windRows) {
      final currentCode = normalizeSecurityCode(
        _string(row, ['Wind代码', 'windcode', '证券代码', '股票代码', 'code']) ??
            fallbackCode,
      );
      final eventDate = _normalizeWindDate(
        _string(row, [
              '除权除息日',
              '股权登记日',
              '派息日',
              '分红年度',
              '公告日期',
              '事件日期',
              '日期',
              'date',
            ]) ??
            '',
      );
      final categoryName =
          _string(row, [
            '事件类型',
            '事件名称',
            '方案类型',
            '分红方案',
            '标题',
            '名称',
            'category_name',
          ]) ??
          'Wind corporate action';
      if (currentCode.isEmpty ||
          eventDate.isEmpty ||
          !_isXdxrLikeEvent(categoryName, row)) {
        continue;
      }
      rowCode ??= currentCode;
      if (currentCode != rowCode) continue;
      normalized.add({
        'date': eventDate,
        'category': 1,
        'categoryName': categoryName,
        'a': _number(row, [
          '每股派息税前',
          '每股派息',
          '派息比例',
          '现金分红比例',
          '现金分红',
          '每10股派息',
          '派息',
          'a',
        ]),
        'b': _number(row, ['送股比例', '每10股送股', '送股', 'b']),
        'c': _number(row, ['转增比例', '每10股转增', '转增', 'c']),
        'd': _number(row, ['配股比例', '每10股配股', '配股', 'd']),
        'raw_json': jsonEncode(row),
      });
    }
    if (rowCode == null || normalized.isEmpty) return null;
    normalized.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    return (code: rowCode, rows: normalized);
  } catch (_) {
    return null;
  }
}

List<Map<String, dynamic>> tryNormalizeWindCorporateActionPayload(
  String content, {
  String? symbol,
}) {
  try {
    final parsed = jsonDecode(content);
    final windRows = _extractWindRows(parsed);
    if (windRows.isEmpty) return const [];
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final fallbackSymbol = normalizeSecurityCode(symbol ?? '').toUpperCase();
    final normalized = <Map<String, dynamic>>[];
    for (final row in windRows) {
      final currentSymbol = normalizeSecurityCode(
        _string(row, ['Wind代码', 'windcode', '证券代码', '股票代码', 'code']) ??
            fallbackSymbol,
      ).toUpperCase();
      final actionDate = _normalizeWindDate(
        _string(row, [
              '除权除息日',
              '股权登记日',
              '派息日',
              '分红年度',
              '公告日期',
              '事件日期',
              '日期',
              'date',
            ]) ??
            '',
      );
      final label =
          _string(row, [
            '事件类型',
            '事件名称',
            '方案类型',
            '分红方案',
            '标题',
            '名称',
            'category_name',
          ]) ??
          '';
      final actionType = _corporateActionType(label, row);
      if (currentSymbol.isEmpty || actionDate.isEmpty || actionType == null) {
        continue;
      }
      normalized.add({
        'symbol': currentSymbol,
        'action_type': actionType,
        'action_date': actionDate,
        'value': _corporateActionValue(actionType, row),
        'source': 'wind',
        'updated_at': updatedAt,
        'raw_json': jsonEncode(row),
      });
    }
    normalized.sort(
      (a, b) => '${a['action_date']}'.compareTo('${b['action_date']}'),
    );
    return normalized;
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> tryNormalizeWindGlobalStatementPayload(
  String content, {
  String? symbol,
}) {
  try {
    final parsed = jsonDecode(content);
    final windRows = _extractWindRows(parsed);
    if (windRows.isEmpty) return const [];
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final result = <Map<String, dynamic>>[];
    final fallbackSymbol = normalizeSecurityCode(symbol ?? '').toUpperCase();
    for (final row in windRows) {
      final rowSymbol = normalizeSecurityCode(
        _string(row, ['Wind代码', 'windcode', '证券代码', 'code']) ?? fallbackSymbol,
      ).toUpperCase();
      final period = _normalizeWindDate(
        _string(row, ['交易时间', '报告期', '日期', '时间', 'date']) ?? updatedAt,
      );
      if (rowSymbol.isEmpty || period.isEmpty) continue;
      for (final entry in row.entries) {
        final field = entry.key;
        if (_isIdentityOrDateField(field)) continue;
        final value = _coerceNumber(entry.value);
        if (value == null) continue;
        result.add({
          'symbol': rowSymbol,
          'statement_type': 'wind_global_fundamentals',
          'period': period,
          'item': field,
          'value': value,
          'source': 'Wind',
          'updated_at': updatedAt,
          'raw_json': jsonEncode({'field': field, 'value': value, 'row': row}),
        });
      }
    }
    return result;
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> tryNormalizeWindGlobalProfilePayload(
  String content, {
  String? symbol,
}) {
  try {
    final parsed = jsonDecode(content);
    final windRows = _extractWindRows(parsed);
    if (windRows.isEmpty) return const [];
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final fallbackSymbol = normalizeSecurityCode(symbol ?? '').toUpperCase();
    final result = <Map<String, dynamic>>[];
    for (final row in windRows) {
      final rowSymbol = normalizeSecurityCode(
        _string(row, ['Wind代码', 'windcode', '证券代码', 'code']) ?? fallbackSymbol,
      ).toUpperCase();
      if (rowSymbol.isEmpty) continue;
      for (final entry in row.entries) {
        final field = entry.key;
        final value = entry.value;
        if (value == null || '$value'.trim().isEmpty) continue;
        if (RegExp(
          r'Wind代码|windcode|证券代码|code',
          caseSensitive: false,
        ).hasMatch(field)) {
          continue;
        }
        result.add({
          'symbol': rowSymbol,
          'field_key': field,
          'field_value': value is Map || value is List
              ? jsonEncode(value)
              : '$value',
          'field_type': value is List
              ? 'array'
              : value == null
              ? 'null'
              : value.runtimeType.toString(),
          'source': 'Wind',
          'updated_at': updatedAt,
          'raw_json': jsonEncode({field: value}),
        });
      }
    }
    return result;
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> tryNormalizeWindGlobalRecommendationPayload(
  String content, {
  String? symbol,
}) {
  try {
    final parsed = jsonDecode(content);
    final windRows = _extractWindRows(parsed);
    if (windRows.isEmpty) return const [];
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final fallbackSymbol = normalizeSecurityCode(symbol ?? '').toUpperCase();
    return windRows
        .map((row) {
          final rowSymbol = normalizeSecurityCode(
            _string(row, ['Wind代码', 'windcode', '证券代码', 'code']) ??
                fallbackSymbol,
          ).toUpperCase();
          final period = _normalizeWindDate(
            _string(row, ['交易时间', '报告期', '日期', '时间', 'date']) ?? updatedAt,
          );
          if (rowSymbol.isEmpty || period.isEmpty) return null;
          final counts = _windRecommendationCounts(row);
          if (counts == null) return null;
          return {
            'symbol': rowSymbol,
            'period': period,
            'strong_buy': counts['strong_buy'],
            'buy': counts['buy'],
            'hold': counts['hold'],
            'sell': counts['sell'],
            'strong_sell': counts['strong_sell'],
            'source': 'Wind',
            'updated_at': updatedAt,
            'raw_json': jsonEncode(row),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> tryNormalizeWindGlobalHolderPayload(
  String content, {
  String? symbol,
}) {
  try {
    final parsed = jsonDecode(content);
    final windRows = _extractWindRows(parsed);
    if (windRows.isEmpty) return const [];
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final fallbackSymbol = normalizeSecurityCode(symbol ?? '').toUpperCase();
    return windRows
        .map((row) {
          final rowSymbol = normalizeSecurityCode(
            _string(row, ['Wind代码', 'windcode', '证券代码', 'code']) ??
                fallbackSymbol,
          ).toUpperCase();
          final holderName = _string(row, [
            '股东名称',
            '持有人名称',
            '机构名称',
            '名称',
            'holder_name',
            'name',
          ]);
          final reportedDate = _normalizeWindDate(
            _string(row, ['报告期', '截止日期', '日期', 'date', 'reported_date']) ??
                updatedAt,
          );
          if (rowSymbol.isEmpty || holderName == null || reportedDate.isEmpty) {
            return null;
          }
          return {
            'symbol': rowSymbol,
            'holder_type':
                _string(row, ['股东类型', '持有人类型', '类型', 'holder_type', 'type']) ??
                'wind_equity_holder',
            'holder_name': holderName,
            'reported_date': reportedDate,
            'pct_held': _number(row, [
              '持股比例',
              '占总股本比例',
              '持仓比例',
              'pct_held',
              'percent',
            ]),
            'shares': _number(row, ['持股数', '持股数量', 'shares', '数量']),
            'value': _number(row, ['持仓市值', '市值', 'value']),
            'pct_change': _number(row, ['持股变动比例', '变动比例', 'pct_change']),
            'source': 'Wind',
            'updated_at': updatedAt,
            'raw_json': jsonEncode(row),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> tryNormalizeWindStockShareholderPayload(
  String content, {
  String? code,
}) {
  try {
    final parsed = jsonDecode(content);
    final windRows = _extractWindRows(parsed);
    if (windRows.isEmpty) return const [];
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final fallbackCode = normalizeSecurityCode(code ?? '');
    return windRows.indexed
        .map((entry) {
          final index = entry.$1;
          final row = entry.$2;
          final rowCode = normalizeSecurityCode(
            _string(row, ['Wind代码', 'windcode', '证券代码', 'code']) ??
                fallbackCode,
          );
          final holderName = _string(row, [
            '股东名称',
            '持有人名称',
            '机构名称',
            '名称',
            'holder_name',
            'name',
          ]);
          final reportDate = _normalizeWindDate(
            _string(row, ['报告期', '截止日期', '日期', 'date', 'reported_date']) ??
                fetchedAt,
          );
          if (rowCode.isEmpty || holderName == null || reportDate.isEmpty) {
            return null;
          }
          return {
            'code': rowCode,
            'report_date': reportDate,
            'holder_name': holderName,
            'holder_type':
                _string(row, [
                  '股东类型',
                  '持有人类型',
                  '股本性质',
                  '类型',
                  'holder_type',
                  'type',
                ]) ??
                'wind_equity_holder',
            'rank': _number(row, ['排名', '序号', '编号', 'rank']) ?? index + 1,
            'hold_shares': _number(row, ['持股数', '持股数量', 'shares', '数量']),
            'hold_pct': _number(row, [
              '持股比例',
              '占总股本比例',
              '持仓比例',
              'pct_held',
              'percent',
            ]),
            'share_nature': _string(row, ['股本性质', '股份性质', 'share_nature']),
            'announcement_date': _normalizeWindDate(
              _string(row, ['公告日期', 'ann_date', 'announcement_date']) ?? '',
            ),
            'shareholder_note': _string(row, ['股东说明', '说明', '备注', 'note']),
            'shareholder_count': _number(row, ['股东总数', 'shareholder_count']),
            'average_holding': _number(row, ['平均持股数', 'average_holding']),
            'source': 'Wind',
            'fetched_at': fetchedAt,
            'raw_json': jsonEncode(row),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> tryNormalizeWindFundPerformancePayload(
  String content, {
  String? fundCode,
}) {
  try {
    final parsed = jsonDecode(content);
    final windRows = _extractWindRows(parsed);
    if (windRows.isEmpty) return const [];
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final fallbackCode = normalizeSecurityCode(fundCode ?? '');
    return windRows
        .map((row) {
          final code = normalizeSecurityCode(
            _string(row, ['基金代码', '基金Wind代码', 'Wind代码', 'windcode', 'code']) ??
                fallbackCode,
          );
          final metricDate = _normalizeWindDate(
            _string(row, ['净值日期', '交易日期', '日期', '报告期', 'date']) ?? fetchedAt,
          );
          if (code.isEmpty || metricDate.isEmpty) return null;
          return {
            'code': code,
            'metric_date': metricDate,
            'provider': 'wind',
            'capability_id': 'wind.fund.performance_metrics',
            'source_action': 'get_fund_performance',
            'nav': _number(row, ['单位净值', '最新净值', 'nav']),
            'return_ytd': _number(row, ['今年以来', '年初至今', 'return_ytd']),
            'return_1w': _number(row, ['近1周', '近一周', 'return_1w']),
            'return_1m': _number(row, ['近1月', '近一月', 'return_1m']),
            'return_3m': _number(row, ['近3月', '近三月', 'return_3m']),
            'return_6m': _number(row, ['近6月', '近六月', 'return_6m']),
            'return_1y': _number(row, ['近1年', '近一年', 'return_1y']),
            'return_2y': _number(row, ['近2年', '近二年', 'return_2y']),
            'return_3y': _number(row, ['近3年', '近三年', 'return_3y']),
            'return_since_inception': _number(row, [
              '成立以来',
              'return_since_inception',
            ]),
            'fetched_at': fetchedAt,
            'raw_json': jsonEncode(row),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> tryNormalizeWindFundListPayload(
  String content, {
  String? fundCode,
}) {
  try {
    final parsed = jsonDecode(content);
    final windRows = _extractWindRows(parsed);
    if (windRows.isEmpty) return const [];
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final fallbackCode = normalizeSecurityCode(fundCode ?? '');
    return windRows
        .map((row) {
          final code = normalizeSecurityCode(
            _string(row, ['基金代码', '基金Wind代码', 'Wind代码', 'windcode', 'code']) ??
                fallbackCode,
          );
          final name = _string(row, [
            '基金简称',
            '基金名称',
            '证券简称',
            '中文简称',
            '名称',
            'fund_name',
            'name',
          ]);
          if (code.isEmpty || name == null || name.isEmpty) return null;
          return {
            'code': code,
            'name': name,
            'fund_type': _string(row, ['基金类型', '投资类型', '类型', 'fund_type']),
            'company': _string(row, [
              '基金公司',
              '基金管理人',
              '管理人',
              '管理公司',
              'company',
            ]),
            'manager': _string(row, ['基金经理', '现任基金经理', '经理', 'manager']),
            'setup_date': _normalizeWindDate(
              _string(row, ['成立日期', '设立日期', 'setup_date', 'found_date']) ?? '',
            ),
            'total_size': _number(row, [
              '基金规模',
              '资产净值',
              '最新规模',
              '规模',
              'total_size',
            ]),
            'nav': _number(row, ['单位净值', '最新净值', 'nav']),
            'nav_date': _normalizeWindDate(
              _string(row, ['净值日期', '交易日期', '日期', 'nav_date']) ?? '',
            ),
            'return_1y': _number(row, ['近1年', '近一年', 'return_1y']),
            'return_3y': _number(row, ['近3年', '近三年', 'return_3y']),
            'return_ytd': _number(row, ['今年以来', '年初至今', 'return_ytd']),
            'source': 'Wind',
            'updated_at': updatedAt,
            'raw_json': jsonEncode(row),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> tryNormalizeWindFundManagerPayload(
  String content, {
  String? fundCode,
}) {
  final funds = tryNormalizeWindFundListPayload(content, fundCode: fundCode);
  return funds
      .where((row) => (row['manager']?.toString().trim().isNotEmpty ?? false))
      .map(
        (row) => {
          'manager_name': row['manager'],
          'company': row['company'],
          'fund_code': row['code'],
          'fund_name': row['name'],
          'fund_type': row['fund_type'],
          'total_size': row['total_size'],
          'updated_at': row['updated_at'],
          'source': 'Wind',
          'raw_json': row['raw_json'],
        },
      )
      .toList(growable: false);
}

List<Map<String, dynamic>> tryNormalizeWindFundNavPayload(
  String content, {
  String? fundCode,
}) {
  try {
    final parsed = jsonDecode(content);
    final windRows = _extractWindRows(parsed);
    if (windRows.isEmpty) return const [];
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final fallbackCode = normalizeSecurityCode(fundCode ?? '');
    return windRows
        .map((row) {
          final code = normalizeSecurityCode(
            _string(row, ['基金代码', '基金Wind代码', 'Wind代码', 'windcode', 'code']) ??
                fallbackCode,
          );
          final date = _normalizeWindDate(
            _string(row, ['净值日期', '交易日期', '日期', '时间', 'date']) ?? '',
          );
          final nav = _number(row, ['单位净值', '最新净值', '收盘价', 'nav', 'close']);
          if (code.isEmpty || date.isEmpty || nav == null) return null;
          return {
            'code': code,
            'date': date,
            'nav': nav,
            'acc_nav': _number(row, ['累计净值', '复权单位净值', 'acc_nav']),
            'daily_return': _number(row, ['日涨跌幅', '涨跌幅', 'daily_return']),
            'source': 'Wind',
            'fetched_at': fetchedAt,
            'raw_json': jsonEncode(row),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

({String code, String tradeDate, List<double> values})?
tryNormalizeWindIndexMomentumPayload(String content, {String? code}) {
  try {
    final parsed = jsonDecode(content);
    final windRows = _extractWindRows(parsed);
    if (windRows.isEmpty) return null;
    final fallbackCode = normalizeSecurityCode(code ?? '');
    final values = <double>[];
    String? rowCode;
    String? tradeDate;
    for (final row in windRows) {
      final currentCode = normalizeSecurityCode(
        _string(row, ['Wind代码', 'windcode', '指数代码', '证券代码', 'code']) ??
            fallbackCode,
      );
      final currentDate = _normalizeWindDate(
        _string(row, ['交易时间', '交易日期', '日期', '时间', 'date']) ?? '',
      );
      if (currentCode.isEmpty || currentDate.isEmpty) continue;
      rowCode ??= currentCode;
      tradeDate ??= currentDate;
      if (currentCode != rowCode || currentDate != tradeDate) continue;
      values.addAll(_windMomentumValues(row));
    }
    if (rowCode == null || tradeDate == null || values.isEmpty) return null;
    return (code: rowCode, tradeDate: tradeDate, values: values);
  } catch (_) {
    return null;
  }
}

StockQuote? tryNormalizeWindQuotePayload(String content, {String? code}) {
  try {
    final parsed = jsonDecode(content);
    final row = _findQuoteLikeMap(parsed) ?? _findWindQuoteTableRow(parsed);
    if (row == null) return null;
    final normalizedCode = normalizeSecurityCode(
      code ?? _string(row, ['Wind代码', 'windcode', '代码', '证券代码', 'code']) ?? '',
    );
    if (normalizedCode.isEmpty) return null;
    final price = _number(row, ['最新成交价', '最新价', '现价', '收盘价', 'close', 'price']);
    if (price == null || price <= 0) return null;
    final prevClose = _number(row, ['昨收盘', '前收盘价', 'prevClose']) ?? 0;
    final change =
        _number(row, ['涨跌', 'change']) ??
        (prevClose > 0 ? price - prevClose : 0);
    final changePct =
        _number(row, ['涨跌幅', 'changePct', 'pct_chg']) ??
        (prevClose > 0 ? change / prevClose * 100 : 0);
    return StockQuote(
      code: normalizedCode,
      timestamp:
          _normalizeQuoteTimestamp(
            _string(row, ['交易时间', 'trade_time', 'dateTime', 'DateTime']),
          ) ??
          _normalizeQuoteTimestamp(_string(row, ['日期', 'date', 'Date'])),
      name: _string(row, ['证券简称', '中文简称', '名称', 'name']) ?? normalizedCode,
      price: price,
      change: change,
      changePct: changePct,
      open: _number(row, ['今日开盘价', '今开', '开盘价', 'open']) ?? 0,
      high: _number(row, ['今日最高价', '最高价', '最高', 'high']) ?? 0,
      low: _number(row, ['今日最低价', '最低价', '最低', 'low']) ?? 0,
      prevClose: prevClose,
      volume: _number(row, ['成交量', 'volume']) ?? 0,
      amount: _number(row, ['成交额', 'amount']) ?? 0,
      pe: _number(row, ['市盈率(TTM)', '最新市盈率PE', '市盈率', 'PE', 'pe']),
      pb: _number(row, ['市净率', '最新市净率PB', 'PB', 'pb']),
      marketCap: _number(row, ['总市值1', '总市值', '流通市值', 'marketCap']),
      turnoverRate: _number(row, ['换手率', 'turnoverRate']),
      source: 'Wind',
    );
  } catch (_) {
    return null;
  }
}

String? _normalizeQuoteTimestamp(String? value) {
  if (value == null || value.isEmpty) return null;
  final trimmed = value.trim();
  final parsed = DateTime.tryParse(trimmed);
  if (parsed != null) return parsed.toUtc().toIso8601String();
  final dateOnly = _normalizeWindDate(trimmed);
  if (dateOnly.isNotEmpty) return '${dateOnly}T00:00:00.000Z';
  return null;
}

List<Map<String, dynamic>> tryNormalizeWindFundamentalPayload(
  String content, {
  String? code,
}) {
  try {
    final parsed = jsonDecode(content);
    final rows = _extractWindRows(parsed);
    if (rows.isEmpty) return const [];
    final now = DateTime.now().toUtc().toIso8601String();
    final normalized = <Map<String, dynamic>>[];
    for (final row in rows) {
      final normalizedCode = normalizeSecurityCode(
        _string(row, ['Wind代码', 'windcode', '证券代码', 'code']) ?? code ?? '',
      );
      if (normalizedCode.isEmpty) continue;
      final reportDate = _normalizeWindDate(
        _string(row, ['交易时间', '报告期', 'report_date']) ?? now,
      );
      final fact = <String, dynamic>{
        'code': normalizedCode,
        'report_date': reportDate,
        'pe_ttm': _number(row, ['最新市盈率PE_TTM', '最新市盈率PE', '市盈率(TTM)', '市盈率']),
        'pb': _number(row, ['最新市净率PB_LF', '最新市净率PB', '市净率']),
        'ps_ttm': _number(row, ['市销率(TTM)', '最新市销率PS']),
        'roe': _number(row, ['最新净资产收益率ROE', '最新ROE', 'ROE']),
        'gross_margin': _number(row, ['销售毛利率', '毛利率', 'gross_margin']),
        'net_margin': _number(row, ['销售净利率', '净利率', 'net_margin']),
        'revenue': _number(row, ['营业总收入', '营业收入', '营收', 'revenue']),
        'revenue_yoy': _number(row, ['营收同比增长率', '营业收入同比增长率']),
        'net_profit': _number(row, ['归母净利润', '净利润', '利润总额', 'net_profit']),
        'profit_yoy': _number(row, ['净利润同比增长率', '归母净利润同比增长率']),
        'total_assets': _number(row, ['总资产', '资产总计', 'total_assets']),
        'total_liabilities': _number(row, ['总负债', '负债合计', 'total_liabilities']),
        'debt_ratio': _number(row, ['资产负债率', 'debt_ratio']),
        'market_cap': _number(row, ['总市值', '总市值1', '流通市值']),
        'source': 'Wind',
        'fetched_at': now,
        'raw_json': jsonEncode(row),
      };
      final hasKnownMetric = fact.entries.any(
        (entry) =>
            entry.key != 'code' &&
            entry.key != 'report_date' &&
            entry.key != 'source' &&
            entry.key != 'fetched_at' &&
            entry.key != 'raw_json' &&
            entry.value != null,
      );
      if (hasKnownMetric) normalized.add(fact);
    }
    return normalized;
  } catch (_) {
    return const [];
  }
}

({String code, Map<String, dynamic> payload})?
tryNormalizeWindCompanyInfoPayload(
  String content, {
  String? code,
  required String infoType,
}) {
  try {
    final parsed = jsonDecode(content);
    final rows = _extractWindRows(parsed);
    var normalizedCode = normalizeSecurityCode(code ?? '');
    if (rows.isNotEmpty) {
      normalizedCode = normalizeSecurityCode(
        _string(rows.first, ['Wind代码', 'windcode', '证券代码', 'code']) ??
            normalizedCode,
      );
    }
    if (normalizedCode.isEmpty) return null;
    final categories = rows
        .map((row) {
          final title =
              _string(row, [
                '标题',
                'title',
                '名称',
                'name',
                '基金名称',
                '债券简称',
                '指数简称',
                '公司名称',
                '证券简称',
                '中文简称',
              ]) ??
              _string(row, ['类型', 'type', '类别', 'category']) ??
              infoType;
          return {'title': title};
        })
        .toList(growable: false);
    final payload = <String, dynamic>{
      'categories': categories,
      'first_content': rows.isNotEmpty
          ? _previewWindRow(rows.first)
          : _previewWindContent(parsed),
      'rows': rows,
      'raw': parsed,
      'source': 'Wind',
      'info_type': infoType,
    };
    return (code: normalizedCode, payload: payload);
  } catch (_) {
    return null;
  }
}

({String code, List<KlineBar> bars})? tryNormalizeWindKlinePayload(
  String content, {
  String? code,
}) {
  try {
    final parsed = jsonDecode(content);
    final rows = _extractWindRows(parsed);
    if (rows.isEmpty) return null;
    var normalizedCode = normalizeSecurityCode(code ?? '');
    final bars = <KlineBar>[];
    for (final row in rows) {
      normalizedCode = normalizeSecurityCode(
        _string(row, ['Wind代码', 'windcode', '证券代码', 'code']) ?? normalizedCode,
      );
      final date = _normalizeWindDate(
        _string(row, ['交易日期', '日期', '时间', 'trade_date', 'date']) ?? '',
      );
      final open = _number(row, ['开盘价', '今日开盘价', 'open']);
      final high = _number(row, ['最高价', '今日最高价', 'high']);
      final low = _number(row, ['最低价', '今日最低价', 'low']);
      final close = _number(row, ['收盘价', '最新成交价', 'close']);
      if (normalizedCode.isEmpty ||
          date.isEmpty ||
          open == null ||
          high == null ||
          low == null ||
          close == null ||
          close <= 0) {
        continue;
      }
      bars.add(
        KlineBar(
          date: date,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: _number(row, ['成交量', 'volume']) ?? 0,
          amount: _number(row, ['成交额', 'amount']) ?? 0,
          changePct: _number(row, ['涨跌幅', 'changePct', 'pct_chg']),
          turnoverRate: _number(row, ['换手率', 'turnoverRate']),
        ),
      );
    }
    if (normalizedCode.isEmpty || bars.isEmpty) return null;
    bars.sort((a, b) => a.date.compareTo(b.date));
    return (code: normalizedCode, bars: bars);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _findQuoteLikeMap(Object? value) {
  if (value is Map) {
    final row = value.cast<String, dynamic>();
    if (_number(row, ['最新成交价', '最新价', '现价', '收盘价', 'close', 'price']) != null) {
      return row;
    }
    for (final child in row.values) {
      final found = _findQuoteLikeMap(child);
      if (found != null) return found;
    }
  } else if (value is List) {
    for (final child in value) {
      final found = _findQuoteLikeMap(child);
      if (found != null) return found;
    }
  }
  return null;
}

Map<String, dynamic>? _findWindQuoteTableRow(Object? value) {
  for (final row in _extractWindRows(value)) {
    if (_number(row, ['最新成交价', '最新价', '现价', '收盘价', 'close', 'price']) != null) {
      return row;
    }
  }
  return null;
}

List<Map<String, dynamic>> _extractWindRows(Object? value) {
  final rows = <Map<String, dynamic>>[];
  void visit(Object? candidate) {
    if (candidate is Map) {
      final map = candidate.cast<String, dynamic>();
      final columns = map['columns'];
      final rawRows = map['rows'];
      if (columns is List && rawRows is List) {
        final names = columns
            .map((column) {
              if (column is Map) return '${column['name'] ?? ''}';
              return '$column';
            })
            .where((name) => name.trim().isNotEmpty)
            .toList(growable: false);
        if (names.isNotEmpty) {
          for (final rawRow in rawRows) {
            if (rawRow is! List) continue;
            final row = <String, dynamic>{};
            for (var i = 0; i < names.length && i < rawRow.length; i++) {
              row[names[i]] = rawRow[i];
            }
            rows.add(row);
          }
        }
        return;
      }
      if (_looksLikeWindFundamentalRow(map)) rows.add(map);
      final data = map['data'];
      if (data != null) visit(data);
    } else if (candidate is List) {
      for (final item in candidate) {
        visit(item);
      }
    }
  }

  visit(value);
  return rows;
}

bool _looksLikeWindFundamentalRow(Map<String, dynamic> row) {
  final hasCode = _string(row, ['Wind代码', 'windcode', '证券代码', 'code']) != null;
  if (!hasCode) return false;
  return _number(row, [
        '最新市盈率PE_TTM',
        '最新市盈率PE',
        '市盈率(TTM)',
        '市盈率',
        '最新市净率PB_LF',
        '最新市净率PB',
        '市净率',
        '市销率(TTM)',
        '最新市销率PS',
        '最新净资产收益率ROE',
        '最新ROE',
        'ROE',
        '总市值',
        '总市值1',
        '流通市值',
      ]) !=
      null;
}

String? _string(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value != null && '$value'.trim().isNotEmpty) return '$value'.trim();
  }
  return null;
}

String _normalizeWindDate(String value) {
  final trimmed = value.trim();
  final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(trimmed);
  if (compact != null) {
    return '${compact.group(1)}-${compact.group(2)}-${compact.group(3)}';
  }
  return trimmed.length > 10 ? trimmed.substring(0, 10) : trimmed;
}

String? _normalizeWindDateTime(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(value.trim());
  if (parsed != null) return parsed.toUtc().toIso8601String();
  final date = _normalizeWindDate(value);
  if (date.isEmpty) return null;
  return '${date}T00:00:00.000Z';
}

bool _isXdxrLikeEvent(String categoryName, Map<String, dynamic> row) {
  final text = '$categoryName\n${_previewWindRow(row)}';
  return RegExp(
    r'(分红|派息|除权|除息|送股|转增|配股|股息|dividend|split|rights)',
    caseSensitive: false,
  ).hasMatch(text);
}

String? _corporateActionType(String label, Map<String, dynamic> row) {
  final text = '$label\n${_previewWindRow(row)}';
  if (RegExp(r'(配股|供股|rights)', caseSensitive: false).hasMatch(text)) {
    return 'rights';
  }
  if (RegExp(r'(拆股|合股|拆细|split)', caseSensitive: false).hasMatch(text)) {
    return 'split';
  }
  if (RegExp(r'(送股|转增)', caseSensitive: false).hasMatch(text)) {
    return 'split';
  }
  if (RegExp(r'(分红|派息|除息|股息|dividend)', caseSensitive: false).hasMatch(text)) {
    return 'dividend';
  }
  if (RegExp(r'(资本利得|capital gains?)', caseSensitive: false).hasMatch(text)) {
    return 'capital_gains';
  }
  return null;
}

double? _corporateActionValue(String actionType, Map<String, dynamic> row) {
  if (actionType == 'dividend' || actionType == 'capital_gains') {
    return _number(row, [
      '每股派息税前',
      '每股派息',
      '派息比例',
      '现金分红比例',
      '现金分红',
      '每10股派息',
      '派息',
      'amount',
      'value',
    ]);
  }
  if (actionType == 'split') {
    final bonus = _number(row, ['送股比例', '每10股送股', '送股']);
    final transfer = _number(row, ['转增比例', '每10股转增', '转增']);
    return _number(row, ['拆股比例', 'splitRatio', 'ratio', 'value']) ??
        ((bonus != null || transfer != null)
            ? (bonus ?? 0) + (transfer ?? 0)
            : null);
  }
  if (actionType == 'rights') {
    return _number(row, [
      '配股比例',
      '每10股配股',
      '配股',
      'rightsRatio',
      'ratio',
      'value',
    ]);
  }
  return _number(row, ['value', 'amount']);
}

List<double> _windMomentumValues(Map<String, dynamic> row) {
  final result = <double>[];
  const preferred = [
    '涨跌幅',
    '近1月涨跌幅',
    '近3月涨跌幅',
    '近6月涨跌幅',
    '近1年涨跌幅',
    '6周期相对强弱指标',
    '12周期相对强弱指标',
    '指数平滑异同移动平均',
    'DIF快线',
    'DEA慢线',
    '随机指标K值',
    '随机指标D值',
    '随机指标J值',
    '14周期顺势指标',
    '26周期能量指标',
    'MACD',
    'RSI',
    'KDJ_K',
    'KDJ_D',
    'KDJ_J',
    'momentum',
    'value',
  ];
  for (final field in preferred) {
    final value = _number(row, [field]);
    if (value != null) result.add(value);
  }
  if (result.isNotEmpty) return result;
  for (final entry in row.entries) {
    final field = entry.key;
    if (RegExp(
      r'代码|名称|简称|日期|时间|name|code',
      caseSensitive: false,
    ).hasMatch(field)) {
      continue;
    }
    if (!RegExp(
      r'涨跌|强弱|动量|RSI|MACD|KDJ|DIF|DEA|CCI|能量|momentum|return|change',
      caseSensitive: false,
    ).hasMatch(field)) {
      continue;
    }
    final value = entry.value;
    if (value is num) {
      result.add(value.toDouble());
    } else if (value is String) {
      final parsed = double.tryParse(
        value.replaceAll('%', '').replaceAll(',', '').trim(),
      );
      if (parsed != null) result.add(parsed);
    }
  }
  return result;
}

double? _number(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll('%', '').replaceAll(',', '').trim();
      final parsed = double.tryParse(cleaned);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

Map<String, double?>? _windRecommendationCounts(Map<String, dynamic> row) {
  final direct = {
    'strong_buy': _number(row, ['强烈买入', '强力买入', 'strong_buy', 'strongBuy']),
    'buy': _number(row, ['买入', '推荐', '增持', 'buy']),
    'hold': _number(row, ['持有', '中性', 'neutral', 'hold']),
    'sell': _number(row, ['卖出', '减持', 'sell']),
    'strong_sell': _number(row, ['强烈卖出', 'strong_sell', 'strongSell']),
  };
  if (direct.values.any((value) => value != null)) return direct;
  return null;
}

double? _coerceNumber(Object? value) {
  if (value == null || value == '') return null;
  if (value is num) return value.toDouble();
  return double.tryParse(
    '$value'.replaceAll('%', '').replaceAll(',', '').trim(),
  );
}

bool _isIdentityOrDateField(String field) {
  return RegExp(
    r'代码|名称|简称|日期|时间|报告期|name|code|date|time|period',
    caseSensitive: false,
  ).hasMatch(field);
}

int? _int(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.replaceAll(',', '').trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

String _previewWindRow(Map<String, dynamic> row) {
  final parts = <String>[];
  for (final entry in row.entries) {
    final value = '${entry.value}'.trim();
    if (value.isEmpty) continue;
    parts.add('${entry.key}: $value');
    if (parts.length >= 3) break;
  }
  if (parts.isEmpty) return jsonEncode(row);
  return parts.join(' | ');
}

String _previewWindContent(Object? value) {
  if (value is String) return value;
  try {
    final encoded = jsonEncode(value);
    return encoded.length > 240 ? '${encoded.substring(0, 240)}...' : encoded;
  } catch (_) {
    return '$value';
  }
}
