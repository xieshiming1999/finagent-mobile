import 'dart:io';

import 'package:flutter/services.dart';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../../../shared/api_config.dart';
import 'prompt.dart' as tool_prompt;

typedef UIStateProvider = Map<String, dynamic> Function();

class EnvironmentTool extends Tool {
  UIStateProvider? uiStateProvider;
  ApiConfigStore? apiConfig;

  static const _channel = MethodChannel('finagent_mobile/device_info');

  @override
  String get name => 'Environment';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'key': {
        'type': 'string',
        'description':
            'If provided, returns the config value for this key (from API Keys settings). Omit to get full environment info.',
      },
    },
  };

  @override
  bool get isReadOnly => true;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final key = input['key'] as String?;
    if (key != null && key.isNotEmpty) {
      final value = apiConfig?.get(key);
      return ToolResult(
        toolUseId: toolUseId,
        content: value ?? 'Config key "$key" not found.',
      );
    }

    final now = DateTime.now();
    final result = <String, dynamic>{
      'time': now.toIso8601String(),
      'platform': Platform.operatingSystem,
      'basePath': context.basePath,
    };

    if (uiStateProvider != null) {
      result['ui'] = uiStateProvider!();
    }

    if (apiConfig != null) {
      final keys = apiConfig!.all.keys.toList();
      if (keys.isNotEmpty) {
        result['configKeys'] = keys;
      }
    }

    try {
      final memInfo = await _channel.invokeMethod('getMemoryInfo');
      if (memInfo is Map) {
        result['memory'] = Map<String, dynamic>.from(memInfo);
      }
    } catch (_) {}

    final buf = StringBuffer();
    result.forEach((k, v) {
      if (v is Map) {
        buf.writeln('$k:');
        (v as Map<String, dynamic>).forEach(
          (k2, v2) => buf.writeln('  $k2: $v2'),
        );
      } else if (v is List) {
        buf.writeln('$k: ${v.join(', ')}');
      } else {
        buf.writeln('$k: $v');
      }
    });

    return ToolResult(
      toolUseId: toolUseId,
      content: buf.toString().trimRight(),
    );
  }
}
