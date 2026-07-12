import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/provider_router_tool/provider_router_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ProviderRouter routes quote with code-owned provider order and blocks',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final result =
          jsonDecode(
                (await ProviderRouterTool().call('router-1', {
                  'action': 'route',
                  'task': 'quote',
                  'preferredProviders': ['sina', 'tdx'],
                  'temporarilyBlockedProviders': ['tdx'],
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(result['contract'], 'provider-router-route-v1');
      expect(result['order'], ['sina']);
      expect(
        result['providerModules'],
        contains(
          isA<Map>()
              .having((row) => row['provider'], 'provider', 'sina')
              .having(
                (row) => row['descriptorStatus'],
                'descriptorStatus',
                'registered',
              )
              .having(
                (row) => row['descriptor']['category'],
                'category',
                'public-direct-http',
              ),
        ),
      );
      expect(
        result['descriptorSource']['registeredProviders'],
        contains('macro-official'),
      );
      expect(
        result['skipped'],
        contains(
          isA<Map>().having((row) => row['provider'], 'provider', 'tdx'),
        ),
      );
      expect(result['serialProviders'], contains('sina'));
    },
  );

  test('ProviderRouter explains credential and compatibility gates', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final result =
        jsonDecode(
              (await ProviderRouterTool().call('router-2', {
                'action': 'route',
                'task': 'macro',
                'gates': {'tushareConfigured': true},
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(result['order'], ['tushare']);
    expect(
      result['skipped'],
      contains(
        isA<Map>().having(
          (row) => row['reason'],
          'reason',
          'wind_not_configured',
        ),
      ),
    );
    expect(
      result['skipped'],
      contains(
        isA<Map>()
            .having((row) => row['provider'], 'provider', 'akshare')
            .having((row) => row['reason'], 'reason', contains('descriptor')),
      ),
    );
    expect(result['providerHealthSource']['descriptorRows'], greaterThan(0));
  });

  test(
    'ProviderRouter descriptor policy blocks unsupported mobile providers even when compatibility is requested',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final result =
          jsonDecode(
                (await ProviderRouterTool(
                      runtimeHealthProvider: () => const [],
                    ).call('router-descriptor-policy', {
                      'action': 'route',
                      'task': 'sector',
                      'gates': {'allowAkshareCompatibility': true},
                    }, context))
                    .content,
              )
              as Map<String, dynamic>;

      expect(result['order'], isNot(contains('akshare')));
      expect(
        result['providerHealth'],
        contains(
          isA<Map>()
              .having((row) => row['provider'], 'provider', 'akshare')
              .having((row) => row['reason'], 'reason', contains('descriptor')),
        ),
      );
    },
  );

  test(
    'ProviderRouter uses provider health to skip unhealthy provider',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final result =
          jsonDecode(
                (await ProviderRouterTool().call('router-health', {
                  'action': 'route',
                  'task': 'quote',
                  'providerHealth': [
                    {
                      'provider': 'tdx',
                      'status': 'runtime_unavailable',
                      'reason': 'native socket unavailable',
                    },
                  ],
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(result['order'].first, 'eastmoneyDirect');
      expect(
        result['providerHealth'],
        contains(
          isA<Map>().having(
            (row) => row['reason'],
            'reason',
            contains('runtime_unavailable'),
          ),
        ),
      );
    },
  );

  test('ProviderRouter merges runtime provider health by default', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final tool = ProviderRouterTool(
      runtimeHealthProvider: () => [
        {
          'provider': 'tdx',
          'status': 'runtime_unavailable',
          'reason': 'runtime probe failed',
          'source': 'test-runtime-health',
        },
      ],
    );

    final result =
        jsonDecode(
              (await tool.call('router-runtime-health', {
                'action': 'route',
                'task': 'quote',
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(result['order'].first, 'eastmoneyDirect');
    expect(result['providerHealthSource']['runtimeRows'], 1);
    expect(result['providerHealthSource']['contractRows'], 0);
    expect(result['providerHealthSource']['runtimeEnabled'], true);
    expect(
      result['providerHealth'],
      contains(
        isA<Map>().having(
          (row) => row['reason'],
          'reason',
          contains('runtime_unavailable'),
        ),
      ),
    );
  });

  test('ProviderRouter merges data API contract probe health', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final result =
        jsonDecode(
              (await ProviderRouterTool(
                    runtimeHealthProvider: () => const [],
                  ).call('router-contract-health', {
                    'action': 'route',
                    'task': 'fund',
                  }, context))
                  .content,
            )
            as Map<String, dynamic>;

    expect(result['providerHealthSource']['contractRows'], greaterThan(0));
    expect(
      result['providerHealth'],
      contains(
        isA<Map>()
            .having((row) => row['provider'], 'provider', 'tushare')
            .having((row) => row['reason'], 'reason', contains('contract')),
      ),
    );
  });

  test(
    'ProviderRouter can disable runtime provider health for diagnostics',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final tool = ProviderRouterTool(
        runtimeHealthProvider: () => [
          {
            'provider': 'tdx',
            'status': 'runtime_unavailable',
            'reason': 'runtime probe failed',
            'source': 'test-runtime-health',
          },
        ],
      );

      final result =
          jsonDecode(
                (await tool.call('router-runtime-health-off', {
                  'action': 'route',
                  'task': 'quote',
                  'includeRuntimeHealth': false,
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(result['order'].first, 'tdx');
      expect(result['providerHealth'], isEmpty);
      expect(result['providerHealthSource']['runtimeEnabled'], false);
    },
  );

  test('ProviderRouter rejects unsupported task through tool error', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final result = await ProviderRouterTool().call('router-3', {
      'action': 'route',
      'task': 'unknown',
    }, context);

    expect(result.isError, true);
    expect(result.content, contains('requires a supported task'));
  });
}

ToolContext _tempContext() {
  final dir = Directory.systemTemp.createTempSync(
    'finagent_provider_router_test_',
  );
  return ToolContext(basePath: dir.path, serviceBaseUrl: '');
}
