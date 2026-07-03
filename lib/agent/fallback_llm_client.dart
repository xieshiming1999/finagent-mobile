import 'dart:async';

import 'llm_client.dart';
import 'log.dart';
import 'message.dart';
import 'tool.dart';

/// LLM client with automatic fallback: tries clients in order,
/// switches to the next on persistent errors.
class FallbackLLMClient extends LLMClient {
  final List<LLMClient> _clients;
  int _activeIndex = 0;

  FallbackLLMClient(List<LLMClient> clients)
    : _clients = clients,
      super(baseUrl: clients.first.baseUrl);

  @override
  LLMClient clone() =>
      FallbackLLMClient(_clients.map((c) => c.clone()).toList());

  @override
  Stream<SSEEvent> sendMessage({
    required List<Message> messages,
    required List<Tool> tools,
    String? systemPrompt,
    int? maxOutputTokens,
    String? model,
  }) {
    final controller = StreamController<SSEEvent>();
    _tryWithFallback(
      controller,
      messages,
      tools,
      systemPrompt,
      maxOutputTokens,
      model,
    );
    return controller.stream;
  }

  Future<void> _tryWithFallback(
    StreamController<SSEEvent> controller,
    List<Message> messages,
    List<Tool> tools,
    String? systemPrompt,
    int? maxOutputTokens,
    String? model,
  ) async {
    final startIndex = _activeIndex;
    var attempts = 0;

    while (attempts < _clients.length) {
      final client = _clients[_activeIndex];
      log(
        'FallbackLLM',
        'Trying ${client.baseUrl} (${_activeIndex + 1}/${_clients.length})',
      );

      final events = <SSEEvent>[];
      bool hasContent = false;
      bool hasError = false;

      try {
        await for (final event in client.sendMessage(
          messages: messages,
          tools: tools,
          systemPrompt: systemPrompt,
          maxOutputTokens: maxOutputTokens,
          model: model,
        )) {
          if (event is SSETextDelta ||
              event is SSEToolCall ||
              event is SSEToolCallStart) {
            hasContent = true;
          }
          if (event is SSEError && !hasContent) {
            hasError = true;
            events.add(event);
            continue;
          }
          if (event is SSEDone && hasError && !hasContent) {
            break;
          }
          controller.add(event);
          if (event is SSEDone) {
            if (!controller.isClosed) await controller.close();
            return;
          }
        }
      } catch (e) {
        log('FallbackLLM', 'Client error: $e');
        hasError = true;
      }

      if (hasContent) {
        if (!controller.isClosed) {
          controller.add(SSEDone());
          await controller.close();
        }
        return;
      }

      // No content received — try next client
      attempts++;
      _activeIndex = (startIndex + attempts) % _clients.length;
      log('FallbackLLM', 'Falling back to ${_clients[_activeIndex].baseUrl}');
    }

    // All clients failed
    if (!controller.isClosed) {
      controller.add(SSEError('All ${_clients.length} LLM endpoints failed'));
      controller.add(SSEDone());
      await controller.close();
    }
  }

  @override
  void cancel() {
    for (final c in _clients) {
      c.cancel();
    }
  }
}
