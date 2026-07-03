import 'dart:convert';
import 'dart:io';

import 'goal_automation_types.dart';

class GoalAutomationSuggestion {
  final String id;
  final String title;
  final String description;
  final GoalTemplateId templateId;
  final String source;
  final String dedupKey;
  final String status;
  final int createdAt;
  final int? resolvedAt;

  const GoalAutomationSuggestion({
    required this.id,
    required this.title,
    required this.description,
    required this.templateId,
    required this.source,
    required this.dedupKey,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
  });

  GoalAutomationSuggestion copyWith({String? status, int? resolvedAt}) =>
      GoalAutomationSuggestion(
        id: id,
        title: title,
        description: description,
        templateId: templateId,
        source: source,
        dedupKey: dedupKey,
        status: status ?? this.status,
        createdAt: createdAt,
        resolvedAt: resolvedAt ?? this.resolvedAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'templateId': templateId.wireName,
    'source': source,
    'dedupKey': dedupKey,
    'status': status,
    'createdAt': createdAt,
    'resolvedAt': resolvedAt,
  };

  factory GoalAutomationSuggestion.fromJson(Map<String, dynamic> json) =>
      GoalAutomationSuggestion(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        templateId:
            GoalTemplateIdWire.parse(json['templateId'] as String? ?? '') ??
            GoalTemplateId.apiErrorTriage,
        source: json['source'] as String? ?? 'catalog',
        dedupKey: json['dedupKey'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        resolvedAt: (json['resolvedAt'] as num?)?.toInt(),
      );
}

class GoalAutomationSuggestionStore {
  final String basePath;
  final List<GoalAutomationSuggestion> _suggestions = [];

  static const int maxPending = 5;

  GoalAutomationSuggestionStore(this.basePath) {
    _load();
  }

  String get _path => '$basePath/memory/goal-automation-suggestions.json';

  List<GoalAutomationSuggestion> listPending() =>
      _suggestions.where((item) => item.status == 'pending').toList();

  List<GoalAutomationSuggestion> seedCatalog(
    List<GoalTemplate> templates,
    bool Function(GoalTemplateId id) enabled,
  ) {
    for (final template in templates) {
      if (enabled(template.id)) continue;
      _add(
        title: 'Enable ${template.title}',
        description: template.objective,
        templateId: template.id,
        source: 'catalog',
        dedupKey: 'goal-template:${template.id.wireName}',
      );
    }
    return listPending()
        .where((suggestion) => !enabled(suggestion.templateId))
        .toList();
  }

  GoalAutomationSuggestion? accept(String ref) => _resolve(ref, 'accepted');

  GoalAutomationSuggestion? dismiss(String ref) => _resolve(ref, 'dismissed');

  GoalAutomationSuggestion? _add({
    required String title,
    required String description,
    required GoalTemplateId templateId,
    required String source,
    required String dedupKey,
  }) {
    if (_suggestions.any((item) => item.dedupKey == dedupKey)) return null;
    if (listPending().length >= maxPending) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final suggestion = GoalAutomationSuggestion(
      id: '${templateId.wireName}-$now',
      title: title,
      description: description,
      templateId: templateId,
      source: source,
      dedupKey: dedupKey,
      status: 'pending',
      createdAt: now,
    );
    _suggestions.add(suggestion);
    _save();
    return suggestion;
  }

  GoalAutomationSuggestion? _resolve(String ref, String status) {
    final index = _suggestions.indexWhere(
      (item) =>
          item.id == ref ||
          item.templateId.wireName == ref ||
          item.dedupKey == ref,
    );
    if (index < 0 || _suggestions[index].status != 'pending') return null;
    final next = _suggestions[index].copyWith(
      status: status,
      resolvedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _suggestions[index] = next;
    _save();
    return next;
  }

  void _load() {
    final file = File(_path);
    if (!file.existsSync()) return;
    try {
      final data = jsonDecode(file.readAsStringSync());
      final rows = data is Map ? data['suggestions'] : data;
      if (rows is! List) return;
      _suggestions
        ..clear()
        ..addAll(
          rows
              .whereType<Map>()
              .map(
                (row) => GoalAutomationSuggestion.fromJson(
                  row.map((key, value) => MapEntry('$key', value)),
                ),
              )
              .where((row) => row.id.isNotEmpty && row.dedupKey.isNotEmpty),
        );
    } catch (_) {}
  }

  void _save() {
    final file = File(_path);
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'suggestions': _suggestions.map((item) => item.toJson()).toList(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }
}
