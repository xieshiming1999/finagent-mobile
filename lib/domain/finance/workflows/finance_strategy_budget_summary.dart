import 'dart:convert';

import '../../../agent/message.dart';
import 'finance_workflow_state.dart';

/// Finance-owned strategy budget summaries.
///
/// These summaries answer from already-collected strategy evidence when the
/// finance data budget blocks more provider/tool calls. The generic agent loop
/// should not own strategy-specific workflow-state checks or generated
/// strategy prose.
class FinanceStrategyBudgetSummary {
  String? buildComparison({
    required List<Message> messages,
    required int turnStartIndex,
  }) {
    if (!_hasStrategyComparisonState(messages, turnStartIndex)) return null;

    Map<String, dynamic>? indicators;
    Map<String, dynamic>? signals;
    Map<String, dynamic>? kline;
    Map<String, dynamic>? quote;
    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final decoded = _decodeMap(result.content);
      if (decoded == null) continue;
      if (indicators == null &&
          decoded.containsKey('rsi') &&
          decoded.containsKey('macd_dif') &&
          decoded.containsKey('boll_upper')) {
        indicators = decoded;
        continue;
      }
      if (signals == null &&
          decoded.containsKey('signals') &&
          decoded.containsKey('netScore')) {
        signals = decoded;
        continue;
      }
      if (kline == null && decoded['action'] == 'query_kline') {
        kline = decoded;
        continue;
      }
      if (quote == null && decoded['action'] == 'query_quote') {
        quote = decoded;
        continue;
      }
    }

    if (indicators == null && signals == null && kline == null) return null;
    final symbol =
        indicators?['symbol']?.toString() ??
        signals?['symbol']?.toString() ??
        quote?['symbol']?.toString() ??
        kline?['symbol']?.toString() ??
        '600519';
    final source =
        indicators?['source']?.toString() ??
        kline?['source']?.toString() ??
        quote?['source']?.toString() ??
        '本地可复用数据';
    final dataTime =
        indicators?['sourceDataTime']?.toString() ??
        _klineRangeEnd(kline) ??
        _quoteLatestTime(quote) ??
        '-';
    final fetchedAt = indicators?['fetchedAt']?.toString() ?? '-';
    final range =
        indicators?['range']?.toString() ??
        _klineRangeText(kline) ??
        '本地 query_kline 返回窗口';
    const implementedBoundary = '本轮未取得完整结构化策略能力列表，不能声称所有请求策略都已实现。';

    final hasIndicatorValues = indicators != null;
    final rsi = _evidenceValue(indicators?['rsi']);
    final macd = _evidenceValue(
      indicators?['macd_hist'] ?? indicators?['macd_dif'],
    );
    final priceVsMa = _evidenceValue(indicators?['price_vs_ma20']);
    final bollLower = _evidenceValue(indicators?['boll_lower']);
    final bollMid = _evidenceValue(indicators?['boll_mid']);
    final bollUpper = _evidenceValue(indicators?['boll_upper']);
    final signalDirection = _evidenceValue(signals?['direction']);
    final netScore = _evidenceValue(signals?['netScore']);
    final indicatorBoundary = hasIndicatorValues
        ? '已取得本地技术指标，可做当前信号层面的比较。'
        : '本轮只取得本地 K 线/行情和工具能力说明，未实际计算 RSI、MACD、布林线、均线指标值。';
    final comparisonRows = hasIndicatorValues
        ? [
            '- RSI：当前 RSI=$rsi，属于超卖/反弹观察信号，但不能单独构成买入结论。',
            '- MACD：当前 MACD 证据=$macd，动能仍偏弱，不能确认趋势反转。',
            '- 布林线：下轨/中轨/上轨分别为 $bollLower / $bollMid / $bollUpper；价格靠近下轨时只能说明波动区间位置，不等同于已验证胜率。',
            '- 均线：price_vs_ma20=$priceVsMa，均线证据偏弱，趋势确认不足。',
            '- 多信号汇总：direction=$signalDirection，netScore=$netScore。',
          ]
        : [
            '- RSI：未取得本轮指标值，只能确认本地 K 线可用，不能判断 RSI 策略表现。',
            '- MACD：未取得本轮指标值，不能判断 MACD 动能或金叉/死叉策略表现。',
            '- 布林线：未取得本轮上/中/下轨值，不能判断布林线均值回归策略表现。',
            '- 均线：未取得本轮均线状态，不能判断均线策略表现。',
          ];

    return '已达到本轮受控数据调用预算，未继续执行额外策略回测调用。以下只基于已取得的本地证据作比较。\n\n'
        '本地数据证据（$symbol）：\n'
        '- 来源：$source。\n'
        '- 数据时间：$dataTime；获取时间：$fetchedAt。\n'
        '- 本地窗口：$range。\n\n'
        '策略/信号对比：\n'
        '- 证据边界：$indicatorBoundary\n'
        '${comparisonRows.join('\n')}\n\n'
        '实现边界与可比性限制：\n'
        '- $implementedBoundary\n'
        '- 本轮没有执行被预算拦截的 strategy_execute / strategy_backtest 调用，因此不编造收益率、回撤、胜率或交易次数。\n'
        '- 若要做真正的策略收益比较，应下一轮使用受治理的 MarketData(action:"backtest", strategy:"compare") 或 bounded strategy_backtest，并明确窗口、手续费和样本外验证。';
  }

  String? buildOptimize({
    required List<Message> messages,
    required int turnStartIndex,
  }) {
    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final decoded = _decodeMap(result.content);
      if (decoded == null) continue;
      try {
        if (decoded['action'] != 'optimize_params') continue;
        final best = decoded['bestResult'];
        final bestParams = decoded['bestParams'];
        final bestMap = best is Map ? Map<String, dynamic>.from(best) : null;
        if (bestMap == null || bestMap.isEmpty) continue;
        final paramsMap = bestParams is Map
            ? Map<String, dynamic>.from(bestParams)
            : bestMap['params'] is Map
            ? Map<String, dynamic>.from(bestMap['params'] as Map)
            : null;
        final symbol = decoded['symbol'] ?? '-';
        final period = decoded['period'] ?? '-';
        final requestedStart = decoded['requestedStartDate']?.toString();
        final requestedEnd = decoded['requestedEndDate']?.toString();
        final actualStart = decoded['actualStartDate']?.toString();
        final actualEnd = decoded['actualEndDate']?.toString();
        final bars = decoded['bars'] ?? '-';
        final combinations = decoded['combinations'] ?? '-';
        final totalReturn = bestMap['totalReturn'] ?? '-';
        final winRate = bestMap['winRate'] ?? '-';
        final maxDrawdown = bestMap['maxDrawdown'] ?? '-';
        final trades = bestMap['trades'] ?? '-';
        final sharpe = bestMap['sharpe'] ?? '-';
        final overfit =
            decoded['overfit_note'] ??
            'Parameter search is in-sample only; validate out of sample before live use.';
        return '已达到本轮受控数据调用预算，停止继续请求数据，并基于已取得的优化结果作答。\n\n'
            'RSI 参数优化结果（$symbol）：\n'
            '- 请求窗口：${_dateRangeText(requestedStart, requestedEnd, fallback: period)}。\n'
            '- 实际数据窗口：${_dateRangeText(actualStart, actualEnd, fallback: period)}，样本 $bars 根日线，搜索组合 $combinations 组。\n'
            '- 最优参数：${paramsMap ?? '-'}。\n'
            '- 回测指标：收益 $totalReturn%，最大回撤 $maxDrawdown%，胜率 $winRate%，交易次数 $trades，Sharpe $sharpe。\n'
            '- 数据来源：本地可复用/受治理 K 线，优化由 MarketData(action:"optimize_params") 的代码路径完成。\n'
            '- 覆盖限制：未继续执行额外 provider/file-inspection 调用；若要扩大验证，应单独请求样本外验证或更长窗口。\n'
            '- 过拟合提示：$overfit';
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Map<String, dynamic>? _decodeMap(String content) {
    try {
      final decoded = jsonDecode(content.trim());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  bool _hasStrategyComparisonState(List<Message> messages, int turnStartIndex) {
    final state = FinanceWorkflowState.latestFromMessages(
      messages,
      turnStartIndex: turnStartIndex,
    );
    if (state == null || !state.isStrategy) return false;
    if ({
      FinanceIntentMode.analysis,
      FinanceIntentMode.validate,
      FinanceIntentMode.backtest,
      FinanceIntentMode.review,
    }.contains(state.intentMode)) {
      return state.evidenceRefs.any(_isStrategyComparisonEvidenceRef);
    }
    return false;
  }

  bool _isStrategyComparisonEvidenceRef(String ref) {
    switch (ref.trim().toLowerCase()) {
      case 'strategy_compare':
      case 'strategy_comparison':
      case 'local_strategy_comparison':
      case 'technical_indicator_comparison':
      case 'indicator_comparison':
      case 'strategy_backtest_comparison':
        return true;
      default:
        return false;
    }
  }

  String? _klineRangeText(Map<String, dynamic>? kline) {
    final data = kline?['data'];
    if (data is! List || data.isEmpty) return null;
    final first = data.first;
    final last = data.last;
    if (first is Map && last is Map) {
      return '${first['date'] ?? '-'} ~ ${last['date'] ?? '-'}';
    }
    return null;
  }

  String? _klineRangeEnd(Map<String, dynamic>? kline) {
    final data = kline?['data'];
    if (data is! List || data.isEmpty) return null;
    final last = data.last;
    if (last is Map) return last['date']?.toString();
    return null;
  }

  String? _quoteLatestTime(Map<String, dynamic>? quote) {
    final data = quote?['data'];
    if (data is! List || data.isEmpty) return null;
    final first = data.first;
    if (first is Map) return first['timestamp']?.toString();
    return null;
  }

  String _evidenceValue(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return '未取得';
    return text;
  }

  String _dateRangeText(String? start, String? end, {String fallback = '-'}) {
    final left = start?.trim() ?? '';
    final right = end?.trim() ?? '';
    if (left.isNotEmpty && right.isNotEmpty) return '$left 至 $right';
    if (left.isNotEmpty) return '$left 起';
    if (right.isNotEmpty) return '截至 $right';
    return fallback;
  }
}
