import 'dart:convert';

import '../../../agent/ask_user_question_contract.dart';
import '../../../agent/message.dart';
import 'finance_workflow_state.dart';

class FinanceCustomStrategyPreflight {
  List<ToolUse>? buildToolCalls(List<Message> messages) {
    final start = messages.lastIndexWhere(
      (message) => message.role == Role.user,
    );
    if (start < 0) return null;
    final userContent = messages[start].content;
    final workflowState = FinanceWorkflowState.latestFromMessages(
      messages,
      turnStartIndex: start,
    );
    final userWorkflowState = FinanceWorkflowState.fromUserContent(userContent);
    final commandState = _isCustomStrategyWorkflow(userWorkflowState)
        ? userWorkflowState
        : workflowState;
    if (!_isCustomStrategyWorkflow(workflowState)) return null;

    final turnMessages = messages.skip(start + 1).toList();
    final toolCalls = _collectToolCalls(turnMessages);
    final results = _successfulToolResults(turnMessages);
    final structuredSpec = _structuredStrategySpec(userContent);
    final comparisonSymbols = _comparisonSymbolsFromSpec(structuredSpec);
    if (_isCustomStrategySaveAndRunWorkflow(commandState)) {
      final activeRun = _latestSuccessfulRun(turnMessages);
      if (activeRun != null) {
        final missingSubject = _missingRunSubject(
          commandState,
          turnMessages,
          activeRun.strategyId,
        );
        if (missingSubject != null) {
          return [
            ToolUse(
              id: 'custom_strategy_run_${DateTime.now().microsecondsSinceEpoch}',
              name: 'MarketData',
              input: {
                'action': 'custom_strategy_run',
                'strategyId': activeRun.strategyId,
                'symbols': [missingSubject],
              },
            ),
          ];
        }
      }
      final listedStrategyId = _latestRunnableStrategyIdFromList(
        turnMessages,
        commandState?.subjects ?? const <String>[],
      );
      if (listedStrategyId != null &&
          commandState?.subjects.isNotEmpty == true) {
        final calls = _missingSubjectRunCalls(
          turnMessages,
          strategyId: listedStrategyId,
          subjects: commandState!.subjects,
        );
        if (calls.isNotEmpty) return calls;
      }
      final selectedStrategyId = _selectedStrategyIdFromQuestionAnswer(
        turnMessages,
      );
      if (selectedStrategyId != null &&
          commandState?.subjects.isNotEmpty == true) {
        final calls = _missingSubjectRunCalls(
          turnMessages,
          strategyId: selectedStrategyId,
          subjects: commandState!.subjects,
        );
        if (calls.isNotEmpty) return calls;
      }
      final wrongIdentitySymbol = _latestWrongIdentityRunSymbol(
        toolCalls,
        activeRun?.strategyId,
      );
      if (activeRun != null &&
          wrongIdentitySymbol != null &&
          wrongIdentitySymbol != activeRun.symbol &&
          !_hasSuccessfulRunForSymbol(
            turnMessages,
            strategyId: activeRun.strategyId,
            symbol: wrongIdentitySymbol,
          )) {
        return [
          ToolUse(
            id: 'custom_strategy_run_${DateTime.now().microsecondsSinceEpoch}',
            name: 'MarketData',
            input: {
              'action': 'custom_strategy_run',
              'strategyId': activeRun.strategyId,
              'symbols': [wrongIdentitySymbol],
            },
          ),
        ];
      }
      final requestedStrategyId = _requestedStrategyIdFromState(commandState);
      final saved = requestedStrategyId == null
          ? _latestSavedStrategy(turnMessages)
          : _SavedStrategy(
              strategyId: requestedStrategyId,
              symbol:
                  _symbolFromStateOrSpec(commandState, structuredSpec) ?? '',
            );
      final hasRun = _hasSuccessfulRun(
        toolCalls,
        results,
        strategyId: requestedStrategyId,
      );
      if (saved != null && !hasRun) {
        return [
          ToolUse(
            id: 'custom_strategy_run_${DateTime.now().microsecondsSinceEpoch}',
            name: 'MarketData',
            input: {
              'action': 'custom_strategy_run',
              'strategyId': saved.strategyId,
              if (saved.symbol.isNotEmpty) 'symbols': [saved.symbol],
            },
          ),
        ];
      }
      if (saved == null) {
        final latestBacktest = _latestBacktestedStrategy(
          messages.take(start).toList(),
        );
        if (latestBacktest != null) {
          return [
            ToolUse(
              id: 'custom_strategy_save_${DateTime.now().microsecondsSinceEpoch}',
              name: 'MarketData',
              input: {
                'action': 'custom_strategy_save',
                'strategySpec': latestBacktest.strategySpec,
                'evidence': latestBacktest.evidence,
              },
            ),
          ];
        }
        if (commandState?.intentMode == FinanceIntentMode.rerun &&
            !_hasSuccessfulStrategyList(toolCalls, results)) {
          return [
            ToolUse(
              id: 'custom_strategy_list_${DateTime.now().microsecondsSinceEpoch}',
              name: 'MarketData',
              input: {'action': 'custom_strategy_list'},
            ),
          ];
        }
      }
    }
    final hasValidate = toolCalls.any(
      (call) =>
          call.name == 'MarketData' &&
          call.input['action'] == 'custom_strategy_validate' &&
          results.contains(call.id),
    );
    final hasBacktest = toolCalls.any(
      (call) =>
          call.name == 'MarketData' &&
          call.input['action'] == 'custom_strategy_backtest' &&
          results.contains(call.id),
    );
    final hasHelp = toolCalls.any(
      (call) =>
          call.name == 'MarketData' &&
          call.input['action'] == 'custom_strategy_help' &&
          results.contains(call.id),
    );
    if (comparisonSymbols.length >= 2) {
      final completedSymbols = _completedBacktestSymbols(turnMessages);
      final missingSymbols = comparisonSymbols
          .where((symbol) => !completedSymbols.contains(symbol))
          .toList(growable: false);
      if (missingSymbols.isEmpty) return null;
      if (hasHelp) {
        final calls = <ToolUse>[];
        for (final symbol in missingSymbols) {
          final strategySpec = _strategySpecForSymbol(structuredSpec, symbol);
          if (strategySpec == null) continue;
          calls.add(
            ToolUse(
              id: 'custom_strategy_backtest_${symbol}_${DateTime.now().microsecondsSinceEpoch}',
              name: 'MarketData',
              input: {
                'action': 'custom_strategy_backtest',
                'strategySpec': strategySpec,
                'symbols': [symbol],
              },
            ),
          );
        }
        return calls.isEmpty ? null : calls;
      }
    }
    if (hasBacktest) return null;
    if (hasValidate && _isCustomStrategyBacktestWorkflow(commandState)) {
      final validation = _latestValidatedStrategy(turnMessages);
      if (validation != null) {
        return [
          ToolUse(
            id: 'custom_strategy_backtest_${DateTime.now().microsecondsSinceEpoch}',
            name: 'MarketData',
            input: {
              'action': 'custom_strategy_backtest',
              'strategySpec': validation.strategySpec,
              'symbols': [validation.symbol],
            },
          ),
        ];
      }
      return null;
    }
    if (hasValidate && _hasValidatedFundStrategy(turnMessages)) {
      if (_hasOrdinaryAndMoneyFundEvidence(turnMessages)) return null;
      if (!_isCustomStrategyFundObservationWorkflow(commandState)) return null;
      if (_hasSuccessfulCustomStrategyObserve(turnMessages)) return null;
      final strategySpec = _latestValidatedFundStrategySpec(turnMessages);
      if (strategySpec == null) return null;
      final fundRows = _latestFundRows(turnMessages);
      if (fundRows.isNotEmpty) {
        return [
          ToolUse(
            id: 'custom_strategy_observe_${DateTime.now().microsecondsSinceEpoch}',
            name: 'MarketData',
            input: {
              'action': 'custom_strategy_observe',
              'strategySpec': strategySpec,
              'fundRows': fundRows,
            },
          ),
        ];
      }
      final fundCode = _latestFundCodeFromAskUserQuestion(turnMessages);
      if (fundCode != null &&
          !_hasSuccessfulFundRowsForCode(turnMessages, fundCode) &&
          !_hasPendingFundReadbackCall(toolCalls, fundCode)) {
        return [
          ToolUse(
            id: 'fund_strategy_nav_${DateTime.now().microsecondsSinceEpoch}',
            name: 'MarketData',
            input: {
              'action': 'query_fund_nav',
              'symbols': [fundCode],
              'limit': 120,
            },
          ),
        ];
      }
      if (!_hasAskUserQuestionCall(turnMessages)) {
        return [
          ToolUse(
            id: 'fund_strategy_target_${DateTime.now().microsecondsSinceEpoch}',
            name: 'AskUserQuestion',
            input: {
              'questions': [
                {
                  'question':
                      '基金观察策略已经通过验证。需要一个具体基金代码或名称才能读取净值并生成观察证据；请提供目标基金，或选择只保留策略验证结果。',
                  'header': '基金标的',
                  'options': [
                    {
                      'label': '提供基金代码',
                      'description':
                          '继续读取该基金的净值或收益数据，并生成 custom_strategy_observe 观察证据。',
                    },
                    {
                      'label': '只保留验证',
                      'description': '停止在 StrategySpec 验证结果，不读取基金数据。',
                    },
                  ],
                  'multiSelect': false,
                },
              ],
            },
          ),
        ];
      }
    }
    if (hasValidate) return null;
    if (toolCalls.any(_isCustomStrategyToolCall) &&
        !toolCalls.any(
          (call) =>
              call.name == 'MarketData' &&
              call.input['action'] == 'custom_strategy_help',
        )) {
      return null;
    }
    if (hasHelp && _isCustomStrategyBacktestWorkflow(commandState)) {
      final symbol =
          _symbolFromStateOrSpec(commandState, structuredSpec) ??
          _candidateSymbolFromEvidence(turnMessages);
      if (symbol == null) return null;
      final strategySpec = _strategySpecForSymbol(structuredSpec, symbol);
      if (strategySpec == null) return null;
      return [
        ToolUse(
          id: 'custom_strategy_validate_${DateTime.now().microsecondsSinceEpoch}',
          name: 'MarketData',
          input: {
            'action': 'custom_strategy_validate',
            'strategySpec': strategySpec,
          },
        ),
      ];
    }
    if (hasHelp && _isCustomStrategyValidateWorkflow(commandState)) {
      if (structuredSpec == null) return null;
      return [
        ToolUse(
          id: 'custom_strategy_validate_${DateTime.now().microsecondsSinceEpoch}',
          name: 'MarketData',
          input: {
            'action': 'custom_strategy_validate',
            'strategySpec': structuredSpec,
          },
        ),
      ];
    }
    if (hasHelp) return null;

    return [
      ToolUse(
        id: 'custom_strategy_preflight_${DateTime.now().microsecondsSinceEpoch}',
        name: 'MarketData',
        input: {'action': 'custom_strategy_help'},
      ),
    ];
  }

  bool _isCustomStrategyWorkflow(FinanceWorkflowState? state) {
    return state?.workflowKind == FinanceWorkflowKind.strategyDesign ||
        state?.workflowKind == FinanceWorkflowKind.strategyReview;
  }

  bool _isCustomStrategyBacktestWorkflow(FinanceWorkflowState? state) {
    return _isCustomStrategyWorkflow(state) &&
        state?.intentMode == FinanceIntentMode.backtest;
  }

  bool _isCustomStrategyValidateWorkflow(FinanceWorkflowState? state) {
    return _isCustomStrategyWorkflow(state) &&
        (state?.intentMode == FinanceIntentMode.validate ||
            state?.intentMode == FinanceIntentMode.analysis ||
            state?.intentMode == FinanceIntentMode.unknown);
  }

  bool _isCustomStrategySaveAndRunWorkflow(FinanceWorkflowState? state) {
    return _isCustomStrategyWorkflow(state) &&
        (state?.intentMode == FinanceIntentMode.save ||
            state?.intentMode == FinanceIntentMode.rerun);
  }

  bool _isCustomStrategyFundObservationWorkflow(FinanceWorkflowState? state) {
    return _isCustomStrategyWorkflow(state) &&
        state?.assetClass == FinanceAssetClass.fund &&
        state?.intentMode == FinanceIntentMode.observe;
  }

  Map<String, dynamic>? _structuredStrategySpec(String content) {
    final payload = _structuredPayload(content);
    final spec = payload?['strategySpec'];
    return spec is Map ? Map<String, dynamic>.from(spec) : null;
  }

  Map<String, dynamic>? _structuredPayload(String content) {
    final marker = content.lastIndexOf('data:');
    if (marker < 0) return null;
    final text = content.substring(marker + 'data:'.length).trim();
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      final prefix = _balancedJsonObjectPrefix(text);
      if (prefix == null) return null;
      try {
        final decoded = jsonDecode(prefix);
        return decoded is Map<String, dynamic> ? decoded : null;
      } catch (_) {
        return null;
      }
    }
  }

  String? _balancedJsonObjectPrefix(String text) {
    if (!text.startsWith('{')) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5c) {
          escaped = true;
        } else if (code == 0x22) {
          inString = false;
        }
        continue;
      }
      if (code == 0x22) {
        inString = true;
      } else if (code == 0x7b) {
        depth++;
      } else if (code == 0x7d) {
        depth--;
        if (depth == 0) return text.substring(0, i + 1);
      }
    }
    return null;
  }

  String? _requestedStrategyIdFromState(FinanceWorkflowState? state) {
    if (state == null || state.intentMode != FinanceIntentMode.rerun) {
      return null;
    }
    final subject = state.subject?.trim();
    return subject == null || subject.isEmpty ? null : subject;
  }

  String? _symbolFromState(FinanceWorkflowState? state) {
    final subject = state?.subject?.trim();
    if (subject == null || subject.isEmpty) return null;
    final match = RegExp(r'(?<!\d)([036]\d{5})(?!\d)').firstMatch(subject);
    return match?.group(1);
  }

  String? _symbolFromStateOrSpec(
    FinanceWorkflowState? state,
    Map<String, dynamic>? spec,
  ) {
    return _symbolFromSpec(spec) ?? _symbolFromState(state);
  }

  String? _symbolFromSpec(Map<String, dynamic>? spec) {
    if (spec == null) return null;
    final symbol = '${spec['symbol'] ?? spec['code'] ?? ''}'.trim();
    if (symbol.isNotEmpty) return symbol;
    final symbols = spec['symbols'];
    if (symbols is List && symbols.isNotEmpty) {
      final value = '${symbols.first}'.trim();
      if (value.isNotEmpty) return value;
    }
    final universe = spec['universe'];
    if (universe is Map) {
      final universeSymbols = universe['symbols'];
      if (universeSymbols is List && universeSymbols.isNotEmpty) {
        final value = '${universeSymbols.first}'.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  List<String> _comparisonSymbolsFromSpec(Map<String, dynamic>? spec) {
    final symbols = <String>[];
    void add(Object? value) {
      final text = '$value'.trim();
      if (text.isNotEmpty && !symbols.contains(text)) symbols.add(text);
    }

    final direct = spec?['symbols'];
    if (direct is List) {
      for (final value in direct) {
        add(value);
      }
    }
    final universe = spec?['universe'];
    if (universe is Map) {
      final universeSymbols = universe['symbols'];
      if (universeSymbols is List) {
        for (final value in universeSymbols) {
          add(value);
        }
      }
    }
    return symbols;
  }

  Map<String, dynamic>? _strategySpecForSymbol(
    Map<String, dynamic>? spec,
    String symbol,
  ) {
    if (spec == null) return null;
    final copy = Map<String, dynamic>.from(spec);
    copy['symbol'] = symbol;
    copy['symbols'] = [symbol];
    final universe = copy['universe'];
    if (universe is Map) {
      copy['universe'] = {
        ...universe,
        'symbols': [symbol],
      };
    }
    return copy;
  }

  Set<String> _completedBacktestSymbols(List<Message> messages) {
    final symbols = <String>{};
    for (final message in messages) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded['action'] != 'custom_strategy_backtest' ||
            decoded['status'] != 'backtested') {
          continue;
        }
        final symbol = decoded['symbol']?.toString();
        if (symbol != null && symbol.isNotEmpty) symbols.add(symbol);
      } catch (_) {
        continue;
      }
    }
    return symbols;
  }

  bool _isCustomStrategyToolCall(ToolUse call) {
    final action = call.input['action']?.toString() ?? '';
    return call.name == 'MarketData' && action.startsWith('custom_strategy_');
  }

  bool _hasSuccessfulRun(
    List<ToolUse> toolCalls,
    Set<String> successfulResults, {
    String? strategyId,
  }) {
    return toolCalls.any((call) {
      if (call.name != 'MarketData' ||
          call.input['action'] != 'custom_strategy_run' ||
          !successfulResults.contains(call.id)) {
        return false;
      }
      if (strategyId == null || strategyId.isEmpty) return true;
      return '${call.input['strategyId'] ?? ''}'.trim() == strategyId;
    });
  }

  bool _hasSuccessfulStrategyList(
    List<ToolUse> toolCalls,
    Set<String> successfulResults,
  ) {
    return toolCalls.any(
      (call) =>
          call.name == 'MarketData' &&
          call.input['action'] == 'custom_strategy_list' &&
          successfulResults.contains(call.id),
    );
  }

  bool _hasValidatedFundStrategy(List<Message> messages) {
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded['action'] != 'custom_strategy_validate' ||
            decoded['status'] != 'validated') {
          continue;
        }
        final spec = decoded['normalizedSpec'] ?? decoded['spec'];
        if (spec is Map && _isFundSpec(spec)) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  Map<String, dynamic>? _latestValidatedFundStrategySpec(
    List<Message> messages,
  ) {
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded['action'] != 'custom_strategy_validate' ||
            decoded['status'] != 'validated') {
          continue;
        }
        final spec = decoded['normalizedSpec'] ?? decoded['spec'];
        if (spec is Map && _isFundSpec(spec)) {
          return Map<String, dynamic>.from(spec);
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  bool _isFundSpec(Map spec) {
    final assetClass = '${spec['assetClass'] ?? ''}'.toLowerCase();
    final market = '${spec['market'] ?? ''}'.toLowerCase();
    return assetClass == 'fund' || market == 'fund';
  }

  bool _hasSuccessfulCustomStrategyObserve(List<Message> messages) {
    for (final message in messages) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is Map && decoded['action'] == 'custom_strategy_observe') {
          return true;
        }
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  bool _hasOrdinaryAndMoneyFundEvidence(List<Message> messages) {
    var hasOrdinaryNav = false;
    var hasMoneyYield = false;
    for (final message in messages) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        final action = '${decoded['action'] ?? ''}';
        final rows = decoded['data'];
        final hasRows = rows is List && rows.isNotEmpty;
        if (action == 'query_fund_nav' && hasRows) hasOrdinaryNav = true;
        if ((action == 'query_fund_money_yield' ||
                action == 'fund_money_yield') &&
            hasRows) {
          hasMoneyYield = true;
        }
        if (hasOrdinaryNav && hasMoneyYield) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> _latestFundRows(List<Message> messages) {
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        final action = '${decoded['action'] ?? ''}';
        if (action != 'query_fund_nav' &&
            action != 'query_fund_money_yield' &&
            action != 'query_fund_performance') {
          continue;
        }
        final rows = decoded['data'];
        if (rows is List) {
          final mapped = rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false);
          if (mapped.isNotEmpty) return mapped;
        }
      } catch (_) {
        continue;
      }
    }
    return const <Map<String, dynamic>>[];
  }

  bool _hasAskUserQuestionCall(List<Message> messages) {
    return messages.any(
      (message) => (message.toolUses ?? const <ToolUse>[]).any(
        (call) => call.name == 'AskUserQuestion',
      ),
    );
  }

  String? _latestFundCodeFromAskUserQuestion(List<Message> messages) {
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final structured = latestAskUserQuestionStructuredAnswer(result.content);
      if (structured == null) continue;
      final candidates = [
        structured['fundCode'],
        structured['code'],
        structured['symbol'],
        structured['selectedOptionLabel'],
      ];
      for (final candidate in candidates) {
        final code = _normalizeFundCode('$candidate');
        if (code != null) return code;
      }
    }
    return null;
  }

  String? _normalizeFundCode(String value) {
    final text = value.trim();
    if (RegExp(r'^\d{6}$').hasMatch(text)) return text;
    return null;
  }

  bool _hasPendingFundReadbackCall(List<ToolUse> toolCalls, String fundCode) {
    return toolCalls.any((call) {
      if (call.name != 'MarketData') return false;
      final action = '${call.input['action'] ?? ''}';
      if (action != 'query_fund_nav' &&
          action != 'query_fund_money_yield' &&
          action != 'query_fund_performance') {
        return false;
      }
      final symbols = call.input['symbols'];
      if (symbols is List) {
        return symbols.map((value) => '$value'.trim()).contains(fundCode);
      }
      final symbol = '${call.input['symbol'] ?? call.input['code'] ?? ''}'
          .trim();
      return symbol == fundCode;
    });
  }

  bool _hasSuccessfulFundRowsForCode(List<Message> messages, String fundCode) {
    for (final row in _latestFundRows(messages)) {
      final code = '${row['code'] ?? row['symbol'] ?? ''}'.trim();
      if (code == fundCode) return true;
    }
    return false;
  }

  bool _hasSuccessfulRunForSymbol(
    List<Message> messages, {
    required String strategyId,
    required String symbol,
  }) {
    final normalizedSymbol = _normalizeSymbol(symbol);
    for (final message in messages) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded['action'] != 'custom_strategy_run' ||
            decoded['status'] != 'backtested') {
          continue;
        }
        if ('${decoded['strategyId'] ?? ''}' != strategyId) continue;
        if (_normalizeSymbol('${decoded['symbol'] ?? ''}') ==
            normalizedSymbol) {
          return true;
        }
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  List<ToolUse> _missingSubjectRunCalls(
    List<Message> messages, {
    required String strategyId,
    required List<String> subjects,
  }) {
    final calls = <ToolUse>[];
    for (final subject in subjects) {
      final symbol = _normalizeSymbol(subject);
      if (symbol.isEmpty || !_isStockCode(symbol)) continue;
      if (_hasSuccessfulRunForSymbol(
        messages,
        strategyId: strategyId,
        symbol: symbol,
      )) {
        continue;
      }
      calls.add(
        ToolUse(
          id: 'custom_strategy_run_${symbol}_${DateTime.now().microsecondsSinceEpoch}',
          name: 'MarketData',
          input: {
            'action': 'custom_strategy_run',
            'strategyId': strategyId,
            'symbols': [symbol],
          },
        ),
      );
    }
    return calls;
  }

  String? _latestRunnableStrategyIdFromList(
    List<Message> messages,
    List<String> subjects,
  ) {
    final subjectSymbols = subjects
        .map(_normalizeSymbol)
        .where(_isStockCode)
        .toSet();
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic> ||
            decoded['action'] != 'custom_strategy_list') {
          continue;
        }
        final strategies = decoded['strategies'];
        if (strategies is! List) continue;
        final candidates = strategies
            .whereType<Map>()
            .map((strategy) => Map<String, dynamic>.from(strategy))
            .where(_isRunnableListedStockStrategy)
            .toList(growable: false);
        if (candidates.isEmpty) continue;
        final fullCoverage = candidates.firstWhere(
          (strategy) =>
              _listedStrategySymbols(strategy).containsAll(subjectSymbols),
          orElse: () => const <String, dynamic>{},
        );
        final selected = fullCoverage.isNotEmpty
            ? fullCoverage
            : candidates.firstWhere(
                (strategy) => _listedStrategySymbols(
                  strategy,
                ).intersection(subjectSymbols).isNotEmpty,
                orElse: () => candidates.first,
              );
        final strategyId = '${selected['strategyId'] ?? ''}'.trim();
        if (strategyId.isNotEmpty && !_isStockCode(strategyId)) {
          return strategyId;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  bool _isRunnableListedStockStrategy(Map<String, dynamic> strategy) {
    if ('${strategy['status'] ?? ''}' != 'backtested') return false;
    final strategyId = '${strategy['strategyId'] ?? ''}'.trim();
    if (strategyId.isEmpty || _isStockCode(strategyId)) return false;
    final assetClass = '${strategy['assetClass'] ?? ''}'.trim().toLowerCase();
    return assetClass.isEmpty || assetClass == 'stock' || assetClass == 'cn';
  }

  Set<String> _listedStrategySymbols(Map<String, dynamic> strategy) {
    final symbols = <String>{};
    final values = strategy['symbols'];
    if (values is List) {
      for (final value in values) {
        final symbol = _normalizeSymbol('$value');
        if (_isStockCode(symbol)) symbols.add(symbol);
      }
    }
    return symbols;
  }

  String? _selectedStrategyIdFromQuestionAnswer(List<Message> messages) {
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final structured = latestAskUserQuestionStructuredAnswer(result.content);
      if (structured == null) continue;
      final label = '${structured['selectedOptionLabel'] ?? ''}'.trim();
      if (label.isNotEmpty && !_isStockCode(label)) return label;
    }
    return null;
  }

  String? _missingRunSubject(
    FinanceWorkflowState? state,
    List<Message> messages,
    String strategyId,
  ) {
    if (state == null || state.subjects.isEmpty) return null;
    for (final subject in state.subjects) {
      final symbol = _normalizeSymbol(subject);
      if (symbol.isEmpty || !_isStockCode(symbol)) continue;
      if (!_hasSuccessfulRunForSymbol(
        messages,
        strategyId: strategyId,
        symbol: symbol,
      )) {
        return symbol;
      }
    }
    return null;
  }

  _SavedStrategy? _latestSuccessfulRun(List<Message> messages) {
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded['action'] != 'custom_strategy_run' ||
            decoded['status'] != 'backtested') {
          continue;
        }
        var strategyId = '${decoded['strategyId'] ?? ''}'.trim();
        if (_isStockCode(strategyId)) {
          final validation = decoded['validation'];
          if (validation is Map) {
            final validationStrategyId = '${validation['strategyId'] ?? ''}'
                .trim();
            if (validationStrategyId.isNotEmpty &&
                !_isStockCode(validationStrategyId)) {
              strategyId = validationStrategyId;
            }
          }
        }
        final symbol = '${decoded['symbol'] ?? ''}'.trim();
        if (strategyId.isEmpty || symbol.isEmpty) continue;
        return _SavedStrategy(strategyId: strategyId, symbol: symbol);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String? _latestWrongIdentityRunSymbol(
    List<ToolUse> toolCalls,
    String? activeStrategyId,
  ) {
    for (final call in toolCalls.reversed) {
      if (call.name != 'MarketData' ||
          call.input['action'] != 'custom_strategy_run') {
        continue;
      }
      final strategyId = '${call.input['strategyId'] ?? ''}'.trim();
      if (!_isStockCode(strategyId) || strategyId == activeStrategyId) {
        continue;
      }
      return strategyId;
    }
    return null;
  }

  List<ToolUse> _collectToolCalls(List<Message> messages) {
    final calls = <ToolUse>[];
    for (final message in messages) {
      final uses = message.toolUses;
      if (uses != null) calls.addAll(uses);
    }
    return calls;
  }

  Set<String> _successfulToolResults(List<Message> messages) {
    final ids = <String>{};
    for (final message in messages) {
      final result = message.toolResult;
      if (result != null && !result.isError) ids.add(result.toolUseId);
    }
    return ids;
  }

  String? _candidateSymbolFromEvidence(List<Message> messages) {
    final quoteChangePct = <String, num>{};
    final klineCounts = <String, int>{};
    for (final message in messages) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        final watchlistCandidate = _candidateSymbolFromWatchlist(decoded);
        if (watchlistCandidate != null) return watchlistCandidate;
        final action = decoded['action']?.toString();
        if (action == 'query_quote') {
          final rows = decoded['data'];
          if (rows is List) {
            for (final row in rows) {
              if (row is! Map) continue;
              final code = row['code']?.toString() ?? row['symbol']?.toString();
              if (code == null || code.isEmpty) continue;
              quoteChangePct[code] =
                  _asNum(row['changePct'] ?? row['change_pct']) ?? 0;
            }
          }
        }
        if (action == 'query_kline') {
          final symbol = decoded['symbol']?.toString();
          final count = _asNum(decoded['count'])?.toInt() ?? 0;
          if (symbol != null && symbol.isNotEmpty) {
            klineCounts[symbol] = count;
          }
        }
      } catch (_) {
        continue;
      }
    }
    final candidates = klineCounts.entries
        .where((entry) => entry.value >= 60)
        .map((entry) => entry.key)
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((left, right) {
      final byChange = (quoteChangePct[right] ?? 0).compareTo(
        quoteChangePct[left] ?? 0,
      );
      if (byChange != 0) return byChange;
      return (klineCounts[right] ?? 0).compareTo(klineCounts[left] ?? 0);
    });
    return candidates.first;
  }

  String? _candidateSymbolFromWatchlist(Map<String, dynamic> decoded) {
    final items = decoded['items'];
    if (items is! List) return null;
    for (final item in items) {
      if (item is! Map) continue;
      final type = item['type']?.toString().toLowerCase();
      if (type != null && type != 'stock') continue;
      final status = item['status']?.toString().toLowerCase();
      if (status != null &&
          status.isNotEmpty &&
          status != 'watching' &&
          status != 'watch') {
        continue;
      }
      final symbol = item['symbol']?.toString();
      if (symbol != null && RegExp(r'^[036]\d{5}$').hasMatch(symbol)) {
        return symbol;
      }
    }
    return null;
  }

  _ValidatedStrategy? _latestValidatedStrategy(List<Message> messages) {
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded['action'] != 'custom_strategy_validate' ||
            decoded['status'] != 'validated') {
          continue;
        }
        final spec = decoded['normalizedSpec'] ?? decoded['spec'];
        if (spec is! Map) continue;
        final strategySpec = Map<String, dynamic>.from(spec);
        final symbol =
            strategySpec['symbol']?.toString() ??
            ((strategySpec['symbols'] is List &&
                    (strategySpec['symbols'] as List).isNotEmpty)
                ? (strategySpec['symbols'] as List).first.toString()
                : null);
        if (symbol == null || symbol.isEmpty) continue;
        return _ValidatedStrategy(strategySpec: strategySpec, symbol: symbol);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  _BacktestedStrategy? _latestBacktestedStrategy(List<Message> messages) {
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded['action'] != 'custom_strategy_backtest' ||
            decoded['status'] != 'backtested') {
          continue;
        }
        final validation = decoded['validation'];
        if (validation is! Map) continue;
        final spec = validation['spec'];
        if (spec is! Map) continue;
        final strategySpec = Map<String, dynamic>.from(spec);
        final symbol =
            decoded['symbol']?.toString() ??
            strategySpec['symbol']?.toString() ??
            ((strategySpec['symbols'] is List &&
                    (strategySpec['symbols'] as List).isNotEmpty)
                ? (strategySpec['symbols'] as List).first.toString()
                : null);
        final strategyId =
            decoded['strategyId']?.toString() ??
            validation['strategyId']?.toString() ??
            strategySpec['id']?.toString();
        if (symbol == null ||
            symbol.isEmpty ||
            strategyId == null ||
            strategyId.isEmpty) {
          continue;
        }
        return _BacktestedStrategy(
          strategyId: strategyId,
          symbol: symbol,
          strategySpec: strategySpec,
          evidence: Map<String, dynamic>.from(decoded),
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  _SavedStrategy? _latestSavedStrategy(List<Message> messages) {
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded['action'] != 'custom_strategy_save' ||
            !_hasBacktestedEvidence(decoded)) {
          continue;
        }
        final symbol = _savedStrategySymbol(decoded);
        final strategyId = decoded['strategyId']?.toString();
        if (symbol == null ||
            symbol.isEmpty ||
            strategyId == null ||
            strategyId.isEmpty) {
          continue;
        }
        return _SavedStrategy(strategyId: strategyId, symbol: symbol);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String? _savedStrategySymbol(Map<String, dynamic> payload) {
    String? firstFrom(Object? value) {
      if (value is List && value.isNotEmpty) {
        final text = value.first?.toString().trim();
        return text == null || text.isEmpty ? null : text;
      }
      return null;
    }

    final spec = payload['spec'];
    if (spec is Map) {
      final direct = spec['symbol']?.toString().trim();
      if (direct != null && direct.isNotEmpty) return direct;
      final fromSymbols = firstFrom(spec['symbols']);
      if (fromSymbols != null) return fromSymbols;
      final fromCodes = firstFrom(spec['codes']);
      if (fromCodes != null) return fromCodes;
    }
    final summary = payload['strategySpecSummary'];
    if (summary is Map) {
      final direct = summary['symbol']?.toString().trim();
      if (direct != null && direct.isNotEmpty) return direct;
      final fromSymbols = firstFrom(summary['symbols']);
      if (fromSymbols != null) return fromSymbols;
    }
    final nextActionInput = payload['nextActionInput'];
    if (nextActionInput is Map) {
      final fromSymbols = firstFrom(nextActionInput['symbols']);
      if (fromSymbols != null) return fromSymbols;
      final direct = nextActionInput['symbol']?.toString().trim();
      if (direct != null && direct.isNotEmpty) return direct;
    }
    return null;
  }

  bool _hasBacktestedEvidence(Map<String, dynamic> payload) {
    if (payload['status'] == 'backtested') return true;
    final evidence = payload['evidence'];
    return evidence is Map && evidence['status'] == 'backtested';
  }

  num? _asNum(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  bool _isStockCode(String value) => RegExp(r'^[036]\d{5}$').hasMatch(value);

  String _normalizeSymbol(String value) => value
      .trim()
      .toUpperCase()
      .replaceFirst(RegExp(r'\.(SH|SZ)$'), '')
      .replaceFirst(RegExp(r'^(SH|SZ)'), '');
}

class _ValidatedStrategy {
  const _ValidatedStrategy({required this.strategySpec, required this.symbol});

  final Map<String, dynamic> strategySpec;
  final String symbol;
}

class _BacktestedStrategy {
  const _BacktestedStrategy({
    required this.strategyId,
    required this.symbol,
    required this.strategySpec,
    required this.evidence,
  });

  final String strategyId;
  final String symbol;
  final Map<String, dynamic> strategySpec;
  final Map<String, dynamic> evidence;
}

class _SavedStrategy {
  const _SavedStrategy({required this.strategyId, required this.symbol});

  final String strategyId;
  final String symbol;
}
