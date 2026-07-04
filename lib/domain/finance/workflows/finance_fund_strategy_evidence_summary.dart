import 'dart:convert';

import '../../../agent/message.dart';

/// Summarizes fund StrategySpec evidence when the agent starts drifting toward
/// stock-only strategy tools after fund NAV/yield evidence is already present.
class FinanceFundStrategyEvidenceSummary {
  String? build({
    required List<Message> messages,
    required int turnStartIndex,
    required String failureSummary,
  }) {
    Map<String, dynamic>? fundNav;
    Map<String, dynamic>? fundYield;
    Map<String, dynamic>? observation;
    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final decoded = _decodeJsonMap(result.content);
      if (decoded == null) continue;
      switch (decoded['action']) {
        case 'query_fund_nav':
        case 'fund_nav':
          fundNav ??= decoded;
          break;
        case 'query_fund_money_yield':
        case 'fund_money_yield':
          fundYield ??= decoded;
          break;
        case 'custom_strategy_observe':
        case 'custom_strategy_fund_backtest':
          observation ??= decoded;
          break;
      }
    }
    if (fundNav == null && fundYield == null && observation == null) {
      return null;
    }
    final code =
        _seriesCode(fundNav) ??
        _seriesCode(fundYield) ??
        _seriesCode(observation) ??
        '-';
    final navRows = _rows(fundNav);
    final yieldRows = _rows(fundYield);
    final observedRows = _rows(observation);
    final sourceTime =
        _seriesValue(fundNav, 'endDate') ??
        _seriesValue(fundYield, 'endDate') ??
        _fallbackText(observation?['sourceDataTime']);
    final fetchedAt =
        _seriesValue(fundNav, 'fetchedAt') ??
        _seriesValue(fundYield, 'fetchedAt') ??
        _fallbackText(observation?['fetchedAt']);
    return [
      '已达到本轮受控数据调用预算，下面直接使用已经取得的基金定投观察策略证据作答；未继续调用股票策略、文件读取、脚本或额外 provider。',
      '',
      '## 基金定投观察策略',
      '',
      '- 观察对象：$code。',
      '- NAV 证据：${_evidenceLine(fundNav, 'query_fund_nav', navRows)}',
      '- 货币基金收益证据：${_evidenceLine(fundYield, 'query_fund_money_yield', yieldRows)}',
      '- 策略观察证据：${_evidenceLine(observation, 'custom_strategy_observe/custom_strategy_fund_backtest', observedRows)}',
      '- 数据时间：$sourceTime；获取时间：$fetchedAt。',
      '',
      '## 边界',
      '',
      '- 本轮是基金观察/定投证据，不是股票回测或买卖建议。',
      '- 普通基金应使用净值、阶段收益、回撤和波动；货币基金应使用万份收益/七日年化。',
      '- 不使用股票 K 线、个股资金流、盘口或股票策略工具替代基金判断。',
      '- 本轮失败/跳过：$failureSummary',
    ].join('\n');
  }

  Map<String, dynamic>? _decodeJsonMap(String content) {
    if (!content.trimLeft().startsWith('{')) return null;
    try {
      final decoded = jsonDecode(content);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  int _rows(Map<String, dynamic>? payload) {
    if (payload == null) return 0;
    final data = payload['data'];
    if (data is List) return data.length;
    final series = payload['seriesSummary'];
    if (series is List && series.isNotEmpty && series.first is Map) {
      final rows = (series.first as Map)['rows'];
      if (rows is num) return rows.toInt();
    }
    return 0;
  }

  String? _seriesCode(Map<String, dynamic>? payload) {
    final direct = _textValue(payload?['code'] ?? payload?['fundCode']);
    if (direct.isNotEmpty) return direct;
    final series = payload?['seriesSummary'];
    if (series is List && series.isNotEmpty && series.first is Map) {
      final code = _textValue((series.first as Map)['code']);
      if (code.isNotEmpty) return code;
    }
    return null;
  }

  String? _seriesValue(Map<String, dynamic>? payload, String key) {
    final direct = _textValue(payload?[key]);
    if (direct.isNotEmpty) return direct;
    final series = payload?['seriesSummary'];
    if (series is List && series.isNotEmpty && series.first is Map) {
      final value = _textValue((series.first as Map)[key]);
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  String _evidenceLine(Map<String, dynamic>? payload, String action, int rows) {
    if (payload == null) return '$action 未取得。';
    final source = _textValue(payload['source'] ?? payload['provider']);
    final cache = _textValue(
      payload['cacheStatus'] ?? payload['cacheDecision'],
    );
    return '$action rows=$rows；source=${source.isEmpty ? '-' : source}；cache=${cache.isEmpty ? '-' : cache}。';
  }

  String _textValue(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text == 'null' ? '' : text;
  }

  String _fallbackText(Object? value, {String fallback = '-'}) {
    final text = _textValue(value);
    return text.isEmpty ? fallback : text;
  }
}
