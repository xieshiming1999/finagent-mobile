import 'dart:io';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/domain/market/services/finance_news_market_data_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finance news fetch exposes live source health', () async {
    final dir = await Directory.systemTemp.createTemp('finagent-news-live-');
    try {
      final service = FinanceNewsMarketDataService(
        eastmoneyFetcher: (query, limit) async => [
          {
            'title': '$query 新闻线索',
            'summary': '宏观新闻摘要',
            'source': '东方财富',
            'published_at': '2026-07-09T09:00:00.000Z',
          },
        ],
        sinaFetcher: (_, _) async => const [],
        windInvoker: (_, _, _) async {},
      );

      final result = await service.fetch(
        ToolContext(basePath: dir.path, serviceBaseUrl: ''),
        {
          'query': 'A股',
          'provider': 'eastmoneyDirect',
          'providerMode': 'strict',
          'cacheMode': 'live-only',
        },
      );

      expect(result['count'], 1);
      expect(result['sourceHealth'], {
        'status': 'live',
        'provider': 'eastmoneyDirect',
        'lastSuccessfulFetch': isA<String>(),
        'nextRetryPolicy': contains('normal cache-first reuse'),
      });
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('finance news empty provider rows remain classified failures', () async {
    final dir = await Directory.systemTemp.createTemp('finagent-news-empty-');
    try {
      final service = FinanceNewsMarketDataService(
        eastmoneyFetcher: (_, _) async => const [],
        sinaFetcher: (_, _) async => const [],
        windInvoker: (_, _, _) async {},
      );

      await expectLater(
        service.fetch(
          ToolContext(basePath: dir.path, serviceBaseUrl: ''),
          {
            'query': '不存在的新闻主题',
            'provider': 'eastmoneyDirect',
            'providerMode': 'strict',
            'cacheMode': 'live-only',
          },
        ),
        throwsA(
          predicate(
            (error) =>
                '$error'.contains('All finance news providers failed') &&
                '$error'.contains('returned empty finance news rows'),
          ),
        ),
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
