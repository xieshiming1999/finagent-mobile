import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

MarkdownStyleSheet chatMarkdownStyle(
  BuildContext context, {
  bool isUser = false,
  double fontSize = 13,
}) {
  final cs = Theme.of(context).colorScheme;
  final textColor = isUser ? cs.onPrimary : null;

  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: TextStyle(fontSize: fontSize, color: textColor),
    strong: TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: fontSize,
      color: textColor,
    ),
    code: TextStyle(
      fontSize: fontSize - 1,
      color: cs.onSurface,
      backgroundColor: cs.surfaceContainerHighest,
    ),
    codeblockDecoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    blockquoteDecoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      border: Border(left: BorderSide(color: cs.primary, width: 3)),
      borderRadius: BorderRadius.circular(4),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    tableBorder: TableBorder.all(color: cs.outline.withValues(alpha: 0.3)),
    tableHead: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize, color: textColor),
    tableBody: TextStyle(fontSize: fontSize, color: textColor),
  );
}
