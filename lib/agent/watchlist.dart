import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

class WatchlistAssetSuggestion {
  final String code;
  final String name;
  final String type;
  final String? market;
  final String? company;

  const WatchlistAssetSuggestion({
    required this.code,
    required this.name,
    required this.type,
    this.market,
    this.company,
  });
}

class WatchCondition {
  String field; // price / changePct / volume
  String op; // > / < / >= / <= / ==
  double value;
  String action; // ui_alert / notify_chat / notify_event
  String? message;
  bool triggered;

  WatchCondition({
    required this.field,
    required this.op,
    required this.value,
    this.action = 'ui_alert',
    this.message,
    this.triggered = false,
  });

  Map<String, dynamic> toJson() => {
    'field': field,
    'op': op,
    'value': value,
    'action': action,
    'message': message,
    'triggered': triggered,
  };

  factory WatchCondition.fromJson(Map<String, dynamic> j) => WatchCondition(
    field: j['field'] as String? ?? 'price',
    op: j['op'] as String? ?? '>',
    value: (j['value'] as num?)?.toDouble() ?? 0,
    action: j['action'] as String? ?? 'ui_alert',
    message: j['message'] as String?,
    triggered: j['triggered'] as bool? ?? false,
  );

  bool evaluate(double actual) => switch (op) {
    '>' => actual > value,
    '<' => actual < value,
    '>=' => actual >= value,
    '<=' => actual <= value,
    '==' => (actual - value).abs() < 0.001,
    _ => false,
  };
}

class WatchlistGroup {
  String id;
  String name;
  String type; // stock / fund / custom
  DateTime createdAt;
  int refreshIntervalSec;

  WatchlistGroup({
    String? id,
    required this.name,
    this.type = 'stock',
    DateTime? createdAt,
    this.refreshIntervalSec = 300,
  }) : id = id ?? _genId(),
       createdAt = createdAt ?? DateTime.now();

  static String _genId() => md5
      .convert(utf8.encode('${DateTime.now().microsecondsSinceEpoch}'))
      .toString()
      .substring(0, 8);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'createdAt': createdAt.toIso8601String(),
    'refreshIntervalSec': refreshIntervalSec,
  };

  factory WatchlistGroup.fromJson(Map<String, dynamic> j) => WatchlistGroup(
    id: j['id'] as String?,
    name: j['name'] as String? ?? '',
    type: j['type'] as String? ?? 'stock',
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
    refreshIntervalSec: (j['refreshIntervalSec'] as num?)?.toInt() ?? 300,
  );
}

class WatchlistItem {
  String id;
  String groupId;
  String symbol;
  String name;
  String type; // stock / fund / etf / index
  String status; // watching / entered / exited
  String source; // agent / user / stock-picking / event
  Set<String> tags;
  DateTime addedAt;
  double priceAtAdd;
  int? score;
  String? rating;

  String? entryCondition;
  String? strategyId;
  Map<String, dynamic>? strategyRules;
  double? targetEntryPrice;
  double? stopLoss;
  double? targetPrice;
  double? suggestedWeight;

  double? actualEntryPrice;
  DateTime? enteredAt;
  double? exitPrice;
  DateTime? exitedAt;
  double? profitPct;

  // AI 分析结果缓存
  String? analysisResult;
  DateTime? analysisAt;

  // runtime only — not persisted
  double? currentPrice;
  double? changePct;
  double? volume;
  double? openPrice;
  double? closePrice;
  double? highPrice;
  double? lowPrice;

  // 条件触发 (持久化)
  List<WatchCondition> conditions;

  WatchlistItem({
    String? id,
    required this.groupId,
    required this.symbol,
    this.name = '',
    this.type = 'stock',
    this.status = 'watching',
    this.source = 'user',
    Set<String>? tags,
    DateTime? addedAt,
    this.priceAtAdd = 0,
    this.score,
    this.rating,
    this.entryCondition,
    this.strategyId,
    this.strategyRules,
    this.targetEntryPrice,
    this.stopLoss,
    this.targetPrice,
    this.suggestedWeight,
    this.actualEntryPrice,
    this.enteredAt,
    this.exitPrice,
    this.exitedAt,
    this.profitPct,
    this.analysisResult,
    this.analysisAt,
    List<WatchCondition>? conditions,
  }) : id = id ?? WatchlistGroup._genId(),
       tags = tags ?? {},
       addedAt = addedAt ?? DateTime.now(),
       conditions = conditions ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'symbol': symbol,
    'name': name,
    'type': type,
    'status': status,
    'source': source,
    'tags': tags.toList(),
    'addedAt': addedAt.toIso8601String(),
    'priceAtAdd': priceAtAdd,
    'score': score,
    'rating': rating,
    'entryCondition': entryCondition,
    'strategyId': strategyId,
    'strategyRules': strategyRules,
    'targetEntryPrice': targetEntryPrice,
    'stopLoss': stopLoss,
    'targetPrice': targetPrice,
    'suggestedWeight': suggestedWeight,
    'actualEntryPrice': actualEntryPrice,
    'enteredAt': enteredAt?.toIso8601String(),
    'exitPrice': exitPrice,
    'exitedAt': exitedAt?.toIso8601String(),
    'profitPct': profitPct,
    'analysisResult': analysisResult,
    'analysisAt': analysisAt?.toIso8601String(),
    'conditions': conditions.map((c) => c.toJson()).toList(),
  };

  factory WatchlistItem.fromJson(Map<String, dynamic> j) => WatchlistItem(
    id: j['id'] as String?,
    groupId: j['groupId'] as String? ?? '',
    symbol: j['symbol'] as String? ?? '',
    name: j['name'] as String? ?? '',
    type: j['type'] as String? ?? 'stock',
    status: j['status'] as String? ?? 'watching',
    source: j['source'] as String? ?? 'user',
    tags: (j['tags'] as List?)?.map((e) => e.toString()).toSet(),
    addedAt: DateTime.tryParse(j['addedAt'] as String? ?? ''),
    priceAtAdd: (j['priceAtAdd'] as num?)?.toDouble() ?? 0,
    score: (j['score'] as num?)?.toInt(),
    rating: j['rating'] as String?,
    entryCondition: j['entryCondition'] as String?,
    strategyId: j['strategyId'] as String?,
    strategyRules: j['strategyRules'] is Map
        ? Map<String, dynamic>.from(j['strategyRules'] as Map)
        : null,
    targetEntryPrice: (j['targetEntryPrice'] as num?)?.toDouble(),
    stopLoss: (j['stopLoss'] as num?)?.toDouble(),
    targetPrice: (j['targetPrice'] as num?)?.toDouble(),
    suggestedWeight: (j['suggestedWeight'] as num?)?.toDouble(),
    actualEntryPrice: (j['actualEntryPrice'] as num?)?.toDouble(),
    enteredAt: DateTime.tryParse(j['enteredAt'] as String? ?? ''),
    exitPrice: (j['exitPrice'] as num?)?.toDouble(),
    exitedAt: DateTime.tryParse(j['exitedAt'] as String? ?? ''),
    profitPct: (j['profitPct'] as num?)?.toDouble(),
    analysisResult: j['analysisResult'] as String?,
    analysisAt: DateTime.tryParse(j['analysisAt'] as String? ?? ''),
    conditions: (j['conditions'] as List?)
        ?.map((e) => WatchCondition.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class WatchlistStore {
  final List<WatchlistGroup> groups = [];
  final List<WatchlistItem> items = [];
  String _filePath = '';
  String _basePath = '';
  void Function()? onChanged;

  void load(String basePath) {
    _basePath = basePath;
    _filePath = '$basePath/memory/watchlist.json';
    final file = File(_filePath);
    if (!file.existsSync()) {
      _addDefaultGroups();
      return;
    }
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      groups.addAll(
        (json['groups'] as List?)?.map(
              (e) => WatchlistGroup.fromJson(e as Map<String, dynamic>),
            ) ??
            [],
      );
      items.addAll(
        (json['items'] as List?)?.map(
              (e) => WatchlistItem.fromJson(e as Map<String, dynamic>),
            ) ??
            [],
      );
      if (groups.isEmpty) _addDefaultGroups();
    } catch (_) {
      if (groups.isEmpty) _addDefaultGroups();
    }
  }

  void save() {
    if (_filePath.isEmpty) return;
    final file = File(_filePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'groups': groups.map((g) => g.toJson()).toList(),
        'items': items.map((i) => i.toJson()).toList(),
      }),
    );
  }

  void _notify() {
    save();
    onChanged?.call();
  }

  void addGroup(WatchlistGroup g) {
    groups.add(g);
    _notify();
  }

  void removeGroup(String groupId) {
    groups.removeWhere((g) => g.id == groupId);
    items.removeWhere((i) => i.groupId == groupId);
    _notify();
  }

  void addItem(WatchlistItem item) {
    items.removeWhere(
      (i) =>
          i.groupId == item.groupId &&
          i.symbol == item.symbol &&
          i.status == 'watching',
    );
    items.add(item);
    _notify();
  }

  void removeItem(String itemId) {
    items.removeWhere((i) => i.id == itemId);
    _notify();
  }

  void updateItem(String itemId, void Function(WatchlistItem) updater) {
    final item = items.where((i) => i.id == itemId).firstOrNull;
    if (item != null) {
      updater(item);
      _notify();
    }
  }

  List<WatchlistItem> getByGroup(String groupId) =>
      items.where((i) => i.groupId == groupId).toList();
  List<WatchlistItem> getByStatus(String status) =>
      items.where((i) => i.status == status).toList();
  List<WatchlistItem> getByType(String type) =>
      items.where((i) => i.type == type).toList();

  List<WatchlistItem> query({
    String? groupId,
    String? symbol,
    String? status,
    String? type,
    String? tag,
    String? strategyId,
  }) {
    final results = items.where((i) {
      if (groupId != null && i.groupId != groupId) return false;
      if (symbol != null && i.symbol != symbol) return false;
      if (status != null && i.status != status) return false;
      if (type != null && i.type != type) return false;
      if (tag != null && !i.tags.contains(tag)) return false;
      if (strategyId != null && i.strategyId != strategyId) return false;
      return true;
    }).toList();
    results.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return results;
  }

  WatchlistGroup get defaultGroup => groups.first;
  WatchlistGroup? groupForType(String type) =>
      groups.where((g) => g.type == type).firstOrNull;

  List<WatchlistAssetSuggestion> searchCachedAssets(
    String query, {
    required String type,
    int limit = 8,
  }) {
    final q = query.trim();
    if (_basePath.isEmpty || q.length < 2) return const [];
    final dbFile = File('$_basePath/data/market_data.db');
    if (!dbFile.existsSync()) return const [];
    Database? db;
    try {
      db = sqlite3.open(dbFile.path, mode: OpenMode.readOnly);
      final boundedLimit = limit.clamp(1, 20);
      if (type == 'fund') {
        return db
            .select(
              '''
              SELECT code,name,fund_type,company
              FROM fund_list
              WHERE code LIKE ? OR name LIKE ?
              ORDER BY CASE WHEN code = ? THEN 0 WHEN code LIKE ? THEN 1 ELSE 2 END,
                       COALESCE(total_size, 0) DESC,
                       code
              LIMIT ?
              ''',
              ['%$q%', '%$q%', q, '$q%', boundedLimit],
            )
            .map(
              (row) => WatchlistAssetSuggestion(
                code: '${row['code'] ?? ''}',
                name: '${row['name'] ?? ''}',
                type: '${row['fund_type'] ?? 'fund'}',
                company: row['company'] == null ? null : '${row['company']}',
              ),
            )
            .where((row) => row.code.isNotEmpty)
            .toList();
      }
      return db
          .select(
            '''
            SELECT code,name,market,stock_type
            FROM stock_list
            WHERE delist_date IS NULL AND (code LIKE ? OR name LIKE ?)
            ORDER BY CASE WHEN code = ? THEN 0 WHEN code LIKE ? THEN 1 ELSE 2 END,
                     code
            LIMIT ?
            ''',
            ['%$q%', '%$q%', q, '$q%', boundedLimit],
          )
          .map(
            (row) => WatchlistAssetSuggestion(
              code: '${row['code'] ?? ''}',
              name: '${row['name'] ?? ''}',
              type: '${row['stock_type'] ?? 'stock'}',
              market: row['market'] == null ? null : '${row['market']}',
            ),
          )
          .where((row) => row.code.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    } finally {
      db?.close();
    }
  }

  void _addDefaultGroups() {
    groups.add(WatchlistGroup(name: '自选股票', type: 'stock'));
    groups.add(WatchlistGroup(name: '自选基金', type: 'fund'));
  }
}
