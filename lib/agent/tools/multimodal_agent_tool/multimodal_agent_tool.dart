import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../llm_client.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../utils/file_utils.dart';

class MultimodalAgentTool extends Tool {
  final LLMClient? Function() visionClientProvider;

  MultimodalAgentTool({required this.visionClientProvider});

  @override
  String get name => 'MultimodalAgent';

  @override
  String get description =>
      'Analyze image/audio files with a configured multimodal model. Use this only when the required evidence is visual and cannot be verified from page text, DOM, or structured tool output.';

  @override
  String get prompt =>
      'Dispatch image analysis to the configured vision model.\n'
      'Parameters:\n'
      '- files: image file paths, usually from WebView screenshot or Read image result\n'
      '- task: what to inspect in the image\n'
      'Do not use this for generated HTML dashboard/page readability checks when WebView query/get_info/get_html or DOM selectors can answer the task. Calling this only to confirm text, table rows, headings, or source labels in a DOM-readable page is incorrect. Use this after WebView(action:"screenshot") only for visual-only evidence such as chart pixels, canvas rendering, image/crop content, or layout overlap when text/DOM evidence is insufficient.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'files': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Image file paths to analyze',
      },
      'task': {'type': 'string', 'description': 'Visual analysis task'},
    },
    'required': ['files', 'task'],
  };

  @override
  bool get isReadOnly => true;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final rawFiles = input['files'];
    final task = (input['task'] as String? ?? '').trim();
    if (rawFiles is! List || rawFiles.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'files is required and must contain at least one image path',
        isError: true,
      );
    }
    if (task.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'task is required',
        isError: true,
      );
    }

    final client = visionClientProvider();
    if (client == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'No multimodal provider configured. Add an enabled LLM provider tagged "multimodal" in settings.',
        isError: true,
      );
    }

    final images = <Uint8List>[];
    final resolvedPaths = <String>[];
    for (final item in rawFiles) {
      final resolved = normalizePath(item.toString(), context.basePath);
      final lower = resolved.toLowerCase();
      if (!lower.endsWith('.png') &&
          !lower.endsWith('.jpg') &&
          !lower.endsWith('.jpeg') &&
          !lower.endsWith('.webp') &&
          !lower.endsWith('.gif')) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'Unsupported multimodal file type: $resolved',
          isError: true,
        );
      }
      final file = File(resolved);
      if (!file.existsSync()) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'File not found: $resolved',
          isError: true,
        );
      }
      images.add(file.readAsBytesSync());
      resolvedPaths.add(resolved);
    }

    final messages = [Message(role: Role.user, content: task, images: images)];
    final text = StringBuffer();
    final errors = <String>[];
    await for (final event in client.sendMessage(
      systemPrompt:
          'You are a vision analysis sub-agent. Inspect the provided image(s), answer the task directly, and do not call tools.',
      messages: messages,
      tools: const [],
      maxOutputTokens: 4096,
    )) {
      if (event is SSETextDelta) text.write(event.text);
      if (event is SSEError) errors.add(event.message);
    }

    if (errors.isNotEmpty && text.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'MultimodalAgent failed: ${errors.join('; ')}',
        isError: true,
      );
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: '[MultimodalAgent]\n\n${text.toString().trim()}',
      imagePaths: resolvedPaths,
    );
  }
}
