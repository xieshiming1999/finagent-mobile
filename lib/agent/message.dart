import 'dart:convert';
import 'dart:typed_data';

/// Message models for the Agent system.
/// Independent of any UI framework.

enum Role { user, assistant, tool }

/// Represents an LLM's request to call a tool.
class ToolUse {
  final String id;
  final String name;
  final Map<String, dynamic> input;

  const ToolUse({required this.id, required this.name, required this.input});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'input': input};

  factory ToolUse.fromJson(Map<String, dynamic> json) => ToolUse(
    id: json['id'] as String,
    name: json['name'] as String,
    input: Map<String, dynamic>.from(json['input'] as Map),
  );
}

/// Represents the result of executing a tool.
class ToolResult {
  final String toolUseId;
  String content;
  final bool isError;

  /// Optional image data returned by the tool (e.g., rendered PDF page).
  /// When present, sent as image content block alongside text in tool_result.
  /// Mutable — old images may be stripped to limit body size.
  List<Uint8List>? images;

  /// File paths where images were persisted (for session serialization).
  final List<String>? imagePaths;

  ToolResult({
    required this.toolUseId,
    required this.content,
    this.isError = false,
    this.images,
    this.imagePaths,
  });

  Map<String, dynamic> toJson() => {
    'toolUseId': toolUseId,
    'content': content,
    if (isError) 'isError': true,
    // Images not persisted to session — too large for JSONL
  };

  factory ToolResult.fromJson(Map<String, dynamic> json) => ToolResult(
    toolUseId: json['toolUseId'] as String,
    content: json['content'] as String,
    isError: json['isError'] as bool? ?? false,
  );
}

/// A single message in the conversation.
class Message {
  final Role role;
  final String content;
  final List<ToolUse>? toolUses;
  final ToolResult? toolResult;
  final DateTime? timestamp;
  final bool isCompactSummary;

  /// True for recap/away-summary messages inserted after user inactivity.
  final bool isRecap;

  /// Optional image data attached to a user message (for multimodal models).
  /// Supports multiple images. Mutable — old images may be stripped to limit body size.
  List<Uint8List>? images;

  /// Optional audio data attached to a user message.
  final Uint8List? audioBytes;
  final String? audioFormat; // 'wav', 'mp3', 'm4a'

  /// LLM thinking/reasoning content. Mutable — cleared for historical turns.
  /// Only kept for the current turn to maintain reasoning coherence across
  /// multi-step tool calls. Not persisted to session files.
  String? reasoning;

  Message({
    required this.role,
    this.content = '',
    this.toolUses,
    this.toolResult,
    this.timestamp,
    this.isCompactSummary = false,
    this.isRecap = false,
    this.images,
    this.audioBytes,
    this.audioFormat,
    this.reasoning,
  });

  /// Backward compat: single image shortcut.
  Uint8List? get imageBytes =>
      images?.isNotEmpty == true ? images!.first : null;

  /// Convert to OpenAI chat format for the server API.
  Map<String, dynamic> toOpenAI() {
    switch (role) {
      case Role.user:
        final hasImages = images != null && images!.isNotEmpty;
        final hasAudio = audioBytes != null;
        if (hasImages || hasAudio) {
          // Multi-part content (OpenAI vision/audio format)
          final parts = <Map<String, dynamic>>[];
          // Images first (recommended order for multimodal)
          if (hasImages) {
            for (final img in images!) {
              parts.add({
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/png;base64,${base64Encode(img)}',
                },
              });
            }
          }
          // Audio
          if (hasAudio) {
            parts.add({
              'type': 'input_audio',
              'input_audio': {
                'data': base64Encode(audioBytes!),
                'format': audioFormat ?? 'wav',
              },
            });
          }
          // Text last
          if (content.isNotEmpty) {
            parts.add({'type': 'text', 'text': content});
          }
          return {'role': 'user', 'content': parts};
        }
        return {'role': 'user', 'content': content};

      case Role.assistant:
        // When assistant has tool_calls with empty content, some LLM APIs
        // (e.g. Claude proxy) reject empty string "". Use null instead.
        final assistantContent =
            (content.isEmpty && toolUses != null && toolUses!.isNotEmpty)
            ? null
            : content;
        final map = <String, dynamic>{
          'role': 'assistant',
          'content': assistantContent,
        };
        if (reasoning != null && reasoning!.isNotEmpty) {
          map['reasoning'] = reasoning;
        }
        if (toolUses != null && toolUses!.isNotEmpty) {
          map['tool_calls'] = toolUses!.map((t) {
            return {
              'id': t.id,
              'type': 'function',
              'function': {'name': t.name, 'arguments': jsonEncode(t.input)},
            };
          }).toList();
        }
        return map;

      case Role.tool:
        final hasImages =
            toolResult!.images != null && toolResult!.images!.isNotEmpty;
        if (hasImages) {
          // OpenAI tool role only supports string content.
          // Append image as a follow-up user message instead (handled by caller).
          // Here we just return the text part.
          return {
            'role': 'tool',
            'tool_call_id': toolResult!.toolUseId,
            'content': toolResult!.content,
          };
        }
        return {
          'role': 'tool',
          'tool_call_id': toolResult!.toolUseId,
          'content': toolResult!.content,
        };
    }
  }

  /// Convert to Anthropic Messages API format.
  Map<String, dynamic> toAnthropic() {
    switch (role) {
      case Role.user:
        final hasImages = images != null && images!.isNotEmpty;
        if (hasImages) {
          final parts = <Map<String, dynamic>>[];
          for (final img in images!) {
            parts.add({
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/png',
                'data': base64Encode(img),
              },
            });
          }
          if (content.isNotEmpty) {
            parts.add({'type': 'text', 'text': content});
          }
          return {'role': 'user', 'content': parts};
        }
        return {'role': 'user', 'content': content};

      case Role.assistant:
        final blocks = <Map<String, dynamic>>[];
        // Include thinking block if reasoning is available
        if (reasoning != null && reasoning!.isNotEmpty) {
          blocks.add({'type': 'thinking', 'thinking': reasoning!});
        }
        if (content.isNotEmpty) {
          blocks.add({'type': 'text', 'text': content});
        }
        if (toolUses != null) {
          for (final tu in toolUses!) {
            blocks.add({
              'type': 'tool_use',
              'id': tu.id,
              'name': tu.name,
              'input': tu.input,
            });
          }
        }
        return {'role': 'assistant', 'content': blocks};

      case Role.tool:
        final resultContent = <Map<String, dynamic>>[];
        // Images first
        if (toolResult!.images != null) {
          for (final img in toolResult!.images!) {
            resultContent.add({
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/png',
                'data': base64Encode(img),
              },
            });
          }
        }
        // Text
        resultContent.add({'type': 'text', 'text': toolResult!.content});
        return {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': toolResult!.toolUseId,
              'content': resultContent,
              if (toolResult!.isError) 'is_error': true,
            },
          ],
        };
    }
  }

  /// Serialize to JSON for JSONL session persistence.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'role': role.name, 'content': content};
    if (toolUses != null && toolUses!.isNotEmpty) {
      json['toolUses'] = toolUses!.map((t) => t.toJson()).toList();
    }
    if (toolResult != null) {
      json['toolResult'] = toolResult!.toJson();
    }
    if (timestamp != null) {
      json['timestamp'] = timestamp!.toIso8601String();
    }
    if (isCompactSummary) {
      json['isCompactSummary'] = true;
    }
    if (isRecap) {
      json['isRecap'] = true;
    }
    if (images != null && images!.isNotEmpty) {
      json['imageBase64List'] = images!.map(base64Encode).toList();
    }
    if (audioBytes != null) {
      json['audioBase64'] = base64Encode(audioBytes!);
      if (audioFormat != null) json['audioFormat'] = audioFormat;
    }
    return json;
  }

  /// Deserialize from JSON (JSONL session persistence).
  factory Message.fromJson(Map<String, dynamic> json) {
    final roleStr = json['role'] as String;
    final role = Role.values.firstWhere((r) => r.name == roleStr);

    // Parse images — support both old single-image and new multi-image format
    List<Uint8List>? images;
    if (json['imageBase64List'] != null) {
      images = (json['imageBase64List'] as List)
          .map((s) => base64Decode(s as String))
          .toList();
    } else if (json['imageBase64'] != null) {
      // Backward compat: old single-image format
      images = [base64Decode(json['imageBase64'] as String)];
    }

    return Message(
      role: role,
      content: json['content'] as String? ?? '',
      toolUses: json['toolUses'] != null
          ? (json['toolUses'] as List)
                .map(
                  (t) => ToolUse.fromJson(Map<String, dynamic>.from(t as Map)),
                )
                .toList()
          : null,
      toolResult: json['toolResult'] != null
          ? ToolResult.fromJson(
              Map<String, dynamic>.from(json['toolResult'] as Map),
            )
          : null,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
      isCompactSummary: json['isCompactSummary'] as bool? ?? false,
      isRecap: json['isRecap'] as bool? ?? false,
      images: images,
      audioBytes: json['audioBase64'] != null
          ? base64Decode(json['audioBase64'] as String)
          : null,
      audioFormat: json['audioFormat'] as String?,
    );
  }
}
