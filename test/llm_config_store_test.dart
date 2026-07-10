import 'package:flutter_test/flutter_test.dart';
import 'package:finagent/shared/llm_config.dart';

void main() {
  test('provider-specific User-Agent is persisted as plaintext metadata', () {
    final config = LLMProviderConfig(
      model: 'kimi-for-coding',
      extras: {'header_User-Agent': 'provider-specific-agent'},
    );

    final restored = LLMProviderConfig.fromJson(config.toJson());

    expect(restored.extras['header_User-Agent'], 'provider-specific-agent');
  });

  test('enabled untagged providers remain eligible for general chat', () {
    final store = LLMConfigStore()
      ..providers = [
        LLMProviderConfig(
          id: 'deepseek',
          url: 'https://api.deepseek.com/anthropic',
          endpoint: '/v1/messages',
          key: 'test-key',
          model: 'deepseek-v4-pro',
          schema: 'anthropic',
          tags: {},
        ),
        LLMProviderConfig(
          id: 'kimi',
          url: 'https://api.moonshot.cn/anthropic',
          endpoint: '/v1/messages',
          key: 'test-key',
          model: 'kimi-for-coding',
          schema: 'anthropic',
          tags: {'llm', 'multimodal'},
        ),
      ];

    final llmProviders = store.getByTag('llm');

    expect(llmProviders.map((p) => p.id), ['deepseek', 'kimi']);
    expect(store.getByTag('multimodal').map((p) => p.id), ['kimi']);
  });
}
