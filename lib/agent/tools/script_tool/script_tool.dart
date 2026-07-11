import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';

import '../../bridge/bridge_js.dart';
import '../../data_fetcher/http_utils.dart' show decodeResponseBody;
import '../../http_bridge.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../../../shared/api_config.dart';
import '../utils/file_utils.dart';
import 'prompt.dart' as tool_prompt;

class ScriptTool extends Tool {
  ApiConfigStore? apiConfig;
  static const _timeout = Duration(seconds: 15);

  @override
  String get name => 'Script';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'code': {'type': 'string', 'description': 'JavaScript code to execute'},
    },
    'required': ['code'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) => true;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final code = input['code'] as String? ?? '';
    if (code.trim().isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'code is required.',
        isError: true,
      );
    }

    final js = getJavascriptRuntime();
    final sw = Stopwatch()..start();
    try {
      final fetchResults = await _prefetchCalls(code, context.serviceBaseUrl);

      js.evaluate('''
        var __fetchCache = ${jsonEncode(fetchResults)};
        var __sideEffects = { notifications: [], logs: [] };
        var __apiConfig = ${jsonEncode(apiConfig?.toMap() ?? {})};
        var Bridge = {};
        ${BridgeJs.httpBridge}
        ${BridgeJs.consoleSideEffects}
        ${BridgeJs.dataFunctions}
        ${BridgeJs.statsFunctions}
      ''');

      // Register File ops via sendMessage channels
      _registerFileChannels(js, context.basePath);

      js.evaluate('''
        ${BridgeJs.fileBridgeSendMessage}
        ${BridgeJs.globalAliases}
      ''');

      final wrappedCode =
          '''
        (function() {
          try {
            var __result = (function() { $code })();
            return JSON.stringify({
              ok: true,
              result: __result === undefined ? null : __result,
              sideEffects: __sideEffects,
            });
          } catch(e) {
            return JSON.stringify({ ok: false, error: e.message || String(e), sideEffects: __sideEffects });
          }
        })()
      ''';

      final jsResult = js.evaluate(wrappedCode);
      final parsed = jsonDecode(jsResult.stringResult) as Map<String, dynamic>;

      final buf = StringBuffer();
      final logs = (parsed['sideEffects']?['logs'] as List?) ?? [];
      if (logs.isNotEmpty) {
        buf.writeln('Console output:');
        for (final log in logs) {
          buf.writeln('  $log');
        }
      }

      var isScriptError = parsed['ok'] != true;
      if (!isScriptError) {
        final result = parsed['result'];
        if (result is String && _looksLikeBridgeChannelError(result)) {
          isScriptError = true;
          buf.writeln('Bridge channel failed: $result');
        } else {
          buf.writeln(result is String ? result : jsonEncode(result));
        }
      } else {
        buf.writeln('Script execution failed: ${parsed['error']}');
      }

      sw.stop();
      final elapsed = sw.elapsedMilliseconds;
      buf.writeln(
        '\n(executed in ${elapsed}ms, ${fetchResults.length} HTTP pre-fetched)',
      );

      return ToolResult(
        toolUseId: toolUseId,
        content: buf.toString().trimRight(),
        isError: isScriptError,
      );
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Script execution failed: $e',
        isError: true,
      );
    } finally {
      js.dispose();
    }
  }

  bool _looksLikeBridgeChannelError(String value) {
    final text = value.trimLeft();
    return text.startsWith('Error:') ||
        text.startsWith('Unsupported algorithm:') ||
        text.startsWith('Invalid ');
  }

  void _registerFileChannels(JavascriptRuntime js, String basePath) {
    js.onMessage('readFile', (args) {
      try {
        final path = args is String ? args : args.toString();
        final fullPath = normalizePath(path, basePath);
        final file = File(fullPath);
        if (!file.existsSync()) {
          return 'SCRIPT_BRIDGE_ERROR: file does not exist: $path';
        }
        return file.readAsStringSync();
      } catch (e) {
        return 'SCRIPT_BRIDGE_ERROR: $e';
      }
    });

    js.onMessage('writeFile', (args) {
      try {
        final argList = args is List
            ? args
            : (args is String ? jsonDecode(args) as List : [args]);
        if (argList.length < 2) {
          return 'SCRIPT_BRIDGE_ERROR: writeFile requires path and content';
        }
        final path = argList[0].toString();
        final content = argList[1].toString();
        final fullPath = normalizePath(path, basePath);
        if (isInBundleDir(fullPath, basePath)) {
          return 'SCRIPT_BRIDGE_ERROR: cannot write to bundle/';
        }
        final file = File(fullPath);
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(content);
        return 'OK';
      } catch (e) {
        return 'SCRIPT_BRIDGE_ERROR: $e';
      }
    });

    js.onMessage('listDir', (args) {
      try {
        final path = args is String ? args : args.toString();
        final fullPath = normalizePath(path, basePath);
        final dir = Directory(fullPath);
        if (!dir.existsSync()) {
          return 'SCRIPT_BRIDGE_ERROR: directory does not exist: $path';
        }
        final entries = dir.listSync();
        final result = entries.map((e) {
          final name = e.path.split('/').last;
          final type = e is Directory ? 'dir' : 'file';
          return {'name': name, 'type': type};
        }).toList();
        return jsonEncode(result);
      } catch (e) {
        return 'SCRIPT_BRIDGE_ERROR: $e';
      }
    });

    js.onMessage('fileExists', (args) {
      try {
        final path = args is String ? args : args.toString();
        final fullPath = normalizePath(path, basePath);
        return (File(fullPath).existsSync() || Directory(fullPath).existsSync())
            ? 'true'
            : 'false';
      } catch (e) {
        return 'SCRIPT_BRIDGE_ERROR: $e';
      }
    });

    js.onMessage('fileStat', (args) {
      try {
        final path = args is String ? args : args.toString();
        final fullPath = normalizePath(path, basePath);
        final stat = FileStat.statSync(fullPath);
        if (stat.type == FileSystemEntityType.notFound) {
          return 'SCRIPT_BRIDGE_ERROR: path does not exist: $path';
        }
        return jsonEncode({
          'size': stat.size,
          'modified': stat.modified.toIso8601String(),
          'type': stat.type == FileSystemEntityType.directory ? 'dir' : 'file',
        });
      } catch (e) {
        return 'SCRIPT_BRIDGE_ERROR: $e';
      }
    });
  }

  Future<Map<String, dynamic>> _prefetchCalls(
    String script,
    String serviceBaseUrl,
  ) async {
    final pattern = RegExp(
      r'''(?:callService|Bridge\.(?:get|post|put|delete|fetch))\s*\(\s*['"](.*?)['"]\s*(?:,\s*(\{[\s\S]*?\})\s*(?:,\s*['"](\w+)['"]\s*)?)?\)''',
    );
    final varPattern = RegExp(
      r'''(?:callService|Bridge\.(?:get|post|put|delete|fetch))\s*\(\s*(\w+)\s*(?:,\s*(\{[\s\S]*?\})\s*(?:,\s*['"](\w+)['"]\s*)?)?\)''',
    );
    final varDeclPattern = RegExp(
      r'''(?:const|let|var)\s+(\w+)\s*=\s*(?:['"]([^'"]+)['"]|`([^`]+)`)''',
    );

    final vars = <String, String>{};
    for (final m in varDeclPattern.allMatches(script)) {
      vars[m.group(1)!] = m.group(2) ?? m.group(3) ?? '';
    }

    final results = <String, dynamic>{};
    final futures = <Future<void>>[];

    void addFetch(String path, String? paramsStr, String methodStr) {
      Map<String, dynamic> params = {};
      if (paramsStr != null) {
        try {
          params = jsonDecode(paramsStr) as Map<String, dynamic>;
        } catch (_) {}
      }
      final cacheKey = '$methodStr:$path|${jsonEncode(params)}';
      if (results.containsKey(cacheKey)) return;

      futures.add(() async {
        try {
          final response = await bridgeHttp(
            url: path,
            method: methodStr,
            params: methodStr == 'GET' || methodStr == 'DELETE' ? params : null,
            body: methodStr == 'POST' || methodStr == 'PUT' ? params : null,
            serviceBaseUrl: serviceBaseUrl,
          ).timeout(_timeout);

          try {
            final body = decodeResponseBody(response);
            results[cacheKey] = jsonDecode(body);
          } catch (_) {
            results[cacheKey] = {'raw': decodeResponseBody(response)};
          }
        } catch (e) {
          results[cacheKey] = {'error': e.toString()};
        }
      }());
    }

    for (final match in pattern.allMatches(script)) {
      addFetch(
        match.group(1)!,
        match.group(2),
        match.group(3)?.toUpperCase() ?? 'GET',
      );
    }
    for (final match in varPattern.allMatches(script)) {
      final varName = match.group(1)!;
      final resolved = vars[varName];
      if (resolved != null && resolved.isNotEmpty) {
        addFetch(
          resolved,
          match.group(2),
          match.group(3)?.toUpperCase() ?? 'GET',
        );
      }
    }

    await Future.wait(futures);
    return results;
  }
}
