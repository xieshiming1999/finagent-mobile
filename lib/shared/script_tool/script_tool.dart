import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_js/flutter_js.dart';

import '../../agent/bridge/bridge_js.dart';
import '../../agent/data_fetcher/http_utils.dart' show decodeResponseBody;
import '../../agent/http_bridge.dart';
import '../../agent/log.dart';
import '../../agent/message.dart';
import '../../agent/tool.dart';
import '../../agent/tool_context.dart';
import '../../agent/tools/utils/file_utils.dart';
import '../api_config.dart';
import 'prompt.dart' as tool_prompt;

class ScriptTool extends Tool {
  ApiConfigStore? apiConfig;
  static const _httpTimeout = Duration(seconds: 15);

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
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final code = input['code'] as String?;
    if (code == null || code.trim().isEmpty) {
      return 'code is required.';
    }
    return null;
  }

  String _securePath(
    String basePath,
    String relativePath, {
    bool allowBundle = false,
  }) {
    final resolved = normalizePath(relativePath, basePath);
    if (!allowBundle && isInBundleDir(resolved, basePath)) {
      throw Exception(
        'Access to bundle/ directory is not allowed: $relativePath',
      );
    }
    return resolved;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final code = input['code'] as String;
    final basePath = context.basePath;
    final logs = <String>[];
    final sw = Stopwatch()..start();

    JavascriptRuntime? jsRuntime;
    try {
      jsRuntime = getJavascriptRuntime();

      // Pre-fetch HTTP calls for the sync Bridge.fetch pattern
      final fetchResults = await _prefetchCalls(code, context.serviceBaseUrl);

      // Console + global state
      jsRuntime.evaluate('''
        ${BridgeJs.consoleArray}
        var __fetchCache = ${jsonEncode(fetchResults)};
        var __sideEffects = { notifications: [], logs: __logs, fileOps: [] };
        var __apiConfig = ${jsonEncode(apiConfig?.toMap() ?? {})};
        var Bridge = {};
        ${BridgeJs.httpBridge}
        ${BridgeJs.dataFunctions}
        ${BridgeJs.statsFunctions}
      ''');

      // Register native channels for File ops + hash + parseXML
      _registerFileChannels(jsRuntime, basePath);
      _registerDataChannels(jsRuntime);

      // JS-side wrappers calling sendMessage
      jsRuntime.evaluate('''
        ${BridgeJs.fileBridgeSendMessage}
        ${BridgeJs.hashSendMessage}
        ${BridgeJs.globalAliases}
      ''');

      // Execute user code
      final result = jsRuntime.evaluate(code);

      // Collect console logs
      final logsResult = jsRuntime.evaluate('JSON.stringify(__logs)');
      try {
        final logList = jsonDecode(logsResult.stringResult) as List<dynamic>;
        for (final l in logList) {
          logs.add(l.toString());
        }
      } catch (_) {}

      final output = StringBuffer();
      if (logs.isNotEmpty) {
        output.writeln('Console output:');
        for (final l in logs) {
          output.writeln('  $l');
        }
        output.writeln();
      }
      final resultText = result.stringResult;
      final isBridgeError = _looksLikeBridgeChannelError(resultText);
      output.writeln(
        isBridgeError
            ? 'Bridge channel failed: $resultText'
            : 'Result: $resultText',
      );
      sw.stop();
      output.writeln(
        '\n(executed in ${sw.elapsedMilliseconds}ms, ${fetchResults.length} HTTP pre-fetched)',
      );

      log(
        'Script',
        'Executed ${code.length} chars, result: ${resultText.length} chars',
      );

      return ToolResult(
        toolUseId: toolUseId,
        content: output.toString(),
        isError: isBridgeError,
      );
    } catch (e) {
      log('Script', 'Error: $e');
      final output = StringBuffer();
      if (logs.isNotEmpty) {
        output.writeln('Console output before error:');
        for (final l in logs) {
          output.writeln('  $l');
        }
        output.writeln();
      }
      output.writeln('Error: $e');
      return ToolResult(
        toolUseId: toolUseId,
        content: output.toString(),
        isError: true,
      );
    } finally {
      jsRuntime?.dispose();
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
        final fullPath = _securePath(basePath, path);
        final file = File(fullPath);
        if (!file.existsSync()) return 'Error: File not found: $path';
        return file.readAsStringSync();
      } catch (e) {
        return 'Error: $e';
      }
    });

    js.onMessage('writeFile', (args) {
      try {
        final argList = args is List
            ? args
            : (args is String ? jsonDecode(args) as List : [args]);
        if (argList.length < 2) {
          return 'Error: writeFile requires path and content';
        }
        final path = argList[0].toString();
        final content = argList[1].toString();
        final fullPath = _securePath(basePath, path);
        final file = File(fullPath);
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(content);
        return 'OK';
      } catch (e) {
        return 'Error: $e';
      }
    });

    js.onMessage('listDir', (args) {
      try {
        final path = args is String ? args : args.toString();
        final fullPath = _securePath(basePath, path);
        final dir = Directory(fullPath);
        if (!dir.existsSync()) return 'Error: Directory not found: $path';
        final entries = dir.listSync();
        final result = entries.map((e) {
          final name = e.path.split('/').last;
          final type = e is Directory ? 'dir' : 'file';
          return {'name': name, 'type': type};
        }).toList();
        return jsonEncode(result);
      } catch (e) {
        return 'Error: $e';
      }
    });

    js.onMessage('fileExists', (args) {
      try {
        final path = args is String ? args : args.toString();
        final fullPath = _securePath(basePath, path);
        final exists =
            File(fullPath).existsSync() || Directory(fullPath).existsSync();
        return exists ? 'true' : 'false';
      } catch (e) {
        return 'Error: $e';
      }
    });

    js.onMessage('fileStat', (args) {
      try {
        final path = args is String ? args : args.toString();
        final fullPath = _securePath(basePath, path);
        final stat = FileStat.statSync(fullPath);
        if (stat.type == FileSystemEntityType.notFound) {
          return 'Error: Not found: $path';
        }
        return jsonEncode({
          'size': stat.size,
          'modified': stat.modified.toIso8601String(),
          'type': stat.type == FileSystemEntityType.directory ? 'dir' : 'file',
        });
      } catch (e) {
        return 'Error: $e';
      }
    });
  }

  void _registerDataChannels(JavascriptRuntime js) {
    js.onMessage('hash', (args) {
      try {
        final argList = args is List
            ? args
            : (args is String ? jsonDecode(args) as List : [args]);
        final text = argList[0].toString();
        final algo = argList.length > 1 ? argList[1].toString() : 'sha256';
        final bytes = utf8.encode(text);
        switch (algo) {
          case 'sha256':
            return sha256.convert(bytes).toString();
          case 'sha1':
            return sha1.convert(bytes).toString();
          case 'sha512':
            return sha512.convert(bytes).toString();
          case 'md5':
            return md5.convert(bytes).toString();
          default:
            return 'Error: Unsupported algorithm: $algo (use sha256, sha1, sha512, md5)';
        }
      } catch (e) {
        return 'Error: $e';
      }
    });

    js.onMessage('parseXML', (args) {
      try {
        final text = args is String ? args : args.toString();
        return jsonEncode(_parseXML(text));
      } catch (e) {
        return 'Error: $e';
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
          ).timeout(_httpTimeout);

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

  // --- Simple XML parser ---

  static Map<String, dynamic> _parseXML(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return {};
    final nodes = _parseXMLNodes(trimmed, 0);
    if (nodes.isEmpty) return {};
    return nodes.first;
  }

  static List<Map<String, dynamic>> _parseXMLNodes(String text, int depth) {
    if (depth > 50) return [];
    final nodes = <Map<String, dynamic>>[];
    final tagPattern = RegExp(
      r'<(\w[\w\-.]*)((?:\s+\w[\w\-.]*\s*=\s*"[^"]*")*)\s*(/?)>',
    );
    var pos = 0;

    while (pos < text.length) {
      final match = tagPattern.matchAsPrefix(text, pos);
      if (match == null) {
        pos++;
        continue;
      }

      final tagName = match.group(1)!;
      final attrStr = match.group(2) ?? '';
      final selfClose = match.group(3) == '/';

      final attrs = <String, String>{};
      final attrPattern = RegExp(r'(\w[\w\-.]*)\s*=\s*"([^"]*)"');
      for (final am in attrPattern.allMatches(attrStr)) {
        attrs[am.group(1)!] = am.group(2)!;
      }

      if (selfClose) {
        nodes.add({'tag': tagName, if (attrs.isNotEmpty) 'attrs': attrs});
        pos = match.end;
        continue;
      }

      final closeTag = '</$tagName>';
      final closeIdx = text.indexOf(closeTag, match.end);
      if (closeIdx == -1) {
        pos = match.end;
        continue;
      }

      final inner = text.substring(match.end, closeIdx).trim();
      final hasChildTags = RegExp(r'<\w').hasMatch(inner);

      final node = <String, dynamic>{
        'tag': tagName,
        if (attrs.isNotEmpty) 'attrs': attrs,
      };

      if (hasChildTags) {
        node['children'] = _parseXMLNodes(inner, depth + 1);
      } else if (inner.isNotEmpty) {
        node['text'] = inner;
      }

      nodes.add(node);
      pos = closeIdx + closeTag.length;
    }

    return nodes;
  }
}
