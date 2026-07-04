import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data_fetcher/api_stats.dart';
import '../../data_fetcher/http_utils.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class XueqiuTradeTool extends Tool {
  XueqiuTradeTool({required this.cookie, required this.portfolioCodes});

  final String cookie;
  final List<String> portfolioCodes;

  static const _webBaseUrl = 'https://xueqiu.com';
  static const _stockBaseUrl = 'https://stock.xueqiu.com';
  static const _snowxBaseUrl = 'https://tc.xueqiu.com/tc/snowx';
  static Map<String, String> get _headers => {
    'User-Agent': configuredHttpUserAgent(),
    'Origin': 'https://xueqiu.com',
    'Referer': 'https://xueqiu.com/performance',
  };
  static const _minInterval = Duration(milliseconds: 300);
  DateTime _lastRequest = DateTime(2000);

  @override
  String get name => 'XueqiuTrade';

  @override
  String get description =>
      'Xueqiu simulated trading through the current MONI contract: discover portfolios, inspect holdings/performance, place buy/sell trades, and add cash transfers.';

  @override
  String get prompt {
    final portfolios = portfolioCodes.isEmpty
        ? '(未配置)'
        : portfolioCodes.join(', ');
    return '''雪球模拟交易（MONI 合同）。

已配置组合: $portfolios

- help — 帮助
- portfolios — 读取雪球模拟组合列表，返回 name/gid 映射
- balance — 读取组合总资产/现金/市值/盈亏
- position — 读取组合持仓与收益构成
- history — 读取最近股票交易和银证转账记录
- preview_order — 校验并估算订单，不写入雪球
- buy — 模拟买入。需要 symbol / shares / price
- sell — 模拟卖出。需要 symbol / shares / price
- transfer_in — 模拟转入现金。需要 amount
- transfer_out — 模拟转出现金。需要 amount

可选参数:
- portfolio: 组合名称或 gid；默认使用第一个已配置组合
- date: YYYY-MM-DD；默认今天
- commission_rate / tax_rate: 默认 1
- market: 转账市场，默认 CHA

仓位合同:
- MONI 当前实测合同使用显式 shares；不要把本地 Portfolio 的 A 股 100 股规则套用到 XueqiuTrade 仓位测算。
- 如果用户只要求测算，或明确说不要交易，仅读取 portfolios / balance / position / quote 后给出计算；不要询问执行确认，不要 preview、buy、sell 或 transfer。
- 如果用户之后明确授权执行，先调用 preview_order，并以 provider 返回结果判断该股数是否可执行。

示例:
XueqiuTrade(action:"portfolios")
XueqiuTrade(action:"balance", portfolio:"finasimu")
XueqiuTrade(action:"preview_order", portfolio:"finasimu", side:"buy", symbol:"SH600519", shares:5, price:1215)
XueqiuTrade(action:"buy", portfolio:"finasimu", symbol:"SH600519", shares:5, price:1215)
XueqiuTrade(action:"transfer_in", portfolio:"finasimu", amount:10000)''';
  }

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': [
          'help',
          'portfolios',
          'balance',
          'position',
          'history',
          'preview_order',
          'buy',
          'sell',
          'transfer_in',
          'transfer_out',
        ],
      },
      'portfolio': {
        'type': 'string',
        'description':
            'Portfolio name or gid. Defaults to first configured one.',
      },
      'side': {
        'type': 'string',
        'description': '(preview_order) Order side: buy or sell.',
      },
      'symbol': {
        'type': 'string',
        'description': 'Stock symbol, e.g. SH600519 or AAPL.',
      },
      'shares': {'type': 'number', 'description': 'Trade shares for buy/sell.'},
      'price': {'type': 'number', 'description': 'Trade price for buy/sell.'},
      'amount': {
        'type': 'number',
        'description': 'Cash amount for transfer_in / transfer_out.',
      },
      'date': {
        'type': 'string',
        'description':
            'Trade or transfer date in YYYY-MM-DD. Defaults to today.',
      },
      'market': {
        'type': 'string',
        'description': 'Transfer market code. Defaults to CHA.',
      },
      'commission_rate': {
        'type': 'number',
        'description': 'Commission rate. Defaults to 1.',
      },
      'tax_rate': {'type': 'number', 'description': 'Tax rate. Defaults to 1.'},
      'row': {
        'type': 'number',
        'description': 'History row limit. Defaults to 20.',
      },
    },
    'required': ['action'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) {
    final action = input['action'] as String? ?? 'help';
    return action == 'buy' ||
        action == 'sell' ||
        action == 'transfer_in' ||
        action == 'transfer_out';
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = input['action'] as String? ?? 'help';
    try {
      return switch (action) {
        'help' => ToolResult(toolUseId: toolUseId, content: prompt),
        'portfolios' => await _portfolios(toolUseId),
        'balance' => await _balance(toolUseId, input),
        'position' => await _position(toolUseId, input),
        'history' => await _history(toolUseId, input),
        'preview_order' => await _previewOrder(toolUseId, input),
        'buy' => await _trade(toolUseId, input, 1),
        'sell' => await _trade(toolUseId, input, 2),
        'transfer_in' => await _transfer(toolUseId, input, 1),
        'transfer_out' => await _transfer(toolUseId, input, 2),
        _ => ToolResult(
          toolUseId: toolUseId,
          content: 'Unknown action "$action". Use help.',
          isError: true,
        ),
      };
    } catch (e) {
      return ToolResult(toolUseId: toolUseId, content: '$e', isError: true);
    }
  }

  Future<ToolResult> _portfolios(String toolUseId) async {
    final groups = await _loadGroups();
    final configured = portfolioCodes.toSet();
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'source': 'xueqiu',
        'tradeContract': _tradeContract(),
        'configured': portfolioCodes,
        'portfolios': groups
            .map(
              (g) => {
                'name': g.name,
                'gid': g.gid,
                'configured':
                    configured.contains(g.name) ||
                    configured.contains(g.gid.toString()),
                'openStatus': g.openStatus,
                'order': g.orderId,
              },
            )
            .toList(),
      }),
    );
  }

  Future<ToolResult> _balance(
    String toolUseId,
    Map<String, dynamic> input,
  ) async {
    final group = await _resolvePortfolio(input);
    final payload = await _getJson(
      _snowxUri('/MONI/performances.json', {'gid': '${group.gid}'}),
    );
    final performances =
        ((payload['result_data'] as Map?)?['performances'] as List?) ?? [];
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'source': 'xueqiu',
        'tradeContract': _tradeContract(),
        'portfolio': {'name': group.name, 'gid': group.gid},
        'performances': performances,
      }),
    );
  }

  Future<ToolResult> _position(
    String toolUseId,
    Map<String, dynamic> input,
  ) async {
    final group = await _resolvePortfolio(input);
    final holdings = await _getJson(
      _snowxUri('/MONI/forchart/holdstock.json', {
        'gid': '${group.gid}',
        'period': '1m',
      }),
    );
    final roa = await _getJson(
      _snowxUri('/MONI/forchart/roa.json', {
        'gid': '${group.gid}',
        'period': '1m',
        'market': 'ALL',
      }),
    );
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'source': 'xueqiu',
        'tradeContract': _tradeContract(),
        'portfolio': {'name': group.name, 'gid': group.gid},
        'holdstock': (holdings['result_data'] as List?) ?? [],
        'roa': (roa['result_data'] as Map?) ?? {},
      }),
    );
  }

  Future<ToolResult> _history(
    String toolUseId,
    Map<String, dynamic> input,
  ) async {
    final group = await _resolvePortfolio(input);
    final row = ((input['row'] as num?)?.toInt() ?? 20).clamp(1, 1000);
    final symbol = (input['symbol'] as String?)?.trim();
    final txParams = <String, String>{'gid': '${group.gid}', 'row': '$row'};
    if (symbol != null && symbol.isNotEmpty) {
      txParams['symbol'] = _normalizeSymbol(symbol);
    }
    final transactions = await _getJson(
      _snowxUri('/MONI/transaction/list.json', txParams),
    );
    final transfers = await _getJson(
      _snowxUri('/MONI/bank_transfer/query.json', {
        'gid': '${group.gid}',
        'row': '$row',
      }),
    );
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'source': 'xueqiu',
        'tradeContract': _tradeContract(),
        'portfolio': {'name': group.name, 'gid': group.gid},
        'transactions': _withReadableTimes(
          (transactions['result_data'] as Map?) ?? {},
        ),
        'bankTransfers': _withReadableTimes(
          (transfers['result_data'] as Map?) ?? {},
        ),
      }),
    );
  }

  Future<ToolResult> _previewOrder(
    String toolUseId,
    Map<String, dynamic> input,
  ) async {
    final group = await _resolvePortfolio(input);
    final rawSide = '${input['side'] ?? input['orderSide'] ?? ''}'
        .trim()
        .toLowerCase();
    final type = rawSide == 'buy' || rawSide == '1'
        ? 1
        : rawSide == 'sell' || rawSide == '2'
        ? 2
        : 0;
    final symbol = input['symbol'] as String?;
    final shares = (input['shares'] as num?)?.toDouble();
    final price = (input['price'] as num?)?.toDouble();
    if (type == 0 ||
        symbol == null ||
        symbol.trim().isEmpty ||
        shares == null ||
        shares <= 0 ||
        price == null ||
        price <= 0) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'side(buy/sell), symbol, shares, and price are required. Example: XueqiuTrade(action:"preview_order", portfolio:"finasimu", side:"buy", symbol:"SH600519", shares:5, price:1215)',
        isError: true,
      );
    }
    final normalizedSymbol = _normalizeSymbol(symbol);
    final warnings = <String>[];
    await _tryPreviewEvidence(
      'search_symbol',
      warnings,
      () => _searchSymbol(normalizedSymbol),
    );
    await _tryPreviewEvidence(
      'quote',
      warnings,
      () => _loadQuote(normalizedSymbol),
    );
    final balancePayload = await _tryPreviewEvidence(
      'balance',
      warnings,
      () => _getJson(
        _snowxUri('/MONI/performances.json', {'gid': '${group.gid}'}),
      ),
    );
    final holdings = await _tryPreviewEvidence(
      'position',
      warnings,
      () => _getJson(
        _snowxUri('/MONI/forchart/holdstock.json', {
          'gid': '${group.gid}',
          'period': '1m',
        }),
      ),
    );
    final tradeValue = shares * price;
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'source': 'xueqiu',
        'action': 'preview_order',
        'tradeContract': _tradeContract(),
        'sideEffect': false,
        'portfolio': {'name': group.name, 'gid': group.gid},
        'order': {
          'side': type == 1 ? 'buy' : 'sell',
          'symbol': normalizedSymbol,
          'shares': shares,
          'price': price,
          'date': _resolveDate(input['date'] as String?),
          'commission_rate': (input['commission_rate'] as num?) ?? 1,
          'tax_rate': (input['tax_rate'] as num?) ?? 1,
        },
        'estimated': {
          'tradeValue': double.parse(tradeValue.toStringAsFixed(2)),
          'note':
              'Xueqiu computes final commission/tax on write; preview does not call transaction/add.json.',
        },
        'readbackEvidence': {
          'balance': {
            'source': 'xueqiu',
            'portfolio': {'name': group.name, 'gid': group.gid},
            'performances':
                ((balancePayload?['result_data'] as Map?)?['performances']
                    as List?) ??
                [],
          },
          'position': {
            'source': 'xueqiu',
            'portfolio': {'name': group.name, 'gid': group.gid},
            'holdstock': (holdings?['result_data'] as List?) ?? [],
          },
        },
        'warnings': warnings,
        'nextStep':
            'If execution is still intended, ask for explicit confirmation before XueqiuTrade(action:"buy"|"sell").',
      }),
    );
  }

  Future<T?> _tryPreviewEvidence<T>(
    String label,
    List<String> warnings,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } catch (e) {
      warnings.add('$label: $e');
      return null;
    }
  }

  Map<String, dynamic> _tradeContract() => {
    'executionSurface': 'xueqiu_moni_simulated_trade',
    'shareSizing': 'explicit_shares',
    'lotSize': 1,
    'sizingOnlyBehavior':
        'answer_without_preview_or_write_when_user_says_not_to_trade',
    'sizingGuidance': [
      'For MONI sizing, cash can be mapped to any positive explicit share count such as 5, 8, 16, or 83 when price and cash allow it.',
      'Do not claim a portfolio cannot buy only because it cannot afford 100 shares; that is a local Portfolio or real-market assumption, not this XueqiuTrade contract.',
      'For sizing-only requests, give candidate share counts and the next confirmation fields without calling AskUserQuestion.',
    ],
    'writeActions': ['buy', 'sell', 'transfer_in', 'transfer_out'],
    'writeRequires': ['explicit_user_authorization', 'preview_order_before_write'],
    'localPortfolioLotRuleApplies': false,
  };

  Future<ToolResult> _trade(
    String toolUseId,
    Map<String, dynamic> input,
    int type,
  ) async {
    final group = await _resolvePortfolio(input);
    final symbol = input['symbol'] as String?;
    final shares = (input['shares'] as num?)?.toDouble();
    final price = (input['price'] as num?)?.toDouble();
    if (symbol == null ||
        symbol.trim().isEmpty ||
        shares == null ||
        price == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'symbol / shares / price are required. Example: XueqiuTrade(action:"buy", portfolio:"finasimu", symbol:"SH600519", shares:5, price:1215)',
        isError: true,
      );
    }
    final normalizedSymbol = _normalizeSymbol(symbol);
    await _searchSymbol(normalizedSymbol);
    await _loadQuote(normalizedSymbol);
    final payload =
        await _postJson(Uri.parse('$_snowxBaseUrl/MONI/transaction/add.json'), {
          'type': '$type',
          'date': _resolveDate(input['date'] as String?),
          'gid': '${group.gid}',
          'symbol': normalizedSymbol,
          'price': _formatNumber(price),
          'shares': _formatNumber(shares),
          'tax_rate': '${(input['tax_rate'] as num?) ?? 1}',
          'commission_rate': '${(input['commission_rate'] as num?) ?? 1}',
        });
    final readback = await _postWriteReadback(
      group,
      kind: _XueqiuWriteKind.trade,
      symbol: normalizedSymbol,
      row: 100,
    );
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'source': 'xueqiu',
        'portfolio': {'name': group.name, 'gid': group.gid},
        'action': type == 1 ? 'buy' : 'sell',
        'sideEffect': true,
        'executionStatus': 'executed',
        'executionVenue': 'xueqiu_moni',
        'result': payload['result_data'],
        'message': payload['msg'],
        'postTradeReadback': readback,
      }),
    );
  }

  Future<ToolResult> _transfer(
    String toolUseId,
    Map<String, dynamic> input,
    int type,
  ) async {
    final group = await _resolvePortfolio(input);
    final amount = (input['amount'] as num?)?.toDouble();
    if (amount == null || amount <= 0) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'amount is required. Example: XueqiuTrade(action:"transfer_in", portfolio:"finasimu", amount:10000)',
        isError: true,
      );
    }
    final payload = await _postJson(
      Uri.parse('$_snowxBaseUrl/MONI/bank_transfer/add.json'),
      {
        'gid': '${group.gid}',
        'type': '$type',
        'date': _resolveDate(input['date'] as String?),
        'market': (input['market'] as String?)?.trim().isNotEmpty == true
            ? (input['market'] as String).trim()
            : 'CHA',
        'amount': _formatNumber(amount),
      },
    );
    final readback = await _postWriteReadback(
      group,
      kind: _XueqiuWriteKind.transfer,
      row: 100,
    );
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'source': 'xueqiu',
        'portfolio': {'name': group.name, 'gid': group.gid},
        'action': type == 1 ? 'transfer_in' : 'transfer_out',
        'sideEffect': true,
        'executionStatus': 'executed',
        'executionVenue': 'xueqiu_moni',
        'result': payload['result_data'],
        'message': payload['msg'],
        'postTradeReadback': readback,
      }),
    );
  }

  Future<Map<String, dynamic>> _postWriteReadback(
    _PortfolioGroup group, {
    required _XueqiuWriteKind kind,
    String? symbol,
    int row = 100,
  }) async {
    final warnings = <String>[];
    final boundedRow = row.clamp(1, 1000);
    final balance = await _tryPreviewEvidence(
      'balance_after_write',
      warnings,
      () => _getJson(
        _snowxUri('/MONI/performances.json', {'gid': '${group.gid}'}),
      ),
    );
    final txParams = <String, String>{
      'gid': '${group.gid}',
      'row': '$boundedRow',
    };
    if (symbol != null && symbol.trim().isNotEmpty) {
      txParams['symbol'] = _normalizeSymbol(symbol);
    }
    final transactions = await _tryPreviewEvidence(
      'history_after_write_transactions',
      warnings,
      () => _getJson(_snowxUri('/MONI/transaction/list.json', txParams)),
    );
    final transfers = await _tryPreviewEvidence(
      'history_after_write_transfers',
      warnings,
      () => _getJson(
        _snowxUri('/MONI/bank_transfer/query.json', {
          'gid': '${group.gid}',
          'row': '$boundedRow',
        }),
      ),
    );
    Map<String, dynamic>? position;
    if (kind == _XueqiuWriteKind.trade) {
      final holdings = await _tryPreviewEvidence(
        'position_after_write_holdstock',
        warnings,
        () => _getJson(
          _snowxUri('/MONI/forchart/holdstock.json', {
            'gid': '${group.gid}',
            'period': '1m',
          }),
        ),
      );
      final roa = await _tryPreviewEvidence(
        'position_after_write_roa',
        warnings,
        () => _getJson(
          _snowxUri('/MONI/forchart/roa.json', {
            'gid': '${group.gid}',
            'period': '1m',
            'market': 'ALL',
          }),
        ),
      );
      position = {
        'source': 'xueqiu',
        'portfolio': {'name': group.name, 'gid': group.gid},
        'holdstock': (holdings?['result_data'] as List?) ?? [],
        'roa': (roa?['result_data'] as Map?) ?? {},
      };
    }
    return {
      'source': 'xueqiu',
      'readbackAction': kind == _XueqiuWriteKind.trade
          ? 'xueqiu_trade_balance_position_history_after_write'
          : 'xueqiu_transfer_balance_history_after_write',
      'readbackStatus': warnings.isEmpty ? 'verified' : 'partial',
      'portfolio': {'name': group.name, 'gid': group.gid},
      'balance': {
        'source': 'xueqiu',
        'portfolio': {'name': group.name, 'gid': group.gid},
        'performances':
            ((balance?['result_data'] as Map?)?['performances'] as List?) ?? [],
      },
      'position': position,
      'history': {
        'source': 'xueqiu',
        'portfolio': {'name': group.name, 'gid': group.gid},
        'transactions': _withReadableTimes(
          (transactions?['result_data'] as Map?) ?? {},
        ),
        'bankTransfers': _withReadableTimes(
          (transfers?['result_data'] as Map?) ?? {},
        ),
      },
      'warnings': warnings,
      'fetchedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<List<_PortfolioGroup>> _loadGroups() async {
    final payload = await _getJson(
      _snowxUri('/MONI/trans_group/list.json', {}),
    );
    final list =
        ((payload['result_data'] as Map?)?['trans_groups'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map(
          (raw) => _PortfolioGroup(
            name: '${raw['name'] ?? ''}',
            gid: int.tryParse('${raw['gid'] ?? ''}') ?? 0,
            openStatus: int.tryParse('${raw['open_status'] ?? ''}') ?? 0,
            orderId: int.tryParse('${raw['order_id'] ?? ''}') ?? 0,
          ),
        )
        .where((g) => g.name.isNotEmpty && g.gid > 0)
        .toList();
  }

  Future<_PortfolioGroup> _resolvePortfolio(Map<String, dynamic> input) async {
    final groups = await _loadGroups();
    if (groups.isEmpty) {
      throw Exception('雪球未返回任何模拟组合。');
    }
    final candidates = <String>[
      if ((input['portfolio'] as String?)?.trim().isNotEmpty == true)
        (input['portfolio'] as String).trim(),
      ...portfolioCodes.where((e) => e.trim().isNotEmpty).map((e) => e.trim()),
    ];
    if (candidates.isEmpty) {
      return groups.first;
    }
    for (final candidate in candidates) {
      for (final group in groups) {
        if (group.name == candidate) return group;
      }
      final gid = int.tryParse(candidate);
      if (gid != null) {
        for (final group in groups) {
          if (group.gid == gid) return group;
        }
      }
    }
    throw Exception(
      '未找到组合 "${candidates.first}"。请先调用 XueqiuTrade(action:"portfolios") 查看可用 name/gid。',
    );
  }

  Future<void> _searchSymbol(String symbol) async {
    final payload = await _getJson(
      Uri.parse(
        '$_webBaseUrl/query/v1/search/stock.json',
      ).replace(queryParameters: {'code': symbol, 'size': '10'}),
    );
    final list =
        (payload['stocks'] as List?) ?? (payload['data'] as List?) ?? [];
    if (list.isEmpty) {
      throw Exception('stock not found on Xueqiu: $symbol');
    }
  }

  Future<void> _loadQuote(String symbol) async {
    await _getJson(
      Uri.parse(
        '$_stockBaseUrl/v5/stock/batch/quote.json',
      ).replace(queryParameters: {'symbol': symbol, 'extend': 'detail'}),
    );
  }

  String _normalizeSymbol(String input) {
    final upper = input.trim().toUpperCase();
    if (upper.startsWith('SH') ||
        upper.startsWith('SZ') ||
        upper.startsWith('BJ') ||
        upper.startsWith('HK') ||
        RegExp(r'^[A-Z]+$').hasMatch(upper)) {
      return upper;
    }
    final clean = upper.replaceAll(
      RegExp(r'\.(SH|SZ|BJ|HK)$', caseSensitive: false),
      '',
    );
    if (!RegExp(r'^\d{6}$').hasMatch(clean)) return upper;
    if (clean.startsWith('6') || clean.startsWith('9')) return 'SH$clean';
    if (clean.startsWith('43') ||
        clean.startsWith('83') ||
        clean.startsWith('87') ||
        clean.startsWith('92')) {
      return 'BJ$clean';
    }
    return 'SZ$clean';
  }

  String _resolveDate(String? raw) {
    if (raw != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return raw;
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  String _formatNumber(num value) {
    final asDouble = value.toDouble();
    if (asDouble == asDouble.truncateToDouble()) {
      return asDouble.toInt().toString();
    }
    return asDouble.toString();
  }

  Uri _snowxUri(String path, Map<String, String> params) {
    return Uri.parse('$_snowxBaseUrl$path').replace(queryParameters: params);
  }

  dynamic _withReadableTimes(dynamic value) {
    if (value is List) {
      return value.map(_withReadableTimes).toList();
    }
    if (value is! Map) return value;
    final out = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = '${entry.key}';
      out[key] = _withReadableTimes(entry.value);
      if (key == 'time' ||
          key == 'create_at' ||
          key == 'update_at' ||
          key == 'record_date') {
        final millis = _timestampMillis(entry.value);
        if (millis != null) {
          final utc = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
          final beijing = utc.add(const Duration(hours: 8));
          out['${key}_iso'] = utc.toIso8601String();
          out['${key}_beijing'] =
              '${_pad4(beijing.year)}-${_pad2(beijing.month)}-${_pad2(beijing.day)} '
              '${_pad2(beijing.hour)}:${_pad2(beijing.minute)}:${_pad2(beijing.second)}';
        }
      }
    }
    return out;
  }

  int? _timestampMillis(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && RegExp(r'^\d+$').hasMatch(value)) {
      return int.tryParse(value);
    }
    return null;
  }

  String _pad2(int value) => value.toString().padLeft(2, '0');
  String _pad4(int value) => value.toString().padLeft(4, '0');

  Future<void> _throttle() async {
    final elapsed = DateTime.now().difference(_lastRequest);
    if (elapsed < _minInterval) {
      await Future.delayed(_minInterval - elapsed);
    }
    _lastRequest = DateTime.now();
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    await _throttle();
    final sw = Stopwatch()..start();
    try {
      final resp = await http.get(
        uri,
        headers: {..._headers, 'Cookie': cookie},
      );
      sw.stop();
      if (resp.statusCode != 200) {
        _record('GET', uri, sw.elapsedMilliseconds, false, resp.statusCode);
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      _checkResult(body);
      _record('GET', uri, sw.elapsedMilliseconds, true, 200);
      return body;
    } catch (e) {
      if (sw.isRunning) sw.stop();
      _record('GET', uri, sw.elapsedMilliseconds, false, -1, '$e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, String> body,
  ) async {
    await _throttle();
    final sw = Stopwatch()..start();
    try {
      final resp = await http.post(
        uri,
        headers: {
          ..._headers,
          'Cookie': cookie,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );
      sw.stop();
      if (resp.statusCode != 200) {
        _record('POST', uri, sw.elapsedMilliseconds, false, resp.statusCode);
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }
      final payload = jsonDecode(resp.body) as Map<String, dynamic>;
      _checkResult(payload);
      _record('POST', uri, sw.elapsedMilliseconds, true, 200);
      return payload;
    } catch (e) {
      if (sw.isRunning) sw.stop();
      _record('POST', uri, sw.elapsedMilliseconds, false, -1, '$e');
      rethrow;
    }
  }

  void _record(
    String method,
    Uri uri,
    int durationMs,
    bool success,
    int statusCode, [
    String? error,
  ]) {
    ApiStats.instance.record(
      source: 'xueqiu',
      method: method,
      url: uri.toString(),
      statusCode: statusCode,
      durationMs: durationMs,
      success: success,
      error: error,
    );
  }

  void _checkResult(Map<String, dynamic> body) {
    final success = body['success'];
    final code =
        '${body['result_code'] ?? body['error_code'] ?? body['code'] ?? ''}';
    final msg = '${body['msg'] ?? body['error_description'] ?? ''}'.trim();
    if (code == '400016' || code == 'LOGIN_REQUIRED') {
      throw Exception('雪球 Cookie 已过期，请在设置中更新 XQ_COOKIE');
    }
    if (success == false || (code.isNotEmpty && code != '60000')) {
      throw Exception(
        'Xueqiu API error $code${msg.isNotEmpty ? ': $msg' : ''}',
      );
    }
  }
}

enum _XueqiuWriteKind { trade, transfer }

class _PortfolioGroup {
  const _PortfolioGroup({
    required this.name,
    required this.gid,
    required this.openStatus,
    required this.orderId,
  });

  final String name;
  final int gid;
  final int openStatus;
  final int orderId;
}
