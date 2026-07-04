import 'dart:math';

/// Spinner verbs — displayed while Agent is running.
/// Ref: claude-code-best/src/constants/spinnerVerbs.ts (188 verbs)
const spinnerVerbs = [
  'Brewing',
  'Thinking',
  'Computing',
  'Crafting',
  'Cooking',
  'Simmering',
  'Fermenting',
  'Crystallizing',
  'Orchestrating',
  'Synthesizing',
  'Composing',
  'Forging',
  'Architecting',
  'Pondering',
  'Concocting',
  'Incubating',
  'Envisioning',
  'Manifesting',
  'Percolating',
  'Hatching',
  'Cultivating',
  'Harmonizing',
  'Weaving',
  'Distilling',
];

/// Turn completion verbs — displayed as "{verb} 5s" when done.
/// Ref: claude-code-best/src/constants/turnCompletionVerbs.ts
const turnCompleteVerbs = [
  'Brewed',
  'Cooked',
  'Crafted',
  'Worked',
  'Sautéed',
  'Baked',
];

const localizedSpinnerVerbsZh = [
  '思考中',
  '计算中',
  '整理中',
  '分析中',
  '生成中',
  '规划中',
  '汇总中',
  '检索中',
  '推理中',
  '编排中',
  '构建中',
  '准备中',
];

const localizedTurnCompleteVerbsZh = [
  '完成',
  '处理完成',
  '分析完成',
  '生成完成',
  '整理完成',
  '执行完成',
];

final _random = Random();

/// Pick a random spinner verb.
String randomSpinnerVerb() =>
    spinnerVerbs[_random.nextInt(spinnerVerbs.length)];

/// Pick a random turn-completion verb.
String randomTurnCompleteVerb() =>
    turnCompleteVerbs[_random.nextInt(turnCompleteVerbs.length)];

/// Pick a locale-aware spinner verb for visible mobile agent status.
String localizedRandomSpinnerVerb({required bool isChinese}) => isChinese
    ? localizedSpinnerVerbsZh[_random.nextInt(localizedSpinnerVerbsZh.length)]
    : randomSpinnerVerb();

/// Pick a locale-aware completion verb for visible mobile agent status.
String localizedRandomTurnCompleteVerb({required bool isChinese}) => isChinese
    ? localizedTurnCompleteVerbsZh[_random.nextInt(
        localizedTurnCompleteVerbsZh.length,
      )]
    : randomTurnCompleteVerb();

/// Tool 名称的中文描述。
String toolDisplayName(String toolName) => switch (toolName) {
  'Read' || 'FileRead' => '读取文件',
  'Write' || 'FileWrite' => '写入文件',
  'Edit' || 'FileEdit' => '编辑文件',
  'Glob' => '搜索文件',
  'Grep' => '搜索内容',
  'LS' => '列出目录',
  'Bash' => '执行命令',
  'ServiceCall' => '调用 API',
  'UIControl' => '操作界面',
  'UIQuery' => '查询界面',
  'Skill' => '加载技能',
  'AskUserQuestion' => '等待回答',
  'Agent' => '启动子代理',
  'CronCreate' || 'CronDelete' || 'CronList' => '定时任务',
  'TaskCreate' || 'TaskUpdate' || 'TaskGet' || 'TaskList' => '任务管理',
  'TaskOutput' => '获取任务结果',
  'TaskStop' => '停止任务',
  'EnterPlanMode' => '进入规划',
  'ExitPlanMode' => '退出规划',
  'Echo' => '测试',
  _ => toolName,
};

/// 格式化持续时间。
String formatDuration(int ms) {
  if (ms < 1000) return '${ms}ms';
  final seconds = ms ~/ 1000;
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final secs = seconds % 60;
  return '${minutes}m ${secs}s';
}

/// 格式化 token 数量。
String formatTokens(int tokens) {
  if (tokens < 1000) return '$tokens';
  if (tokens < 10000) return '${(tokens / 1000).toStringAsFixed(1)}K';
  return '${(tokens / 1000).toStringAsFixed(0)}K';
}
