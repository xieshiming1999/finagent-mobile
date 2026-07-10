import 'dart:convert';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../../watchlist.dart';

class WatchlistTool extends Tool {
  final WatchlistStore store;

  WatchlistTool({required this.store});

  @override
  String get name => 'Watchlist';

  @override
  String get description =>
      'Manage watchlists: create groups, add/remove symbols, track entry/exit, query by type/status/tag.';

  @override
  String get prompt => '''管理自选列表(观察池)。
- create_group — 创建列表. name, type(stock/fund/etf)
- list_groups  — 列出所有列表
- delete_group — 删除列表
- add    — 加入观察. groupId, symbol, name, type(stock/fund/etf/index/macro-condition), tags, entryCondition, strategyId, strategyRules, portfolioEvidence, rebalanceDraft, targetEntryPrice, stopLoss, targetPrice, suggestedWeight, score, rating, source
- remove — 移除. itemId
- update — 更新属性. itemId + 要更新的字段
- list   — 查询. groupId, symbol, status(watching/entered/exited), type, tag, strategyId
- enter  — 标记已入场. itemId, actualEntryPrice
- exit   — 标记已退出. itemId, exitPrice
- summary — 概览(各组数量/状态统计)
- help   — 帮助''';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': [
          'create_group',
          'list_groups',
          'delete_group',
          'add',
          'remove',
          'update',
          'list',
          'enter',
          'exit',
          'summary',
          'help',
        ],
      },
      'name': {'type': 'string'},
      'type': {
        'type': 'string',
        'description': 'stock/fund/etf/index/macro-condition',
      },
      'groupId': {'type': 'string'},
      'symbol': {'type': 'string'},
      'tags': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'status': {'type': 'string'},
      'tag': {'type': 'string'},
      'itemId': {'type': 'string'},
      'entryCondition': {'type': 'string'},
      'strategyId': {'type': 'string'},
      'strategyRules': {
        'type': 'object',
        'description':
            'Structured strategy-derived rules used for watchlist/monitor provenance.',
      },
      'macroEvidence': {
        'type': 'object',
        'description':
            'Structured macro evidence/provenance used for macro-condition observation rows.',
      },
      'portfolioEvidence': {
        'type': 'object',
        'description':
            'Structured portfolio ranking evidence returned by custom_strategy_rank.',
      },
      'rebalanceDraft': {
        'type': 'object',
        'description':
            'Bounded rebalance draft returned by custom_strategy_rank. Evidence only; does not place orders.',
      },
      'targetEntryPrice': {'type': 'number'},
      'stopLoss': {'type': 'number'},
      'targetPrice': {'type': 'number'},
      'suggestedWeight': {'type': 'number'},
      'actualEntryPrice': {'type': 'number'},
      'exitPrice': {'type': 'number'},
      'score': {'type': 'integer'},
      'rating': {'type': 'string'},
      'source': {'type': 'string'},
    },
    'required': ['action'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) {
    final action = input['action'] as String? ?? 'help';
    return action == 'add' ||
        action == 'remove' ||
        action == 'enter' ||
        action == 'exit' ||
        action == 'delete_group';
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = input['action'] as String? ?? 'help';
    return switch (action) {
      'help' => ToolResult(toolUseId: toolUseId, content: prompt),
      'create_group' => _createGroup(toolUseId, input),
      'list_groups' => _listGroups(toolUseId),
      'delete_group' => _deleteGroup(toolUseId, input),
      'add' => _add(toolUseId, input),
      'remove' => _remove(toolUseId, input),
      'update' => _update(toolUseId, input),
      'list' => _list(toolUseId, input),
      'enter' => _enter(toolUseId, input),
      'exit' => _exit(toolUseId, input),
      'summary' => _summary(toolUseId),
      _ => ToolResult(
        toolUseId: toolUseId,
        content: 'Unknown action "$action". Use help.',
        isError: true,
      ),
    };
  }

  ToolResult _createGroup(String id, Map<String, dynamic> input) {
    final name = input['name'] as String?;
    if (name == null || name.isEmpty) {
      return ToolResult(toolUseId: id, content: 'name required', isError: true);
    }
    final group = WatchlistGroup(name: name, refreshIntervalSec: 300);
    store.addGroup(group);
    return ToolResult(
      toolUseId: id,
      content:
          'Created group "$name" (id: ${group.id}). Total groups: ${store.groups.length}',
    );
  }

  ToolResult _listGroups(String id) {
    final list = store.groups
        .map(
          (g) => {
            'id': g.id,
            'name': g.name,
            'itemCount': store.getByGroup(g.id).length,
            'watching': store
                .getByGroup(g.id)
                .where((i) => i.status == 'watching')
                .length,
            'entered': store
                .getByGroup(g.id)
                .where((i) => i.status == 'entered')
                .length,
          },
        )
        .toList();
    return ToolResult(
      toolUseId: id,
      content: const JsonEncoder.withIndent('  ').convert({'groups': list}),
    );
  }

  ToolResult _deleteGroup(String id, Map<String, dynamic> input) {
    final groupId = input['groupId'] as String?;
    if (groupId == null) {
      return ToolResult(
        toolUseId: id,
        content: 'groupId required',
        isError: true,
      );
    }
    store.removeGroup(groupId);
    return ToolResult(
      toolUseId: id,
      content:
          'Deleted group $groupId. ${store.groups.length} group(s) remaining.',
    );
  }

  ToolResult _add(String id, Map<String, dynamic> input) {
    final itemType = _normalizeWatchItemType(input['type']);
    final symbol = itemType == 'macro-condition'
        ? _macroConditionSymbol(input)
        : input['symbol'] as String?;
    if (symbol == null || symbol.isEmpty) {
      return ToolResult(
        toolUseId: id,
        content: 'symbol required',
        isError: true,
      );
    }
    final groupId =
        input['groupId'] as String? ??
        store.groupForType(itemType)?.id ??
        store.defaultGroup.id;
    final tag = (input['tag'] as String?)?.trim() ?? '';
    final tags =
        (input['tags'] as List?)?.map((e) => e.toString()).toSet() ??
        <String>{};
    if (tag.isNotEmpty) tags.add(tag);
    final inferredName = (input['name'] as String?)?.trim() ?? '';
    if ((itemType == 'fund' || itemType == 'etf') && inferredName.isEmpty) {
      return ToolResult(
        toolUseId: id,
        content:
            'name required for fund/etf watchlist items; tag is classification metadata, not display name',
        isError: true,
      );
    }
    if (itemType == 'macro-condition' &&
        inferredName.isEmpty &&
        (input['entryCondition'] as String?)?.trim().isNotEmpty != true) {
      return ToolResult(
        toolUseId: id,
        content:
            'name or entryCondition required for macro-condition watchlist items; macro conditions are observation context, not tradable instruments',
        isError: true,
      );
    }
    if (itemType == 'macro-condition' && !_hasMacroConditionEvidence(input)) {
      return ToolResult(
        toolUseId: id,
        content: const JsonEncoder.withIndent('  ').convert({
          'error': 'macro-condition evidence required',
          'requiredBeforeAdd': [
            {
              'tool': 'MarketData',
              'input': {
                'action': 'query_macro_factors',
                'target': '<asset/theme>',
                'limit': 10,
              },
            },
            {
              'tool': 'MarketData',
              'input': {
                'action': 'query_macro_attribution',
                'target': '<asset/theme>',
                'limit': 10,
              },
            },
            {
              'tool': 'MarketData',
              'input': {
                'action': 'query_finance_news',
                'query': '<asset/theme>',
                'limit': 10,
              },
            },
          ],
          'acceptedEvidenceFields': [
            'macroEvidence',
            'strategyRules.evidenceTier',
            'strategyRules.provenance',
            'source with governed provider/evidence metadata',
          ],
          'boundary':
              'macro-condition rows are observation/invalidation evidence only, not executable buy/sell triggers',
        }),
        isError: true,
      );
    }
    final item = WatchlistItem(
      groupId: groupId,
      symbol: symbol,
      name: inferredName.isNotEmpty
          ? inferredName
          : input['entryCondition'] as String? ?? 'Macro condition',
      type: itemType,
      source: input['source'] as String? ?? 'agent',
      tags: tags,
      priceAtAdd: _numValue(input['targetEntryPrice'])?.toDouble() ?? 0,
      score: _numValue(input['score'])?.toInt(),
      rating: input['rating'] as String?,
      entryCondition: input['entryCondition'] as String?,
      strategyId: input['strategyId'] as String?,
      strategyRules: _normalizeStrategyRules(input),
      targetEntryPrice: _numValue(input['targetEntryPrice'])?.toDouble(),
      stopLoss: _numValue(input['stopLoss'])?.toDouble(),
      targetPrice: _numValue(input['targetPrice'])?.toDouble(),
      suggestedWeight: _numValue(input['suggestedWeight'])?.toDouble(),
    );
    store.addItem(item);
    final groupItems = store.getByGroup(groupId);
    final monitorSuggestion = _monitorSuggestionFor(item);
    if (monitorSuggestion != null) {
      return ToolResult(
        toolUseId: id,
        content: const JsonEncoder.withIndent('  ').convert({
          'action': 'add',
          'status': 'added',
          'item': _itemToJson(item),
          'groupId': groupId,
          'groupItemCount': groupItems.length,
          'next': monitorSuggestion,
        }),
      );
    }
    if (itemType == 'macro-condition') {
      return ToolResult(
        toolUseId: id,
        content: const JsonEncoder.withIndent('  ').convert({
          'action': 'add',
          'status': 'added',
          'item': _itemToJson(item),
          'groupId': groupId,
          'groupItemCount': groupItems.length,
          'readbackAction': {
            'tool': 'Watchlist',
            'input': {
              'action': 'list',
              'type': 'macro-condition',
              'status': 'watching',
            },
          },
          'boundary':
              'macro/news context is observation evidence, not an executable buy/sell trigger',
        }),
      );
    }
    return ToolResult(
      toolUseId: id,
      content:
          'Added ${item.name.isNotEmpty ? item.name : symbol} to watchlist (id: ${item.id}, group: $groupId, ${groupItems.length} items in group)',
    );
  }

  bool _hasMacroConditionEvidence(Map<String, dynamic> input) {
    if (input['macroEvidence'] is Map &&
        (input['macroEvidence'] as Map).isNotEmpty) {
      return true;
    }
    final rules = _normalizeStrategyRules(input);
    if (rules != null) {
      const evidenceKeys = {
        'evidenceTier',
        'provenance',
        'sourceEvidence',
        'macroEvidence',
        'dataQuality',
        'refreshPolicy',
        'missingEvidence',
      };
      if (evidenceKeys.any(rules.containsKey)) return true;
    }
    final source = (input['source'] as String?)?.trim() ?? '';
    if (source.isEmpty) return false;
    const genericSources = {'agent', 'user', 'manual'};
    if (genericSources.contains(source.toLowerCase())) return false;
    return source.contains('provider=') ||
        source.contains('evidence') ||
        source.contains('interface') ||
        source.contains('provenance') ||
        source.contains('official') ||
        source.contains('macro');
  }

  ToolResult _remove(String id, Map<String, dynamic> input) {
    final itemId = input['itemId'] as String?;
    if (itemId == null) {
      return ToolResult(
        toolUseId: id,
        content: 'itemId required',
        isError: true,
      );
    }
    store.removeItem(itemId);
    return ToolResult(
      toolUseId: id,
      content:
          'Removed $itemId from watchlist. ${store.items.length} total items remaining.',
    );
  }

  ToolResult _update(String id, Map<String, dynamic> input) {
    final itemId = input['itemId'] as String?;
    if (itemId == null) {
      return ToolResult(
        toolUseId: id,
        content: 'itemId required',
        isError: true,
      );
    }
    store.updateItem(itemId, (item) {
      if (input.containsKey('tags')) {
        item.tags = (input['tags'] as List).map((e) => e.toString()).toSet();
      }
      if (input.containsKey('entryCondition')) {
        item.entryCondition = input['entryCondition'] as String?;
      }
      if (input.containsKey('strategyId')) {
        item.strategyId = input['strategyId'] as String?;
      }
      if (input.containsKey('strategyRules')) {
        item.strategyRules = _normalizeStrategyRules(input);
      } else if (input.containsKey('portfolioEvidence') ||
          input.containsKey('rebalanceDraft')) {
        item.strategyRules = _normalizeStrategyRules(input);
      }
      if (input.containsKey('targetEntryPrice')) {
        item.targetEntryPrice = _numValue(
          input['targetEntryPrice'],
        )?.toDouble();
      }
      if (input.containsKey('stopLoss')) {
        item.stopLoss = _numValue(input['stopLoss'])?.toDouble();
      }
      if (input.containsKey('targetPrice')) {
        item.targetPrice = _numValue(input['targetPrice'])?.toDouble();
      }
      if (input.containsKey('suggestedWeight')) {
        item.suggestedWeight = _numValue(input['suggestedWeight'])?.toDouble();
      }
      if (input.containsKey('score')) {
        item.score = _numValue(input['score'])?.toInt();
      }
      if (input.containsKey('rating')) item.rating = input['rating'] as String?;
      if (input.containsKey('status')) item.status = input['status'] as String;
    });
    return ToolResult(toolUseId: id, content: 'Updated $itemId');
  }

  ToolResult _list(String id, Map<String, dynamic> input) {
    final results = store.query(
      groupId: input['groupId'] as String?,
      symbol: input['symbol'] as String?,
      status: input['status'] as String?,
      type: input['type'] as String?,
      tag: input['tag'] as String?,
      strategyId: input['strategyId'] as String?,
    );
    final list = results
        .map(
          (i) => {
            'id': i.id,
            'symbol': i.symbol,
            'name': i.name,
            'type': i.type,
            'status': i.status,
            'tags': i.tags.toList(),
            'addedAt': i.addedAt.toIso8601String(),
            'priceAtAdd': i.priceAtAdd,
            'currentPrice': i.currentPrice,
            'changePct': i.changePct != null
                ? '${i.changePct! >= 0 ? "+" : ""}${i.changePct!.toStringAsFixed(2)}%'
                : null,
            'score': i.score,
            'rating': i.rating,
            'entryCondition': i.entryCondition,
            'strategyId': i.strategyId,
            'strategyRules': i.strategyRules,
            if (i.strategyRules?['portfolioEvidence'] != null)
              'portfolioEvidence': i.strategyRules!['portfolioEvidence'],
            if (i.strategyRules?['rebalanceDraft'] != null)
              'rebalanceDraft': i.strategyRules!['rebalanceDraft'],
            if (i.status == 'entered') ...{
              'actualEntryPrice': i.actualEntryPrice,
              'stopLoss': i.stopLoss,
              'targetPrice': i.targetPrice,
              'pnl': i.actualEntryPrice != null && i.currentPrice != null
                  ? '${((i.currentPrice! - i.actualEntryPrice!) / i.actualEntryPrice! * 100).toStringAsFixed(1)}%'
                  : null,
            },
          },
        )
        .toList();
    final hasFundSignals = results.any(
      (item) =>
          (item.type == 'fund' || item.type == 'etf') &&
          item.status == 'watching',
    );
    final stockSymbols = <String>{
      for (final item in results)
        if (item.status == 'watching' &&
            (item.type.isEmpty || item.type == 'stock') &&
            item.symbol.isNotEmpty)
          item.symbol,
    }.take(12).toList();
    final payload = <String, dynamic>{'count': list.length, 'items': list};
    if (stockSymbols.length >= 2) {
      payload['nextAction'] = {
        'tool': 'MarketData',
        'action': 'custom_strategy_help',
        'strategy': 'custom_strategy_rank',
        'symbols': stockSymbols,
        'topN': stockSymbols.length < 3 ? stockSymbols.length : 3,
        'maxPositionWeight': 0.35,
        'rebalanceInterval': 'monthly',
        'requiresStrategySpec': true,
        'afterStrategySpec': {
          'tool': 'MarketData',
          'action': 'custom_strategy_rank',
          'symbols': stockSymbols,
          'topN': stockSymbols.length < 3 ? stockSymbols.length : 3,
          'maxPositionWeight': 0.35,
          'rebalanceInterval': 'monthly',
        },
        'boundary':
            'Evidence-only portfolio observation. Use portfolioEvidence, concentrationEvidence, drawdown-budget evidence, candidateFailureEvidence, and rebalanceDraft. Do not create watchlist entries, Portfolio orders, XueqiuTrade actions, broker orders, or automatic rebalances unless a separate user confirmation authorizes that side effect.',
        'reason':
            'Multiple watched stock symbols are available. For portfolio observation, inspect the governed custom_strategy_rank contract, construct a StrategySpec, then call custom_strategy_rank with that StrategySpec instead of manually ranking quotes or K-line summaries.',
      };
    }
    if (hasFundSignals) {
      final fundNextAction = {
        'tool': 'DataProcess',
        'action': 'watch_signal_check',
        'type': 'fund',
        'status': 'watching',
        'reason':
            'Use this structured contract to evaluate fund/ETF watchlist signals from WatchlistStore plus canonical fund NAV or money-yield rows. Do not interpret entryCondition text manually.',
      };
      if (payload.containsKey('nextAction')) {
        payload['fundSignalNextAction'] = fundNextAction;
      } else {
        payload['nextAction'] = fundNextAction;
      }
    }
    return ToolResult(
      toolUseId: id,
      content: const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  ToolResult _enter(String id, Map<String, dynamic> input) {
    final itemId = input['itemId'] as String?;
    final price = (input['actualEntryPrice'] as num?)?.toDouble();
    if (itemId == null || price == null) {
      return ToolResult(
        toolUseId: id,
        content: 'itemId and actualEntryPrice required',
        isError: true,
      );
    }
    store.updateItem(itemId, (item) {
      item.status = 'entered';
      item.actualEntryPrice = price;
      item.enteredAt = DateTime.now();
    });
    return ToolResult(
      toolUseId: id,
      content: 'Marked $itemId as entered @ $price',
    );
  }

  ToolResult _exit(String id, Map<String, dynamic> input) {
    final itemId = input['itemId'] as String?;
    final price = (input['exitPrice'] as num?)?.toDouble();
    if (itemId == null || price == null) {
      return ToolResult(
        toolUseId: id,
        content: 'itemId and exitPrice required',
        isError: true,
      );
    }
    store.updateItem(itemId, (item) {
      item.status = 'exited';
      item.exitPrice = price;
      item.exitedAt = DateTime.now();
      if (item.actualEntryPrice != null && item.actualEntryPrice! > 0) {
        item.profitPct =
            (price - item.actualEntryPrice!) / item.actualEntryPrice! * 100;
      }
    });
    final item = store.items.where((i) => i.id == itemId).firstOrNull;
    final pnl = item?.profitPct != null
        ? ' (${item!.profitPct! >= 0 ? "+" : ""}${item.profitPct!.toStringAsFixed(1)}%)'
        : '';
    return ToolResult(
      toolUseId: id,
      content: 'Marked $itemId as exited @ $price$pnl',
    );
  }

  ToolResult _summary(String id) {
    final watching = store.getByStatus('watching').length;
    final entered = store.getByStatus('entered').length;
    final exited = store.getByStatus('exited').length;
    final groupSummary = store.groups.map((g) {
      final items = store.getByGroup(g.id);
      return {
        'name': g.name,
        'total': items.length,
        'watching': items.where((i) => i.status == 'watching').length,
        'entered': items.where((i) => i.status == 'entered').length,
      };
    }).toList();
    return ToolResult(
      toolUseId: id,
      content: const JsonEncoder.withIndent('  ').convert({
        'total': store.items.length,
        'watching': watching,
        'entered': entered,
        'exited': exited,
        'groups': groupSummary,
      }),
    );
  }
}

num? _numValue(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value.trim());
  return null;
}

String _normalizeWatchItemType(Object? value) {
  final type = '${value ?? 'stock'}'.trim().toLowerCase();
  if (type == 'macro_condition' || type == 'macro' || type == 'macro-risk') {
    return 'macro-condition';
  }
  return type.isEmpty ? 'stock' : type;
}

String _macroConditionSymbol(Map<String, dynamic> input) {
  final explicit = '${input['symbol'] ?? input['conditionId'] ?? ''}'.trim();
  if (explicit.isNotEmpty) return explicit;
  final basis =
      '${input['name'] ?? input['entryCondition'] ?? input['source'] ?? 'macro-condition'}'
          .trim();
  final slug = basis
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fa5]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final bounded = slug.length > 48 ? slug.substring(0, 48) : slug;
  return 'macro:${bounded.isEmpty ? 'condition' : bounded}';
}

Map<String, dynamic>? _normalizeStrategyRules(Map<String, dynamic> input) {
  final rules = input['strategyRules'] is Map
      ? Map<String, dynamic>.from(input['strategyRules'] as Map)
      : <String, dynamic>{};
  if (input['portfolioEvidence'] is Map) {
    rules['portfolioEvidence'] = Map<String, dynamic>.from(
      input['portfolioEvidence'] as Map,
    );
  }
  if (input['rebalanceDraft'] is Map) {
    rules['rebalanceDraft'] = Map<String, dynamic>.from(
      input['rebalanceDraft'] as Map,
    );
  }
  if (rules.isEmpty) return null;
  return rules;
}

Map<String, dynamic>? _monitorSuggestionFor(WatchlistItem item) {
  if ((item.strategyId == null || item.strategyId!.isEmpty) &&
      item.strategyRules == null) {
    return null;
  }
  final isFundLike =
      item.type.toLowerCase() == 'fund' || item.type.toLowerCase() == 'etf';
  return {
    'tool': 'MonitorCreate',
    'template': isFundLike ? 'fund_rule_monitor' : 'strategy_signal',
    'readbackTool': 'MonitorList',
    'params': {
      'code': item.symbol,
      'name': item.name.isNotEmpty ? item.name : item.symbol,
      'strategyId': item.strategyId,
      'strategyRules': item.strategyRules,
    },
    'boundary': isFundLike
        ? 'Signal/observation monitor only; no Portfolio, XueqiuTrade, broker, buy, sell, transfer, subscription, redemption, or order side effect is authorized.'
        : 'Signal monitor only; no Portfolio, XueqiuTrade, broker, buy, sell, transfer, or order side effect is authorized.',
  };
}

Map<String, dynamic> _itemToJson(WatchlistItem item) {
  return {
    'id': item.id,
    'groupId': item.groupId,
    'symbol': item.symbol,
    'name': item.name,
    'type': item.type,
    'status': item.status,
    'source': item.source,
    'tags': item.tags.toList(),
    'priceAtAdd': item.priceAtAdd,
    'currentPrice': item.currentPrice,
    'changePct': item.changePct,
    'score': item.score,
    'rating': item.rating,
    'entryCondition': item.entryCondition,
    'strategyId': item.strategyId,
    'strategyRules': item.strategyRules,
    'targetEntryPrice': item.targetEntryPrice,
    'stopLoss': item.stopLoss,
    'targetPrice': item.targetPrice,
    'suggestedWeight': item.suggestedWeight,
    'actualEntryPrice': item.actualEntryPrice,
    'exitPrice': item.exitPrice,
    'profitPct': item.profitPct,
    'addedAt': item.addedAt.toIso8601String(),
    'enteredAt': item.enteredAt?.toIso8601String(),
    'exitedAt': item.exitedAt?.toIso8601String(),
  };
}
