import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'llm_client.dart';
import 'log.dart';
import 'message.dart';
import 'tool.dart';

/// LLM client for remote OpenAI-compatible APIs.
///
/// Supports any endpoint that implements the OpenAI chat completions protocol with SSE streaming:
/// OpenAI, Claude (via proxy), DeepSeek, Qwen, etc.
/// The baseUrl should be the full URL including the path (e.g., 'https://api.deepseek.com/v1/chat/completions').
class OpenAILLMClient extends LLMClient {
  final String model;
  final String apiKey;
  final double temperature;
  final int? maxContextSize;
  final bool supportsVision;
  final String? userAgent;

  /// OpenAI reasoning effort level.
  /// Values: "none", "minimal", "low", "medium", "high", "xhigh". Empty string = don't send.
  final String reasoningEffort;
  final String thinkingType;

  OpenAILLMClient({
    required this.model,
    required this.apiKey,
    required super.baseUrl,
    this.temperature = 0.7,
    this.maxContextSize,
    this.supportsVision = false,
    this.reasoningEffort = 'medium',
    this.thinkingType = '',
    this.userAgent,
  });

  @override
  LLMClient clone() => OpenAILLMClient(
    model: model,
    apiKey: apiKey,
    baseUrl: baseUrl,
    temperature: temperature,
    maxContextSize: maxContextSize,
    supportsVision: supportsVision,
    reasoningEffort: reasoningEffort,
    thinkingType: thinkingType,
    userAgent: userAgent,
  );

  @override
  Stream<SSEEvent> sendMessage({
    required List<Message> messages,
    required List<Tool> tools,
    String? systemPrompt,
    int? maxOutputTokens,
    String? model,
  }) {
    final controller = StreamController<SSEEvent>();
    _startStream(
      controller: controller,
      messages: messages,
      tools: tools,
      systemPrompt: systemPrompt,
      maxOutputTokens: maxOutputTokens,
      modelOverride: model,
    );
    return controller.stream;
  }

  Future<void> _startStream({
    required StreamController<SSEEvent> controller,
    required List<Message> messages,
    required List<Tool> tools,
    String? systemPrompt,
    int? maxOutputTokens,
    String? modelOverride,
  }) async {
    await LLMClient.semaphore.acquire();
    try {
      final openaiMessages = <Map<String, dynamic>>[];
      if (systemPrompt != null) {
        openaiMessages.add({'role': 'system', 'content': systemPrompt});
      }
      // Collect images from tool results — OpenAI tool role doesn't support image blocks.
      // Images are batched and injected as a user message after the tool result group.
      var pendingImages = <Uint8List>[];
      for (var i = 0; i < messages.length; i++) {
        final msg = messages[i];
        openaiMessages.add(msg.toOpenAI());

        // Collect images from tool results
        if (supportsVision &&
            msg.role == Role.tool &&
            msg.toolResult?.images != null &&
            msg.toolResult!.images!.isNotEmpty) {
          pendingImages.addAll(msg.toolResult!.images!);
        }

        // Flush pending images when next message is not a tool result
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

      final body = <String, dynamic>{
        'model': modelOverride ?? model,
        'messages': openaiMessages,
        'stream': true,
        'temperature': temperature,
      };
      if (tools.isNotEmpty) {
        final sorted = tools.toList()..sort((a, b) => a.name.compareTo(b.name));
        body['tools'] = sorted.map((t) => t.toOpenAI()).toList();
      }
      if (maxOutputTokens != null) {
        body['max_completion_tokens'] = maxOutputTokens;
      }
      if (reasoningEffort.isNotEmpty) {
        body['reasoning_effort'] = reasoningEffort;
      }
      if (thinkingType.isNotEmpty) {
        body['thinking'] = {'type': thinkingType};
      }

      final jsonBody = jsonEncode(body);
      log(
        'RemoteLLM',
        'Sending ${messages.length} msgs to $model '
            '(tools=${tools.length}, body=${jsonBody.length} bytes)',
      );

      final reqHeaders = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };
      final configuredUserAgent = userAgent?.trim();
      if (configuredUserAgent != null && configuredUserAgent.isNotEmpty) {
        reqHeaders['User-Agent'] = configuredUserAgent;
      }

      // Send with retry: exponential backoff with jitter for 400/500/529/network errors
      const maxRetries = 9;
      http.Client? httpClient;
      http.StreamedResponse? response;

      for (var attempt = 0; attempt <= maxRetries; attempt++) {
        try {
          httpClient = createKeepAliveClient();
          final req = http.Request('POST', Uri.parse(baseUrl));
          req.headers.addAll(reqHeaders);
          req.body = jsonBody;
          response = await httpClient.send(req);

          if (response.statusCode == 200) break;

          final responseBody = await response.stream.bytesToString();
          httpClient.close();

          if (response.statusCode == 400 ||
              response.statusCode == 500 ||
              response.statusCode == 529) {
            if (attempt < maxRetries) {
              final delay = retryDelaySeconds(attempt, initial: 2, max: 30);
              log(
                'RemoteLLM',
                'HTTP ${response.statusCode}, retry ${attempt + 1}/$maxRetries in ${delay}s...',
              );
              await Future.delayed(Duration(seconds: delay));
              continue;
            }
          }

          log('RemoteLLM', 'Error ${response.statusCode}: $responseBody');
          controller.add(
            SSEError('API error ${response.statusCode}: $responseBody'),
          );
          controller.add(SSEDone());
          await controller.close();
          return;
        } catch (e) {
          httpClient?.close();
          if (attempt < maxRetries) {
            final delay = retryDelaySeconds(attempt, initial: 2, max: 20);
            log(
              'RemoteLLM',
              'Fetch error, retry ${attempt + 1}/$maxRetries in ${delay}s... $e',
            );
            await Future.delayed(Duration(seconds: delay));
            continue;
          }
          log('RemoteLLM', 'All retries exhausted: $e');
          controller.add(
            SSEError('Network error after $maxRetries retries: $e'),
          );
          controller.add(SSEDone());
          await controller.close();
          return;
        }
      }

      if (response == null || response.statusCode != 200) {
        controller.add(SSEError('Failed after $maxRetries retries'));
        controller.add(SSEDone());
        await controller.close();
        return;
      }

      // Parse SSE stream (with transparent retry on stream break before any content)
      const maxStreamRetries = 3;
      for (
        var streamAttempt = 0;
        streamAttempt <= maxStreamRetries;
        streamAttempt++
      ) {
        final lineBuffer = StringBuffer();
        final toolAccumulator = _ToolCallAccumulator();
        final thinkingBuffer = StringBuffer();
        String? lastFinishReason;
        bool hasContent = false;

        await for (final chunk
            in response!.stream
                .transform(utf8.decoder)
                .timeout(
                  streamReadTimeout,
                  onTimeout: (sink) {
                    log(
                      'RemoteLLM',
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
            if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;

            var data = trimmed.substring(5).trim();
            if (data == '[DONE]') {
              if (thinkingBuffer.isNotEmpty) {
                final thinking = thinkingBuffer.toString();
                log('RemoteLLM', 'Thinking (${thinking.length} chars)');
              }
              if (toolAccumulator.hasData && lastFinishReason != 'length') {
                for (final tc in toolAccumulator.build()) {
                  controller.add(tc);
                }
              }
              controller.add(SSEDone(finishReason: lastFinishReason));
              await controller.close();
              httpClient?.close();
              return;
            }

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;

              if (json.containsKey('error')) {
                controller.add(
                  SSEError(json['error']['message'] as String? ?? 'Unknown'),
                );
                continue;
              }

              if (json.containsKey('usage')) {
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

              if (finishReason != null) lastFinishReason = finishReason;

              if (delta != null) {
                // Thinking/reasoning
                final reasoningValue =
                    delta['reasoning'] ?? delta['reasoning_content'];
                if (reasoningValue != null) {
                  final reasoning = reasoningValue as String;
                  if (reasoning.isNotEmpty) {
                    thinkingBuffer.write(reasoning);
                    controller.add(SSEThinkingDelta(reasoning));
                  }
                }

                // Text content
                if (delta.containsKey('content') && delta['content'] != null) {
                  final content = delta['content'] as String;
                  if (content.isNotEmpty) {
                    hasContent = true;
                    controller.add(SSETextDelta(content));
                  }
                }

                // Tool calls
                if (delta.containsKey('tool_calls')) {
                  hasContent = true;
                  final toolCalls = delta['tool_calls'] as List<dynamic>;
                  for (final tc in toolCalls) {
                    toolAccumulator.addDelta(tc as Map<String, dynamic>);
                  }
                }
              }

              if (finishReason == 'tool_calls' && toolAccumulator.hasData) {
                for (final tc in toolAccumulator.build()) {
                  controller.add(tc);
                }
              }
            } catch (e) {
              log('RemoteLLM', 'Parse error: $e');
            }
          }
        }

        // Stream ended without [DONE]
        if (!hasContent && streamAttempt < maxStreamRetries) {
          log(
            'RemoteLLM',
            'Stream broke with no content, retry ${streamAttempt + 1}/$maxStreamRetries...',
          );
          httpClient?.close();
          await Future.delayed(Duration(seconds: 2));
          httpClient = createKeepAliveClient();
          final req = http.Request('POST', Uri.parse(baseUrl));
          req.headers.addAll(reqHeaders);
          req.body = jsonBody;
          response = await httpClient.send(req);
          if (response.statusCode != 200) break;
          continue;
        }

        // Had content or exhausted retries — finish normally
        if (!controller.isClosed) {
          if (toolAccumulator.hasData) {
            for (final tc in toolAccumulator.build()) {
              controller.add(tc);
            }
          }
          controller.add(SSEDone());
          await controller.close();
        }
        httpClient?.close();
        return;
      } // end stream retry loop
    } catch (e) {
      if (!controller.isClosed) {
        log('RemoteLLM', 'Error: $e');
        controller.add(SSEError(e.toString()));
        controller.add(SSEDone());
        await controller.close();
      }
    } finally {
      LLMClient.semaphore.release();
    }
  }
}

// ─── Tool Call Accumulator ───

class _ToolCallAccumulator {
  final Map<int, _ToolCallBuilder> _builders = {};

  void addDelta(Map<String, dynamic> tc) {
    final index = tc['index'] as int? ?? 0;
    _builders.putIfAbsent(index, () => _ToolCallBuilder());
    final builder = _builders[index]!;

    if (tc.containsKey('id') && tc['id'] != null) {
      builder.id = tc['id'] as String;
    }

    final fn = tc['function'] as Map<String, dynamic>?;
    if (fn != null) {
      if (fn.containsKey('name') && fn['name'] != null) {
        builder.name = fn['name'] as String;
      }
      if (fn.containsKey('arguments') && fn['arguments'] != null) {
        final argFragment = fn['arguments'] as String;
        if (!(argFragment == '{}' && builder.argsBuffer.isEmpty)) {
          builder.argsBuffer.write(argFragment);
        }
      }
    }
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
        log('RemoteLLM', 'Tool args parse error for ${builder.name}: $e');
        args = {};
      }
      results.add(
        SSEToolCall(id: builder.id!, name: builder.name!, arguments: args),
      );
    }
    _builders.clear();
    return results;
  }

  bool get hasData => _builders.isNotEmpty;
}

class _ToolCallBuilder {
  String? id;
  String? name;
  final StringBuffer argsBuffer = StringBuffer();
}
