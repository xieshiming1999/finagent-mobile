import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/session_index.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/session_search_tool/session_search_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SessionSearch returns structured search rows', () async {
    final root = Directory.systemTemp.createTempSync('session_search_contract_');
    try {
      final sessionsDir = Directory('${root.path}/sessions')..createSync();
      File('${sessionsDir.path}/current.jsonl').writeAsStringSync('{}\n');
      final index = SessionIndex(sessionsDir: sessionsDir.path);
      index.indexMessage(
        sessionId: 's1',
        sessionFile: 'current.jsonl',
        role: 'assistant',
        content: 'Watchlist add 300059 with risk boundary',
        timestamp: DateTime.utc(2026, 7, 1, 10),
        sessionTitle: '历史股票建议',
      );
      final context = ToolContext(
        basePath: root.path,
        serviceBaseUrl: 'http://localhost:3033',
      )..sessionIndex = index;

      final result = await SessionSearchTool().call(
        'search',
        {'query': 'Watchlist', 'limit': 5},
        context,
      );

      final decoded = jsonDecode(result.content) as Map<String, dynamic>;
      expect(decoded['contract'], 'session-search-result-v1');
      expect(decoded['mode'], 'search');
      expect(decoded['count'], 1);
      expect(decoded['results'], isA<List>());
      expect(decoded['results'][0]['sessionId'], 's1');
      expect(decoded['results'][0]['snippet'], contains('Watchlist'));
    } finally {
      if (root.existsSync()) root.deleteSync(recursive: true);
    }
  });
}
