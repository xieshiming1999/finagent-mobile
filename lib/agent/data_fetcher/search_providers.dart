import 'dart:convert';

import 'package:http/http.dart' as http;

/// Brave Search API wrapper. Free: 1000 queries/month.
/// Requires BRAVE_SEARCH_KEY in Settings.
class BraveSearchProvider {
  final String apiKey;

  BraveSearchProvider({required this.apiKey});

  Future<List<Map<String, dynamic>>> search(
    String query, {
    int count = 10,
  }) async {
    final response = await http
        .get(
          Uri.parse(
            'https://api.search.brave.com/res/v1/web/search',
          ).replace(queryParameters: {'q': query, 'count': '$count'}),
          headers: {
            'Accept': 'application/json',
            'Accept-Encoding': 'gzip',
            'X-Subscription-Token': apiKey,
          },
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 429) {
      throw Exception(
        'Brave Search: rate limit exceeded (1000/month free tier)',
      );
    }
    if (response.statusCode != 200) {
      throw Exception('Brave Search: HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final webResults = json['web'] as Map<String, dynamic>? ?? {};
    final results = webResults['results'] as List? ?? [];

    return results.take(count).map((r) {
      final item = r as Map<String, dynamic>;
      return {
        'title': item['title'] ?? '',
        'url': item['url'] ?? '',
        'content': item['description'] ?? '',
        'engine': 'brave',
      };
    }).toList();
  }
}

/// Tavily Search API wrapper. Free: 1000 queries/month.
/// Designed for AI agents — returns structured content, not just URLs.
/// Requires TAVILY_API_KEY in Settings.
class TavilySearchProvider {
  final String apiKey;

  TavilySearchProvider({required this.apiKey});

  Future<List<Map<String, dynamic>>> search(
    String query, {
    int maxResults = 10,
    bool includeAnswer = true,
  }) async {
    final response = await http
        .post(
          Uri.parse('https://api.tavily.com/search'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'api_key': apiKey,
            'query': query,
            'max_results': maxResults,
            'include_answer': includeAnswer,
            'search_depth': 'basic',
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 429) {
      throw Exception('Tavily: rate limit exceeded (1000/month free tier)');
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Tavily: HTTP ${response.statusCode}: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final results = json['results'] as List? ?? [];
    final answer = json['answer'] as String?;

    final output = results.take(maxResults).map((r) {
      final item = r as Map<String, dynamic>;
      return {
        'title': item['title'] ?? '',
        'url': item['url'] ?? '',
        'content': item['content'] ?? '',
        'score': item['score'],
        'engine': 'tavily',
      };
    }).toList();

    // Tavily's AI-generated answer is a unique feature
    if (answer != null && answer.isNotEmpty && output.isNotEmpty) {
      output.first['ai_answer'] = answer;
    }

    return output;
  }
}
