import 'package:finagent/agent/tools/tool_catalog_tool/provider_module_descriptors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('provider module descriptors cover required finance families', () {
    final providers = providerModuleDescriptors
        .map((descriptor) => descriptor.provider)
        .toSet();

    expect(
      providers,
      containsAll({
        'local',
        'eastmoneyDirect',
        'tdx',
        'yfinance',
        'wind',
        'tushare',
        'sina',
        'tencent',
        'akshare',
        'macro-official',
        'macro-research',
        'search',
        'xueqiu',
        'ui-artifact',
      }),
    );
  });

  test('provider module descriptors expose routing and evidence contracts', () {
    for (final descriptor in providerModuleDescriptors) {
      expect(descriptor.provider.trim(), isNotEmpty);
      expect(descriptor.title.trim(), isNotEmpty);
      expect(descriptor.category.trim(), isNotEmpty);
      expect(descriptor.runtimeAvailability, isNotEmpty);
      expect(descriptor.agentPaths, isNotEmpty);
      expect(descriptor.requiredAccess, isNotEmpty);
      expect(descriptor.capabilityFamilies, isNotEmpty);
      expect(descriptor.schemaDecision.trim(), isNotEmpty);
      expect(descriptor.cacheReadbackContract.trim(), isNotEmpty);
      expect(descriptor.healthEvidence.trim(), isNotEmpty);
      expect(descriptor.routingPolicy.trim(), isNotEmpty);
      expect(descriptor.uiSurface.trim(), isNotEmpty);
      expect(descriptor.discovery.trim(), isNotEmpty);
      expect(descriptor.status.trim(), isNotEmpty);
    }
  });

  test('macro descriptors are evidence-oriented, not trading signals', () {
    final official = providerModuleDescriptors.singleWhere(
      (descriptor) => descriptor.provider == 'macro-official',
    );
    final research = providerModuleDescriptors.singleWhere(
      (descriptor) => descriptor.provider == 'macro-research',
    );

    expect(official.category, 'macro-official-api-provider');
    expect(official.routingPolicy, contains('not direct buy/sell rules'));
    expect(official.capabilityFamilies, contains('numeric-series'));
    expect(research.category, 'research-source-provider');
    expect(research.schemaDecision, contains('key claims/hash'));
  });
}
