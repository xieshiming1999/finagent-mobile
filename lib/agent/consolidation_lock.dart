import 'dart:io';

import 'package:path/path.dart' as p;

import 'log.dart';

// Reference: claude-code-best/src/services/autoDream/consolidationLock.ts

const _lockFileName = '.consolidate-lock';
const _staleThresholdMs = 60 * 60 * 1000; // 1 hour

/// Read the last consolidation time from the lock file's mtime.
/// Returns 0 if lock file does not exist.
int readLastConsolidatedAt(String memoryDir) {
  final lockFile = File(p.join(memoryDir, _lockFileName));
  if (!lockFile.existsSync()) return 0;
  return lockFile.statSync().modified.millisecondsSinceEpoch;
}

/// Try to acquire the consolidation lock.
/// Returns the prior mtime (for rollback) on success, or null if blocked.
int? tryAcquireConsolidationLock(String memoryDir) {
  final lockPath = p.join(memoryDir, _lockFileName);
  final lockFile = File(lockPath);

  final priorMtime = lockFile.existsSync()
      ? lockFile.statSync().modified.millisecondsSinceEpoch
      : 0;

  if (lockFile.existsSync()) {
    final age = DateTime.now().millisecondsSinceEpoch - priorMtime;
    final body = lockFile.readAsStringSync().trim();

    // If lock is fresh (< 1 hour) and body is non-empty, another process holds it
    if (age < _staleThresholdMs && body.isNotEmpty) {
      log('ConsolidationLock', 'Lock held by another process (age: ${age}ms)');
      return null;
    }
    // Stale lock — reclaim
    log('ConsolidationLock', 'Reclaiming stale lock (age: ${age}ms)');
  }

  // Acquire: write a marker and stamp mtime to now
  Directory(memoryDir).createSync(recursive: true);
  lockFile.writeAsStringSync('dream-active');
  log('ConsolidationLock', 'Lock acquired (priorMtime: $priorMtime)');
  return priorMtime;
}

/// Release the lock after successful dream.
/// Clears the body but keeps the file so mtime = "last dream time".
void releaseConsolidationLock(String memoryDir) {
  final lockFile = File(p.join(memoryDir, _lockFileName));
  if (lockFile.existsSync()) {
    lockFile.writeAsStringSync('');
  }
  log('ConsolidationLock', 'Lock released');
}

/// Rollback the lock on failure (restore prior mtime so the time gate passes again).
void rollbackConsolidationLock(String memoryDir, int priorMtime) {
  final lockFile = File(p.join(memoryDir, _lockFileName));
  if (priorMtime == 0) {
    if (lockFile.existsSync()) lockFile.deleteSync();
  } else {
    lockFile.writeAsStringSync('');
    final priorTime = DateTime.fromMillisecondsSinceEpoch(priorMtime);
    lockFile.setLastModifiedSync(priorTime);
  }
  log('ConsolidationLock', 'Lock rolled back to $priorMtime');
}

/// Record a manual consolidation (/dream command).
/// Creates the lock file with mtime = now.
void recordConsolidation(String memoryDir) {
  Directory(memoryDir).createSync(recursive: true);
  final lockFile = File(p.join(memoryDir, _lockFileName));
  lockFile.writeAsStringSync('');
  log('ConsolidationLock', 'Manual consolidation recorded');
}

/// Count files in memoryDir that were modified after [sinceMs].
/// Includes .md files in memory/ and memory/skills/.
int countModifiedFilesSince(String memoryDir, int sinceMs) {
  final dir = Directory(memoryDir);
  if (!dir.existsSync()) return 0;

  var count = 0;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.md')) continue;
    if (p.basename(entity.path).startsWith('.')) continue;
    if (entity.statSync().modified.millisecondsSinceEpoch > sinceMs) {
      count++;
    }
  }
  return count;
}
