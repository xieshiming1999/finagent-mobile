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
      }
    }

    if (fundNav == null || fundYield == null) return null;
    final navCodes = _codesFromPayload(fundNav);
    final yieldCodes = _codesFromPayload(fundYield);
    if (navCodes.isEmpty || yieldCodes.isEmpty) return null;

    final ordinaryCode = navCodes.first;
    final moneyCode = yieldCodes.first;
    final ordinaryIdentity = _identityFor(fundList, ordinaryCode);
    final moneyIdentity = _identityFor(fundList, moneyCode);
    final navSummary = _seriesSummaryFor(fundNav, ordinaryCode);
    final yieldRow = _latestRowFor(fundYield, moneyCode);

    return [
      '已停止脚本、文件读取或额外 scratch 计算；下面直接使用本轮结构化基金证据作答。',
      '',
      '## 基金类型与证据口径',
      '',
      '| 基金 | 类型证据 | 正确观察证据 | 本轮数据 |',
      '|---|---|---|---|',
      '| ${_fundLabel(ordinaryIdentity, ordinaryCode)} | ${_typeText(ordinaryIdentity, fallback: '普通基金或非货币基金，需以 fund_list 类型字段继续确认')} | 普通基金使用 NAV、阶段收益、回撤、持仓和业绩指标；不要使用货币基金万份收益口径。 | ${_navLine(navSummary, fundNav)} |',
      '| ${_fundLabel(moneyIdentity, moneyCode)} | ${_typeText(moneyIdentity, fallback: '货币基金或现金管理类基金，需以 fund_list 类型字段继续确认')} | 货币基金使用万份收益、七日年化、收益稳定性和流动性；不要套用普通 NAV 趋势/回撤策略。 | ${_moneyYieldLine(yieldRow, fundYield)} |',
      '',
      '## 结论边界',
      '',
      '- 普通基金和货币基金的数据语义不同，不能把货币基金当普通净值基金做 NAV 趋势、K 线形态、PE/PB 或股票技术分析。',
      '- 本轮已取得普通基金 NAV 证据和货币基金收益证据；不需要 `Script`、文件读取、股票 K 线工具或额外 provider 调用来完成这次比较。',
      '- 若后续要做策略或监控，普通基金应进入基金 NAV/回撤观察合同；货币基金应进入 money-yield/七日年化收益观察合同。',
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
