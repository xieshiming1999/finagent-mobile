import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'log.dart';
import 'message.dart';
import 'tool.dart';

/// Shared HTTP client with TCP keepalive enabled.
http.Client createKeepAliveClient() {
  final inner = HttpClient()
    ..idleTimeout = const Duration(minutes: 5)
    ..connectionTimeout = const Duration(seconds: 30);
  return IOClient(inner);
}

/// Stream read timeout: if no data received for this duration, the stream
/// is considered stalled and should be retried. Prevents indefinite hangs
/// when TCP connection stays open but server stops sending.
const streamReadTimeout = Duration(seconds: 180);

final _rng = Random();

/// Exponential backoff with jitter (inspired by kimi-cli's tenacity).
int retryDelaySeconds(int attempt, {double initial = 1.0, double max = 30.0}) {
  final base = initial * (1 << attempt); // 1, 2, 4, 8, 16...
  final capped = base.clamp(initial, max);
  final jitter = capped * 0.5 * _rng.nextDouble(); // 0..+50%
  return (capped + jitter).round();
}

/// Events emitted during SSE streaming from the server.
sealed class SSEEvent {}

class SSETextDelta extends SSEEvent {
  final String text;
  SSETextDelta(this.text);
}

class SSEToolCall extends SSEEvent {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  SSEToolCall({required this.id, required this.name, required this.arguments});
}

class SSEDone extends SSEEvent {
  final String? finishReason; // "stop", "tool_calls", "length", etc.
  SSEDone({this.finishReason});
}

class SSEError extends SSEEvent {
  final String message;
  SSEError(this.message);
}

/// Token 用量统计（从 LLM 响应的 usage 字段解析）。
class SSEUsage extends SSEEvent {
  final int promptTokens;
  final int completionTokens;
  SSEUsage({required this.promptTokens, required this.completionTokens});
}

/// LLM thinking/reasoning content (e.g., Ollama's `reasoning` field).
class SSEThinkingDelta extends SSEEvent {
  final String text;
  SSEThinkingDelta(this.text);
}

/// Emitted when a tool call starts streaming (before args are complete).
/// Allows UI to show tool name immediately instead of "thinking...".
class SSEToolCallStart extends SSEEvent {
  final String id;
  final String name;
  SSEToolCallStart({required this.id, required this.name});
}

/// Incremental output character count (for tool arg deltas that don't go through SSETextDelta).
class SSEOutputChars extends SSEEvent {
  final int chars;
  SSEOutputChars(this.chars);
}

/// Accumulates streaming tool_call deltas into complete tool calls.
class _ToolCallAccumulator {
  final Map<int, _ToolCallBuilder> _builders = {};

  /// Returns the number of argument chars consumed (for output char tracking).
  int addDelta(Map<String, dynamic> tc) {
    final index = tc['index'] as int? ?? 0;
    _builders.putIfAbsent(index, () => _ToolCallBuilder());
    final builder = _builders[index]!;

    if (tc.containsKey('id') && tc['id'] != null) {
      builder.id = tc['id'] as String;
    }

    int chars = 0;
    final fn = tc['function'] as Map<String, dynamic>?;
    if (fn != null) {
      if (fn.containsKey('name') && fn['name'] != null) {
        builder.name = fn['name'] as String;
      }
      if (fn.containsKey('arguments') && fn['arguments'] != null) {
        final argFragment = fn['arguments'] as String;
        // Skip empty object fragments '{}' — some LLM proxies send these
        // before the real arguments, causing concatenation like '{}{"key":"val"}'
        if (argFragment == '{}' && builder.argsBuffer.isEmpty) {
          // Skip — wait for real arguments
        } else {
          builder.argsBuffer.write(argFragment);
          chars = argFragment.length;
        }
      }
    }
    return chars;
  }

  List<SSEToolCall> build() {
    final results = <SSEToolCall>[];
    for (final builder in _builders.values) {
      if (builder.id == null || builder.name == null) continue;
      Map<String, dynamic> args;
      final rawArgs = builder.argsBuffer.toString();
      try {
        args = rawArgs.isEmpty
            ? {}
            : jsonDecode(rawArgs) as Map<String, dynamic>;
      } catch (e) {
        // Try to recover: if rawArgs has concatenated JSON like '{}{"key":"val"}',
        // split at '}{' and take the last valid JSON object
        Map<String, dynamic>? recovered;
        final splitIdx = rawArgs.indexOf('}{');
        if (splitIdx > 0) {
          try {
            recovered =
                jsonDecode(rawArgs.substring(splitIdx + 1))
                    as Map<String, dynamic>;
          } catch (_) {}
        }
        if (recovered != null && recovered.isNotEmpty) {
          log(
            'LLM',
            'Recovered tool args for ${builder.name} from concatenated JSON',
          );
          args = recovered;
        } else {
          log(
            'LLM',
            'Tool call args parse error for ${builder.name}: $e, raw: $rawArgs',
          );
          args = {};
        }
      }
      results.add(
        SSEToolCall(id: builder.id!, name: builder.name!, arguments: args),
      );
    }
    _builders.clear(); // Prevent duplicate emissions
    return results;
  }

  bool get hasData => _builders.isNotEmpty;

  /// Append raw arguments string when JSON parsing of the SSE line fails.
  void appendRawArgs(int index, String fragment) {
    _builders.putIfAbsent(index, () => _ToolCallBuilder());
    _builders[index]!.argsBuffer.write(fragment);
  }
}

class _ToolCallBuilder {
  String? id;
  String? name;
  final StringBuffer argsBuffer = StringBuffer();
}

/// Concurrency limiter for LLM API requests.
/// All LLMClient instances (including clones) share one static semaphore.
/// Mobile default: maxConcurrent=1 (serialize). Desktop can increase.
class LLMSemaphore {
  int maxConcurrent;
  int _running = 0;
  final _queue = <Completer<void>>[];

  LLMSemaphore({this.maxConcurrent = 1});

  Future<void> acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
  }

  void release() {
    if (_running > 0) _running--;
    if (_queue.isNotEmpty && _running < maxConcurrent) {
      _running++;
      _queue.removeAt(0).complete();
    }
  }

  int get running => _running;
  int get waiting => _queue.length;
}

/// Client for communicating with the CC Mobile Server.
/// Sends OpenAI-format requests and receives SSE streaming responses.
class LLMClient {
  static LLMSemaphore semaphore = LLMSemaphore(maxConcurrent: 1);

  String baseUrl;
  http.Client? _httpClient;
  bool _cancelled = false;

  LLMClient({String baseUrl = 'http://localhost:3033'})
    : baseUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

  bool get cancelled => _cancelled;

  /// Create a new instance with the same configuration (for sub-agents).
  LLMClient clone() => LLMClient(baseUrl: baseUrl);

  Stream<SSEEvent> sendMessage({
    required List<Message> messages,
    required List<Tool> tools,
    String? systemPrompt,
    int? maxOutputTokens,
    String? model,
  }) {
    final controller = StreamController<SSEEvent>();
    _httpClient = createKeepAliveClient();

    _startStream(
      controller: controller,
      messages: messages,
      tools: tools,
      systemPrompt: systemPrompt,
      maxOutputTokens: maxOutputTokens,
      model: model,
    );

    return controller.stream;
  }

  Future<void> _startStream({
    required StreamController<SSEEvent> controller,
    required List<Message> messages,
    required List<Tool> tools,
    String? systemPrompt,
    int? maxOutputTokens,
    String? model,
  }) async {
    await semaphore.acquire();
    try {
      final openaiMessages = <Map<String, dynamic>>[];
      var pendingImages = <Uint8List>[];

      if (systemPrompt != null) {
        openaiMessages.add({'role': 'system', 'content': systemPrompt});
      }

      for (var i = 0; i < messages.length; i++) {
        final msg = messages[i];
        openaiMessages.add(msg.toOpenAI());

        if (msg.role == Role.tool &&
            msg.toolResult?.images != null &&
            msg.toolResult!.images!.isNotEmpty) {
          pendingImages.addAll(msg.toolResult!.images!);
        }

        if (pendingImages.isNotEmpty) {
          final nextIsToolResult =
              i + 1 < messages.length && messages[i + 1].role == Role.tool;
          if (!nextIsToolResult) {
            final parts = <Map<String, dynamic>>[];
            for (final img in pendingImages) {
              parts.add({
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/png;base64,${base64Encode(img)}',
                },
              });
            }
            parts.add({
              'type': 'text',
              'text': '[Images from tool results above]',
            });
            openaiMessages.add({'role': 'user', 'content': parts});
            pendingImages = [];
          }
        }
      }

      final body = jsonEncode({
        'messages': openaiMessages,
        'tools': tools.map((t) => t.toOpenAI()).toList(),
        'stream': true,
        'max_tokens': ?maxOutputTokens,
        'model': ?model,
      });

      log(
        'LLM',
        'Sending ${messages.length} messages, body length: ${body.length}',
      );

      const retryableStatusCodes = {400, 408, 429, 500, 502, 503, 504};
      const maxRetries = 10;

      http.StreamedResponse? response;
      for (var attempt = 0; attempt <= maxRetries; attempt++) {
        try {
          final request = http.Request(
            'POST',
            Uri.parse('$baseUrl/v1/chat/completions'),
          );
          request.headers['Content-Type'] = 'application/json';
          request.body = body;

          _httpClient ??= createKeepAliveClient();
          response = await _httpClient!.send(request);

          if (response.statusCode == 200) break;

          final responseBody = await response.stream.bytesToString();

          if (!retryableStatusCodes.contains(response.statusCode) ||
              attempt >= maxRetries) {
            log(
              'LLM',
              'Error ${response.statusCode} (attempt ${attempt + 1}/${maxRetries + 1}): $responseBody',
            );
            controller.add(
              SSEError('Server error ${response.statusCode}: $responseBody'),
            );
            controller.add(SSEDone());
            await controller.close();
            return;
          }

          final delay = retryDelaySeconds(attempt, initial: 2, max: 30);
          log(
            'LLM',
            'Retryable error ${response.statusCode}, waiting ${delay}s before retry (${attempt + 1}/$maxRetries)...',
          );
          controller.add(
            SSETextDelta(
              '\n[LLM error ${response.statusCode}, retrying in ${delay}s...]\n',
            ),
          );
          await Future<void>.delayed(Duration(seconds: delay));
          _httpClient?.close();
          _httpClient = createKeepAliveClient();
        } catch (e) {
          const maxNetworkRetries = 3;
          if (attempt >= maxNetworkRetries) {
            log('LLM', 'Network error after $maxNetworkRetries retries: $e');
            controller.add(SSEError('Network error: $e'));
            controller.add(SSEDone());
            await controller.close();
            return;
          }
          final delay = retryDelaySeconds(attempt, initial: 2, max: 15);
          log(
            'LLM',
            'Network error ($e), waiting ${delay}s before retry (${attempt + 1}/$maxRetries)...',
          );
          controller.add(
            SSETextDelta('\n[Network error, retrying in ${delay}s...]\n'),
          );
          await Future<void>.delayed(Duration(seconds: delay));
          _httpClient?.close();
          _httpClient = createKeepAliveClient();
        }
      }

      if (response == null || response.statusCode != 200) {
        controller.add(SSEError('Failed after ${maxRetries + 1} attempts'));
        controller.add(SSEDone());
        await controller.close();
        return;
      }

      // Parse SSE stream, accumulating tool call deltas
      final lineBuffer = StringBuffer();
      final toolAccumulator = _ToolCallAccumulator();
      String? lastFinishReason;

      try {
        await for (final chunk
            in response.stream
                .transform(utf8.decoder)
                .timeout(
                  streamReadTimeout,
                  onTimeout: (sink) {
                    log(
                      'LLM',
                      'Stream read timeout (${streamReadTimeout.inSeconds}s no data)',
                    );
                    sink.addError(
                      TimeoutException('Stream stalled', streamReadTimeout),
                    );
                    sink.close();
                  },
                )) {
          lineBuffer.write(chunk);
          final lines = lineBuffer.toString().split('\n');
          lineBuffer.clear();
          lineBuffer.write(lines.removeLast());

          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            if (!trimmed.startsWith('data:')) continue;

            var data = trimmed.substring(5);
            if (data.startsWith(' ')) data = data.substring(1);
            if (data == '[DONE]') {
              // Emit accumulated tool calls before done — but NOT if truncated
              if (toolAccumulator.hasData && lastFinishReason != 'length') {
                for (final tc in toolAccumulator.build()) {
                  controller.add(tc);
                }
              }
              controller.add(SSEDone(finishReason: lastFinishReason));
              await controller.close();
              return;
            }

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;

              if (json.containsKey('error')) {
                controller.add(SSEError(json['error']['message'] as String));
                continue;
              }

              // 解析 usage（通常在最后一个 chunk 里）
              if (json['usage'] != null) {
                final usage = json['usage'] as Map<String, dynamic>;
                controller.add(
                  SSEUsage(
                    promptTokens:
                        (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
                    completionTokens:
                        (usage['completion_tokens'] as num?)?.toInt() ?? 0,
                  ),
                );
              }

              final choices = json['choices'] as List<dynamic>?;
              if (choices == null || choices.isEmpty) continue;

              final choice = choices[0] as Map<String, dynamic>;
              final delta = choice['delta'] as Map<String, dynamic>?;
              final finishReason = choice['finish_reason'] as String?;

              // Track last finish reason for SSEDone
              if (finishReason != null) {
                lastFinishReason = finishReason;
              }

              if (delta != null) {
                // Thinking/reasoning (e.g. DeepSeek, Ollama)
                if (delta.containsKey('reasoning') &&
                    delta['reasoning'] != null) {
                  final reasoning = delta['reasoning'] as String;
                  if (reasoning.isNotEmpty) {
                    controller.add(SSEThinkingDelta(reasoning));
                  }
                }

                // Text content
                if (delta.containsKey('content') && delta['content'] != null) {
                  controller.add(SSETextDelta(delta['content'] as String));
                }

                // Tool call deltas — accumulate, don't emit yet
                if (delta.containsKey('tool_calls')) {
                  final toolCalls = delta['tool_calls'] as List<dynamic>;
                  for (final tc in toolCalls) {
                    final chars = toolAccumulator.addDelta(
                      tc as Map<String, dynamic>,
                    );
                    if (chars > 0) {
                      controller.add(SSEOutputChars(chars));
                    }
                  }
                }
              }

              // When finish_reason is "tool_calls", emit accumulated tool calls
              if (finishReason == 'tool_calls') {
                if (toolAccumulator.hasData) {
                  final built = toolAccumulator.build();
                  log('LLM', 'Tool calls: ${built.length}');
                  for (final tc in built) {
                    log('LLM', '-> ${tc.name}(${tc.arguments})');
                    controller.add(tc);
                  }
                } else {
                  log(
                    'LLM',
                    'finish_reason=tool_calls but no accumulated data',
                  );
                }
              }
            } catch (e) {
              log('LLM', 'Parse error: $e');
              log('LLM', 'Raw data: $data');
            }
          }
        }
      } on TimeoutException {
        // Stream stalled — treat as connection error
        if (!controller.isClosed) {
          controller.add(
            SSEError(
              'Connection stalled (no data for ${streamReadTimeout.inSeconds}s)',
            ),
          );
          controller.add(SSEDone());
          await controller.close();
        }
        return;
      }

      if (!controller.isClosed) {
        if (toolAccumulator.hasData) {
          for (final tc in toolAccumulator.build()) {
            controller.add(tc);
          }
        }
        controller.add(SSEDone());
        await controller.close();
      }
    } catch (e) {
      if (!controller.isClosed) {
        controller.add(SSEError(e.toString()));
        controller.add(SSEDone());
        await controller.close();
      }
    } finally {
      semaphore.release();
    }
  }

  void cancel() {
    _cancelled = true;
    _httpClient?.close();
    _httpClient = null;
  }

  void resetCancel() {
    _cancelled = false;
  }
}
