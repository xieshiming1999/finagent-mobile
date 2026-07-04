import 'dart:convert';

import '../../../agent/message.dart';
import '../../../agent/tool.dart';
import 'finance_workflow_state.dart';

typedef FinanceRecoveryToolCall =
    Future<ToolResult> Function(
      Tool tool,
      String toolUseId,
      Map<String, dynamic> input,
    );

/// Finance-owned recovery for bounded strategy-monitor turns.
///
/// The generic agent loop owns the budget decision and tool-result
/// persistence. This helper owns finance workflow-state checks, evidence
/// interpretation, recovery tool inputs, and final finance wording.
class FinanceStrategyMonitorRecovery {
  Future<String?> build({
    required String? prompt,
    required List<Message> messages,
    required Tool? Function(String name) toolByName,
    required FinanceRecoveryToolCall callTool,
  }) async {
    final latestUserIndex = messages.lastIndexWhere(
      (message) => message.role == Role.user,
    );
    if (latestUserIndex < 0) return null;
    final workflowState = FinanceWorkflowState.latestFromMessages(
      messages,
      turnStartIndex: latestUserIndex,
    );
    if (!_isStrategyMonitorState(workflowState)) return null;
    final turnMessages = _messagesSinceLatestUser(messages);
    final evidence = _latestRsiMonitorEvidence(turnMessages);
    if (evidence == null) return null;

    final createTool = toolByName('MonitorCreate');
    final listTool = toolByName('MonitorList');
    if (createTool == null || listTool == null) return null;
    final watchlistTool = toolByName('Watchlist');

    final symbol =
        _normalizeSymbol(workflowState?.subject) ??
        _normalizeSymbol(evidence['symbol']);
    if (symbol == null) return null;
    final price = evidence['price'] as num?;
    final rsi = evidence['rsi'] as num?;
    final sourceDataTime = evidence['sourceDataTime'] as String? ?? '-';
    final fetchedAt = evidence['fetchedAt'] as String? ?? '-';
    final upper = evidence['upper'] as num?;
    final lower = evidence['lower'] as num?;
    if (price == null || upper == null || lower == null) return null;

    final name = _nameFromEvidence(evidence) ?? symbol;
    final wantsWatchlist = _stateRequestsWatchlist(workflowState);
    ToolResult? watchAddResult;
    ToolResult? watchListResult;
    if (wantsWatchlist && watchlistTool != null) {
      final watchInput = <String, dynamic>{
        'action': 'add',
        'symbol': symbol,
        'name': name,
        'type': 'stock',
        'entryCondition':
            '上破 ${_round2(upper)} 作为趋势修复/确认提醒；跌破 ${_round2(lower)} 作为失效观察提醒。',
        'targetEntryPrice': _roundNum(upper),
        'stopLoss': _roundNum(lower),
        'targetPrice': _roundNum(upper * 1.10),
        'suggestedWeight': 0.08,
        'source':
            'MarketData/DataProcess 已验证证据；数据时间 $sourceDataTime，获取时间 $fetchedAt',
      };
      watchAddResult = await callTool(
        watchlistTool,
        'auto_watchlist_add_${DateTime.now().millisecondsSinceEpoch}',
        watchInput,
      );
      watchListResult = await callTool(
        watchlistTool,
        'auto_watchlist_list_${DateTime.now().millisecondsSinceEpoch}',
        {'action': 'list', 'type': 'stock', 'status': 'watching'},
      );
    }

    final createInput = <String, dynamic>{
      'name': '$symbol RSI 趋势观察',
      'template': 'price_alert',
      'params': {
        'ts_code': '$symbol.SH',
        'name': name,
        'upper': _round2(upper),
        'lower': _round2(lower),
        'market': 'CN',
      },
      'interval': '5m',
      'display': 'value_card',
      'user_prompt': prompt ?? '',
      'description':
          '安全观察监控：当前价 ${_round2(price)}，RSI ${rsi == null ? '-' : _round2(rsi)}；'
          '上破 ${_round2(upper)} 视为趋势修复/确认，下破 ${_round2(lower)} 视为失效观察。'
          '数据时间 $sourceDataTime，获取时间 $fetchedAt。该监控只提醒，不自动交易。',
    };

    final createResult = await callTool(
      createTool,
      'auto_monitor_create_${DateTime.now().millisecondsSinceEpoch}',
      createInput,
    );
    if (createResult.isError) return null;
    final listResult = await callTool(
      listTool,
      'auto_monitor_list_${DateTime.now().millisecondsSinceEpoch}',
      const {},
    );

    return '已基于本轮已取得的治理行情、RSI/技术指标和回测证据创建安全监控。\n\n'
        '- 标的：$name（$symbol）。\n'
        '- 当前证据：价格 ${_round2(price)}，RSI ${rsi == null ? '-' : _round2(rsi)}，数据时间 $sourceDataTime，获取时间 $fetchedAt。\n'
        '- 仓位建议：本轮只做观察准备，不下单；若后续用户确认交易，单票试探仓建议不超过总资产 5%-10%，并以单笔最大亏损约 5% 反推股数。\n'
        '${watchAddResult == null ? '' : '- 观察池写入：${watchAddResult.content.split('\n').first}\n'}'
        '${watchListResult == null ? '' : '- 观察池读回：${watchListResult.isError ? watchListResult.content : 'Watchlist(list) 已返回 watching 股票列表。'}\n'}'
        '- 监控条件：上破 ${_round2(upper)} 作为趋势修复/确认提醒；下破 ${_round2(lower)} 作为失效观察提醒。\n'
        '- 周期：5 分钟。\n'
        '- 性质：这是观察/提醒监控，不会自动买卖、不会调用券商、雪球买卖、转账或模拟盘交易。\n'
        '- 创建结果：${createResult.content.split('\n').first}\n'
        '- 读取确认：${listResult.isError ? listResult.content : 'MonitorList 已返回当前监控列表。'}\n'
        '- 本轮工具/Provider 失败：${_failureSummary(turnMessages)}';
  }

  List<Message> _messagesSinceLatestUser(List<Message> messages) {
    final start = messages.lastIndexWhere(
      (message) => message.role == Role.user,
    );
    if (start < 0) return messages;
    return messages.skip(start + 1).toList(growable: false);
  }

  bool _isStrategyMonitorState(FinanceWorkflowState? state) {
    if (state == null) return false;
    if (state.workflowKind != FinanceWorkflowKind.monitorReview) return false;
    if (state.assetClass == FinanceAssetClass.fund) return false;
    if (state.executionMode == FinanceExecutionMode.blocked) return false;
    return state.intentMode == FinanceIntentMode.observe ||
        state.intentMode == FinanceIntentMode.review;
  }

  bool _stateRequestsWatchlist(FinanceWorkflowState? state) {
    return state?.evidenceRefs.any((ref) {
          final normalized = ref.trim().toLowerCase();
          return normalized == 'watchlist' || normalized == 'watchlist.add';
        }) ==
        true;
  }

  Map<String, dynamic>? _latestRsiMonitorEvidence(List<Message> messages) {
    Map<String, dynamic>? quoteFallback;
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final content = result.content.trim();
      if (!content.startsWith('{')) continue;
      try {
        final decoded = jsonDecode(content);
        if (decoded is! Map<String, dynamic>) continue;
        if (!decoded.containsKey('rsi')) {
          quoteFallback ??= _quoteMonitorEvidenceFromPayload(decoded);
          continue;
        }
        final price = _asNum(decoded['price']);
        final rsi = _asNum(decoded['rsi']);
        if (price == null || rsi == null) continue;
        final ma10 = _asNum(decoded['ma10']);
        final ma20 = _asNum(decoded['ma20']);
        final atr = _asNum(decoded['atr']);
        final upper = _confirmationLevel(price, [
          _asNum(decoded['boll_upper']),
          ma10,
          ma20,
        ]);
        final lower = _invalidationLevel(
          price,
          atr: atr,
          levels: [ma10, ma20, _asNum(decoded['boll_lower'])],
        );
        return {
          if (decoded['symbol'] != null)
            'symbol': decoded['symbol']?.toString(),
          if (decoded['name'] != null) 'name': decoded['name']?.toString(),
          'price': price,
          'rsi': rsi,
          'upper': upper,
          'lower': lower,
          'sourceDataTime':
              decoded['sourceDataTime']?.toString() ??
              decoded['date']?.toString(),
          'fetchedAt': decoded['fetchedAt']?.toString(),
        };
      } catch (_) {
        continue;
      }
    }
    return quoteFallback;
  }

  Map<String, dynamic>? _quoteMonitorEvidenceFromPayload(
    Map<String, dynamic> decoded,
  ) {
    if (decoded['action'] != 'query_quote') return null;
    final rows = decoded['data'];
    if (rows is! List || rows.isEmpty) return null;
    Map<String, dynamic>? best;
    num? bestChange;
    for (final row in rows) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final price = _asNum(map['price'] ?? map['close'] ?? map['current']);
      if (price == null || price <= 0) continue;
      final change =
          _asNum(map['change_pct'] ?? map['pct_chg'] ?? map['changePercent']) ??
          0;
      if (best == null || change > (bestChange ?? -999999)) {
        best = map;
        bestChange = change;
      }
    }
    if (best == null) return null;
    final symbol = best['code']?.toString() ?? best['symbol']?.toString();
    final price = _asNum(best['price'] ?? best['close'] ?? best['current']);
    if (symbol == null || price == null) return null;
    return {
      'symbol': symbol,
      if (best['name'] != null) 'name': best['name']?.toString(),
      'price': price,
      'rsi': null,
      'upper': price * 1.03,
      'lower': price * 0.97,
      'sourceDataTime':
          best['timestamp']?.toString() ??
          best['sourceDataTime']?.toString() ??
          decoded['sourceDataTime']?.toString(),
      'fetchedAt':
          best['fetchedAt']?.toString() ??
          best['fetched_at']?.toString() ??
          decoded['fetchedAt']?.toString(),
    };
  }

  String? _nameFromEvidence(Map<String, dynamic> evidence) {
    final name = evidence['name']?.toString().trim();
    return name == null || name.isEmpty ? null : name;
  }

  String? _normalizeSymbol(Object? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(r'\d{6}').firstMatch(raw);
    return match?.group(0) ?? raw;
  }

  num? _asNum(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  num _roundNum(num value) => double.parse(value.toStringAsFixed(2));

  String _round2(num value) => value.toStringAsFixed(2);

  num _confirmationLevel(num price, List<num?> levels) {
    final above =
        levels.whereType<num>().where((value) => value > price).toList()
          ..sort();
    return above.isNotEmpty ? above.first : price * 1.03;
  }

  num _invalidationLevel(num price, {num? atr, required List<num?> levels}) {
    if (atr != null && atr > 0 && price - atr < price) return price - atr;
    final below =
        levels
            .whereType<num>()
            .where((value) => value > 0 && value < price)
            .toList()
          ..sort((a, b) => b.compareTo(a));
    return below.isNotEmpty ? below.first : price * 0.97;
  }

  String _failureSummary(List<Message> messages) {
    final failures = <String>[];
    for (final message in messages) {
      final result = message.toolResult;
      if (result == null || !result.isError) continue;
      failures.add(result.content.replaceAll(RegExp(r'\s+'), ' ').trim());
    }
    if (failures.isEmpty) return '无阻断性工具错误。';
    return failures.take(3).join('；');
  }
}
