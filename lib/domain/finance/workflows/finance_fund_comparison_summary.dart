import 'dart:convert';

import '../../../agent/message.dart';

/// Summarizes ordinary-fund versus money-fund evidence when the agent starts
/// drifting toward scratch tools after structured fund readbacks are available.
class FinanceFundComparisonSummary {
  String? build({
    required List<Message> messages,
    required int turnStartIndex,
    required String failureSummary,
  }) {
    Map<String, dynamic>? fundList;
    Map<String, dynamic>? fundNav;
    Map<String, dynamic>? fundYield;
    Map<String, dynamic>? fundPerformance;
    Map<String, dynamic>? macroFactors;

    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final decoded = _decodeMap(result.content);
      if (decoded == null) continue;
      switch (decoded['action']) {
        case 'query_fund_list':
        case 'fund_list':
          fundList ??= decoded;
          break;
        case 'query_fund_nav':
          fundNav ??= decoded;
          break;
        case 'query_fund_money_yield':
        case 'fund_money_yield':
          fundYield ??= decoded;
          break;
        case 'query_fund_performance':
        case 'fund_performance':
          fundPerformance ??= decoded;
          break;
        case 'query_macro_factors':
          macroFactors ??= decoded;
          break;
      }
    }

    if (fundNav == null && fundYield == null && fundPerformance == null) {
      return null;
    }
    final navCodes = _codesFromPayload(fundNav);
    final yieldCodes = _codesFromPayload(fundYield);
    final performanceCodes = _codesFromPayload(fundPerformance);
    final comparisonCodes = <String>{
      ...navCodes,
      ...yieldCodes,
      ...performanceCodes,
    }.toList(growable: false);
    if (comparisonCodes.length < 2 && macroFactors == null) return null;

    final rows = <String>[];
    for (final code in comparisonCodes.take(4)) {
      final identity = _identityFor(fundList, code);
      rows.add(
        '| ${_fundLabel(identity, code)} | ${_typeText(identity, fallback: '类型需继续确认')} | ${_navEvidenceFor(fundNav, code)} | ${_performanceEvidenceFor(fundPerformance, code)} | ${_moneyYieldEvidenceFor(fundYield, code)} |',
      );
    }

    return [
      '已停止脚本、文件读取或额外 scratch 计算；下面直接使用本轮结构化基金证据作答。',
      '',
      '## 基金比较证据口径',
      '',
      '| 基金 | 类型证据 | NAV/净值证据 | 业绩指标证据 | 货币收益证据 |',
      '|---|---|---|---|---|',
      ...rows,
      '',
      '## 利率与流动性宏观因素',
      '',
      _macroLine(macroFactors),
      '',
      '- 债券基金通常对利率方向、久期、信用利差和流动性更敏感；利率上行会压制久期资产，流动性宽松有利于债券估值和信用风险偏好。',
      '- 股票基金通常对权益风险偏好、行业盈利预期和市场流动性更敏感；流动性收紧会降低估值弹性，流动性宽松可能放大权益反弹。',
      '- 本轮宏观因子只作为比较背景，不是申购、赎回或调仓指令。',
      '',
      '## 结论边界',
      '',
      '- 债券基金、股票基金和货币基金的数据语义不同，不能用股票 K 线、个股资金流或普通 NAV 口径替代所有基金类型。',
      '- 本轮已取得结构化基金证据和宏观因子读回结果；不需要 `Research`、`Environment`、`Script`、文件读取、股票 K 线工具或额外 provider 调用来完成这次比较。',
      '- 若后续要做策略或监控，应进入基金 NAV/收益/回撤观察合同；交易或定投动作需要单独确认。',
      '- 本轮失败/跳过：$failureSummary',
    ].join('\n');
  }

  Map<String, dynamic>? _decodeMap(String content) {
    final text = content.trim();
    if (!text.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  List<String> _codesFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return const <String>[];
    final codes = <String>{};
    final fundCodes = payload['fundCodes'];
    if (fundCodes is List) {
      for (final value in fundCodes) {
        final code = _cleanCode(value);
        if (code.isNotEmpty) codes.add(code);
      }
    }
    final symbol = _cleanCode(payload['symbol']);
    if (symbol.isNotEmpty) codes.add(symbol);
    for (final row in _rows(payload['data'])) {
      final code = _cleanCode(row['code'] ?? row['symbol'] ?? row['fundCode']);
      if (code.isNotEmpty) codes.add(code);
    }
    for (final row in _rows(payload['seriesSummary'])) {
      final code = _cleanCode(row['code']);
      if (code.isNotEmpty) codes.add(code);
    }
    return codes.toList(growable: false);
  }

  Map<String, dynamic>? _identityFor(
    Map<String, dynamic>? fundList,
    String code,
  ) {
    for (final row in _rows(fundList?['data'])) {
      if (_cleanCode(row['code'] ?? row['symbol']) == code) return row;
    }
    return null;
  }

  Map<String, dynamic>? _seriesSummaryFor(
    Map<String, dynamic>? payload,
    String code,
  ) {
    for (final row in _rows(payload?['seriesSummary'])) {
      if (_cleanCode(row['code']) == code) return row;
    }
    return null;
  }

  Map<String, dynamic>? _latestRowFor(
    Map<String, dynamic>? payload,
    String code,
  ) {
    final rows = _rows(payload?['data'])
        .where((row) => _cleanCode(row['code'] ?? row['symbol']) == code)
        .toList(growable: false);
    if (rows.isEmpty) return null;
    rows.sort((a, b) => '${a['date'] ?? ''}'.compareTo('${b['date'] ?? ''}'));
    return rows.last;
  }

  List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String _fundLabel(Map<String, dynamic>? identity, String code) {
    final name = '${identity?['name'] ?? identity?['fund_name'] ?? ''}'.trim();
    return name.isEmpty ? code : '$name $code';
  }

  String _typeText(Map<String, dynamic>? identity, {required String fallback}) {
    final values = [
      identity?['fund_type'],
      identity?['fundType'],
      identity?['fund_category'],
      identity?['fundCategory'],
    ].map((value) => '${value ?? ''}'.trim()).where((text) => text.isNotEmpty);
    final joined = values.join(' / ');
    return joined.isEmpty ? fallback : joined;
  }

  String _navLine(
    Map<String, dynamic>? summary,
    Map<String, dynamic>? payload,
  ) {
    if (summary == null) {
      return 'NAV readback count=${payload?['count'] ?? '-'}；source=${payload?['source'] ?? '-'}；sourceTime=${payload?['sourceDataTime'] ?? '-'}；fetchedAt=${payload?['fetchedAt'] ?? '-'}';
    }
    return 'rows=${summary['rows'] ?? '-'}；${summary['startDate'] ?? '-'} 至 ${summary['endDate'] ?? '-'}；累计收益 ${_fmtPct(summary['cumulativeReturnPct'])}；最大回撤 ${_fmtPct(summary['maxDrawdownPct'])}；source=${summary['source'] ?? payload?['source'] ?? '-'}；fetchedAt=${summary['fetchedAt'] ?? payload?['fetchedAt'] ?? '-'}';
  }

  String _moneyYieldLine(
    Map<String, dynamic>? row,
    Map<String, dynamic>? payload,
  ) {
    if (row == null) {
      return 'money-yield readback count=${payload?['count'] ?? '-'}；source=${payload?['source'] ?? '-'}；sourceTime=${payload?['sourceDataTime'] ?? '-'}；fetchedAt=${payload?['fetchedAt'] ?? '-'}';
    }
    return 'date=${row['date'] ?? payload?['sourceDataTime'] ?? '-'}；万份收益=${row['million_copies_income'] ?? row['millionCopiesIncome'] ?? '-'}；七日年化=${_fmtPct(row['seven_day_annualized_yield'] ?? row['sevenDayAnnualizedYield'])}；source=${row['source'] ?? payload?['source'] ?? '-'}；fetchedAt=${row['fetched_at'] ?? payload?['fetchedAt'] ?? '-'}';
  }

  String _navEvidenceFor(Map<String, dynamic>? payload, String code) {
    if (payload == null) return '未取得 NAV 读回。';
    final summary = _seriesSummaryFor(payload, code);
    if (summary != null) return _navLine(summary, payload);
    final rows = _rows(
      payload['data'],
    ).where((row) => _cleanCode(row['code'] ?? row['symbol']) == code).length;
    if (rows > 0) {
      return 'NAV rows=$rows；source=${payload['source'] ?? '-'}；fetchedAt=${payload['fetchedAt'] ?? '-'}';
    }
    return 'NAV count=${payload['count'] ?? 0}；未匹配该基金。';
  }

  String _performanceEvidenceFor(Map<String, dynamic>? payload, String code) {
    if (payload == null) return '未取得业绩指标读回。';
    final rows = _rows(payload['data'])
        .where((row) => _cleanCode(row['code'] ?? row['symbol']) == code)
        .toList(growable: false);
    if (rows.isEmpty) {
      return 'performance count=${payload['count'] ?? 0}；未匹配该基金。';
    }
    final row = rows.first;
    return 'metricDate=${row['metric_date'] ?? row['date'] ?? '-'}；近1年=${_fmtPct(row['return_1y'])}；YTD=${_fmtPct(row['return_ytd'])}；source=${row['provider'] ?? payload['source'] ?? '-'}。';
  }

  String _moneyYieldEvidenceFor(Map<String, dynamic>? payload, String code) {
    if (payload == null) return '非货币基金可为空。';
    final row = _latestRowFor(payload, code);
    if (row == null) {
      return 'money-yield count=${payload['count'] ?? 0}；未匹配该基金。';
    }
    return _moneyYieldLine(row, payload);
  }

  String _macroLine(Map<String, dynamic>? payload) {
    if (payload == null) {
      return '- 利率/流动性宏观因子未取得；应把这一点作为宏观证据缺口，而不是假设没有宏观影响。';
    }
    final count = payload['count'] ?? 0;
    final provenance = payload['provenance'];
    final fetchedAt = provenance is Map ? provenance['fetchedAt'] : null;
    if (count is num && count > 0) {
      return '- `query_macro_factors` 返回 $count 行；source=${provenance is Map ? provenance['source'] ?? '-' : '-'}；fetchedAt=${fetchedAt ?? '-'}。这些行只能解释利率/流动性背景，不能直接生成基金买卖信号。';
    }
    return '- `query_macro_factors(family:"rates_liquidity")` 返回 `status:${payload['status'] ?? 'missing'}`；${payload['missingReason'] ?? '当前本地没有匹配利率/流动性因子。'}；fetchedAt=${fetchedAt ?? '-'}。这表示宏观证据层缺口，不表示利率和流动性不重要。';
  }

  String _fmtPct(Object? value) {
    if (value == null) return '-';
    if (value is num) return '${value.toStringAsFixed(2)}%';
    final text = '$value'.trim();
    return text.isEmpty ? '-' : text;
  }

  String _cleanCode(Object? value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '';
    final match = RegExp(r'\d{6}').firstMatch(text);
    return match?.group(0) ?? '';
  }
}
