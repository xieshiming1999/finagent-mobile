/// Format token count in compact form: 14.3k, 1.2m
String formatTokenCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}m';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

/// Agent 运行状态 — 跟踪当前轮次的实时信息。
/// 参考: claude-code-best SpinnerMode + 各种状态统计
///
/// 每个 Agent 轮次（run()）创建一个新的 AgentStatus。
/// UI 根据此状态渲染状态栏。
class AgentStatus {
  /// 当前随机动词（每轮开始时选定）
  String verb;

  /// 当前正在执行的 tool 名称
  String? currentTool;

  /// tool 的补充细节（如文件路径、API 路径）
  String? toolDetail;

  /// 轮次开始时间
  final DateTime startTime;

  /// Accumulated token counts for this turn
  int promptTokens = 0;
  int completionTokens = 0;

  /// Latest prompt_tokens from API response — represents actual context usage.
  /// Unlike promptTokens (which sums across all LLM calls in a turn),
  /// this is the raw value from the most recent API response.
  int lastPromptTokens = 0;

  /// Context window size for percentage display.
  int contextWindow = 0;

  /// Estimated output chars (from streaming deltas, before real usage arrives)
  int outputChars = 0;

  /// Output chars at the time of last real usage event
  int _outputCharsAtLastUsage = 0;

  /// tool 调用次数
  int toolCallCount = 0;
  int toolCallTotal = 0;

  /// tool 调用耗时列表 (ms)
  final List<int> toolDurations = [];

  /// LLM 是否在思考（extended thinking）
  bool isThinking = false;

  /// 最后一次收到 token 的时间（用于 stall 检测）
  DateTime lastTokenTime;

  /// Memory 读写统计
  int memoryReads = 0;
  int memoryWrites = 0;
  int skillLoads = 0;

  /// 是否已完成
  bool isDone = false;

  AgentStatus({required this.verb, DateTime? startTime})
    : startTime = startTime ?? DateTime.now(),
      lastTokenTime = startTime ?? DateTime.now();

  /// 已用时间（毫秒）
  int get elapsedMs => DateTime.now().difference(startTime).inMilliseconds;

  /// 总 token 数
  int get totalTokens => promptTokens + completionTokens;

  /// Estimated completion tokens from output chars (~4 chars/token for mixed CJK/code)
  int get estimatedCompletionTokens => (outputChars / 3).round();

  /// Best-effort total tokens for display.
  /// Uses real usage when available, plus estimated tokens for new output
  /// since the last usage event.
  int get displayTokens {
    final newChars = outputChars - _outputCharsAtLastUsage;
    final estimated = (newChars / 3).round();
    return totalTokens + estimated;
  }

  /// Called when a real usage event arrives.
  void onUsage(int prompt, int completion) {
    promptTokens += prompt;
    completionTokens += completion;
    _outputCharsAtLastUsage = outputChars;
    if (prompt > 0) lastPromptTokens = prompt;
  }

  /// Best-effort current context tokens: API ground truth + estimated new output.
  /// During streaming, output chars grow continuously so the number "moves".
  /// When the next usage event arrives, onUsage() resets the baseline.
  int get currentContextTokens {
    if (lastPromptTokens <= 0) return 0;
    final newChars = outputChars - _outputCharsAtLastUsage;
    final pendingTokens = (newChars / 3).round();
    return lastPromptTokens + pendingTokens;
  }

  /// Context usage ratio (0.0-1.0). Returns 0 if contextWindow not set.
  double get contextUsage => contextWindow > 0 && currentContextTokens > 0
      ? (currentContextTokens / contextWindow).clamp(0.0, 1.0)
      : 0.0;

  /// Format context status like kimi-cli: "5.5% (14.3k/200k)"
  String get contextDisplay {
    if (contextWindow <= 0 || currentContextTokens <= 0) return '';
    return '${(contextUsage * 100).toStringAsFixed(1)}% '
        '(${formatTokenCount(currentContextTokens)}/${formatTokenCount(contextWindow)})';
  }

  /// 是否 stalled（3 秒无 token）
  bool get isStalled =>
      !isDone && DateTime.now().difference(lastTokenTime).inMilliseconds > 3000;

  /// 更新 token 接收时间 + 累计输出字符
  void onTokenReceived({int chars = 0}) {
    lastTokenTime = DateTime.now();
    outputChars += chars;
  }

  /// 记录一次 tool 调用
  void onToolStart(String name, String? detail) {
    currentTool = name;
    toolDetail = detail;
    toolCallCount++;
  }

  /// 记录 tool call streaming start (before execution)
  void onToolCallStreaming(String name) {
    toolCallTotal++;
  }

  /// 记录 tool 完成
  void onToolEnd(int durationMs) {
    toolDurations.add(durationMs);
    currentTool = null;
    toolDetail = null;
  }

  /// 记录 memory 操作
  void trackMemory(String toolName, Map<String, dynamic> input) {
    final path =
        input['file_path'] as String? ??
        input['path'] as String? ??
        input['pattern'] as String? ??
        '';
    if (toolName == 'Skill') {
      skillLoads++;
    } else if (toolName == 'Write' || toolName == 'FileWrite') {
      if (path.contains('memory/')) memoryWrites++;
    } else if (toolName == 'Read' ||
        toolName == 'FileRead' ||
        toolName == 'Glob' ||
        toolName == 'Grep') {
      if (path.contains('memory/')) memoryReads++;
    }
  }
}
