// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../agent/agent.dart' show ToolConfirmResult;
import 'markdown_style.dart';

import '../agent/agent_status.dart';
import '../agent/notification_queue.dart';
import '../features/finance/chat_models.dart';
import 'i18n/app_localizations.dart';
import 'task_list_widget.dart';

part 'dashboard_chat_bubbles.dart';
part 'dashboard_chat_event.dart';
part 'dashboard_chat_content.dart';
part 'dashboard_chat_questions.dart';
part 'dashboard_chat_event_widgets.dart';

class DashboardChatPanel extends StatelessWidget {
  final List<ChatItem> items;
  final bool chatCollapsed;
  final bool fullscreenMode;
  final AgentStatus? agentStatus;
  final String? turnSummary;
  final List<Map<String, dynamic>> tasks;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final String hintText;
  final bool transparent;
  final Widget? header;
  final String? contextInfo;

  const DashboardChatPanel({
    super.key,
    required this.items,
    this.chatCollapsed = false,
    this.fullscreenMode = false,
    this.agentStatus,
    this.turnSummary,
    this.tasks = const [],
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.hintText = '',
    this.transparent = false,
    this.header,
    this.contextInfo,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: transparent ? cs.surface.withValues(alpha: 0.85) : cs.surface,
      child: Column(
        children: [
          ?header,
          if (!chatCollapsed || !fullscreenMode)
            Expanded(child: DashboardChatList(items: items)),
          DashboardStatusBar(agentStatus: agentStatus, turnSummary: turnSummary, contextInfo: contextInfo),
          TaskListWidget(tasks: tasks),
          DashboardInputBar(
            controller: controller,
            focusNode: focusNode,
            onSend: onSend,
              hintText: hintText.isEmpty ? AppLocalizations.of(context).inputMessageHint : hintText,
          ),
        ],
      ),
    );
  }
}

class DashboardChatList extends StatelessWidget {
  final List<ChatItem> items;
  final Widget? header;
  final void Function(String questionText, String optionLabel)? onSelectOption;
  final Map<String, String> collectedAnswers;
  final bool hasPendingQuestions;

  const DashboardChatList({
    super.key,
    required this.items,
    this.header,
    this.onSelectOption,
    this.collectedAnswers = const {},
    this.hasPendingQuestions = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      child: Column(children: [
        ?header,
        Expanded(
          child: items.isEmpty
              ? const SizedBox.shrink()
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  reverse: true,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final item = items[items.length - 1 - i];
                    return _ChatBubble(
                      item: item,
                      onSelectOption: onSelectOption,
                      collectedAnswers: collectedAnswers,
                      hasPendingQuestions: hasPendingQuestions,
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class DashboardInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final String hintText;
  final VoidCallback? onCancel;
  final VoidCallback? onBackground;

  const DashboardInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.hintText,
    this.onCancel,
    this.onBackground,
  });

  @override
  State<DashboardInputBar> createState() => _DashboardInputBarState();
}

class _DashboardInputBarState extends State<DashboardInputBar> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.onKeyEvent = _handleKeyEvent;
  }

  @override
  void didUpdateWidget(DashboardInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.onKeyEvent = null;
      widget.focusNode.onKeyEvent = _handleKeyEvent;
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onSend();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
      color: cs.surface,
      child: Row(children: [
        IconButton(
          icon: Icon(Icons.stop_circle_outlined, size: 16, color: cs.onSurface.withValues(alpha: widget.onCancel != null ? 0.6 : 0.15)),
          onPressed: widget.onCancel,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: EdgeInsets.zero,
          tooltip: l10n.cancel,
        ),
        IconButton(
          icon: Icon(Icons.flip_to_back, size: 16, color: cs.onSurface.withValues(alpha: widget.onBackground != null ? 0.6 : 0.15)),
          onPressed: widget.onBackground,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: EdgeInsets.zero,
          tooltip: l10n.runInBackground,
        ),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            maxLines: null,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: widget.hintText.isEmpty ? l10n.inputMessageHint : widget.hintText,
              hintStyle: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.3)),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide:
                      BorderSide(color: cs.outline.withValues(alpha: 0.2))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide:
                      BorderSide(color: cs.outline.withValues(alpha: 0.2))),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(Icons.send, size: 18, color: cs.primary),
          onPressed: widget.onSend,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
      ]),
    );
  }
}

class DashboardStatusBar extends StatelessWidget {
  final AgentStatus? agentStatus;
  final String? turnSummary;
  final String? contextInfo;

  const DashboardStatusBar({super.key, this.agentStatus, this.turnSummary, this.contextInfo});

  Widget _contextWidget(ColorScheme cs) {
    if (contextInfo == null) return const SizedBox.shrink();
    return Text(contextInfo!,
        style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.4)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final status = agentStatus;
    final summary = turnSummary;

    if (status == null && summary == null && contextInfo == null) return const SizedBox.shrink();

    // Idle — only context info
    if (status == null && summary == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        color: cs.surface,
        child: Row(children: [const Spacer(), _contextWidget(cs)]),
      );
    }

    // Turn complete — summary left, context right
    if (status == null && summary != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        color: cs.surface,
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 10, color: Colors.green.shade400),
            const SizedBox(width: 6),
            Expanded(child: Text(summary,
                style: TextStyle(fontSize: 10, color: Colors.green.shade400),
                overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            _contextWidget(cs),
          ],
        ),
      );
    }

    if (status == null) return const SizedBox.shrink();

    // Running — spinner + verb left, elapsed/tools middle, context right
    final isStalled = status.isStalled;
    final isThinking = status.verb == l10n.thinking;
    final textColor = isStalled
        ? Colors.red.shade300
        : cs.onSurface.withValues(alpha: 0.6);

    final parts = <Widget>[
      Text('${status.verb}...',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: textColor)),
    ];
    if (status.currentTool != null) {
      parts.add(const SizedBox(width: 8));
      parts.add(Text(status.currentTool!,
          style: TextStyle(fontSize: 11, color: textColor)));
      if (status.toolDetail != null && status.toolDetail!.isNotEmpty) {
        parts.add(Text(
          ' (${status.toolDetail})',
          style: TextStyle(
              fontSize: 10, color: textColor.withValues(alpha: 0.6)),
          overflow: TextOverflow.ellipsis,
        ));
      }
    }

    final rightParts = <String>[];
    rightParts.add('${status.elapsedMs ~/ 1000}s');
    if (status.displayTokens > 0) {
      rightParts.add('${status.displayTokens}tok');
    }
    if (status.toolCallTotal > 1) {
      rightParts.add(
        AppLocalizations.of(context).toolProgressText(
          status.toolCallCount,
          status.toolCallTotal,
        ),
      );
    }

    final Widget indicator = isThinking
        ? Icon(Icons.psychology, size: 12, color: Colors.amber.shade400)
        : SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: isStalled ? Colors.red.shade300 : cs.primary,
            ),
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      color: cs.surface,
      child: Row(
        children: [
          indicator,
          const SizedBox(width: 6),
          Flexible(
            fit: FlexFit.loose,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: parts
                  .map((part) => Flexible(fit: FlexFit.loose, child: part))
                  .toList(),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              rightParts.join(' · '),
              style: TextStyle(fontSize: 10, color: textColor),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
          if (contextInfo != null) ...[
            const SizedBox(width: 8),
            _contextWidget(cs),
          ],
        ],
      ),
    );
  }
}
