import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'llm_client.dart';
import 'log.dart';
import 'message.dart';
import 'tool.dart';

String _normalizeEffortForEndpoint(
  String effort,
  String baseUrl,
  String model,
) {
  final endpoint = baseUrl.toLowerCase();
  final modelName = model.toLowerCase();
  if (effort == 'medium' &&
      (endpoint.contains('deepseek.com') ||
          endpoint.contains('kimi') ||
          modelName.contains('deepseek') ||
          modelName.contains('kimi'))) {
    return 'high';
  }
  return effort;
}

/// LLM client for Anthropic Messages API.
///
/// Supports any endpoint implementing the Anthropic protocol:
/// - Claude (api.anthropic.com)
/// - Kimi Code (api.kimi.com/coding) — requires Anthropic protocol
///
/// Key differences from OpenAI:
/// - Auth: `x-api-key` header (not `Authorization: Bearer`)
/// - Endpoint: `/v1/messages` (not `/v1/chat/completions`)
/// - System prompt: top-level `system` field (not in messages)
/// - Tools: `input_schema` (not `parameters`)
/// - SSE: event-based (message_start, content_block_delta, etc.)
class AnthropicLLMClient extends LLMClient {
  final String model;
  final String apiKey;
  final double temperature;
  final String? userAgent;

  /// Anthropic thinking effort level.
  /// Values: "low", "medium", "high", "max". Empty string = don't send.
  final String effort;

  AnthropicLLMClient({
    required this.model,
    required this.apiKey,
    required super.baseUrl,
    this.temperature = 0.7,
    this.userAgent,
    this.effort = 'medium',
  });

  @override
  LLMClient clone() => AnthropicLLMClient(
    model: model,
    apiKey: apiKey,
    baseUrl: baseUrl,
    temperature: temperature,
    userAgent: userAgent,
    effort: effort,
  );

  @override
  Stream<SSEEvent> sendMessage({
    required List<Message> messages,
    required List<Tool> tools,
    String? systemPrompt,
    int? maxOutputTokens,
    String? model,
  }) {
    resetCancel();
    final controller = StreamController<SSEEvent>();
    _startStream(
      controller: controller,
      messages: messages,
      tools: tools,
      systemPrompt: systemPrompt,
      maxOutputTokens: maxOutputTokens,
    );
    return controller.stream;
  }

  Future<void> _startStream({
    required StreamController<SSEEvent> controller,
    required List<Message> messages,
    required List<Tool> tools,
    String? systemPrompt,
    int? maxOutputTokens,
  }) async {
    await LLMClient.semaphore.acquire();
    try {
      final requestEffort = _normalizeEffortForEndpoint(
        effort,
        baseUrl,
        model,
      );
      // Convert messages to Anthropic format, merging adjacent same-role messages
      final anthropicMessages = <Map<String, dynamic>>[];
      for (final msg in messages) {
        final converted = msg.toAnthropic();
        // Anthropic requires alternating user/assistant roles.
        // Merge consecutive same-role messages.
        if (anthropicMessages.isNotEmpty &&
            anthropicMessages.last['role'] == converted['role']) {
          final last = anthropicMessages.last;
          final lastContent = last['content'];
          final newContent = converted['content'];
          // Merge into content blocks list
          final merged = <dynamic>[];
          if (lastContent is List) {
            merged.addAll(lastContent);
          } else if (lastContent is String) {
            merged.add({'type': 'text', 'text': lastContent});
          }
          if (newContent is List) {
            merged.addAll(newContent);
          } else if (newContent is String) {
            merged.add({'type': 'text', 'text': newContent});
          }
          last['content'] = merged;
        } else {
          anthropicMessages.add(converted);
        }
      }

      // Fix orphan tool_use: if an assistant message has tool_use blocks but
      // the next message is NOT a user(tool_result), inject error tool_results.
      // This happens when tool execution fails/is interrupted and user sends a new message.
      for (var i = 0; i < anthropicMessages.length - 1; i++) {
        final msg = anthropicMessages[i];
        if (msg['role'] != 'assistant') continue;
        final content = msg['content'];
        if (content is! List) continue;

        final toolUseIds = <String>[];
        for (final block in content) {
          if (block is Map && block['type'] == 'tool_use') {
            toolUseIds.add(block['id'] as String? ?? '');
          }
        }
        if (toolUseIds.isEmpty) continue;

        // Check if next message has matching tool_results
        final next = anthropicMessages[i + 1];
        if (next['role'] != 'user') continue;
        final nextContent = next['content'];
        final existingResultIds = <String>{};
        if (nextContent is List) {
          for (final block in nextContent) {
            if (block is Map && block['type'] == 'tool_result') {
              existingResultIds.add(block['tool_use_id'] as String? ?? '');
            }
          }
        }

        // Find orphan tool_use ids (no matching tool_result)
        final orphanIds = toolUseIds
            .where((id) => !existingResultIds.contains(id))
            .toList();
        if (orphanIds.isEmpty) continue;

        log(
          'AnthropicLLM',
          'Fixing ${orphanIds.length} orphan tool_use(s) at msg $i',
        );

        // Inject error tool_results into the next user message
        final resultBlocks = orphanIds
            .map(
              (id) => {
                'type': 'tool_result',
                'tool_use_id': id,
                'content': 'Tool execution was interrupted.',
                'is_error': true,
              },
            )
            .toList();

        if (nextContent is List) {
          nextContent.insertAll(0, resultBlocks);
        } else {
          // Next message is plain text user message — convert to blocks
          final blocks = <dynamic>[...resultBlocks];
          if (nextContent != null && nextContent.toString().isNotEmpty) {
            blocks.add({'type': 'text', 'text': nextContent.toString()});
          }
          next['content'] = blocks;
        }
      }

      // Fix orphan tool_result: if a user message has tool_result blocks whose
      // tool_use_id doesn't match any tool_use in the preceding assistant message,
      // remove them. This happens when compact removes the assistant message
      // containing the tool_use but keeps the user message with tool_result.
      for (var i = 0; i < anthropicMessages.length; i++) {
        final msg = anthropicMessages[i];
        if (msg['role'] != 'user') continue;
        final content = msg['content'];
        if (content is! List) continue;

        // Collect tool_use ids from the preceding assistant message
        final precedingToolUseIds = <String>{};
        if (i > 0 && anthropicMessages[i - 1]['role'] == 'assistant') {
          final prevContent = anthropicMessages[i - 1]['content'];
          if (prevContent is List) {
            for (final block in prevContent) {
              if (block is Map && block['type'] == 'tool_use') {
                precedingToolUseIds.add(block['id'] as String? ?? '');
              }
            }
          }
        }

        // Remove tool_result blocks with no matching tool_use
        final orphanResults = <dynamic>[];
        for (final block in content) {
          if (block is Map && block['type'] == 'tool_result') {
            final toolUseId = block['tool_use_id'] as String? ?? '';
            if (!precedingToolUseIds.contains(toolUseId)) {
              orphanResults.add(block);
            }
          }
        }
        if (orphanResults.isNotEmpty) {
          log(
            'AnthropicLLM',
            'Removing ${orphanResults.length} orphan tool_result(s) at msg $i',
          );
          content.removeWhere((b) => orphanResults.contains(b));
          // If content is now empty, add a placeholder text block
          if (content.isEmpty) {
            content.add({
              'type': 'text',
              'text': '[previous tool results compacted]',
            });
          }
        }
      }

      // When thinking is enabled, Anthropic requires every assistant message
      // to contain a 'thinking' content block. Inject a placeholder for any
      // assistant message that doesn't have one (e.g. from session history
      // where reasoning was not persisted).
      if (requestEffort.isNotEmpty) {
        for (var i = 0; i < anthropicMessages.length; i++) {
          final msg = anthropicMessages[i];
          if (msg['role'] != 'assistant') continue;
          final content = msg['content'];
          if (content is List) {
            final hasThinking = content.any(
              (b) => b is Map && b['type'] == 'thinking',
            );
            if (!hasThinking) {
              content.insert(0, {'type': 'thinking', 'thinking': ''});
            }
          }
        }
      }

      // Anthropic/Bedrock requires the conversation to end with a user message.
      // If the last message is assistant (e.g. after compact), append an empty user message.
      if (anthropicMessages.isNotEmpty &&
          anthropicMessages.last['role'] == 'assistant') {
        log(
          'AnthropicLLM',
          'WARNING: last message is assistant, appending user message. '
              'Roles: ${anthropicMessages.map((m) => m['role']).toList()}',
        );
        anthropicMessages.add({'role': 'user', 'content': '继续。'});
      }

      final body = <String, dynamic>{
        'model': model,
        'max_tokens': maxOutputTokens ?? 64000,
        'messages': anthropicMessages,
        'stream': true,
      };
      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        body['system'] = systemPrompt;
      }
      if (tools.isNotEmpty) {
        final sorted = tools.toList()..sort((a, b) => a.name.compareTo(b.name));
        body['tools'] = sorted
            .map(
              (t) => {
                'name': t.name,
                'description': t.description,
                'input_schema': t.inputSchema,
              },
            )
            .toList();
      }
      if (temperature > 0) {
        body['temperature'] = temperature;
      }
      if (requestEffort.isNotEmpty) {
        body['thinking'] = {'type': 'adaptive'};
        body['output_config'] = {'effort': requestEffort};
        // Anthropic requires temperature=1 (or unset) when thinking is enabled
        body.remove('temperature');
      }

      final jsonBody = jsonEncode(body);
      log(
        'AnthropicLLM',
        'Sending ${messages.length} msgs to $model '
            '(tools=${tools.length}, body=${jsonBody.length} bytes)',
      );

      final request = http.Request('POST', Uri.parse(baseUrl));
      request.headers['Content-Type'] = 'application/json';
      request.headers['x-api-key'] = apiKey;
      request.headers['anthropic-version'] = '2023-06-01';
      final configuredUserAgent = userAgent?.trim();
      if (configuredUserAgent != null && configuredUserAgent.isNotEmpty) {
        request.headers['User-Agent'] = configuredUserAgent;
      }
      request.body = jsonBody;

      // Send with retry: exponential backoff with jitter for 429/500/529/network errors
      const maxRetries = 9;
      http.Client? httpClient;
      http.StreamedResponse? response;

      for (var attempt = 0; attempt <= maxRetries; attempt++) {
        if (cancelled) {
          controller.add(SSEError('Cancelled'));
          controller.add(SSEDone());
          await controller.close();
          return;
        }
        try {
          httpClient = createKeepAliveClient();
          final req = http.Request('POST', Uri.parse(baseUrl));
          req.headers.addAll(request.headers);
          req.body = request.body;
          response = await httpClient.send(req);

          if (response.statusCode == 200) break; // success

          final responseBody = await response.stream.bytesToString();
          httpClient.close();

          if (response.statusCode == 429 ||
              response.statusCode == 500 ||
              response.statusCode == 529) {
            if (attempt < maxRetries) {
              final delay = retryDelaySeconds(attempt, initial: 2, max: 30);
              log(
                'AnthropicLLM',
                'HTTP ${response.statusCode}, retry ${attempt + 1}/$maxRetries in ${delay}s...',
              );
              await Future.delayed(Duration(seconds: delay));
              continue;
            }
          }

          // Non-retryable error or retries exhausted
          log('AnthropicLLM', 'Error ${response.statusCode}: $responseBody');
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
              'AnthropicLLM',
              'Fetch error, retry ${attempt + 1}/$maxRetries in ${delay}s... $e',
            );
            await Future.delayed(Duration(seconds: delay));
            continue;
          }
          log('AnthropicLLM', 'All retries exhausted: $e');
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

      // Parse Anthropic SSE stream (with transparent retry on stream break before any content).
      // Format: "event: <type>\ndata: <json>\n\n"
      const maxStreamRetries = 3;
      for (
        var streamAttempt = 0;
        streamAttempt <= maxStreamRetries;
        streamAttempt++
      ) {
        final lineBuffer = StringBuffer();
        String? currentEvent;
        final toolBlocks = <int, _ToolBlock>{};
        String? stopReason;
        bool hasContent = false;

        await for (final chunk
            in response!.stream
                .transform(utf8.decoder)
                .timeout(
                  streamReadTimeout,
                  onTimeout: (sink) {
                    log(
                      'AnthropicLLM',
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

            // Parse event type
            if (trimmed.startsWith('event:')) {
              currentEvent = trimmed.substring(6).trim();
              continue;
            }

            // Parse data
            if (!trimmed.startsWith('data:')) continue;
            final data = trimmed.substring(5).trim();

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final type = json['type'] as String? ?? currentEvent ?? '';

              switch (type) {
                case 'message_start':
                  // Extract initial usage from message_start
                  final msg = json['message'] as Map<String, dynamic>?;
                  if (msg != null) {
                    final usage = msg['usage'] as Map<String, dynamic>?;
                    if (usage != null) {
                      final inputTokens =
                          (usage['input_tokens'] as num?)?.toInt() ?? 0;
                      final cacheCreation =
                          (usage['cache_creation_input_tokens'] as num?)
                              ?.toInt() ??
                          0;
                      final cacheRead =
                          (usage['cache_read_input_tokens'] as num?)?.toInt() ??
                          0;
                      controller.add(
                        SSEUsage(
                          promptTokens: inputTokens + cacheCreation + cacheRead,
                          completionTokens:
                              (usage['output_tokens'] as num?)?.toInt() ?? 0,
                        ),
                      );
                    }
                  }

                case 'content_block_start':
                  final index = json['index'] as int? ?? 0;
                  final block = json['content_block'] as Map<String, dynamic>?;
                  if (block != null && block['type'] == 'tool_use') {
                    toolBlocks[index] = _ToolBlock(
                      id: block['id'] as String? ?? '',
                      name: block['name'] as String? ?? '',
                    );
                    // Notify UI immediately so it can show tool name
                    controller.add(
                      SSEToolCallStart(
                        id: block['id'] as String? ?? '',
                        name: block['name'] as String? ?? '',
                      ),
                    );
                    hasContent = true;
                  }

                case 'content_block_delta':
                  final delta = json['delta'] as Map<String, dynamic>?;
                  if (delta == null) continue;
                  final deltaType = delta['type'] as String? ?? '';
                  final index = json['index'] as int? ?? 0;

                  switch (deltaType) {
                    case 'text_delta':
                      final text = delta['text'] as String? ?? '';
                      if (text.isNotEmpty) {
                        hasContent = true;
                        controller.add(SSETextDelta(text));
                      }
                    case 'input_json_delta':
                      final partialJson =
                          delta['partial_json'] as String? ?? '';
                      if (partialJson.isNotEmpty) {
                        toolBlocks[index]?.argsBuffer.write(partialJson);
                      }
                    case 'thinking_delta':
                      final thinking = delta['thinking'] as String? ?? '';
                      if (thinking.isNotEmpty) {
                        controller.add(SSEThinkingDelta(thinking));
                      }
                    case 'signature_delta':
                      break; // ignore signature
                  }

                case 'content_block_stop':
                  final index = json['index'] as int? ?? 0;
                  final tb = toolBlocks.remove(index);
                  if (tb != null) {
                    Map<String, dynamic> args;
                    final raw = tb.argsBuffer.toString();
                    try {
                      args = raw.isEmpty
                          ? {}
                          : jsonDecode(raw) as Map<String, dynamic>;
                    } catch (e) {
                      Map<String, dynamic>? recovered;
                      final splitIdx = raw.indexOf('}{');
                      if (splitIdx > 0) {
                        try {
                          recovered =
                              jsonDecode(raw.substring(0, splitIdx + 1))
                                  as Map<String, dynamic>;
                        } catch (_) {}
                      }
                      if (recovered != null && recovered.isNotEmpty) {
                        log(
                          'AnthropicLLM',
                          'Recovered tool args for ${tb.name} from concatenated JSON',
                        );
                        args = recovered;
                      } else {
                        log(
                          'AnthropicLLM',
                          'Tool args parse error for ${tb.name}: $e',
                        );
                        args = {};
                      }
                    }
                    controller.add(
                      SSEToolCall(id: tb.id, name: tb.name, arguments: args),
                    );
                  }

                case 'message_delta':
                  final delta = json['delta'] as Map<String, dynamic>?;
                  if (delta != null) {
                    stopReason = delta['stop_reason'] as String?;
                  }
                  final usage = json['usage'] as Map<String, dynamic>?;
                  if (usage != null) {
                    final inputTokens =
                        (usage['input_tokens'] as num?)?.toInt() ?? 0;
                    final cacheCreation =
                        (usage['cache_creation_input_tokens'] as num?)
                            ?.toInt() ??
                        0;
                    final cacheRead =
                        (usage['cache_read_input_tokens'] as num?)?.toInt() ??
                        0;
                    controller.add(
                      SSEUsage(
                        promptTokens: inputTokens + cacheCreation + cacheRead,
                        completionTokens:
                            (usage['output_tokens'] as num?)?.toInt() ?? 0,
                      ),
                    );
                  }

                case 'message_stop':
                  // Map Anthropic stop_reason to OpenAI finish_reason
                  final finishReason = switch (stopReason) {
                    'end_turn' => 'stop',
                    'tool_use' => 'tool_calls',
                    'max_tokens' => 'length',
                    'model_context_window_exceeded' => 'context_exceeded',
                    'refusal' => 'refusal',
                    'pause_turn' => 'stop',
                    _ => stopReason,
                  };
                  controller.add(SSEDone(finishReason: finishReason));
                  await controller.close();
                  httpClient?.close();
                  return;

                case 'ping':
                  break;

                case 'error':
                  final error = json['error'] as Map<String, dynamic>?;
                  final msg = error?['message'] as String? ?? 'Unknown error';
                  controller.add(SSEError(msg));
              }
            } catch (e) {
              log('AnthropicLLM', 'Parse error: $e, data: $data');
            }

            currentEvent = null;
          }
        }

        // Stream ended without message_stop
        if (!hasContent && streamAttempt < maxStreamRetries) {
          log(
            'AnthropicLLM',
            'Stream broke with no content, retry ${streamAttempt + 1}/$maxStreamRetries...',
          );
          httpClient?.close();
          await Future.delayed(Duration(seconds: 2));
          httpClient = createKeepAliveClient();
          final retryReq = http.Request('POST', Uri.parse(baseUrl));
          retryReq.headers.addAll(request.headers);
          retryReq.body = request.body;
          response = await httpClient.send(retryReq);
          if (response.statusCode != 200) break;
          continue;
        }

        if (!controller.isClosed) {
          controller.add(SSEDone());
          await controller.close();
        }
        httpClient?.close();
        return;
      } // end stream retry loop
    } catch (e) {
      if (!controller.isClosed) {
        log('AnthropicLLM', 'Error: $e');
        controller.add(SSEError(e.toString()));
        controller.add(SSEDone());
        await controller.close();
      }
    } finally {
      LLMClient.semaphore.release();
    }
  }
}

/// Accumulates a streaming tool_use content block.
class _ToolBlock {
  final String id;
  final String name;
  final StringBuffer argsBuffer = StringBuffer();

  _ToolBlock({required this.id, required this.name});
}
