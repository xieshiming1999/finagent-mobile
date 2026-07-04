import 'dart:async';

import '../domain/market/services/market_data_resolve_service.dart';
import 'log.dart';
import 'notification_queue.dart';
import 'watchlist.dart';

class WatchlistRefresher {
  final WatchlistStore _store;
  final MarketDataResolveService _resolveService;
  NotificationQueue? chatQueue;
  NotificationQueue? eventQueue;
  Timer? _timer;

  WatchlistRefresher(
    this._store,
    this._resolveService, {
    this.chatQueue,
    this.eventQueue,
  });

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    final activeItems = _store.items
        .where((i) => i.status == 'watching' || i.status == 'entered')
        .toList();
    if (activeItems.isEmpty) return;

    // Skip refresh outside any relevant market hours
    if (!_anyMarketOpen(activeItems)) return;

    final symbols = activeItems.map((i) => i.symbol).toSet().toList();
    try {
      final result = await _resolveService.resolveQuotes(symbols);
      final quoteMap = {for (final q in result.data) q.code: q};

      for (final item in activeItems) {
        final q = quoteMap[item.symbol];
        if (q == null) continue;

        item.currentPrice = q.price;
        item.changePct = q.changePct;
        item.volume = q.volume.toDouble();
        if ((item.name.trim().isEmpty || item.name == item.symbol) &&
            q.name.trim().isNotEmpty &&
            q.name != q.code) {
          item.name = q.name;
        }

        _evaluateConditions(item);

        if (item.status == 'watching') {
          _checkEntryCondition(item);
        } else if (item.status == 'entered') {
          _checkExitCondition(item);
        }
      }

      _store.save();
      _store.onChanged?.call();
    } catch (e) {
      log('WatchlistRefresher', 'Refresh error: $e');
    }
  }

  void _checkEntryCondition(WatchlistItem item) {
    if (item.targetEntryPrice == null || item.currentPrice == null) return;
    if (item.currentPrice! <= item.targetEntryPrice!) {
      chatQueue?.enqueue(
        PendingNotification(
          prompt:
              '📊 ${item.name}(${item.symbol}) 达到入场价 ${item.targetEntryPrice}，当前 ${item.currentPrice}。'
              '${item.entryCondition != null ? "入场条件: ${item.entryCondition}" : ""}'
              '\n建议仓位: ${item.suggestedWeight ?? "—"}%，止损: ${item.stopLoss ?? "—"}，目标: ${item.targetPrice ?? "—"}。'
              '\n是否执行买入?',
          source: 'watchlist',
          priority: NotificationPriority.now,
        ),
      );
    }
  }

  void _checkExitCondition(WatchlistItem item) {
    if (item.currentPrice == null || item.actualEntryPrice == null) return;
    final pnl =
        (item.currentPrice! - item.actualEntryPrice!) /
        item.actualEntryPrice! *
        100;

    if (item.stopLoss != null && item.currentPrice! <= item.stopLoss!) {
      eventQueue?.enqueue(
        PendingNotification(
          prompt:
              '⚠️ ${item.name}(${item.symbol}) 触及止损 ${item.stopLoss}! 当前 ${item.currentPrice} (${pnl.toStringAsFixed(1)}%)',
          source: 'watchlist',
          priority: NotificationPriority.now,
        ),
      );
    }

    if (item.targetPrice != null && item.currentPrice! >= item.targetPrice!) {
      eventQueue?.enqueue(
        PendingNotification(
          prompt:
              '🎯 ${item.name}(${item.symbol}) 达到目标价 ${item.targetPrice}! 当前 ${item.currentPrice} (${pnl.toStringAsFixed(1)}%)',
          source: 'watchlist',
          priority: NotificationPriority.now,
        ),
      );
    }
  }

  void _evaluateConditions(WatchlistItem item) {
    for (final cond in item.conditions) {
      if (cond.triggered) continue;
      final actual = switch (cond.field) {
        'price' => item.currentPrice,
        'changePct' => item.changePct,
        'volume' => item.volume,
        _ => null,
      };
      if (actual == null) continue;
      if (!cond.evaluate(actual)) continue;

      cond.triggered = true;
      final msg =
          cond.message ??
          '${item.name}(${item.symbol}) ${cond.field} ${cond.op} ${cond.value} 已触发';

      switch (cond.action) {
        case 'notify_chat':
          chatQueue?.enqueue(
            PendingNotification(
              prompt: '📊 $msg',
              source: 'watchlist',
              priority: NotificationPriority.now,
            ),
          );
        case 'notify_event':
          eventQueue?.enqueue(
            PendingNotification(
              prompt: '📊 $msg',
              source: 'watchlist',
              priority: NotificationPriority.now,
            ),
          );
        case 'ui_alert' || _:
          _store.onChanged?.call();
      }
    }
  }

  /// Check if any market relevant to the watchlist items is currently open.
  bool _anyMarketOpen(List<WatchlistItem> items) {
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 8),
    ); // Beijing time
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      // Weekend: only crypto/forex markets (not supported yet)
      return false;
    }
    final minutes = now.hour * 60 + now.minute;

    for (final item in items) {
      final market = _detectMarket(item.symbol);
      switch (market) {
        case 'cn_stock': // A股 9:25-15:05 (含集合竞价和收盘延迟)
          if (minutes >= 9 * 60 + 25 && minutes <= 15 * 60 + 5) return true;
        case 'cn_futures': // 期货 日盘 9:00-15:00 + 夜盘 21:00-02:30
          if (minutes >= 9 * 60 && minutes <= 15 * 60) return true;
          if (minutes >= 21 * 60 || minutes <= 2 * 60 + 30) return true;
        case 'hk': // 港股 9:30-16:10
          if (minutes >= 9 * 60 + 30 && minutes <= 16 * 60 + 10) return true;
        case 'us': // 美股 21:30-04:00 北京时间 (夏令)
          if (minutes >= 21 * 60 + 30 || minutes <= 4 * 60) return true;
        default: // 未知市场: A股时间
          if (minutes >= 9 * 60 + 25 && minutes <= 15 * 60 + 5) return true;
      }
    }
    return false;
  }

  String _detectMarket(String symbol) {
    final code = symbol.replaceAll(RegExp(r'\.\w+$'), '');
    if (RegExp(r'^\d{6}$').hasMatch(code)) return 'cn_stock';
    if (RegExp(r'^[A-Z]{1,3}\d{3,4}$').hasMatch(code)) {
      return 'cn_futures'; // RB2510, AL2506
    }
    if (code.length == 5 && RegExp(r'^\d{5}$').hasMatch(code)) {
      return 'hk'; // 00700
    }
    if (RegExp(r'^[A-Z]{1,5}$').hasMatch(code)) return 'us'; // AAPL, TSLA
    return 'cn_stock';
  }
}
