import 'dart:io';

import 'package:path/path.dart' as p;

import 'log.dart';

// Reference: claude-code-best/src/utils/backgroundHousekeeping.ts

const _cleanupMaxAgeDays = 7;

/// Directories under memory/ to clean up.
const _cleanupTargets = ['.tool_outputs', '.screenshots'];

/// Run background housekeeping: clean up old temp files.
/// Should be called once, delayed after first agent turn.
Future<void> runBackgroundHousekeeping(String memoryDir) async {
  log('Housekeeping', 'Starting background housekeeping');
  var totalDeleted = 0;

  for (final target in _cleanupTargets) {
    final dir = Directory(p.join(memoryDir, target));
    if (!dir.existsSync()) continue;
    totalDeleted += _cleanupOldFiles(dir);
  }

  // Also clean up old file history beyond a broader age
  final historyDir = Directory(p.join(memoryDir, '.file_history'));
  if (historyDir.existsSync()) {
    totalDeleted += _cleanupOldFiles(historyDir, maxAgeDays: 30);
  }

  if (totalDeleted > 0) {
    log('Housekeeping', 'Deleted $totalDeleted old files');
  } else {
    log('Housekeeping', 'Nothing to clean up');
  }
}

/// Delete files older than [maxAgeDays] in [dir] (recursive).
/// Returns count of deleted files.
int _cleanupOldFiles(Directory dir, {int maxAgeDays = _cleanupMaxAgeDays}) {
  final cutoff = DateTime.now().subtract(Duration(days: maxAgeDays));
  var count = 0;

  try {
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final stat = entity.statSync();
      if (stat.modified.isBefore(cutoff)) {
        entity.deleteSync();
        count++;
      }
    }

    // Remove empty directories
    _removeEmptyDirs(dir);
  } catch (e) {
    log('Housekeeping', 'Cleanup error in ${dir.path}: $e');
  }

  return count;
}

/// Remove empty directories recursively (bottom-up).
void _removeEmptyDirs(Directory dir) {
  for (final entity in dir.listSync()) {
    if (entity is Directory) {
      _removeEmptyDirs(entity);
      if (entity.listSync().isEmpty) {
        entity.deleteSync();
      }
    }
  }
}
