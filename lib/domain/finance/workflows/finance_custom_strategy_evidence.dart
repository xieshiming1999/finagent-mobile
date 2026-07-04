import 'dart:convert';

import '../../../agent/message.dart';
import 'finance_workflow_state.dart';

/// Finance-owned custom StrategySpec evidence summaries.
///
/// These methods summarize already-returned custom strategy tool results. They
/// deliberately do not execute tools or decide permissions.
class FinanceCustomStrategyEvidence {
  String? validation(List<Message> messages, int turnStartIndex) {
    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final decoded = _decodeResultMap(result.content);
      if (decoded == null) continue;
      try {
        if (decoded['action'] != 'custom_strategy_validate') continue;
        if (decoded['status'] != 'validated') continue;
        final spec = decoded['normalizedSpec'];
        final report = decoded['validationReport'];
        final accepted = report is Map ? report['acceptedRules'] : null;
        final warnings = report is Map ? report['warnings'] : null;
        final assumptions = report is Map ? report['assumptions'] : null;
        final unsupported = report is Map ? report['unsupported'] : null;
        final id = spec is Map ? spec['id']?.toString() : null;
        final name = spec is Map ? spec['name']?.toString() : null;
        final symbol = _customStrategySymbol(spec);
        return [
          '策略结构已验证通过，本轮按用户要求停在验证步骤，未执行回测、保存、脚本或额外行情查询。',
          '',
          '- 策略：${name?.isNotEmpty == true ? name : id ?? '自定义策略'}。',
          if (id != null && id.isNotEmpty) '- strategyId：$id。',
          if (symbol != null && symbol.isNotEmpty) '- 标的：$symbol。',
          '- 已接受规则：${_compactJsonList(accepted)}。',
          '- 假设条件：${_compactJsonList(assumptions)}。',
          '- 警告：${_compactJsonList(warnings)}。',
          '- 不支持的可执行部分：${_compactJsonList(unsupported, empty: '无')}。',
          '',
          '下一步如果需要回测，请单独要求“用这个策略回测”；如果需要保存，请先完成回测证据后再保存。',
        ].join('\n');
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String? backtest(List<Message> messages, int turnStartIndex) {
    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final decoded = _decodeResultMap(result.content);
      if (decoded == null) continue;
      try {
        if (decoded['action'] != 'custom_strategy_backtest') continue;
        if (decoded['status'] != 'backtested') continue;
        final validation = decoded['validation'];
        final validationMap = validation is Map ? validation : const {};
        final spec = validationMap['spec'];
        final metrics = decoded['metrics'];
        final metricsMap = metrics is Map ? metrics : const {};
        final assumptions = decoded['assumptions'];
        final assumptionMap = assumptions is Map ? assumptions : const {};
        final dataCoverage = _strategyDataCoverageSummary(decoded);
        return [
          '已完成自定义策略回测，并停止追加新的策略变体、交易动作、监控或自选股写入。本回答以 `custom_strategy_backtest` 的结构化结果为准。',
          '',
          '- 标的：${decoded['symbol'] ?? _customStrategySymbol(spec) ?? '-'}。',
          '- 策略ID：${decoded['strategyId'] ?? validationMap['strategyId'] ?? '-'}。',
          '- 数据覆盖：$dataCoverage。',
          '- 交易次数：${metricsMap['tradeCount'] ?? metricsMap['trades'] ?? decoded['trades'] ?? 0}。',
          '- 总收益率：${metricsMap['totalReturnPct'] ?? metricsMap['totalReturn'] ?? decoded['totalReturn'] ?? '-'}%。',
          '- 最大回撤：${metricsMap['maxDrawdownPct'] ?? metricsMap['maxDrawdown'] ?? decoded['maxDrawdown'] ?? '-'}%。',
          '- 胜率：${metricsMap['winRatePct'] ?? metricsMap['winRate'] ?? decoded['winRate'] ?? '-'}%。',
          '- 佣金/滑点：${assumptionMap['commissionPct'] ?? '-'}% / ${assumptionMap['slippagePct'] ?? '-'}%。',
          '- 仓位规则：${assumptionMap['positionSizing'] ?? '-'}。',
          '- 退出规则：${_customStrategyExitSummary(spec)}。',
          '',
          '结果边界：未保存策略；未调用 `custom_strategy_save`；未执行交易、监控创建或自选股写入。若交易次数为 0，说明该窗口内未触发完整买入条件，不能据此推断参数放宽后的表现。',
        ].join('\n');
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String? comparison({
    required List<Message> messages,
    required int turnStartIndex,
  }) {
    final workflowState = _workflowStateForTurn(messages, turnStartIndex);
    if (!_isStrategyBacktestWorkflow(workflowState)) return null;

    final calls = _toolCalls(messages.skip(turnStartIndex));
    final results = _toolResults(messages.skip(turnStartIndex));
    final rows = <Map<String, dynamic>>[];
    for (final call in calls) {
      if (call.name != 'MarketData' ||
          call.input['action'] != 'custom_strategy_backtest') {
        continue;
      }
      final result = results[call.id];
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded['action'] != 'custom_strategy_backtest' ||
            decoded['status'] != 'backtested') {
          continue;
        }
        final validation = decoded['validation'];
        final validationMap = validation is Map ? validation : const {};
        final spec = validationMap['spec'];
        final metrics = decoded['metrics'];
        final metricsMap = metrics is Map ? metrics : const {};
        final assumptions = decoded['assumptions'];
        final assumptionsMap = assumptions is Map ? assumptions : const {};
        rows.add({
          'symbol':
              decoded['symbol'] ??
              call.input['code'] ??
              _customStrategySymbol(spec) ??
              '-',
          'strategyId':
              decoded['strategyId'] ?? validationMap['strategyId'] ?? '-',
          'bars': decoded['bars'] ?? '-',
          'start': decoded['actualStartDate'] ?? '-',
          'end': decoded['actualEndDate'] ?? '-',
          'trades':
              metricsMap['tradeCount'] ??
              metricsMap['trades'] ??
              decoded['trades'] ??
              0,
          'totalReturn':
              metricsMap['totalReturnPct'] ??
              metricsMap['totalReturn'] ??
              decoded['totalReturn'] ??
              0,
          'maxDrawdown':
              metricsMap['maxDrawdownPct'] ??
              metricsMap['maxDrawdown'] ??
              decoded['maxDrawdown'] ??
              0,
          'winRate':
              metricsMap['winRatePct'] ??
              metricsMap['winRate'] ??
              decoded['winRate'] ??
              0,
          'commission': assumptionsMap['commissionPct'] ?? '-',
          'slippage': assumptionsMap['slippagePct'] ?? '-',
          'dataCoverage': _strategyDataCoverageSummary(decoded),
        });
      } catch (_) {
        continue;
      }
    }

    final latestBySymbol = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      latestBySymbol[_normalizeSymbolKey('${row['symbol']}')] = row;
    }
    final comparableRows = latestBySymbol.values.toList();
    if (comparableRows.length < 2) return null;

    comparableRows.sort((left, right) {
      final trades = _numValue(
        right['trades'],
      ).compareTo(_numValue(left['trades']));
      if (trades != 0) return trades;
      final returns = _numValue(
        right['totalReturn'],
      ).compareTo(_numValue(left['totalReturn']));
      if (returns != 0) return returns;
      return _numValue(
        left['maxDrawdown'],
      ).compareTo(_numValue(right['maxDrawdown']));
    });
    final selected = comparableRows.first;

    return [
      '## 多标的动量策略比较',
      '',
      '已停止继续设计新变体或追加行情工具调用。本回答只基于本轮已经完成的 `custom_strategy_backtest` 结果，对同一类 StrategySpec 动量规则做横向比较。',
      '',
      '| 标的 | strategyId | K线 | 区间 | 交易数 | 总收益 | 最大回撤 | 胜率 |',
      '|---|---|---:|---|---:|---:|---:|---:|',
      for (final row in comparableRows)
        '| ${row['symbol']} | ${row['strategyId']} | ${row['bars']} | ${row['start']} ~ ${row['end']} | ${row['trades']} | ${row['totalReturn']}% | ${row['maxDrawdown']}% | ${row['winRate']}% |',
      '',
      '结论：当前可比结果中，优先候选为 ${selected['symbol']}。选择依据是交易触发数、收益和回撤的受控排序；若三者交易数都为 0，则结论只能说明当前窗口没有形成完整动量入场信号，不能推断放宽条件后的表现。',
      '',
      '## 数据来源与回测假设',
      '',
      '- 数据覆盖：${selected['dataCoverage']}。',
      '- 成本假设：佣金 ${selected['commission']}%；滑点 ${selected['slippage']}%。',
      '- 策略边界：没有调用 DataProcess、Script、Read/Grep；没有下单、模拟盘交易、监控或自选股变更。',
      '- Unsupported 边界：如果某个变体返回验证失败，应按失败结果披露，不用新的代理规则冒充原策略。',
    ].join('\n');
  }

  String? saveRunBoundary({
    required List<Message> messages,
    required int turnStartIndex,
  }) {
    final workflowState = _workflowStateForTurn(messages, turnStartIndex);
    if (!_isStrategyRerunWorkflow(workflowState)) return null;
    final calls = _toolCalls(messages.skip(turnStartIndex));
    final results = _toolResults(messages.skip(turnStartIndex));
    Map<String, dynamic>? latestSave;
    String? latestRunError;
    for (final call in calls) {
      final result = results[call.id];
      if (result == null || call.name != 'MarketData') continue;
      if (call.input['action'] == 'custom_strategy_save' && !result.isError) {
        try {
          final decoded = jsonDecode(result.content);
          if (decoded is Map<String, dynamic> &&
              decoded['action'] == 'custom_strategy_save') {
            latestSave = decoded;
          }
        } catch (_) {
          continue;
        }
      }
      if (call.input['action'] == 'custom_strategy_run' && result.isError) {
        latestRunError = result.content;
      }
    }
    final saveStatus = latestSave?['status']?.toString();
    final isNotRunnable = saveStatus == 'validated';
    if (latestSave == null || !isNotRunnable) return null;
    final spec = latestSave['spec'];
    final evidence = latestSave['evidence'];
    final evidenceMap = evidence is Map ? evidence : const {};
    return [
      '## 策略保存与重跑边界',
      '',
      '本轮没有得到可重跑的 backtested 策略。系统已停止继续追加 provider、脚本、文件或交易工具调用。',
      '',
      '- strategyId：${latestSave['strategyId'] ?? _strategyIdFromSpec(spec) ?? '-'}。',
      '- 保存状态：${saveStatus ?? '-'}。',
      '- 策略名称：${_strategyNameFromSpec(spec) ?? '-'}。',
      '- 回测证据：${evidenceMap.isEmpty ? '未随保存结果返回 backtested evidence' : '${evidenceMap['status'] ?? '-'}；${evidenceMap['actualStartDate'] ?? '-'} ~ ${evidenceMap['actualEndDate'] ?? '-'}'}。',
      if (latestRunError != null) '- 重跑结果：$latestRunError。',
      '',
      '结论：该记录可以作为研究/观察草案保存，但不能声明“按 strategyId 重跑一致”。只有 `custom_strategy_backtest` 成功并以 backtested evidence 保存后，`custom_strategy_run` 才能作为可复用策略执行路径。',
      '',
      '后续方向：如果这是基金定投观察策略，应进入基金观察/监控合同；如果需要可执行回测，应先补齐基金 NAV/yield 回测引擎或改用当前 StrategySpec v1 支持的数据与指标。',
    ].join('\n');
  }

  String? rejectedValidation(List<Message> messages, int turnStartIndex) {
    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final decoded = _decodeResultMap(result.content);
      if (decoded == null) continue;
      try {
        if (decoded['action'] != 'custom_strategy_validate' ||
            decoded['status'] != 'rejected') {
          continue;
        }
        final errors = decoded['errors'] is List
            ? (decoded['errors'] as List).map((item) => '$item').toList()
            : const <String>[];
        final warnings = decoded['warnings'] is List
            ? (decoded['warnings'] as List).map((item) => '$item').toList()
            : const <String>[];
        return [
          '该策略未进入可执行回测，并已停止追加代理策略、脚本、文件或额外行情工具调用。本回答只基于 `custom_strategy_validate` 的拒绝结果。',
          '',
          '- 策略ID：${decoded['strategyId'] ?? '-'}。',
          '- 验证状态：rejected。',
          '- 不可执行部分：${errors.isEmpty ? '未返回详细错误' : errors.join('；')}。',
          if (warnings.isNotEmpty) '- 警告：${warnings.join('；')}。',
          '- 结果边界：未调用 `custom_strategy_backtest`，未调用 `custom_strategy_save`，未创建代理规则替代被拒绝的 StrategySpec。',
          '',
          '如果要继续，应先把这些条件改写成当前 StrategySpec v1 支持的指标；代理版策略必须作为新的用户请求重新设计，不能冒充原策略回测。',
        ].join('\n');
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  List<ToolUse> _toolCalls(Iterable<Message> messages) => messages
      .where((message) => message.role == Role.assistant)
      .expand((message) => message.toolUses ?? const <ToolUse>[])
      .toList();

  Map<String, ToolResult> _toolResults(Iterable<Message> messages) {
    final results = <String, ToolResult>{};
    for (final message in messages) {
      final result = message.toolResult;
      if (message.role == Role.tool && result != null) {
        results[result.toolUseId] = result;
      }
    }
    return results;
  }

  String _normalizeSymbolKey(String symbol) => symbol
      .trim()
      .toUpperCase()
      .replaceFirst(RegExp(r'\.(SH|SZ)$'), '')
      .replaceFirst(RegExp(r'^(SH|SZ)'), '');

  FinanceWorkflowState? _workflowStateForTurn(
    List<Message> messages,
    int turnStartIndex,
  ) {
    final userIndex = messages
        .take(turnStartIndex)
        .toList()
        .lastIndexWhere((message) => message.role == Role.user);
    if (userIndex >= 0) {
      final state = FinanceWorkflowState.fromUserContent(
        messages[userIndex].content,
      );
      if (state != null) return state;
    }
    return null;
  }

  bool _isStrategyBacktestWorkflow(FinanceWorkflowState? state) {
    return state?.isStrategy == true &&
        state?.intentMode == FinanceIntentMode.backtest;
  }

  bool _isStrategyRerunWorkflow(FinanceWorkflowState? state) {
    return state?.isStrategy == true &&
        state?.intentMode == FinanceIntentMode.rerun;
  }

  double _numValue(Object? value) {
    if (value is num) return value.toDouble();
    final parsed = double.tryParse('$value'.replaceAll('%', ''));
    return parsed ?? 0;
  }

  String _strategyDataCoverageSummary(Map<dynamic, dynamic> payload) {
    final coverage = payload['dataCoverage'];
    final coverageMap = coverage is Map ? coverage : const {};
    final rows = coverageMap['rows'] ?? payload['bars'] ?? '-';
    final requiredBars = coverageMap['requiredBars'];
    final sufficient = coverageMap['sufficient'];
    final start =
        coverageMap['actualStartDate'] ?? payload['actualStartDate'] ?? '-';
    final end = coverageMap['actualEndDate'] ?? payload['actualEndDate'] ?? '-';
    final source = coverageMap['source'];
    final cacheStatus = coverageMap['cacheStatus'];
    final parts = [
      '$start ~ $end',
      'K线 $rows 根',
      if (requiredBars != null) '要求 $requiredBars 根',
      if (sufficient != null) '覆盖${sufficient == true ? '满足' : '不足'}',
      if (source != null) 'source=$source',
      if (cacheStatus != null) 'cache=$cacheStatus',
    ];
    return parts.join('；');
  }

  String? save(List<Message> messages, int turnStartIndex) {
    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final decoded = _decodeResultMap(result.content);
      if (decoded == null) continue;
      try {
        if (decoded['action'] != 'custom_strategy_save') continue;
        final spec = decoded['strategySpecSummary'] ?? decoded['spec'];
        final evidence =
            decoded['backtestEvidenceSummary'] ?? decoded['evidence'];
        final evidenceMap = evidence is Map ? evidence : const {};
        final validation = decoded['validation'];
        final validationMap = validation is Map ? validation : const {};
        final version = decoded['version'] ?? validationMap['version'] ?? '-';
        return [
          '自定义策略已保存，并停止追加技术指标、脚本、文件或额外行情工具调用。本回答只基于 `custom_strategy_save` 的代码执行结果。',
          '',
          '- 策略ID：${decoded['strategyId'] ?? validationMap['strategyId'] ?? _strategyIdFromSpec(spec) ?? '-'}。',
          '- 版本：$version。',
          '- 保存状态：${decoded['status'] ?? '-'}。',
          '- 策略名称：${_strategyNameFromSpec(spec) ?? '-'}。',
          '- 回测证据：${evidenceMap.isEmpty ? '未随保存结果返回回测证据' : '${_strategyDataCoverageSummary(evidenceMap)}，状态 ${evidenceMap['status'] ?? '-'}'}。',
          '- 数据边界：保存的是经过验证的 StrategySpec 和已有回测证据；未执行真实交易、模拟盘交易、监控创建或自选股变更。',
          '',
          '之后复用时应通过 `custom_strategy_run` 或 strategyId 读取已保存策略，不要把策略名当成内置 backtest strategy 字符串。',
        ].join('\n');
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Map<String, dynamic>? _decodeResultMap(String content) {
    try {
      final decoded = jsonDecode(content.trim());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _customStrategyExitSummary(Object? spec) {
    if (spec is! Map) return '未返回';
    final exit = spec['exit'];
    if (exit is Map && exit.containsKey('any')) {
      return '任一触发（OR）：${_compactJsonList(exit['any'])}';
    }
    if (exit is Map && exit.containsKey('all')) {
      return '全部满足（AND）：${_compactJsonList(exit['all'])}';
    }
    return exit?.toString() ?? '未返回';
  }

  String? _customStrategySymbol(Object? spec) {
    if (spec is! Map) return null;
    final symbol = spec['symbol']?.toString();
    if (symbol != null && symbol.isNotEmpty) return symbol;
    final symbols = spec['symbols'];
    if (symbols is List && symbols.isNotEmpty) return symbols.first.toString();
    final universe = spec['universe'];
    if (universe is Map) {
      final universeSymbols = universe['symbols'];
      if (universeSymbols is List && universeSymbols.isNotEmpty) {
        return universeSymbols.first.toString();
      }
    }
    return null;
  }

  String? _strategyIdFromSpec(Object? spec) {
    if (spec is! Map) return null;
    final id = spec['id']?.toString();
    return id != null && id.isNotEmpty ? id : null;
  }

  String? _strategyNameFromSpec(Object? spec) {
    if (spec is! Map) return null;
    final name = spec['name']?.toString();
    return name != null && name.isNotEmpty ? name : null;
  }

  String _compactJsonList(Object? value, {String empty = '未返回'}) {
    if (value == null) return empty;
    if (value is List) {
      if (value.isEmpty) return empty;
      return value.map((item) => item.toString()).join('；');
    }
    final text = value.toString().trim();
    return text.isEmpty ? empty : text;
  }
}
