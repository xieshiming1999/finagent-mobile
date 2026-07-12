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

  test(
    'SourceReader creates structured macro evidence from source record',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'finagent_source_reader_macro_test_',
      );
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final source = File('${dir.path}/energy.html')
        ..writeAsStringSync(
          '<html><title>Energy Outlook</title><body>2026-07-10 oil supply risk</body></html>',
        );
      final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
      final tool = SourceReaderTool();

      final sourceResult = await tool.call('source-read', {
        'action': 'read',
        'path': source.path,
        'source': 'local-energy',
        'topic': 'energy',
      }, context);
      final sourceDecoded =
          jsonDecode(sourceResult.content) as Map<String, dynamic>;
      final sourceRecordPath = sourceDecoded['artifactHint']['path'] as String;

      final macroResult = await tool.call('macro-evidence', {
        'action': 'macroEvidence',
        'sourceRecordPath': sourceRecordPath,
        'topic': 'energy price shock',
        'region': 'global',
        'assetClass': 'commodity/equity/fund',
        'keyClaims': ['Oil supply risk may keep energy prices elevated.'],
        'affectedAssets': ['energy sector', 'airlines', 'commodity funds'],
        'confidenceEffect':
            'Raises confidence that energy-sensitive assets need scenario monitoring.',
        'freshness': 'current',
        'evidenceClass': 'public-research',
        'missingEvidence': ['No official inventory series attached yet.'],
      }, context);

      expect(macroResult.isError, isFalse);
      final decoded = jsonDecode(macroResult.content) as Map<String, dynamic>;
      expect(decoded['contract'], 'source-reader-macro-evidence-result-v1');
      expect(decoded['record']['contract'], 'macro-evidence-record-v1');
      expect(decoded['record']['title'], 'Energy Outlook');
      expect(decoded['record']['topic'], 'energy price shock');
      expect(
        decoded['record']['tradeBoundary'],
        contains('not a direct buy/sell rule'),
      );
      expect(
        File(decoded['artifactHint']['path'] as String).existsSync(),
        true,
      );
    },
  );

  test(
    'SourceReader macro evidence rejects missing structured fields',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'finagent_source_reader_macro_error_test_',
      );
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final result = await SourceReaderTool().call('macro-error', {
        'action': 'macroEvidence',
        'topic': 'rates',
      }, ToolContext(basePath: dir.path, serviceBaseUrl: ''));

      expect(result.isError, true);
      expect(result.content, contains('missing required structured fields'));
      expect(result.content, contains('do not rely on prompt text inference'));
    },
  );
}
