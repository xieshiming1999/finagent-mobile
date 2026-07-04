import 'dart:async';
import 'dart:io';

import '../../background_task.dart';
import '../../log.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Default timeout: 2 minutes.
const _defaultTimeoutMs = 120000;

/// Max timeout: 10 minutes.
const _maxTimeoutMs = 600000;

/// Max output size before truncation (chars).
const _maxOutputChars = 30000;

/// Progress report threshold: start reporting after 2 seconds.
const _progressThresholdMs = 2000;

/// Progress report interval: every 3 seconds.
const _progressIntervalMs = 3000;

/// Destructive command patterns and their warnings.
/// Reference: claude-code-best destructiveCommandWarning.ts
const _destructiveWarnings = <String, String>{
  'git reset --hard': 'may discard uncommitted changes',
  'git checkout .': 'may discard uncommitted changes',
  'git clean -f': 'may delete untracked files',
  'git push --force': 'may overwrite remote history',
  'git push -f': 'may overwrite remote history',
  'rm -rf': 'may recursively force-remove files',
  'rm -r': 'may recursively remove files',
  'DROP TABLE': 'may permanently delete database table',
  'DELETE FROM': 'may permanently delete database records',
  'kubectl delete': 'may delete Kubernetes resources',
  'terraform destroy': 'may destroy infrastructure',
};

/// Executes bash commands on desktop platforms (macOS, Linux).
///
/// Reference: claude-code-best/src/tools/BashTool/BashTool.tsx
/// Features: cwd persistence, timeout, progress streaming, background execution,
/// destructive command warnings, exit code interpretation.
class BashTool extends Tool {
  /// Current working directory, persists across calls.
  String? _cwd;

  /// Progress callback — set by Agent to receive live output during execution.
  /// Reference: claude-code-best BashTool yields progress events.
  void Function(String toolUseId, String output, int elapsedMs)? onProgress;

  @override
  String get name => 'Bash';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'command': {'type': 'string', 'description': 'The command to execute'},
      'timeout': {
        'type': 'integer',
        'description': 'Optional timeout in milliseconds (max $_maxTimeoutMs)',
      },
      'description': {
        'type': 'string',
        'description': 'Clear, concise description of what this command does',
      },
      'run_in_background': {
        'type': 'boolean',
        'description':
            'Set to true to run this command in the background. '
            'You will be notified when it completes.',
      },
    },
    'required': ['command'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) => true;

  @override
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final command = input['command'] as String?;
    if (command == null || command.trim().isEmpty) {
      return 'command is required and must not be empty.';
    }
    final timeout = input['timeout'] as num?;
    if (timeout != null && timeout > _maxTimeoutMs) {
      return 'timeout must not exceed $_maxTimeoutMs ms (${_maxTimeoutMs ~/ 60000} minutes).';
    }
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final command = input['command'] as String;
    final timeoutMs = (input['timeout'] as num?)?.toInt() ?? _defaultTimeoutMs;
    final desc = input['description'] as String?;
    final runInBackground = input['run_in_background'] as bool? ?? false;

    // Check for destructive commands
    final warning = _getDestructiveWarning(command);
    if (warning != null) {
      log('Bash', 'WARNING: $warning — $command');
    }

    log('Bash', desc ?? command);

    final shell = _findShell();
    final cwd = _cwd ?? context.basePath;

    // Background execution: register task and run async
    if (runInBackground) {
      return _runInBackground(
        toolUseId: toolUseId,
        command: command,
        shell: shell,
        cwd: cwd,
        timeoutMs: timeoutMs,
        desc: desc,
        context: context,
      );
    }

    try {
      final stopwatch = Stopwatch()..start();
      final result = await _execute(
        shell: shell,
        command: command,
        cwd: cwd,
        timeoutMs: timeoutMs,
        toolUseId: toolUseId,
      );
      stopwatch.stop();

      if (result.newCwd != null) {
        _cwd = result.newCwd;
      }

      return _buildResult(
        toolUseId,
        command,
        result,
        timeoutMs,
        warning: warning,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Bash error: $e',
        isError: true,
      );
    }
  }

  /// Run command in background, return task ID immediately.
  /// Reference: claude-code-best BashTool run_in_background handling.
  ToolResult _runInBackground({
    required String toolUseId,
    required String command,
    required String shell,
    required String cwd,
    required int timeoutMs,
    required String? desc,
    required ToolContext context,
  }) {
    final task = context.taskRegistry.register(
      description: desc ?? 'Bash: $command',
      prompt: command,
      toolUseId: toolUseId,
    );
    task.status = BackgroundTaskStatus.running;

    // Fire and forget
    _execute(
          shell: shell,
          command: command,
          cwd: cwd,
          timeoutMs: timeoutMs,
          toolUseId: toolUseId,
        )
        .then((result) {
          if (result.newCwd != null) _cwd = result.newCwd;

          final output = StringBuffer();
          if (result.stdout.isNotEmpty) output.write(result.stdout);
          if (result.stderr.isNotEmpty) {
            if (output.isNotEmpty) output.writeln();
            output.write(result.stderr);
          }
          if (result.timedOut) {
            output.writeln('\n(Command timed out after ${timeoutMs ~/ 1000}s)');
          }
          final exitInfo = _interpretExitCode(command, result.exitCode);
          if (exitInfo != null) {
            output.writeln();
            output.write(exitInfo);
          }

          task.result = _truncate(output.toString());
          task.status =
              result.timedOut ||
                  (result.exitCode != 0 &&
                      !_isExpectedNonZero(command, result.exitCode))
              ? BackgroundTaskStatus.failed
              : BackgroundTaskStatus.completed;
          task.endTime = DateTime.now();
          log(
            'Bash',
            'Background task ${task.id} ${task.status.name}: $command',
          );
        })
        .catchError((e) {
          task.error = '$e';
          task.status = BackgroundTaskStatus.failed;
          task.endTime = DateTime.now();
          log('Bash', 'Background task ${task.id} error: $e');
        });

    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Command started in background (task ID: ${task.id}). '
          'You will be notified when it completes.',
    );
  }

  /// Build final ToolResult from execution result.
  ToolResult _buildResult(
    String toolUseId,
    String command,
    _BashResult result,
    int timeoutMs, {
    String? warning,
    int? elapsedMs,
  }) {
    final output = StringBuffer();

    // Prepend destructive warning if applicable
    if (warning != null) {
      output.writeln('⚠️ Warning: $warning');
    }

    if (result.stdout.isNotEmpty) output.write(result.stdout);
    if (result.stderr.isNotEmpty) {
      if (output.isNotEmpty) output.writeln();
      output.write(result.stderr);
    }

    final exitInfo = _interpretExitCode(command, result.exitCode);

    if (result.timedOut) {
      output.writeln();
      output.writeln(
        '(Command timed out after ${timeoutMs ~/ 1000}s and was killed)',
      );
      return ToolResult(
        toolUseId: toolUseId,
        content: _truncate(output.toString()),
        isError: true,
      );
    }

    if (exitInfo != null) {
      output.writeln();
      output.write(exitInfo);
    }

    final content = output.toString();
    final timeStr = elapsedMs != null
        ? (elapsedMs >= 1000
              ? '${(elapsedMs / 1000).toStringAsFixed(1)}s'
              : '${elapsedMs}ms')
        : null;
    if (content.trim().isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: timeStr != null
            ? '(No output, completed in $timeStr)'
            : '(No output)',
      );
    }

    final truncated = _truncate(content);
    final suffix = timeStr != null ? '\n($timeStr)' : '';
    return ToolResult(
      toolUseId: toolUseId,
      content: '$truncated$suffix',
      isError:
          result.exitCode != 0 && !_isExpectedNonZero(command, result.exitCode),
    );
  }

  /// Find a suitable shell binary.
  String _findShell() {
    final envShell = Platform.environment['SHELL'];
    if (envShell != null && File(envShell).existsSync()) return envShell;
    if (Platform.isMacOS && File('/bin/zsh').existsSync()) return '/bin/zsh';
    return '/bin/bash';
  }

  /// Execute a command and capture output with progress reporting.
  Future<_BashResult> _execute({
    required String shell,
    required String command,
    required String cwd,
    required int timeoutMs,
    required String toolUseId,
  }) async {
    final wrappedCommand = '$command; __exit=\$?; pwd -P; exit \$__exit';

    final process = await Process.start(
      shell,
      ['-c', wrappedCommand],
      workingDirectory: cwd,
      environment: {
        ...Platform.environment,
        'GIT_EDITOR': 'true',
        'LANG': 'en_US.UTF-8',
      },
    );

    process.stdin.close();

    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();
    var timedOut = false;

    // Progress tracking
    final startTime = DateTime.now();
    Timer? progressTimer;
    if (onProgress != null) {
      progressTimer = Timer.periodic(
        const Duration(milliseconds: _progressIntervalMs),
        (_) {
          final elapsed = DateTime.now().difference(startTime).inMilliseconds;
          if (elapsed >= _progressThresholdMs) {
            final currentOutput = stdoutBuf.toString() + stderrBuf.toString();
            if (currentOutput.isNotEmpty) {
              onProgress!(toolUseId, _truncate(currentOutput), elapsed);
            }
          }
        },
      );
    }

    final stdoutFuture = process.stdout
        .transform(const SystemEncoding().decoder)
        .listen((data) => stdoutBuf.write(data))
        .asFuture();
    final stderrFuture = process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((data) => stderrBuf.write(data))
        .asFuture();

    final exitCode = await process.exitCode.timeout(
      Duration(milliseconds: timeoutMs),
      onTimeout: () {
        timedOut = true;
        Process.killPid(process.pid, ProcessSignal.sigkill);
        return -1;
      },
    );

    progressTimer?.cancel();

    await Future.wait([
      stdoutFuture,
      stderrFuture,
    ]).timeout(const Duration(seconds: 5), onTimeout: () => [null, null]);

    // Extract new cwd from stdout (last line is pwd -P output)
    String stdout = stdoutBuf.toString();
    String? newCwd;
    if (!timedOut && stdout.isNotEmpty) {
      final lines = stdout.split('\n');
      while (lines.isNotEmpty && lines.last.trim().isEmpty) {
        lines.removeLast();
      }
      if (lines.isNotEmpty && lines.last.startsWith('/')) {
        final candidate = lines.removeLast().trim();
        if (Directory(candidate).existsSync()) {
          newCwd = candidate;
        }
      }
      stdout = lines.join('\n');
    }

    return _BashResult(
      stdout: stdout,
      stderr: stderrBuf.toString(),
      exitCode: timedOut ? -1 : exitCode,
      timedOut: timedOut,
      newCwd: newCwd,
    );
  }

  /// Get destructive command warning, or null if safe.
  /// Reference: claude-code-best destructiveCommandWarning.ts
  String? _getDestructiveWarning(String command) {
    for (final entry in _destructiveWarnings.entries) {
      if (command.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// Interpret exit code for known commands.
  /// Reference: claude-code-best commandSemantics.ts
  String? _interpretExitCode(String command, int exitCode) {
    if (exitCode == 0) return null;
    final cmd = command.trim().split(' ').first.split('/').last;
    if (cmd == 'grep' && exitCode == 1) return '(grep: no matches found)';
    if (cmd == 'diff' && exitCode == 1) return '(diff: files differ)';
    return '(Exit code: $exitCode)';
  }

  bool _isExpectedNonZero(String command, int exitCode) {
    final cmd = command.trim().split(' ').first.split('/').last;
    return (cmd == 'grep' && exitCode == 1) || (cmd == 'diff' && exitCode == 1);
  }

  String _truncate(String output) {
    if (output.length <= _maxOutputChars) return output;
    return '${output.substring(0, _maxOutputChars)}\n\n'
        '(Output truncated: ${output.length} chars exceeded limit of $_maxOutputChars chars)';
  }
}

class _BashResult {
  final String stdout;
  final String stderr;
  final int exitCode;
  final bool timedOut;
  final String? newCwd;

  const _BashResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.timedOut,
    this.newCwd,
  });
}
