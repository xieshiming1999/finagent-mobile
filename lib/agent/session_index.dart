import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'log.dart';

/// Search result from the session index.
class SearchResult {
  final String sessionId;
  final String title;
  final String snippet;
  final DateTime? timestamp;
  final String filePath;

  const SearchResult({
    required this.sessionId,
    required this.title,
    required this.snippet,
    this.timestamp,
    required this.filePath,
  });
}

/// SQLite FTS5 search index for session messages.
///
/// Architecture: JSONL files remain source of truth; SQLite is a secondary
/// index that can be rebuilt from JSONL at any time.
///
/// Dual-write: caller appends to JSONL as before, also calls [indexMessage].
/// Search: FTS5 query → post-validate file exists → return results.
class SessionIndex {
  final String sessionsDir;

  SessionIndex({required this.sessionsDir});

  Database? _dbInstance;

  Database get _db {
    _dbInstance ??= _openOrCreate();
    return _dbInstance!;
  }

  Database _openOrCreate() {
    final dbPath = p.join(sessionsDir, 'search_index.db');
    Directory(sessionsDir).createSync(recursive: true);
    final db = sqlite3.open(dbPath);

    db.execute('''
      CREATE TABLE IF NOT EXISTS session_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        session_file TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp TEXT,
        session_title TEXT
      )
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_session_id
      ON session_messages(session_id)
    ''');

    // FTS5 virtual table for full-text search
    db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS session_messages_fts
      USING fts5(
        content,
        session_title,
        content='session_messages',
        content_rowid='id',
        tokenize='unicode61'
      )
    ''');

    // Triggers to keep FTS in sync
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS session_messages_ai
      AFTER INSERT ON session_messages BEGIN
        INSERT INTO session_messages_fts(rowid, content, session_title)
        VALUES (new.id, new.content, new.session_title);
      END
    ''');

    db.execute('''
      CREATE TRIGGER IF NOT EXISTS session_messages_ad
      AFTER DELETE ON session_messages BEGIN
        INSERT INTO session_messages_fts(session_messages_fts, rowid, content, session_title)
        VALUES('delete', old.id, old.content, old.session_title);
      END
    ''');

    return db;
  }

  /// Whether the index is available (db opened successfully).
  bool get isAvailable => _dbInstance != null || _tryOpen();

  bool _tryOpen() {
    try {
      _db; // triggers lazy init
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Index a single message. Called during dual-write.
  void indexMessage({
    required String sessionId,
    required String sessionFile,
    required String role,
    required String content,
    DateTime? timestamp,
    String? sessionTitle,
  }) {
    try {
      _db.execute(
        '''
      INSERT INTO session_messages (session_id, session_file, role, content, timestamp, session_title)
      VALUES (?, ?, ?, ?, ?, ?)
    ''',
        [
          sessionId,
          sessionFile,
          role,
          content,
          timestamp?.toIso8601String(),
          sessionTitle,
        ],
      );
    } catch (_) {} // Silently fail — search index is non-critical
  }

  /// Update session file path (e.g., after archiving current.jsonl to history/).
  void updateSessionFile(String sessionId, String newRelativePath) {
    try {
      _db.execute(
        'UPDATE session_messages SET session_file = ? WHERE session_id = ?',
        [newRelativePath, sessionId],
      );
    } catch (_) {}
  }

  /// Update session title for all messages in a session.
  void updateSessionTitle(String sessionId, String title) {
    try {
      _db.execute(
        'UPDATE session_messages SET session_title = ? WHERE session_id = ?',
        [title, sessionId],
      );
    } catch (_) {}
  }

  /// Delete all index entries for a session.
  void deleteSession(String sessionId) {
    try {
      _db.execute('DELETE FROM session_messages WHERE session_id = ?', [
        sessionId,
      ]);
    } catch (_) {}
  }

  /// Full-text search across session messages.
  /// Returns results post-validated against actual files.
  List<SearchResult> search(String query, {int limit = 10}) {
    try {
      return _searchInternal(query, limit: limit);
    } catch (_) {
      return [];
    }
  }

  List<SearchResult> _searchInternal(String query, {int limit = 10}) {
    final sanitized = _sanitizeQuery(query);
    if (sanitized.isEmpty) return [];

    final rows = _db.select(
      '''
      SELECT m.session_id, m.session_file, m.session_title, m.content, m.timestamp
      FROM session_messages_fts fts
      JOIN session_messages m ON m.id = fts.rowid
      WHERE session_messages_fts MATCH ?
      ORDER BY rank
      LIMIT ?
    ''',
      [sanitized, limit * 2],
    ); // fetch extra for post-validation

    final valid = <SearchResult>[];
    final staleIds = <String>{};

    for (final row in rows) {
      final sessionFile = row['session_file'] as String;
      final fullPath = p.join(sessionsDir, sessionFile);

      if (File(fullPath).existsSync()) {
        valid.add(
          SearchResult(
            sessionId: row['session_id'] as String,
            title: (row['session_title'] as String?) ?? '(untitled)',
            snippet: _extractSnippet(row['content'] as String, query),
            timestamp: DateTime.tryParse(row['timestamp'] as String? ?? ''),
            filePath: fullPath,
          ),
        );
        if (valid.length >= limit) break;
      } else {
        staleIds.add(row['session_id'] as String);
      }
    }

    // Lazy cleanup of stale entries
    if (staleIds.isNotEmpty) {
      for (final id in staleIds) {
        _db.execute('DELETE FROM session_messages WHERE session_id = ?', [id]);
      }
    }

    return valid;
  }

  /// List recent sessions (no search query).
  /// List recent sessions (no search query).
  List<SearchResult> listRecent({int limit = 10}) {
    try {
      return _listRecentInternal(limit: limit);
    } catch (_) {
      return [];
    }
  }

  List<SearchResult> _listRecentInternal({int limit = 10}) {
    final rows = _db.select(
      '''
      SELECT DISTINCT session_id, session_file, session_title,
             MIN(timestamp) as first_ts
      FROM session_messages
      GROUP BY session_id
      ORDER BY first_ts DESC
      LIMIT ?
    ''',
      [limit],
    );

    final results = <SearchResult>[];
    for (final row in rows) {
      final sessionFile = row['session_file'] as String;
      final fullPath = p.join(sessionsDir, sessionFile);
      if (!File(fullPath).existsSync()) continue;

      results.add(
        SearchResult(
          sessionId: row['session_id'] as String,
          title: (row['session_title'] as String?) ?? '(untitled)',
          snippet: '',
          timestamp: DateTime.tryParse(row['first_ts'] as String? ?? ''),
          filePath: fullPath,
        ),
      );
    }
    return results;
  }

  /// Rebuild the entire index from JSONL files.
  Future<void> rebuildIndex() async {
    _db.execute('DELETE FROM session_messages');

    final files = <File>[];

    // Current session
    final currentFile = File(p.join(sessionsDir, 'current.jsonl'));
    if (currentFile.existsSync()) files.add(currentFile);

    // History
    final historyDir = Directory(p.join(sessionsDir, 'history'));
    if (historyDir.existsSync()) {
      for (final entity in historyDir.listSync()) {
        if (entity is File && entity.path.endsWith('.jsonl')) {
          files.add(entity);
        }
      }
    }

    _db.execute('BEGIN TRANSACTION');
    try {
      for (final file in files) {
        _indexSessionFile(file);
      }
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      log('SessionIndex', 'Rebuild failed: $e');
    }
  }

  void _indexSessionFile(File file) {
    String? sessionId;
    String? sessionTitle;
    final relativePath = p.relative(file.path, from: sessionsDir);

    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final type = json['type'] as String?;

        switch (type) {
          case 'session_meta':
            sessionId = json['id'] as String?;
          case 'title':
            sessionTitle = json['title'] as String?;
          case 'message':
            final role = json['role'] as String?;
            final content = json['content'] as String?;
            if (role != null &&
                content != null &&
                content.length > 5 &&
                sessionId != null &&
                (role == 'user' || role == 'assistant')) {
              _db.execute(
                '''
                INSERT INTO session_messages
                  (session_id, session_file, role, content, timestamp, session_title)
                VALUES (?, ?, ?, ?, ?, ?)
              ''',
                [
                  sessionId,
                  relativePath,
                  role,
                  content,
                  json['timestamp'],
                  sessionTitle,
                ],
              );
            }
        }
      } catch (_) {
        // Skip malformed lines
      }
    }
  }

  /// Sanitize FTS5 query to prevent syntax errors.
  String _sanitizeQuery(String query) {
    var sanitized = query.replaceAll(RegExp(r'[*(){}[\]^"~]'), ' ');
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return sanitized;
  }

  /// Extract a snippet around the first occurrence of query terms.
  String _extractSnippet(String content, String query, {int radius = 80}) {
    final lower = content.toLowerCase();
    final terms = query.toLowerCase().split(RegExp(r'\s+'));

    int bestPos = -1;
    for (final term in terms) {
      final pos = lower.indexOf(term);
      if (pos >= 0 && (bestPos < 0 || pos < bestPos)) bestPos = pos;
    }

    if (bestPos < 0) {
      return content.length > radius * 2
          ? '${content.substring(0, radius * 2)}...'
          : content;
    }

    final start = (bestPos - radius).clamp(0, content.length);
    final end = (bestPos + radius).clamp(0, content.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < content.length ? '...' : '';
    return '$prefix${content.substring(start, end)}$suffix';
  }

  /// Close the database.
  void dispose() {
    _dbInstance?.close();
    _dbInstance = null;
  }
}
