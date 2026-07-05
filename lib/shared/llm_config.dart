import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Single LLM provider configuration.
class LLMProviderConfig {
  String id;
  String url;
  String endpoint;
  String key;
  String model;
  String schema; // openai / anthropic / proxy
  int maxOutputTokens;
  int maxContextLength;
  double compactThreshold;
  Set<String> tags;
  bool enabled;
  Map<String, String> extras;

  LLMProviderConfig({
    String? id,
    this.url = '',
    this.endpoint = '',
    this.key = '',
    this.model = '',
    this.schema = 'openai',
    this.maxOutputTokens = 8192,
    this.maxContextLength = 160000,
    this.compactThreshold = 0.85,
    Set<String>? tags,
    this.enabled = true,
    Map<String, String>? extras,
  }) : id = id ?? _generateId(),
       tags = tags ?? {'llm'},
       extras = extras ?? {};

  static String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch.toString();
    return md5.convert(utf8.encode(now)).toString().substring(0, 8);
  }

  String get provider {
    if (url.isEmpty) return schema;
    try {
      final host = Uri.parse(url).host;
      final parts = host.split('.');
      if (parts.length >= 2) return parts[parts.length - 2];
      return parts.first;
    } catch (_) {
      return schema;
    }
  }

  String get defaultEndpoint => switch (schema) {
    'anthropic' => '/v1/messages',
    'proxy' => '/v1/chat/completions',
    _ => '/v1/chat/completions',
  };

  String get fullUrl {
    final ep = endpoint.isNotEmpty ? endpoint : defaultEndpoint;
    final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final path = ep.startsWith('/') ? ep : '/$ep';
    return '$base$path';
  }

  int get compactAt => (maxContextLength * compactThreshold).toInt();

  LLMProviderConfig copyWith({String? id}) => LLMProviderConfig(
    id: id ?? _generateId(),
    url: url,
    endpoint: endpoint,
    key: key,
    model: model,
    schema: schema,
    maxOutputTokens: maxOutputTokens,
    maxContextLength: maxContextLength,
    compactThreshold: compactThreshold,
    tags: Set.of(tags),
    enabled: enabled,
    extras: Map.of(extras),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'endpoint': endpoint,
    'key': key,
    'model': model,
    'schema': schema,
    'maxOutputTokens': maxOutputTokens,
    'maxContextLength': maxContextLength,
    'compactThreshold': compactThreshold,
    'tags': tags.toList(),
    'enabled': enabled,
    'extras': extras,
  };

  factory LLMProviderConfig.fromJson(Map<String, dynamic> j) =>
      LLMProviderConfig(
        id: j['id'] as String? ?? _generateId(),
        url: j['url'] as String? ?? '',
        endpoint: j['endpoint'] as String? ?? '',
        key: j['key'] as String? ?? '',
        model: j['model'] as String? ?? '',
        schema: j['schema'] as String? ?? 'openai',
        maxOutputTokens: (j['maxOutputTokens'] as num?)?.toInt() ?? 8192,
        maxContextLength: (j['maxContextLength'] as num?)?.toInt() ?? 160000,
        compactThreshold: (j['compactThreshold'] as num?)?.toDouble() ?? 0.85,
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toSet() ?? {'llm'},
        enabled: j['enabled'] as bool? ?? true,
        extras:
            (j['extras'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, v.toString()),
            ) ??
            {},
      );
}

/// Multi-LLM configuration store with priority ordering.
class LLMConfigStore {
  List<LLMProviderConfig> providers = [];
  String _configPath = '';

  LLMConfigStore();

  Future<void> load({String? configDir}) async {
    if (configDir != null) _configPath = '$configDir/llm_config.json';
    final file = File(_configPath);
    if (!file.existsSync()) return;

    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final version = json['version'] as int? ?? 1;

      if (version >= 2) {
        providers =
            (json['providers'] as List?)
                ?.map(
                  (e) => LLMProviderConfig.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            [];
      } else {
        _migrateV1(json);
      }
    } catch (_) {}
  }

  Future<bool> importFinElectronDefaultIfEmpty() async {
    if (providers.isNotEmpty) return false;
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return false;
    final file = File('$home/.finagent-mobile/config.json');
    if (!file.existsSync()) return false;

    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final models = (json['models'] as List?)?.whereType<Map>().toList() ?? [];
      if (models.isEmpty) return false;
      for (final selected in models.cast<Map<String, dynamic>>()) {
        final apiKey = selected['apiKey'] as String? ?? '';
        final model = selected['model'] as String? ?? '';
        final baseUrl = selected['baseURL'] as String? ?? '';
        if (apiKey.isEmpty || model.isEmpty || baseUrl.isEmpty) continue;

        final provider = (selected['provider'] as String? ?? 'openai')
            .toLowerCase();
        final extras = <String, String>{};
        final effort = selected['effort'];
        if (effort != null) {
          if (provider == 'anthropic') {
            extras['effort'] = effort.toString();
          } else {
            extras['reasoning_effort'] = effort.toString();
          }
        }
        final thinking = selected['thinking'];
        if (thinking is Map && thinking['type'] != null) {
          extras['thinking_type'] = thinking['type'].toString();
        }
        final headers = selected['extraHeaders'];
        if (headers is Map) {
          for (final entry in headers.entries) {
            extras['header_${entry.key}'] = entry.value.toString();
          }
        }
        final capabilities =
            (selected['capabilities'] as Map?)?.cast<String, dynamic>() ?? {};
        final tags = <String>{};
        if (selected['isDefault'] == true) tags.add('llm');
        if (capabilities['vision'] == true) tags.add('multimodal');
        if (tags.isEmpty) continue;

        providers.add(
          LLMProviderConfig(
            id: selected['id'] as String?,
            url: baseUrl,
            endpoint:
                selected['endpoint'] as String? ??
                (provider == 'anthropic'
                    ? '/v1/messages'
                    : '/v1/chat/completions'),
            key: apiKey,
            model: model,
            schema: provider == 'anthropic' ? 'anthropic' : 'openai',
            maxOutputTokens: (selected['maxTokens'] as num?)?.toInt() ?? 8192,
            maxContextLength:
                (selected['contextWindow'] as num?)?.toInt() ?? 160000,
            compactThreshold:
                (selected['compactThreshold'] as num?)?.toDouble() ?? 0.85,
            tags: tags,
            enabled: true,
            extras: extras,
          ),
        );
      }
      if (providers.isEmpty) return false;
      await save();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> importFinElectronHeadersIfMissing() async {
    if (providers.isEmpty) return false;
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return false;
    final file = File('$home/.finagent-mobile/config.json');
    if (!file.existsSync()) return false;

    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final models = (json['models'] as List?)?.whereType<Map>().toList() ?? [];
      final headersById = <String, Map>{};
      final headersByModel = <String, Map>{};
      for (final selected in models.cast<Map<String, dynamic>>()) {
        final headers = selected['extraHeaders'];
        if (headers is! Map || headers.isEmpty) continue;
        final id = selected['id']?.toString() ?? '';
        final model = selected['model']?.toString() ?? '';
        if (id.isNotEmpty) headersById[id] = headers;
        if (model.isNotEmpty) headersByModel[model] = headers;
      }

      var changed = false;
      for (final provider in providers) {
        if (_hasHeader(provider, 'User-Agent')) continue;
        final headers =
            headersById[provider.id] ?? headersByModel[provider.model];
        if (headers == null) continue;
        final value = headers['User-Agent'] ?? headers['user-agent'];
        final userAgent = value?.toString().trim() ?? '';
        if (userAgent.isEmpty) continue;
        provider.extras['header_User-Agent'] = userAgent;
        changed = true;
      }
      if (changed) await save();
      return changed;
    } catch (_) {
      return false;
    }
  }

  bool _hasHeader(LLMProviderConfig provider, String name) {
    final target = 'header_${name.toLowerCase()}';
    return provider.extras.entries.any(
      (entry) =>
          entry.key.toLowerCase() == target && entry.value.trim().isNotEmpty,
    );
  }

  void _migrateV1(Map<String, dynamic> v1) {
    providers.clear();
    final mode = v1['mode'] as String? ?? 'anthropic';

    final openaiUrl = v1['openaiUrl'] as String? ?? '';
    final openaiKey = v1['openaiKey'] as String? ?? '';
    final openaiModel = v1['openaiModel'] as String? ?? '';
    if (openaiKey.isNotEmpty) {
      providers.add(
        LLMProviderConfig(
          url: openaiUrl,
          endpoint: v1['openaiEndpoint'] as String? ?? '',
          key: openaiKey,
          model: openaiModel,
          schema: 'openai',
          enabled: mode == 'openai',
        ),
      );
    }

    final anthUrl =
        v1['anthropicUrl'] as String? ?? 'https://api.anthropic.com';
    final anthKey = v1['anthropicKey'] as String? ?? '';
    final anthModel = v1['anthropicModel'] as String? ?? 'claude-sonnet-4-6';
    if (anthKey.isNotEmpty) {
      providers.add(
        LLMProviderConfig(
          url: anthUrl,
          endpoint: v1['anthropicEndpoint'] as String? ?? '',
          key: anthKey,
          model: anthModel,
          schema: 'anthropic',
          enabled: mode == 'anthropic' || mode == 'proxy',
        ),
      );
    }

    if (providers.isNotEmpty) save();
  }

  Future<void> save() async {
    if (_configPath.isEmpty) return;
    final file = File(_configPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'version': 2,
        'providers': providers.map((p) => p.toJson()).toList(),
      }),
    );
  }

  List<LLMProviderConfig> getByTag(String tag) =>
      providers.where((p) => p.enabled && p.tags.contains(tag)).toList();

  LLMProviderConfig? primary([String tag = 'llm']) {
    final list = getByTag(tag);
    return list.isNotEmpty ? list.first : null;
  }

  void moveUp(int index) {
    if (index <= 0 || index >= providers.length) return;
    final item = providers.removeAt(index);
    providers.insert(index - 1, item);
  }

  void moveDown(int index) {
    if (index < 0 || index >= providers.length - 1) return;
    final item = providers.removeAt(index);
    providers.insert(index + 1, item);
  }

  void add(LLMProviderConfig config) => providers.add(config);

  void removeAt(int index) {
    if (index >= 0 && index < providers.length) providers.removeAt(index);
  }

  LLMProviderConfig duplicate(int index) {
    final copy = providers[index].copyWith();
    providers.insert(index + 1, copy);
    return copy;
  }
}
