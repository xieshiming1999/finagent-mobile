import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'log.dart';

enum NotificationSeverity { notify, alert }

class UINotification {
  final String id;
  final String title;
  final String message;
  final String source;
  final NotificationSeverity severity;
  final DateTime timestamp;
  bool isRead;

  UINotification({
    required this.id,
    required this.title,
    required this.message,
    required this.source,
    this.severity = NotificationSeverity.notify,
    DateTime? timestamp,
    this.isRead = false,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'message': message,
    'source': source,
    'severity': severity.name,
    'timestamp': timestamp.toIso8601String(),
    'isRead': isRead,
  };

  factory UINotification.fromJson(Map<String, dynamic> json) => UINotification(
    id: json['id'] as String,
    title: json['title'] as String,
    message: json['message'] as String,
    source: json['source'] as String? ?? '',
    severity: json['severity'] == 'alert'
        ? NotificationSeverity.alert
        : NotificationSeverity.notify,
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    isRead: json['isRead'] as bool? ?? false,
  );
}

class UINotificationStore {
  final String _filePath;
  final List<UINotification> _items = [];
  void Function()? onChanged;

  static const maxItems = 200;

  UINotificationStore({required String storageDir})
    : _filePath = p.join(storageDir, 'notifications.json');

  List<UINotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => !n.isRead).length;

  void load() {
    final file = File(_filePath);
    if (!file.existsSync()) return;
    try {
      final list = jsonDecode(file.readAsStringSync()) as List;
      _items.clear();
      for (final item in list) {
        _items.add(UINotification.fromJson(item as Map<String, dynamic>));
      }
      log('UINotificationStore', 'Loaded ${_items.length} notifications');
    } catch (e) {
      log('UINotificationStore', 'Load error: $e');
    }
  }

  void _save() {
    try {
      Directory(p.dirname(_filePath)).createSync(recursive: true);
      final json = jsonEncode(_items.map((n) => n.toJson()).toList());
      File(_filePath).writeAsStringSync(json);
    } catch (e) {
      log('UINotificationStore', 'Save error: $e');
    }
  }

  void add(UINotification notification) {
    _items.insert(0, notification);
    if (_items.length > maxItems) {
      _items.removeRange(maxItems, _items.length);
    }
    _save();
    onChanged?.call();
  }

  void markRead(String id) {
    final item = _items.where((n) => n.id == id).firstOrNull;
    if (item == null || item.isRead) return;
    item.isRead = true;
    _save();
    onChanged?.call();
  }

  void markAllRead() {
    var changed = false;
    for (final item in _items) {
      if (!item.isRead) {
        item.isRead = true;
        changed = true;
      }
    }
    if (changed) {
      _save();
      onChanged?.call();
    }
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    _save();
    onChanged?.call();
  }
}
