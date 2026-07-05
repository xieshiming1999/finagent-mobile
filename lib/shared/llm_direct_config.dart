import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// LLM connection mode — kept for backwards compat export.
enum LLMMode { proxy, openai, anthropic }

/// Persisted LLM direct-connection config (v1 legacy — kept for compatibility).
class LLMDirectConfig {
  LLMMode mode;
  String openaiUrl, openaiEndpoint, openaiKey, openaiModel, openaiEffort;
  String anthropicUrl,
      anthropicEndpoint,
      anthropicKey,
      anthropicModel,
      anthropicEffort;

  LLMDirectConfig({
    this.mode = LLMMode.anthropic,
    this.openaiUrl = '',
    this.openaiEndpoint = '',
    this.openaiKey = '',
    this.openaiModel = '',
    this.openaiEffort = 'medium',
    this.anthropicUrl = 'https://api.anthropic.com',
    this.anthropicEndpoint = '',
    this.anthropicKey = '',
    this.anthropicModel = 'claude-sonnet-4-6',
    this.anthropicEffort = 'medium',
  });

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'openaiUrl': openaiUrl,
    'openaiEndpoint': openaiEndpoint,
    'openaiKey': openaiKey,
    'openaiModel': openaiModel,
    'openaiEffort': openaiEffort,
    'anthropicUrl': anthropicUrl,
    'anthropicEndpoint': anthropicEndpoint,
    'anthropicKey': anthropicKey,
    'anthropicModel': anthropicModel,
    'anthropicEffort': anthropicEffort,
  };

  factory LLMDirectConfig.fromJson(Map<String, dynamic> json) =>
      LLMDirectConfig(
        mode: LLMMode.values.firstWhere(
          (m) => m.name == (json['mode'] as String? ?? 'anthropic'),
          orElse: () => LLMMode.anthropic,
        ),
        openaiUrl: json['openaiUrl'] as String? ?? '',
        openaiEndpoint: json['openaiEndpoint'] as String? ?? '',
        openaiKey: json['openaiKey'] as String? ?? '',
        openaiModel: json['openaiModel'] as String? ?? '',
        openaiEffort: json['openaiEffort'] as String? ?? 'medium',
        anthropicUrl:
            json['anthropicUrl'] as String? ?? 'https://api.anthropic.com',
        anthropicEndpoint: json['anthropicEndpoint'] as String? ?? '',
        anthropicKey: json['anthropicKey'] as String? ?? '',
        anthropicModel:
            json['anthropicModel'] as String? ?? 'claude-sonnet-4-6',
        anthropicEffort: json['anthropicEffort'] as String? ?? 'medium',
      );

  static Future<LLMDirectConfig> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/agents/llm_config.json');
      if (!file.existsSync()) return LLMDirectConfig();
      return LLMDirectConfig.fromJson(jsonDecode(file.readAsStringSync()));
    } catch (_) {
      return LLMDirectConfig();
    }
  }

  Future<void> save() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/agents';
    Directory(path).createSync(recursive: true);
    File('$path/llm_config.json').writeAsStringSync(jsonEncode(toJson()));
  }
}
