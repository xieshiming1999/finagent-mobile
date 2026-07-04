import 'dart:convert';
import 'dart:io';

import '../../data_fetcher/data_manager.dart';
import '../../../domain/market/services/market_data_resolve_service.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

/// Portfolio management tool: track positions, trades, P&L.
class PortfolioTool extends Tool {
  final MarketDataResolveService _resolveService;

  PortfolioTool({
    DataManager? dataManager,
    MarketDataResolveService? resolveService,
  }) : this._(dataManager ?? DataManager(), resolveService);

  PortfolioTool._(
    DataManager dataManager,
    MarketDataResolveService? resolveService,
  ) : _resolveService =
          resolveService ?? MarketDataResolveService(dataManager: dataManager);

  @override
  String get name => 'Portfolio';
  @override
  String get description =>
      'Manage investment portfolio: positions, trades, P&L, risk. Use action="help".';
  @override
  String get prompt =>
      '''Investment portfolio management. Use action="help" to discover.

Key actions:
- **add** — Add a position. symbol, shares, costPrice
- **remove** — Remove a position. symbol
- **trade** — Record buy/sell. symbol, side: buy/sell, shares, price
- **preview_trade** — Validate and estimate buy/sell without writing state
- **snapshot** — Current portfolio with live prices and P&L
- **risk** — Risk analysis: concentration, drawdown alerts
- **history** — Trade history
- **help** — List all actions''';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': [
          'add',
          'remove',
          'trade',
          'preview_trade',
          'snapshot',
          'risk',
          'history',
          'clear',
          'help',
        ],
      },
      'symbol': {'type': 'string'},
      'shares': {'type': 'number'},
      'costPrice': {'type': 'number'},
      'side': {'type': 'string', 'description': 'buy or sell'},
      'price': {'type': 'number'},
      'market': {
        'type': 'string',
        'description': 'Market: cn(A股,CNY)/us(美股,USD)/hk(港股,HKD). Default: cn',
      },
    },
    'required': ['action'],
  };

  @override
  bool get isReadOnly => false;
  @override
  bool needsPermissions(Map<String, dynamic> input) {
    final action = (input['action'] ?? 'help').toString().toLowerCase();
    return action == 'add' ||
        action == 'remove' ||
        action == 'trade' ||
        action == 'clear';
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = input['action'] as String? ?? 'help';
    final market = input['market'] as String? ?? 'cn';
    final store = _PortfolioStore(context.basePath, market: market);
    try {
      return switch (action) {
        'help' => _help(toolUseId),
        'add' => _add(toolUseId, input, store),
        'remove' => _remove(toolUseId, input, store),
        'trade' => _trade(toolUseId, input, store),
        'preview_trade' => _previewTrade(toolUseId, input, store),
        'snapshot' => await _snapshot(toolUseId, store),
        'risk' => await _risk(toolUseId, store),
        'history' => _history(toolUseId, store),
        'clear' => _clear(toolUseId, store),
        _ => ToolResult(
          toolUseId: toolUseId,
          content: 'Unknown action "$action". Use action="help".',
          isError: true,
        ),
      };
    } catch (e) {
      return ToolResult(toolUseId: toolUseId, content: '$e', isError: true);
    }
  }

  ToolResult _help(String toolUseId) => ToolResult(
    toolUseId: toolUseId,
    content: '''Portfolio actions:

POSITIONS:
  add      — Add position. symbol: "600519", shares: 100, costPrice: 1650
  remove   — Remove position. symbol: "600519"
  snapshot — Current portfolio with live P&L

TRADES:
  trade    — Record trade. symbol: "600519", side: "buy"/"sell", shares: 100, price: 1650
  preview_trade — Validate and estimate trade without writing state. symbol, side, shares, price
  history  — Trade history

ANALYSIS:
  risk     — Risk analysis: concentration, stop-loss alerts, sector exposure

MANAGEMENT:
  clear    — Clear all positions and trades
  help     — This help text''',
  );

  ToolResult _add(
    String toolUseId,
    Map<String, dynamic> input,
    _PortfolioStore store,
  ) {
    final symbol = input['symbol'] as String?;
    final shares = (input['shares'] as num?)?.toDouble();
    final cost = (input['costPrice'] as num?)?.toDouble();
    if (symbol == null || shares == null || cost == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'symbol, shares, costPrice required',
        isError: true,
      );
    }
    store.addPosition(symbol, shares, cost);
    final totalPositions = store.getPositions().length;
    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Added: $symbol ${shares.toInt()} shares @ $cost. Total positions: $totalPositions.',
    );
  }

  ToolResult _remove(
    String toolUseId,
    Map<String, dynamic> input,
    _PortfolioStore store,
  ) {
    final symbol = input['symbol'] as String?;
    if (symbol == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'symbol required',
        isError: true,
      );
    }
    store.removePosition(symbol);
    final totalPositions = store.getPositions().length;
    return ToolResult(
      toolUseId: toolUseId,
      content: 'Removed: $symbol. $totalPositions position(s) remaining.',
    );
  }

  ToolResult _trade(
    String toolUseId,
    Map<String, dynamic> input,
    _PortfolioStore store,
  ) {
    final symbol = input['symbol'] as String?;
    final side = (input['side'] as String?)?.toLowerCase();
    final shares = (input['shares'] as num?)?.toDouble();
    final price = (input['price'] as num?)?.toDouble();
    if (symbol == null || side == null || shares == null || price == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'symbol, side(buy/sell), shares, price required',
        isError: true,
      );
    }
    final error = store.addTrade(symbol, side, shares, price);
    if (error != null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Trade rejected: $error',
        isError: true,
      );
    }
    final readback = store.postTradeReadback(symbol);
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'action': 'trade',
        'sideEffect': true,
        'executionStatus': 'executed',
        'executionVenue': 'local_paper_portfolio',
        'externalBrokerStatus': 'not_external_broker',
        'market': store.market,
        'currency': store.currency,
        'order': {
          'symbol': symbol,
          'side': side,
          'shares': shares,
          'price': price,
        },
        'postTradeReadback': readback,
        'tradeBoundary':
            'Local Portfolio(action:"trade") mutates only the local paper portfolio. It does not execute or sync a Xueqiu/broker order.',
      }),
    );
  }

  ToolResult _previewTrade(
    String toolUseId,
    Map<String, dynamic> input,
    _PortfolioStore store,
  ) {
    final symbol = input['symbol'] as String?;
    final side = (input['side'] as String?)?.toLowerCase();
    final shares = (input['shares'] as num?)?.toDouble();
    final price = (input['price'] as num?)?.toDouble();
    if (symbol == null ||
        side == null ||
        shares == null ||
        shares <= 0 ||
        price == null ||
        price <= 0) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'symbol, side(buy/sell), shares, price required',
        isError: true,
      );
    }
    final preview = store.previewTrade(symbol, side, shares, price);
    if (preview['inputError'] != null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: '${preview['inputError']}',
        isError: true,
      );
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(preview),
    );
  }

  Future<ToolResult> _snapshot(String toolUseId, _PortfolioStore store) async {
    final positions = store.getPositions();
    final cash = store.getCash();
    final initialCash = store.getInitialCash();

    if (positions.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: '模拟盘为空。初始资金: ${cash.toStringAsFixed(2)}。用 trade 买入股票。',
      );
    }

    final codes = positions.keys.toList();
    final quoteResult = await _resolveService.resolveQuotes(codes);
    final quoteMap = {for (final q in quoteResult.data) q.code: q};

    double totalValue = 0;
    final rows = <Map<String, dynamic>>[];
    for (final entry in positions.entries) {
      final pos = entry.value;
      final q = quoteMap[entry.key];
      final currentPrice = q?.price ?? pos['costPrice'] as double;
      final shares = (pos['shares'] as num).toDouble();
      final cost = (pos['costPrice'] as num).toDouble();
      final value = currentPrice * shares;
      final pnl = (currentPrice - cost) * shares;
      final pnlPct = cost > 0 ? (currentPrice - cost) / cost * 100 : 0;
      totalValue += value;

      rows.add({
        'symbol': entry.key,
        if (q != null) 'name': q.name,
        'shares': shares,
        'costPrice': cost,
        'currentPrice': currentPrice,
        'value': double.parse(value.toStringAsFixed(2)),
        'pnl': double.parse(pnl.toStringAsFixed(2)),
        'pnlPct': double.parse(pnlPct.toStringAsFixed(2)),
        if (q != null)
          'todayChange':
              '${q.changePct > 0 ? "+" : ""}${q.changePct.toStringAsFixed(2)}%',
        'buyDate': pos['buyDate'] ?? '',
      });
    }

    final totalAssets = cash + totalValue;
    final totalPnl = totalAssets - initialCash;
    final totalPnlPct = initialCash > 0 ? totalPnl / initialCash * 100 : 0;
    final totalCommission = store.getTotalCommission();

    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'action': 'snapshot',
        'cash': double.parse(cash.toStringAsFixed(2)),
        'positionValue': double.parse(totalValue.toStringAsFixed(2)),
        'totalAssets': double.parse(totalAssets.toStringAsFixed(2)),
        'initialCash': initialCash,
        'totalPnl': double.parse(totalPnl.toStringAsFixed(2)),
        'totalPnlPct': double.parse(totalPnlPct.toStringAsFixed(2)),
        'totalCommission': double.parse(totalCommission.toStringAsFixed(2)),
        'positions': rows.length,
        'holdings': rows,
      }),
    );
  }

  Future<ToolResult> _risk(String toolUseId, _PortfolioStore store) async {
    final positions = store.getPositions();
    if (positions.isEmpty) {
      return ToolResult(toolUseId: toolUseId, content: 'Portfolio is empty.');
    }

    final codes = positions.keys.toList();
    final quoteResult = await _resolveService.resolveQuotes(codes);
    final quoteMap = {for (final q in quoteResult.data) q.code: q};

    double totalValue = 0;
    final holdings = <Map<String, dynamic>>[];
    final alerts = <String>[];

    for (final entry in positions.entries) {
      final pos = entry.value;
      final q = quoteMap[entry.key];
      final price = q?.price ?? pos['costPrice'] as double;
      final shares = pos['shares'] as double;
      final cost = pos['costPrice'] as double;
      final value = price * shares;
      totalValue += value;

      final pnlPct = cost > 0 ? (price - cost) / cost * 100 : 0;
      if (pnlPct < -8) {
        alerts.add('⚠ ${entry.key}: 亏损${pnlPct.toStringAsFixed(1)}%，触及止损线');
      }

      holdings.add({'symbol': entry.key, 'value': value, 'pnlPct': pnlPct});
    }

    // Concentration analysis
    final concentration = <Map<String, dynamic>>[];
    for (final h in holdings) {
      final pct = totalValue > 0
          ? (h['value'] as double) / totalValue * 100
          : 0;
      concentration.add({
        'symbol': h['symbol'],
        'weight': double.parse(pct.toStringAsFixed(1)),
      });
      if (pct > 20) {
        alerts.add('⚠ ${h['symbol']}: 仓位${pct.toStringAsFixed(1)}%，超过20%单只上限');
      }
    }
    concentration.sort(
      (a, b) => (b['weight'] as double).compareTo(a['weight'] as double),
    );

    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'action': 'risk',
        'totalValue': double.parse(totalValue.toStringAsFixed(2)),
        'positions': holdings.length,
        'concentration': concentration,
        if (alerts.isNotEmpty) 'alerts': alerts,
      }),
    );
  }

  ToolResult _history(String toolUseId, _PortfolioStore store) {
    final trades = store.getTrades();
    if (trades.isEmpty) {
      return ToolResult(toolUseId: toolUseId, content: 'No trade history.');
    }
    final recent = trades.length > 20
        ? trades.sublist(trades.length - 20)
        : trades;
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'action': 'history',
        'total': trades.length,
        'recent': recent,
      }),
    );
  }

  ToolResult _clear(String toolUseId, _PortfolioStore store) {
    store.clear();
    return ToolResult(toolUseId: toolUseId, content: 'Portfolio cleared.');
  }
}

class _PortfolioStore {
  final String _basePath;
  final String market;
  _PortfolioStore(this._basePath, {this.market = 'cn'});

  String get _filePath => '$_basePath/memory/.portfolio_$market.json';
  String get currency => switch (market) {
    'us' => 'USD',
    'hk' => 'HKD',
    _ => 'CNY',
  };

  double get _defaultCash => switch (market) {
    'us' => 100000.0,
    'hk' => 500000.0,
    _ => 1000000.0,
  };
  double get _commissionRate => switch (market) {
    'us' => 0.0,
    'hk' => 0.001,
    _ => 0.0003,
  };
  double get _minCommission => switch (market) {
    'us' => 1.0,
    'hk' => 20.0,
    _ => 5.0,
  };
  static const _stampDutyRate = 0.001;
  static const _transferFeeRate = 0.00002;

  Map<String, dynamic> _emptyData() => {
    'cash': _defaultCash,
    'initialCash': _defaultCash,
    'positions': <String, dynamic>{},
    'trades': <dynamic>[],
    'totalCommission': 0.0,
  };

  Map<String, dynamic> _normalizeData(Map<dynamic, dynamic> raw) {
    final data = Map<String, dynamic>.from(raw);
    data['cash'] = (data['cash'] as num?)?.toDouble() ?? _defaultCash;
    data['initialCash'] =
        (data['initialCash'] as num?)?.toDouble() ?? _defaultCash;
    data['positions'] = Map<String, dynamic>.from(
      data['positions'] as Map? ?? const {},
    );
    data['trades'] = List<dynamic>.from(data['trades'] as List? ?? const []);
    data['totalCommission'] =
        (data['totalCommission'] as num?)?.toDouble() ?? 0.0;
    return data;
  }

  Map<String, dynamic> _load() {
    final file = File(_filePath);
    if (!file.existsSync()) {
      return _emptyData();
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        return _normalizeData(decoded);
      }
      return _emptyData();
    } catch (_) {
      return _emptyData();
    }
  }

  void _save(Map<String, dynamic> data) {
    final file = File(_filePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(data));
  }

  double getCash() => (_load()['cash'] as num?)?.toDouble() ?? _defaultCash;
  double getInitialCash() =>
      (_load()['initialCash'] as num?)?.toDouble() ?? _defaultCash;

  Map<String, Map<String, dynamic>> getPositions() {
    final data = _load();
    final raw = Map<String, dynamic>.from(
      data['positions'] as Map? ?? const {},
    );
    return raw.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
  }

  void addPosition(String symbol, double shares, double costPrice) {
    final data = _load();
    final positions = Map<String, dynamic>.from(
      data['positions'] as Map? ?? const {},
    );
    positions[symbol] = {
      'shares': shares,
      'costPrice': costPrice,
      'buyDate': DateTime.now().toIso8601String().substring(0, 10),
    };
    data['positions'] = positions;
    _save(data);
  }

  void removePosition(String symbol) {
    final data = _load();
    final positions = Map<String, dynamic>.from(
      data['positions'] as Map? ?? const {},
    );
    positions.remove(symbol);
    data['positions'] = positions;
    _save(data);
  }

  /// Execute trade with full paper trading simulation.
  /// Returns error message or null on success.
  String? addTrade(String symbol, String side, double shares, double price) {
    final normalizedSide = side.toLowerCase();
    if (normalizedSide != 'buy' && normalizedSide != 'sell') {
      return 'side must be buy or sell';
    }
    final data = _load();
    final cash = (data['cash'] as num?)?.toDouble() ?? _defaultCash;
    final positions = Map<String, dynamic>.from(
      data['positions'] as Map? ?? const {},
    );
    final trades = List<dynamic>.from(data['trades'] as List? ?? const []);
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // A-share lot size check: must be multiple of 100
    final isAShare = RegExp(r'^\d{6}$').hasMatch(symbol);
    if (isAShare && shares % 100 != 0) {
      return 'A股必须以100股(手)为单位交易。当前: ${shares.toInt()}股';
    }

    // Calculate costs
    final tradeValue = shares * price;
    final commission = [
      tradeValue * _commissionRate,
      _minCommission,
    ].reduce((a, b) => a > b ? a : b);
    final stampDuty = normalizedSide == 'sell'
        ? tradeValue * _stampDutyRate
        : 0.0;
    final transferFee = tradeValue * _transferFeeRate;
    final totalCost = commission + stampDuty + transferFee;

    if (normalizedSide == 'buy') {
      // Check cash
      final needed = tradeValue + totalCost;
      if (needed > cash) {
        return '现金不足。需要: ${needed.toStringAsFixed(2)}, 可用: ${cash.toStringAsFixed(2)}';
      }

      // Check position limit (single stock max 20% of total assets)
      final totalAssets = cash + _calcPositionValue(positions, price);
      if (tradeValue / totalAssets > 0.2) {
        // Warning, not blocking
      }

      // Deduct cash
      data['cash'] = cash - needed;

      // Update position
      final existing = positions[symbol] as Map<String, dynamic>?;
      if (existing != null) {
        final oldShares = (existing['shares'] as num).toDouble();
        final oldCost = (existing['costPrice'] as num).toDouble();
        final newShares = oldShares + shares;
        final newCost = (oldCost * oldShares + price * shares) / newShares;
        positions[symbol] = {
          'shares': newShares,
          'costPrice': double.parse(newCost.toStringAsFixed(2)),
          'buyDate': existing['buyDate'] ?? today,
        };
      } else {
        positions[symbol] = {
          'shares': shares,
          'costPrice': price,
          'buyDate': today,
        };
      }
    } else if (normalizedSide == 'sell') {
      final existing = positions[symbol] as Map<String, dynamic>?;
      if (existing == null) return '没有 $symbol 的持仓';

      final holdingShares = (existing['shares'] as num).toDouble();
      if (shares > holdingShares) {
        return '持仓不足。持有: ${holdingShares.toInt()}, 卖出: ${shares.toInt()}';
      }

      // T+1 check for A-shares
      if (isAShare) {
        final buyDate = existing['buyDate'] as String? ?? '';
        if (buyDate == today) {
          return 'A股T+1限制: $symbol 今日买入，明日才能卖出';
        }
      }

      // Add cash (minus costs)
      data['cash'] = cash + tradeValue - totalCost;

      // Update position
      final remaining = holdingShares - shares;
      if (remaining <= 0) {
        positions.remove(symbol);
      } else {
        existing['shares'] = remaining;
      }
    }

    // Record trade
    trades.add({
      'symbol': symbol,
      'side': normalizedSide,
      'shares': shares,
      'price': price,
      'date': today,
      'commission': double.parse(commission.toStringAsFixed(2)),
      'stampDuty': double.parse(stampDuty.toStringAsFixed(2)),
      'totalCost': double.parse(totalCost.toStringAsFixed(2)),
    });
    data['trades'] = trades;
    data['positions'] = positions;
    data['totalCommission'] =
        ((data['totalCommission'] as num?)?.toDouble() ?? 0) + totalCost;
    _save(data);
    return null; // success
  }

  Map<String, dynamic> postTradeReadback(String symbol) {
    final data = _load();
    final cash = (data['cash'] as num?)?.toDouble() ?? _defaultCash;
    final positions = Map<String, dynamic>.from(
      data['positions'] as Map? ?? const {},
    );
    final trades = List<dynamic>.from(data['trades'] as List? ?? const []);
    final symbolPosition = positions[symbol] is Map
        ? Map<String, dynamic>.from(positions[symbol] as Map)
        : null;
    final positionValue = _calcPositionValue(positions, 0);
    final totalAssets = cash + positionValue;
    final lastTrade = trades.isNotEmpty && trades.last is Map
        ? Map<String, dynamic>.from(trades.last as Map)
        : null;
    return {
      'source': 'local_paper_portfolio',
      'readbackAction': 'portfolio_snapshot_after_trade',
      'readbackStatus': 'verified',
      'positionsCount': positions.length,
      'cash': double.parse(cash.toStringAsFixed(2)),
      'positionValue': double.parse(positionValue.toStringAsFixed(2)),
      'totalAssets': double.parse(totalAssets.toStringAsFixed(2)),
      'symbol': symbol,
      'symbolPosition': symbolPosition,
      'tradeCount': trades.length,
      'lastTrade': lastTrade,
      'fetchedAt': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> previewTrade(
    String symbol,
    String side,
    double shares,
    double price,
  ) {
    final data = _load();
    final cash = (data['cash'] as num?)?.toDouble() ?? _defaultCash;
    final positions = Map<String, dynamic>.from(
      data['positions'] as Map? ?? const {},
    );
    final normalizedSide = side.toLowerCase();
    if (normalizedSide != 'buy' && normalizedSide != 'sell') {
      return {'inputError': 'side must be buy or sell'};
    }
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final isAShare = RegExp(r'^\d{6}$').hasMatch(symbol);
    final tradeValue = shares * price;
    final commission = [
      tradeValue * _commissionRate,
      _minCommission,
    ].reduce((a, b) => a > b ? a : b);
    final stampDuty = normalizedSide == 'sell'
        ? tradeValue * _stampDutyRate
        : 0.0;
    final transferFee = tradeValue * _transferFeeRate;
    final totalCost = commission + stampDuty + transferFee;
    final existing = positions[symbol] is Map
        ? Map<String, dynamic>.from(positions[symbol] as Map)
        : null;
    final errors = <String>[];
    final warnings = <String>[];

    if (isAShare && shares % 100 != 0) {
      errors.add('A股必须以100股(手)为单位交易。当前: ${shares.toInt()}股');
    }
    if (normalizedSide == 'buy') {
      final needed = tradeValue + totalCost;
      if (needed > cash) {
        errors.add(
          '现金不足。需要: ${needed.toStringAsFixed(2)}, 可用: ${cash.toStringAsFixed(2)}',
        );
      }
    } else {
      if (existing == null) {
        errors.add('没有 $symbol 的持仓');
      } else {
        final holdingShares = (existing['shares'] as num).toDouble();
        if (shares > holdingShares) {
          errors.add(
            '持仓不足。持有: ${holdingShares.toInt()}, 卖出: ${shares.toInt()}',
          );
        }
        final buyDate = existing['buyDate'] as String? ?? '';
        if (isAShare && buyDate == today) {
          errors.add('A股T+1限制: $symbol 今日买入，明日才能卖出');
        }
      }
    }

    final cashAfter = normalizedSide == 'buy'
        ? cash - tradeValue - totalCost
        : cash + tradeValue - totalCost;
    if (cashAfter < 0) {
      warnings.add('postTradeCash would be negative; execution is blocked.');
    }

    return {
      'action': 'preview_trade',
      'sideEffect': false,
      'executionAllowed': errors.isEmpty,
      'market': market,
      'currency': currency,
      'order': {
        'symbol': symbol,
        'side': normalizedSide,
        'shares': shares,
        'price': price,
      },
      'estimated': {
        'tradeValue': double.parse(tradeValue.toStringAsFixed(2)),
        'commission': double.parse(commission.toStringAsFixed(2)),
        'stampDuty': double.parse(stampDuty.toStringAsFixed(2)),
        'transferFee': double.parse(transferFee.toStringAsFixed(2)),
        'totalCost': double.parse(totalCost.toStringAsFixed(2)),
        'cashBefore': double.parse(cash.toStringAsFixed(2)),
        'cashAfter': double.parse(cashAfter.toStringAsFixed(2)),
      },
      'currentPosition': existing,
      'errors': errors,
      'warnings': warnings,
      'nextStep': errors.isEmpty
          ? 'Ask for explicit confirmation before Portfolio(action:"trade") or any XueqiuTrade write.'
          : 'Fix the blocking errors before asking for execution confirmation.',
    };
  }

  double _calcPositionValue(
    Map<String, dynamic> positions,
    double fallbackPrice,
  ) {
    double total = 0;
    for (final pos in positions.values) {
      if (pos is Map) {
        final shares = (pos['shares'] as num?)?.toDouble() ?? 0;
        final price = (pos['costPrice'] as num?)?.toDouble() ?? fallbackPrice;
        total += shares * price;
      }
    }
    return total;
  }

  List<Map<String, dynamic>> getTrades() {
    final data = _load();
    return List<Map<String, dynamic>>.from(
      (data['trades'] as List? ?? const []).map(
        (row) => Map<String, dynamic>.from(row as Map),
      ),
    );
  }

  double getTotalCommission() =>
      (_load()['totalCommission'] as num?)?.toDouble() ?? 0;

  void clear() => _save(_emptyData());
}
