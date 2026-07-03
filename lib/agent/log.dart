import 'dart:io';

/// Simple dual-output logger: console + file.
/// Mirrors server/src/shared/log.ts pattern.
/// No Flutter dependency — pure Dart.
class Log {
  static File? _logFile;

  /// Initialize the logger with a base path.
  /// Log file will be at `<basePath>/logs/debug.log`.
  static void init(String basePath) {
    final logDir = Directory('$basePath/logs');
    logDir.createSync(recursive: true);
    _logFile = File('${logDir.path}/debug.log');
  }

  /// Log a message with timestamp to both console and file.
  static void log(String tag, List<Object?> args) {
    final ts = DateTime.now().toIso8601String();
    final msg = args.map((a) => '$a').join(' ');
    final line = '[$ts] [$tag] $msg';

    // ignore: avoid_print
    print(line);
    _logFile?.writeAsStringSync('$line\n', mode: FileMode.append);
  }
}

/// Convenience top-level function.
void log(String tag, [Object? a1, Object? a2, Object? a3, Object? a4]) {
  final args = <Object?>[];
  if (a1 != null) args.add(a1);
  if (a2 != null) args.add(a2);
  if (a3 != null) args.add(a3);
  if (a4 != null) args.add(a4);
  Log.log(tag, args);
}
