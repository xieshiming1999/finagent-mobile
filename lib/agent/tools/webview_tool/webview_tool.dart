import 'dart:typed_data';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart';

class WebViewResult {
  final String content;
  final Uint8List? screenshot;
  final String? screenshotPath;
  final bool isError;

  const WebViewResult({
    required this.content,
    this.screenshot,
    this.screenshotPath,
    this.isError = false,
  });
}

typedef WebViewHandler =
    Future<WebViewResult> Function(String action, Map<String, dynamic> params);

class WebViewTool extends Tool {
  final Map<String, WebViewHandler> _handlers = {};
  String? _activeTarget;

  void registerHandler(String target, WebViewHandler handler) {
    _handlers[target] = handler;
    _activeTarget = target;
  }

  void unregisterHandler(String target) {
    _handlers.remove(target);
    if (_activeTarget == target) {
      _activeTarget = _handlers.keys.lastOrNull;
    }
  }

  @override
  String get name => 'WebView';

  @override
  String get description =>
      'Interact with a WebView: query (execute JS / read DOM), click, input text, screenshot, navigate to URL. Use query with javascript to run JS in the page; use navigate with url to load a page.';

  @override
  String get prompt => webViewToolPrompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': [
          'query',
          'click',
          'input',
          'screenshot',
          'navigate',
          'back',
          'forward',
          'reload',
          'refresh',
          'get_info',
          'scroll',
          'wait_for',
          'get_html',
        ],
        'description':
            'query: execute JS or read DOM via selector/javascript. '
            'click: click element by selector. '
            'input: type text into a field. '
            'screenshot: capture viewport as PNG. '
            'navigate: load a URL (requires url param, NOT for JS execution). '
            'reload: native browser reload. '
            'refresh: re-read active file-backed page from disk when supported. '
            'scroll: scroll the page. '
            'wait_for: wait for a selector to appear.',
      },
      'target': {
        'type': 'string',
        'description': 'WebView target name. Omit for the active WebView.',
      },
      'selector': {'type': 'string', 'description': 'CSS selector.'},
      'javascript': {'type': 'string', 'description': 'JavaScript to execute.'},
      'text': {'type': 'string', 'description': 'Text to type (input action).'},
      'url': {
        'type': 'string',
        'description': 'URL to load (navigate action).',
      },
      'x': {'type': 'integer', 'description': 'Scroll x position or offset.'},
      'y': {'type': 'integer', 'description': 'Scroll y position or offset.'},
      'absolute': {
        'type': 'boolean',
        'description': 'Scroll to absolute position if true (default false).',
      },
      'timeout': {
        'type': 'integer',
        'description': 'Timeout in ms for wait_for (default 5000).',
      },
    },
    'required': ['action'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = input['action'] as String?;
    if (action == null) return 'action is required';

    switch (action) {
      case 'query':
        if (input['javascript'] == null && input['selector'] == null) {
          return 'query requires javascript or selector';
        }
      case 'click' || 'wait_for':
        if (input['selector'] == null) return '$action requires selector';
      case 'input':
        if (input['selector'] == null) return 'input requires selector';
        if (input['text'] == null) return 'input requires text';
      case 'navigate':
        if (input['url'] == null) return 'navigate requires url';
    }
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = input['action'] as String;
    final target = input['target'] as String? ?? _activeTarget;

    if (target == null || !_handlers.containsKey(target)) {
      final available = _handlers.keys.join(', ');
      return ToolResult(
        toolUseId: toolUseId,
        content: available.isEmpty
            ? 'No WebView available.'
            : 'WebView target "$target" not found. Available: $available',
        isError: true,
      );
    }

    try {
      final result = await _handlers[target]!(action, input);
      return ToolResult(
        toolUseId: toolUseId,
        content: result.content,
        images: result.screenshot != null ? [result.screenshot!] : null,
        imagePaths: result.screenshotPath != null
            ? [result.screenshotPath!]
            : null,
        isError: result.isError,
      );
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'WebView error: $e',
        isError: true,
      );
    }
  }
}
