import 'package:flutter/material.dart';

import 'i18n/app_localizations.dart';
import 'api_config.dart';
import 'llm_config.dart';
import 'settings_page_llm_provider_card.dart';

class LlmKeysTab extends StatelessWidget {
  const LlmKeysTab({
    super.key,
    required this.llmStore,
    required this.apiConfigStore,
    required this.showKeys,
    required this.expandedIndex,
    required this.newKeyCtrl,
    required this.newValueCtrl,
    required this.onSaveAll,
    required this.applyChange,
    required this.onShowKeysChanged,
    required this.onExpandedIndexChanged,
  });

  final LLMConfigStore llmStore;
  final ApiConfigStore apiConfigStore;
  final bool showKeys;
  final int expandedIndex;
  final TextEditingController newKeyCtrl;
  final TextEditingController newValueCtrl;
  final VoidCallback onSaveAll;
  final void Function(VoidCallback action) applyChange;
  final ValueChanged<bool> onShowKeysChanged;
  final ValueChanged<int> onExpandedIndexChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text(
              l10n.llmProviders,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                showKeys ? Icons.visibility : Icons.visibility_off,
                size: 16,
              ),
              tooltip: showKeys ? l10n.hideKeys : l10n.showKeys,
              onPressed: () => onShowKeysChanged(!showKeys),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onSaveAll,
              icon: const Icon(Icons.save, size: 16),
              label: Text(l10n.save),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (llmStore.providers.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l10n.noLlmConfigured,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
            ),
          ),
        for (var i = 0; i < llmStore.providers.length; i++)
          LlmProviderCard(
            llmStore: llmStore,
            provider: llmStore.providers[i],
            index: i,
            expandedIndex: expandedIndex,
            showKeys: showKeys,
            applyChange: applyChange,
            onExpandedIndexChanged: onExpandedIndexChanged,
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => applyChange(() {
                llmStore.add(LLMProviderConfig());
                onExpandedIndexChanged(llmStore.providers.length - 1);
              }),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.addLlm),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          l10n.dataSources,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.dataSourcesHelp,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurface.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 8),
        _buildConfigField(
          'TUSHARE_TOKEN',
          l10n.tushareProToken,
          hint: l10n.tushareTokenHelp,
        ),
        const SizedBox(height: 8),
        _buildConfigField(
          'WIND_API_KEY',
          l10n.windAifinMarketApiKey,
          hint: l10n.windApiKeyHelp,
        ),
        const SizedBox(height: 8),
        _buildConfigField(
          'BRAVE_SEARCH_KEY',
          l10n.braveSearchApiKey,
          hint: l10n.braveSearchHelp,
        ),
        const SizedBox(height: 8),
        _buildConfigField(
          'TAVILY_API_KEY',
          l10n.tavilySearchApiKey,
          hint: l10n.tavilySearchHelp,
        ),
        const SizedBox(height: 8),
        _buildConfigField(
          'FRED_API_KEY',
          l10n.fredApiKey,
          hint: l10n.fredApiKeyHelp,
        ),
        const SizedBox(height: 8),
        _buildConfigField(
          'BEA_API_KEY',
          l10n.beaApiKey,
          hint: l10n.beaApiKeyHelp,
        ),
        const SizedBox(height: 8),
        _buildConfigField(
          'EIA_API_KEY',
          l10n.eiaApiKey,
          hint: l10n.eiaApiKeyHelp,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.xueqiuSimTradeHelp,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurface.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 8),
        _buildConfigField(
          'XQ_COOKIE',
          l10n.xueqiuCookie,
          hint: l10n.xueqiuCookieHelp,
        ),
        const SizedBox(height: 8),
        _buildConfigField(
          'XQ_PORTFOLIO',
          l10n.portfolioCodes,
          hint: l10n.portfolioCodesHelp,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.apiKeys,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.customKeyValueHelp,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurface.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in apiConfigStore.all.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    showKeys
                        ? entry.value
                        : (entry.value.length > 20
                              ? '${entry.value.substring(0, 8)}...'
                              : '••••••••'),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  onPressed: () =>
                      applyChange(() => apiConfigStore.remove(entry.key)),
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: newKeyCtrl,
                decoration: InputDecoration(
                  hintText: l10n.keyName,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: newValueCtrl,
                obscureText: !showKeys,
                decoration: InputDecoration(
                  hintText: l10n.valueLower,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              onPressed: () => applyChange(() {
                final key = newKeyCtrl.text.trim();
                final value = newValueCtrl.text.trim();
                if (key.isNotEmpty && value.isNotEmpty) {
                  apiConfigStore.set(key, value);
                  newKeyCtrl.clear();
                  newValueCtrl.clear();
                }
              }),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConfigField(String key, String label, {String? hint}) {
    final value = apiConfigStore.get(key) ?? '';
    final ctrl = TextEditingController(text: value);
    return TextField(
      controller: ctrl,
      obscureText: !showKeys,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          icon: Icon(
            value.isNotEmpty ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: value.isNotEmpty ? Colors.green : null,
          ),
          onPressed: () => applyChange(() {
            final v = ctrl.text.trim();
            if (v.isNotEmpty) {
              apiConfigStore.set(key, v);
            } else {
              apiConfigStore.remove(key);
            }
          }),
        ),
      ),
      style: const TextStyle(fontSize: 13),
      onSubmitted: (v) {
        if (v.trim().isNotEmpty) {
          applyChange(() => apiConfigStore.set(key, v.trim()));
        }
      },
    );
  }
}
