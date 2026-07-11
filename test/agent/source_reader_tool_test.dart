import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/source_reader_tool/source_reader_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SourceReader reads local source and persists source evidence', () async {
    final dir = Directory.systemTemp.createTempSync(
      'finagent_source_reader_tool_test_',
    );
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final source = File('${dir.path}/macro.html')
      ..writeAsStringSync(
        '<html><title>Macro Note</title><body>2026-07-11 rates matter</body></html>',
      );
    final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

    final result = await SourceReaderTool().call('source-1', {
      'action': 'read',
      'path': source.path,
      'source': 'local-test',
      'topic': 'rates',
    }, context);

    expect(result.isError, isFalse);
    final decoded = jsonDecode(result.content) as Map<String, dynamic>;
    expect(decoded['contract'], 'source-reader-result-v1');
    expect(decoded['record']['title'], 'Macro Note');
    expect(decoded['record']['publishedAt'], '2026-07-11');
    expect(decoded['record']['hash'], isNotEmpty);
    expect(File(decoded['artifactHint']['path'] as String).existsSync(), true);
  });

  test('SourceReader rejects missing source locator', () async {
    final dir = Directory.systemTemp.createTempSync(
      'finagent_source_reader_tool_error_test_',
    );
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final result = await SourceReaderTool().call('source-2', {
      'action': 'read',
    }, ToolContext(basePath: dir.path, serviceBaseUrl: ''));

    expect(result.isError, true);
    expect(result.content, contains('requires exactly one of url or path'));
  });
}
