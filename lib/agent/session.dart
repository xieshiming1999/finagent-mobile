import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'message.dart';
import 'session_index.dart';

// Reference: claude-code-best/src/utils/sessionStorage.ts

/// JSONL entry types for session persistence.
sealed class SessionEntry {
  Map<String, dynamic> toJson();

  static SessionEntry fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'session_meta' => SessionMetaEntry.fromJson(json),
      'message' => MessageEntry.fromJson(json),
      'compact_boundary' => CompactBoundaryEntry.fromJson(json),
      'title' => TitleEntry.fromJson(json),
      _ => throw FormatException('Unknown session entry type: $type'),
    };
  }
}

/// First line of a JSONL file — session metadata.
class SessionMetaEntry extends SessionEntry {
  final String id;
  final DateTime createdAt;
  final String? feature;

  SessionMetaEntry({required this.id, required this.createdAt, this.feature});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'session_meta',
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    if (feature != null) 'feature': feature,
  };

  factory SessionMetaEntry.fromJson(Map<String, dynamic> json) =>
      SessionMetaEntry(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        feature: json['feature'] as String?,
      );
}

/// A conversation message entry.
class MessageEntry extends SessionEntry {
  final Message message;

  MessageEntry(this.message);

  @override
  Map<String, dynamic> toJson() => {'type': 'message', ...message.toJson()};

  factory MessageEntry.fromJson(Map<String, dynamic> json) {
    // Remove 'type' before passing to Message.fromJson
    final msgJson = Map<String, dynamic>.from(json)..remove('type');
    return MessageEntry(Message.fromJson(msgJson));
  }
}

/// Compact boundary — marks where compaction happened.
/// Messages before this entry are summarized; the summary is in [summary].
/// Reference: claude-code-best SystemCompactBoundaryMessage
class CompactBoundaryEntry extends SessionEntry {
  final String summary;
  final int preCompactMessageCount;
  final DateTime timestamp;

  CompactBoundaryEntry({
    required this.summary,
    required this.preCompactMessageCount,
    required this.timestamp,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'compact_boundary',
    'summary': summary,
    'preCompactMessageCount': preCompactMessageCount,
    'timestamp': timestamp.toIso8601String(),
  };

  factory CompactBoundaryEntry.fromJson(Map<String, dynamic> json) =>
      CompactBoundaryEntry(
        summary: json['summary'] as String,
        preCompactMessageCount: json['preCompactMessageCount'] as int,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

/// Session title entry (can be appended/updated).
class TitleEntry extends SessionEntry {
  final String title;
  final DateTime timestamp;

  TitleEntry({required this.title, required this.timestamp});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'title',
    'title': title,
    'timestamp': timestamp.toIso8601String(),
  };

  factory TitleEntry.fromJson(Map<String, dynamic> json) => TitleEntry(
    title: json['title'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

/// A single session backed by a JSONL file.
///
/// Supports append-only writes and full reload.
/// Reference: claude-code-best Project class in sessionStorage.ts
class Session {
  final String id;
  final String filePath;
  final DateTime createdAt;
  String? title;
  String? feature;

  /// Optional search index for dual-write. Set by SessionManager.
  SessionIndex? searchIndex;

  Session._({
    required this.id,
    required this.filePath,
    required this.createdAt,
    this.title,
    this.feature,
  });

  /// Append a single entry as one JSONL line.
  void appendEntry(SessionEntry entry) {
    final file = File(filePath);
    file.writeAsStringSync(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
    );
  }

  /// Append a message to the session file and optionally to the search index.
  void appendMessage(Message message) {
    appendEntry(MessageEntry(message));

    // Dual-write to search index
    if (searchIndex != null &&
        (message.role == Role.user || message.role == Role.assistant) &&
        message.content.length > 5) {
      final relativePath = p.relative(filePath, from: p.dirname(filePath));
      searchIndex!.indexMessage(
        sessionId: id,
        sessionFile: relativePath,
        role: message.role.name,
        content: message.content,
        timestamp: message.timestamp,
        sessionTitle: title,
      );
    }
  }

  /// Append a compact boundary marker.
  void appendCompactBoundary(String summary, int preCompactCount) {
    appendEntry(
      CompactBoundaryEntry(
        summary: summary,
        preCompactMessageCount: preCompactCount,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Update the session title.
  void setTitle(String newTitle) {
    title = newTitle;
    appendEntry(TitleEntry(title: newTitle, timestamp: DateTime.now()));
    searchIndex?.updateSessionTitle(id, newTitle);
  }

  /// Create a new session with a fresh JSONL file.
  static Session create(String sessionsDir, {String? feature}) {
    final id = _generateSessionId();
    final filePath = p.join(sessionsDir, 'current.jsonl');

    // Ensure directory exists
    Directory(sessionsDir).createSync(recursive: true);

    // Write session meta as the first line
    final session = Session._(
      id: id,
      filePath: filePath,
      createdAt: DateTime.now(),
      feature: feature,
    );

    final meta = SessionMetaEntry(
      id: id,
      createdAt: session.createdAt,
      feature: feature,
    );
    File(filePath).writeAsStringSync('${jsonEncode(meta.toJson())}\n');

    return session;
  }

  /// Load a session from a JSONL file.
  /// Returns the session and the rebuilt message list.
  /// Messages before the last compact_boundary are discarded.
  static (Session, List<Message>) load(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('Session file not found', filePath);
    }

    final lines = file.readAsLinesSync().where((l) => l.trim().isNotEmpty);

    String? id;
    DateTime? createdAt;
    String? feature;
    String? title;
    final messages = <Message>[];

    for (final line in lines) {
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final entry = SessionEntry.fromJson(json);

        switch (entry) {
          case SessionMetaEntry():
            id = entry.id;
            createdAt = entry.createdAt;
            feature = entry.feature;

          case MessageEntry():
            messages.add(entry.message);

          case CompactBoundaryEntry():
            // Discard all messages before this boundary
            messages.clear();
            // Add the compact summary as the first message
            messages.add(
              Message(
                role: Role.user,
                content: _wrapCompactSummary(entry.summary),
                timestamp: entry.timestamp,
                isCompactSummary: true,
              ),
            );

          case TitleEntry():
            title = entry.title;
        }
      } catch (_) {
        // Skip malformed lines — defensive against crashes mid-write
        continue;
      }
    }

    if (id == null || createdAt == null) {
      throw const FormatException('Session file missing session_meta entry');
    }

    // Remove trailing incomplete tool_use messages (no matching tool_result).
    // This can happen if the app was killed mid-tool-call.
    trimIncompleteToolUse(messages);

    final session = Session._(
      id: id,
      filePath: filePath,
      createdAt: createdAt,
      title: title,
      feature: feature,
    );

    return (session, messages);
  }

  /// Archive this session to the history directory.
  void archive(String historyDir) {
    Directory(historyDir).createSync(recursive: true);

    final now = DateTime.now();
    final dateStr = '${now.year}-${_pad(now.month)}-${_pad(now.day)}';

    // Find next sequence number for this date
    int seq = 1;
    while (File(
      p.join(historyDir, '${dateStr}_${_pad3(seq)}.jsonl'),
    ).existsSync()) {
      seq++;
    }

    final archivePath = p.join(historyDir, '${dateStr}_${_pad3(seq)}.jsonl');
    File(filePath).renameSync(archivePath);

    // Update search index with new file path
    final sessionsDir = p.dirname(historyDir); // historyDir is sessions/history
    final newRelPath = p.relative(archivePath, from: sessionsDir);
    searchIndex?.updateSessionFile(id, newRelPath);
  }

  static String _generateSessionId() {
    final now = DateTime.now();
    final random = now.microsecondsSinceEpoch.toRadixString(36);
    return '${now.millisecondsSinceEpoch.toRadixString(36)}-$random';
  }

  static String _wrapCompactSummary(String summary) =>
      'This session is being continued from a previous conversation that ran '
      'out of context. Here is a summary of the conversation so far:\n\n'
      '$summary\n\n'
      'Continue the conversation from where it left off without asking the '
      'user any further questions. Resume directly with the task at hand.';

  /// Remove orphaned tool_use and tool_result messages.
  /// Handles both directions:
  /// - assistant with tool_uses but missing tool_results
  /// - tool_result without a preceding assistant tool_use
  static void trimIncompleteToolUse(List<Message> messages) {
    // Pass 1: remove orphan tool_result messages (no preceding tool_use)
    final validToolUseIds = <String>{};
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      if (msg.role == Role.assistant && msg.toolUses != null) {
        for (final tu in msg.toolUses!) {
          validToolUseIds.add(tu.id);
        }
      }
    }
    messages.removeWhere((msg) {
      if (msg.role != Role.tool || msg.toolResult == null) return false;
      return !validToolUseIds.contains(msg.toolResult!.toolUseId);
    });

    // Pass 2: remove assistant+tool_results where tool_results are incomplete
    var i = 0;
    while (i < messages.length) {
      final msg = messages[i];
      if (msg.role != Role.assistant || msg.toolUses == null) {
        i++;
        continue;
      }

      final expected = msg.toolUses!.length;
      int actual = 0;
      for (
        var j = i + 1;
        j < messages.length && messages[j].role == Role.tool;
        j++
      ) {
        actual++;
      }

      if (actual < expected) {
        messages.removeRange(i, i + 1 + actual);
      } else {
        i += 1 + actual;
      }
    }
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
  static String _pad3(int n) => n.toString().padLeft(3, '0');
}

/// Summary info for displaying in history list.
class SessionSummary {
  final String id;
  final String filePath;
  final DateTime createdAt;
  final String? title;
  final String? firstPrompt;
  final String? feature;

  const SessionSummary({
    required this.id,
    required this.filePath,
    required this.createdAt,
    this.title,
    this.firstPrompt,
    this.feature,
  });
}

/// Manages session lifecycle: create, load, archive, list history.
///
/// Reference: claude-code-best Project class (simplified)
class SessionManager {
  final String sessionsDir;
  final String historyDir;
  final String archiveDir;

  /// Shared history directory for dual-write. When set, appendToHistory()
  /// writes to this directory instead of [historyDir].
  final String? sharedHistoryDir;

  /// Session search index for full-text search across history.
  late final SessionIndex sessionIndex;

  Session? currentSession;

  SessionManager({required this.sessionsDir, this.sharedHistoryDir})
    : historyDir = p.join(sessionsDir, 'history'),
      archiveDir = p.join(sessionsDir, 'archive') {
    sessionIndex = SessionIndex(sessionsDir: sessionsDir);
  }

  /// Load the current session or create a new one.
  /// Returns the session and the restored message list.
  (Session, List<Message>) loadOrCreate({String? feature}) {
    final currentFile = p.join(sessionsDir, 'current.jsonl');

    if (File(currentFile).existsSync()) {
      try {
        final (session, messages) = Session.load(currentFile);
        session.searchIndex = sessionIndex;
        currentSession = session;
        return (session, messages);
      } catch (_) {
        // Corrupted file — archive it and start fresh
        try {
          File(
            currentFile,
          ).renameSync(p.join(sessionsDir, 'current.corrupted.jsonl'));
        } catch (_) {}
      }
    }

    final session = Session.create(sessionsDir, feature: feature);
    session.searchIndex = sessionIndex;
    currentSession = session;
    return (session, <Message>[]);
  }

  /// Archive the current session and create a new one.
  Session archiveAndCreate({String? feature}) {
    if (currentSession != null) {
      currentSession!.archive(archiveDir);
    }
    final session = Session.create(sessionsDir, feature: feature);
    session.searchIndex = sessionIndex;
    currentSession = session;
    return session;
  }

  /// List all archived sessions (reads head of each file for metadata).
  List<SessionSummary> listHistory() {
    final summaries = <SessionSummary>[];
    for (final dirPath in [archiveDir, historyDir]) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
        try {
          final summary = _readSessionSummary(entity);
          if (summary != null) summaries.add(summary);
        } catch (_) {
          continue;
        }
      }
    }

    // Sort by creation date, most recent first
    summaries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return summaries;
  }

  /// Resume a session from history.
  (Session, List<Message>) resumeSession(String filePath) {
    final (session, messages) = Session.load(filePath);

    // Move the file to current.jsonl
    if (currentSession != null) {
      currentSession!.archive(archiveDir);
    }

    final currentPath = p.join(sessionsDir, 'current.jsonl');
    File(filePath).copySync(currentPath);

    final resumedSession = Session._(
      id: session.id,
      filePath: currentPath,
      createdAt: session.createdAt,
      title: session.title,
      feature: session.feature,
    );
    resumedSession.searchIndex = sessionIndex;
    currentSession = resumedSession;
    return (resumedSession, messages);
  }

  /// Read just enough of a session file to build a summary.
  /// Reads first line (meta) and scans for title and first user message.
  SessionSummary? _readSessionSummary(File file) {
    final lines = file.readAsLinesSync();
    if (lines.isEmpty) return null;

    String? id;
    DateTime? createdAt;
    String? feature;
    String? title;
    String? firstPrompt;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final type = json['type'] as String?;

        if (type == 'session_meta') {
          id = json['id'] as String?;
          createdAt = json['createdAt'] != null
              ? DateTime.parse(json['createdAt'] as String)
              : null;
          feature = json['feature'] as String?;
        } else if (type == 'title') {
          title = json['title'] as String?;
        } else if (type == 'message' &&
            json['role'] == 'user' &&
            firstPrompt == null) {
          firstPrompt = json['content'] as String?;
          if (firstPrompt != null && firstPrompt.length > 100) {
            firstPrompt = '${firstPrompt.substring(0, 100)}...';
          }
        }

        // Once we have meta + title + first prompt, we can stop
        if (id != null && title != null && firstPrompt != null) break;
      } catch (_) {
        continue;
      }
    }

    if (id == null || createdAt == null) return null;

    return SessionSummary(
      id: id,
      filePath: file.path,
      createdAt: createdAt,
      title: title,
      firstPrompt: firstPrompt,
      feature: feature,
    );
  }

  // ─── History dual-write ───

  /// Append a complete conversation unit (user query → agent full response)
  /// to today's history file. The file is named {date}_{source}.jsonl.
  ///
  /// [messages] — the messages to write (user + assistant + tool results).
  /// [source] — 'chat', 'stock', or 'fund'.
  void appendToHistory(List<Message> messages, {String source = 'chat'}) {
    if (messages.isEmpty) return;

    final dir = sharedHistoryDir ?? historyDir;
    Directory(dir).createSync(recursive: true);

    // Use the first user message's timestamp for the date.
    final userMsg = messages.firstWhere(
      (m) => m.role == Role.user,
      orElse: () => messages.first,
    );
    final date = userMsg.timestamp ?? DateTime.now();
    final dateStr = '${date.year}-${_pad(date.month)}-${_pad(date.day)}';
    final filePath = p.join(dir, '${dateStr}_$source.jsonl');

    final buffer = StringBuffer();
    for (final msg in messages) {
      buffer.writeln(jsonEncode(_summarizeForHistory(msg)));
    }

    File(filePath).writeAsStringSync(buffer.toString(), mode: FileMode.append);
  }

  /// List all history files across all sources.
  /// Returns [HistoryFileInfo] sorted by date descending.
  List<HistoryFileInfo> listHistoryFiles() {
    final dir = sharedHistoryDir ?? historyDir;
    final d = Directory(dir);
    if (!d.existsSync()) return [];

    final result = <HistoryFileInfo>[];
    for (final entity in d.listSync()) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
      if (_isSessionArchiveFile(entity)) continue;
      final name = p.basenameWithoutExtension(entity.path);
      // Parse: 2026-04-08_chat or 2026-04-08_chat_002
      final match = RegExp(r'^(\d{4}-\d{2}-\d{2})_(\w+)').firstMatch(name);
      if (match == null) continue;
      final dateStr = match.group(1)!;
      final source = match.group(2)!;
      try {
        final date = DateTime.parse(dateStr);
        // Read first user message as preview
        final preview = _readFirstUserMessage(entity);
        result.add(
          HistoryFileInfo(
            filePath: entity.path,
            date: date,
            source: source,
            preview: preview,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  /// Read the first user message content from a history file.
  String? _readFirstUserMessage(File file) {
    try {
      final lines = file.readAsLinesSync();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final json = jsonDecode(line) as Map<String, dynamic>;
        if (json['role'] == 'user') {
          final content = json['content'] as String? ?? '';
          return content.length > 100
              ? '${content.substring(0, 100)}...'
              : content;
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isSessionArchiveFile(File file) {
    try {
      for (final line in file.readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        final json = jsonDecode(line) as Map<String, dynamic>;
        return json['type'] == 'session_meta';
      }
    } catch (_) {}
    return false;
  }

  /// Summarize a message for history storage.
  /// Strips large tool results (file contents, API data) to keep history lean.
  static Map<String, dynamic> _summarizeForHistory(Message msg) {
    final json = <String, dynamic>{
      'role': msg.role.name,
      'timestamp': (msg.timestamp ?? DateTime.now()).toIso8601String(),
    };

    switch (msg.role) {
      case Role.user:
        json['content'] = msg.content;

      case Role.assistant:
        json['content'] = msg.content;
        if (msg.toolUses != null && msg.toolUses!.isNotEmpty) {
          json['toolUses'] = msg.toolUses!
              .map(
                (t) => {
                  'name': t.name,
                  'input': _summarizeToolInput(t.name, t.input),
                },
              )
              .toList();
        }

      case Role.tool:
        if (msg.toolResult != null) {
          final r = msg.toolResult!;
          json['tool_result'] = {
            if (r.isError) 'isError': true,
            'content': _summarizeToolResult(r.content),
          };
        }
    }

    return json;
  }

  /// Keep only the key parameters for tool inputs (omit file contents etc).
  static Map<String, dynamic> _summarizeToolInput(
    String toolName,
    Map<String, dynamic> input,
  ) {
    switch (toolName) {
      case 'Write' || 'FileWrite':
        return {'file_path': input['file_path'] ?? input['path']};
      case 'Edit' || 'FileEdit':
        return {'file_path': input['file_path'] ?? input['path']};
      case 'Read' || 'FileRead':
        return {
          'file_path': input['file_path'] ?? input['path'],
          if (input['offset'] != null) 'offset': input['offset'],
          if (input['limit'] != null) 'limit': input['limit'],
        };
      case 'ServiceCall':
        return {'method': input['method'], 'path': input['path']};
      case 'UIControl':
        return {
          'action': input['action'],
          // Omit large params.data
        };
      default:
        // For other tools, keep input but truncate long string values
        final summarized = <String, dynamic>{};
        for (final entry in input.entries) {
          final v = entry.value;
          if (v is String && v.length > 200) {
            summarized[entry.key] = '${v.substring(0, 200)}...';
          } else {
            summarized[entry.key] = v;
          }
        }
        return summarized;
    }
  }

  /// Truncate large tool results.
  static String _summarizeToolResult(String content) {
    if (content.length <= 500) return content;
    return '${content.substring(0, 500)}...[truncated]';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

/// Info about a history file for UI display.
class HistoryFileInfo {
  final String filePath;
  final DateTime date;
  final String source; // 'chat', 'stock', 'fund'
  final String? preview; // first user message

  const HistoryFileInfo({
    required this.filePath,
    required this.date,
    required this.source,
    this.preview,
  });
}
