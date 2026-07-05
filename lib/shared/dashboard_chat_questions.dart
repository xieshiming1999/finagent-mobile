part of 'dashboard_chat.dart';

class _UserQuestionCard extends StatelessWidget {
  final ChatItem item;
  final void Function(String questionText, String optionLabel)? onSelectOption;
  final Map<String, String> collectedAnswers;
  final bool isActive;

  const _UserQuestionCard({
    required this.item,
    this.onSelectOption,
    this.collectedAnswers = const {},
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final meta = item.metadata;
    if (meta == null) return const SizedBox.shrink();
    final questionsList = meta['questions'] as List<dynamic>?;
    if (questionsList == null || questionsList.isEmpty) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < questionsList.length; i++) ...[
            if (i > 0) const Divider(height: 12),
            _buildQuestionSection(
              context,
              questionsList[i] as Map<String, dynamic>,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestionSection(
    BuildContext context,
    Map<String, dynamic> question,
  ) {
    final cs = Theme.of(context).colorScheme;
    final questionText = question['question'] as String? ?? '';
    final header = question['header'] as String? ?? '';
    final options = question['options'] as List<dynamic>? ?? [];
    final answered = collectedAnswers[questionText];
    final isAnswered = answered != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: isAnswered
                  ? Colors.green.withValues(alpha: 0.2)
                  : cs.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isAnswered ? '$header: $answered' : header,
              style: TextStyle(
                fontSize: 10,
                color: isAnswered ? Colors.green : cs.primary,
              ),
            ),
          ),
        Text(questionText, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in options)
              _optionChip(
                context,
                option as Map<String, dynamic>,
                questionText,
                isAnswered,
                answered,
              ),
          ],
        ),
      ],
    );
  }

  Widget _optionChip(
    BuildContext context,
    Map<String, dynamic> option,
    String questionText,
    bool isAnswered,
    String? answered,
  ) {
    final label = option['label'] as String? ?? '';
    final description = option['description'] as String? ?? '';
    final isSelected = answered == label;
    final enabled = isActive && !isAnswered && onSelectOption != null;

    if (isSelected) {
      return Tooltip(
        message: description,
        child: FilledButton(
          onPressed: null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            textStyle: const TextStyle(fontSize: 12),
          ),
          child: Text(label),
        ),
      );
    }
    return Tooltip(
      message: description,
      child: OutlinedButton(
        onPressed: enabled ? () => onSelectOption!(questionText, label) : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          textStyle: const TextStyle(fontSize: 12),
          side: BorderSide(
            color: enabled
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _ThinkingBlock extends StatefulWidget {
  final String text;

  const _ThinkingBlock({required this.text});

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.psychology, size: 12, color: Colors.amber.shade400),
              const SizedBox(width: 4),
              Text(
                l10n.thinking,
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 12,
                color: cs.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(top: 2, bottom: 4),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
            ),
            child: SelectableText(
              widget.text,
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
      ],
    );
  }
}
