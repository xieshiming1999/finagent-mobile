import 'dart:io';

import 'package:path/path.dart' as p;

import 'log.dart';

// Reference: claude-code-best file history / checkpoint concept

const _maxVersionsPerFile = 10;
const _historyDirName = '.file_history';

/// Save a snapshot of the file before overwriting/editing.
/// Returns the backup path, or null if file doesn't exist or snapshot failed.
String? snapshotBeforeWrite(String filePath, String basePath) {
  final file = File(filePath);
  if (!file.existsSync()) return null;

  try {
    final relative = p.relative(filePath, from: basePath);
    // Sanitize path separators for directory name
    final safeName = relative.replaceAll(p.separator, '__');
    final historyDir = p.join(basePath, 'memory', _historyDirName, safeName);
    Directory(historyDir).createSync(recursive: true);

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final backupPath = p.join(historyDir, '$timestamp.bak');
    file.copySync(backupPath);

    // Prune old versions
    _pruneHistory(historyDir);

    log('FileHistory', 'Snapshot: $relative → $backupPath');
    return backupPath;
  } catch (e) {
    log('FileHistory', 'Snapshot failed for $filePath: $e');
    return null;
  }
}

/// List available snapshots for a file, newest first.
List<FileSnapshot> listSnapshots(String filePath, String basePath) {
  final relative = p.relative(filePath, from: basePath);
  final safeName = relative.replaceAll(p.separator, '__');
  final historyDir = Directory(
    p.join(basePath, 'memory', _historyDirName, safeName),
  );

  if (!historyDir.existsSync()) return [];

  final snapshots = <FileSnapshot>[];
  for (final entity in historyDir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.bak')) continue;
    final name = p.basenameWithoutExtension(entity.path);
    final timestampValue = int.tryParse(name);
    if (timestampValue == null) continue;
    final timestamp = timestampValue > 9999999999999
        ? DateTime.fromMicrosecondsSinceEpoch(timestampValue)
        : DateTime.fromMillisecondsSinceEpoch(timestampValue);
    snapshots.add(
      FileSnapshot(
        path: entity.path,
        timestamp: timestamp,
        sizeBytes: entity.lengthSync(),
      ),
    );
  }

  snapshots.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return snapshots;
}

/// Restore a file from a snapshot. Returns true on success.
bool restoreSnapshot(String snapshotPath, String originalFilePath) {
  final snapshot = File(snapshotPath);
  if (!snapshot.existsSync()) return false;

  try {
    snapshot.copySync(originalFilePath);
    log('FileHistory', 'Restored: $originalFilePath from $snapshotPath');
    return true;
  } catch (e) {
    log('FileHistory', 'Restore failed: $e');
    return false;
  }
}

/// Restore the most recent snapshot for a file.
/// Returns the snapshot timestamp on success, or null.
DateTime? restoreLatest(String filePath, String basePath) {
  final snapshots = listSnapshots(filePath, basePath);
  if (snapshots.isEmpty) return null;

  final latest = snapshots.first;
  if (restoreSnapshot(latest.path, filePath)) {
    return latest.timestamp;
  }
  return null;
}

/// Keep only the most recent N snapshots per file.
void _pruneHistory(String historyDir) {
  final dir = Directory(historyDir);
  if (!dir.existsSync()) return;

  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.bak'))
      .toList();

  if (files.length <= _maxVersionsPerFile) return;

  // Sort by name (timestamp), oldest first
  files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  final toDelete = files.sublist(0, files.length - _maxVersionsPerFile);
  for (final file in toDelete) {
    file.deleteSync();
  }
  log(
    'FileHistory',
    'Pruned ${toDelete.length} old snapshots from $historyDir',
  );
}

class FileSnapshot {
  final String path;
  final DateTime timestamp;
  final int sizeBytes;
  const FileSnapshot({
    required this.path,
    required this.timestamp,
    required this.sizeBytes,
  });
}
