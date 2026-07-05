import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../agent/data_fetcher/http_utils.dart';

/// Stores user-defined API keys and config values.
/// Persisted to {documentsDir}/agents/api_config.json.
class ApiConfigStore {
  static const webviewUserAgentKey = 'WEBVIEW_USER_AGENT';
  static const httpUserAgentKey = 'HTTP_USER_AGENT';
  static const defaultBrowserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  Map<String, String> _config = {};
  String? _path;

  Map<String, String> get all => Map.unmodifiable(_config);

  String? get(String key) => _config[key];

  String get webviewUserAgent {
    final webview = _config[webviewUserAgentKey]?.trim();
    if (webview != null && webview.isNotEmpty) return webview;
    final http = _config[httpUserAgentKey]?.trim();
    if (http != null && http.isNotEmpty) return http;
    return defaultBrowserUserAgent;
  }

  String get httpUserAgent {
    final http = _config[httpUserAgentKey]?.trim();
    if (http != null && http.isNotEmpty) return http;
    final webview = _config[webviewUserAgentKey]?.trim();
    if (webview != null && webview.isNotEmpty) return webview;
    return defaultBrowserUserAgent;
  }

  void set(String key, String value) {
    _config[key] = value;
    _applyRuntimeHeaders();
    _save();
  }

  void remove(String key) {
    _config.remove(key);
    _applyRuntimeHeaders();
    _save();
  }

  Map<String, String> toMap() => Map.of(_config);

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _path = '${dir.path}/agents/api_config.json';
    try {
      final file = File(_path!);
      if (file.existsSync()) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        _config = json.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {}
    _applyRuntimeHeaders();
  }

  void _applyRuntimeHeaders() {
    configureHttpUserAgent(httpUserAgent);
  }

  void _save() {
    if (_path == null) return;
    try {
      final file = File(_path!);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(_config));
    } catch (_) {}
  }
}
