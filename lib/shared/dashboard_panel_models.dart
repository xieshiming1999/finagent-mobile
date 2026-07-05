import 'dart:convert';
import 'dart:io';

enum DashboardItemType { htmlFile, monitor }

class DashboardItem {
  final String id;
  final String title;
  final DashboardItemType type;
  final String? filePath;
  final DateTime? modified;
  final String? tag;
  final Map<String, dynamic>? monitorData;

  const DashboardItem({
    required this.id,
    required this.title,
    this.type = DashboardItemType.htmlFile,
    this.filePath,
    this.modified,
    this.tag,
    this.monitorData,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type.name,
    if (filePath != null) 'filePath': filePath,
    if (modified != null) 'modified': modified!.toIso8601String(),
    if (tag != null) 'tag': tag,
  };

  factory DashboardItem.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'htmlFile';
    if (typeStr != 'htmlFile' && typeStr != 'monitor') return _invalid;
    return DashboardItem(
      id: json['id'] as String,
      title: json['title'] as String,
      type: typeStr == 'monitor' ? DashboardItemType.monitor : DashboardItemType.htmlFile,
      filePath: json['filePath'] as String?,
      modified: json['modified'] != null ? DateTime.tryParse(json['modified'] as String) : null,
      tag: json['tag'] as String?,
    );
  }

  DashboardItem copyWith({String? tag, Map<String, dynamic>? monitorData}) => DashboardItem(
    id: id,
    title: title,
    type: type,
    filePath: filePath,
    modified: modified,
    tag: tag ?? this.tag,
    monitorData: monitorData ?? this.monitorData,
  );

  static const _invalid = DashboardItem(id: '', title: '');
}

class DashboardStore {
  final String storagePath;

  DashboardStore({required this.storagePath});

  List<DashboardItem> load() {
    final file = File(storagePath);
    if (!file.existsSync()) return [];
    try {
      final list = jsonDecode(file.readAsStringSync()) as List;
      return list.map((e) => DashboardItem.fromJson(e as Map<String, dynamic>)).where((i) => i.id.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  void save(List<DashboardItem> items) {
    final file = File(storagePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(items.map((e) => e.toJson()).toList()));
  }
}
