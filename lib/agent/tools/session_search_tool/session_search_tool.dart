import 'dart:convert';

import '../../message.dart';
import '../../session_index.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Search across conversation history using full-text search.
class SessionSearchTool extends Tool {
  @override
  String get name => 'SessionSearch';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description':
            'Search keywords (supports Chinese). If empty, returns recent sessions.',
      },
      'limit': {'type': 'integer', 'description': 'Max results (default 10).'},
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
    final query = (input['query'] as String?)?.trim();
    final limit = (input['limit'] as int?) ?? 10;

    final index = context.sessionIndex;
    if (index == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Session search index is not available.',
        isError: true,
      );
    }

    if (query == null || query.isEmpty) {
      final recent = index.listRecent(limit: limit);
      if (recent.isEmpty) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'No session history found.',
        );
      }
      return ToolResult(toolUseId: toolUseId, content: _formatRecent(recent));
    }

    final results = index.search(query, limit: limit);
    if (results.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'No sessions found for "$query".',
      );
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: _formatResults(results, query),
    );
  }

  String _formatRecent(List<SearchResult> results) {
    return jsonEncode({
      'contract': 'session-search-result-v1',
      'mode': 'recent',
      'count': results.length,
      'results': [for (final result in results) _row(result)],
      'summary': results.isEmpty
          ? 'No session history found.'
          : 'Recent sessions: ${results.length}',
    });
  }

  String _formatResults(List<SearchResult> results, String query) {
    return jsonEncode({
      'contract': 'session-search-result-v1',
      'mode': 'search',
      'query': query,
      'count': results.length,
      'results': [for (final result in results) _row(result)],
      'summary': 'Found ${results.length} result(s) for "$query".',
    });
  }

  Map<String, dynamic> _row(SearchResult result) => {
    'sessionId': result.sessionId,
    'title': result.title,
    'snippet': result.snippet,
    'timestamp': result.timestamp?.toIso8601String(),
    'filePath': result.filePath,
  };
}
