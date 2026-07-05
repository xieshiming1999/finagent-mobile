import 'package:flutter/material.dart';

import 'i18n/app_localizations.dart';
import 'llm_config.dart';

class LlmProviderCard extends StatelessWidget {
  const LlmProviderCard({
    super.key,
    required this.llmStore,
    required this.provider,
    required this.index,
    required this.expandedIndex,
    required this.showKeys,
    required this.applyChange,
    required this.onExpandedIndexChanged,
  });

  final LLMConfigStore llmStore;
  final LLMProviderConfig provider;
  final int index;
  final int expandedIndex;
  final bool showKeys;
  final void Function(VoidCallback action) applyChange;
  final ValueChanged<int> onExpandedIndexChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final expanded = expandedIndex == index;
    final tagLabels = {
      'llm': l10n.llmTag,
      'multimodal': l10n.vision,
      'generation': l10n.generationTag,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: provider.enabled
          ? cs.surfaceContainerHighest
          : cs.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Column(
        children: [
          InkWell(
            onTap: () => onExpandedIndexChanged(expanded ? -1 : index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    provider.provider,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: provider.enabled
                          ? cs.onSurface
                          : cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.model.isNotEmpty ? provider.model : l10n.noModel,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final tag in provider.tags)
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tagLabels[tag] ?? tag,
                        style: TextStyle(fontSize: 10, color: cs.primary),
                      ),
                    ),
                  const SizedBox(width: 4),
                  if (index > 0)
                    _iconBtn(
                      Icons.arrow_upward,
                      () => applyChange(() {
                        llmStore.moveUp(index);
                        if (expandedIndex == index) {
                          onExpandedIndexChanged(index - 1);
                        }
                      }),
                    ),
                  if (index < llmStore.providers.length - 1)
                    _iconBtn(
                      Icons.arrow_downward,
                      () => applyChange(() {
                        llmStore.moveDown(index);
                        if (expandedIndex == index) {
                          onExpandedIndexChanged(index + 1);
                        }
                      }),
                    ),
                  PopupMenuButton<String>(
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onSelected: (v) => applyChange(() {
                      if (v == 'copy') {
                        llmStore.duplicate(index);
                        onExpandedIndexChanged(index + 1);
                      }
                      if (v == 'toggle') provider.enabled = !provider.enabled;
                      if (v == 'delete') {
                        llmStore.removeAt(index);
                        if (expandedIndex == index) onExpandedIndexChanged(-1);
                      }
                    }),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'copy', child: Text(l10n.duplicate)),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(
                          provider.enabled ? l10n.disable : l10n.enable,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          l10n.delete,
                          style: TextStyle(color: cs.error),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'openai',
                        label: Text(
                          l10n.openaiProvider,
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                      ButtonSegment(
                        value: 'anthropic',
                        label: Text(
                          l10n.anthropicProvider,
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                      ButtonSegment(
                        value: 'proxy',
                        label: Text(
                          l10n.serviceProxy,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                    selected: {provider.schema},
                    onSelectionChanged: (v) =>
                        applyChange(() => provider.schema = v.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _inlineField(
                    l10n.apiUrl,
                    provider.url,
                    (v) => provider.url = v,
                    hint: 'https://api.openai.com',
                  ),
                  _inlineField(
                    l10n.endpoint,
                    provider.endpoint,
                    (v) => provider.endpoint = v,
                    hint: provider.defaultEndpoint,
                  ),
                  _inlineField(
                    l10n.apiKey,
                    provider.key,
                    (v) => provider.key = v,
                    hint: 'sk-...',
                    obscure: !showKeys,
                  ),
                  _inlineField(
                    l10n.model,
                    provider.model,
                    (v) => provider.model = v,
                    hint: 'gpt-4o / claude-sonnet-4-6',
                  ),
                  _inlineField(
                    'User-Agent',
                    provider.extras['header_User-Agent'] ?? '',
                    (v) {
                      final value = v.trim();
                      if (value.isEmpty) {
                        provider.extras.remove('header_User-Agent');
                      } else {
                        provider.extras['header_User-Agent'] = value;
                      }
                    },
                    hint: 'Optional provider-specific request header',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.advanced,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _inlineField(
                    provider.schema == 'anthropic'
                        ? 'max_tokens'
                        : 'max_completion_tokens',
                    provider.maxOutputTokens.toString(),
                    (v) => provider.maxOutputTokens = int.tryParse(v) ?? 8192,
                    hint: provider.schema == 'anthropic' ? '64000' : '8192',
                  ),
                  _inlineField(
                    'max_context_length',
                    provider.maxContextLength.toString(),
                    (v) =>
                        provider.maxContextLength = int.tryParse(v) ?? 160000,
                    hint: '160000',
                  ),
                  _inlineField(
                    'compact_threshold',
                    provider.compactThreshold.toString(),
                    (v) =>
                        provider.compactThreshold = double.tryParse(v) ?? 0.85,
                    hint: '0.85',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.thinking,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (provider.schema == 'openai')
                    _buildDropdown(
                      label: 'reasoning_effort',
                      value: provider.extras['reasoning_effort'] ?? 'medium',
                      options: const [
                        '',
                        'none',
                        'minimal',
                        'low',
                        'medium',
                        'high',
                        'xhigh',
                      ],
                      onChanged: (v) => applyChange(
                        () => provider.extras['reasoning_effort'] = v,
                      ),
                    ),
                  if (provider.schema == 'anthropic')
                    _buildDropdown(
                      label: 'effort',
                      value: provider.extras['effort'] ?? 'medium',
                      options: const ['', 'low', 'medium', 'high', 'max'],
                      onChanged: (v) =>
                          applyChange(() => provider.extras['effort'] = v),
                    ),
                  if (provider.schema != 'openai' &&
                      provider.schema != 'anthropic')
                    _inlineField(
                      'thinking_mode',
                      provider.extras['thinking_mode'] ?? '',
                      (v) => provider.extras['thinking_mode'] = v,
                      hint: 'auto / enabled / disabled',
                    ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.tags,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final tag in ['llm', 'multimodal', 'generation'])
                        FilterChip(
                          label: Text(
                            tagLabels[tag] ?? tag,
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: provider.tags.contains(tag),
                          onSelected: (v) => applyChange(() {
                            if (v) {
                              provider.tags.add(tag);
                            } else {
                              provider.tags.remove(tag);
                            }
                          }),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 14),
    ),
  );

  Widget _inlineField(
    String label,
    String value,
    void Function(String) onChanged, {
    String? hint,
    bool obscure = false,
  }) {
    final ctrl = TextEditingController(text: value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              obscureText: obscure,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> options,
    required void Function(String) onChanged,
  }) {
    const defaultLabel = '(default)';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: options.contains(value) ? value : options.first,
              items: options
                  .map(
                    (o) => DropdownMenuItem(
                      value: o,
                      child: Text(
                        o.isEmpty ? defaultLabel : o,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
