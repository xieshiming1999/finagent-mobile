/// Summarize tool input for UI display — shows meaningful content instead of parameter names.
/// Each app can extend this with app-specific tools.
String summarizeToolInput(String toolName, Map<String, dynamic> input) {
  switch (toolName) {
    // File tools
    case 'Read' || 'FileRead' || 'Write' || 'FileWrite' || 'Edit' || 'FileEdit':
      final path = input['file_path'] as String? ?? '';
      return path.length > 40 ? '...${path.substring(path.length - 40)}' : path;
    case 'Glob':
      return input['pattern'] as String? ?? '';
    case 'Grep':
      final pattern = input['pattern'] as String? ?? '';
      return pattern.length > 40 ? '${pattern.substring(0, 40)}...' : pattern;
    case 'LS':
      return input['path'] as String? ?? '.';
    case 'Bash':
      final cmd = input['command'] as String? ?? '';
      return cmd.length > 60 ? '${cmd.substring(0, 60)}...' : cmd;
    case 'FileManage':
      final action = input['action'] as String? ?? '';
      final path = input['path'] as String? ?? '';
      final name = path.split('/').last;
      return '$action: $name';

    // Agent & task tools
    case 'Agent':
      final name = input['name'] as String? ?? '';
      final desc = input['description'] as String? ?? '';
      final label = name.isNotEmpty ? name : desc;
      return label.length > 50 ? '${label.substring(0, 50)}...' : label;
    case 'TaskCreate':
      return input['subject'] as String? ?? '';
    case 'TaskUpdate':
      final id = input['taskId'] as String? ?? '';
      final status = input['status'] as String? ?? '';
      return status.isNotEmpty ? '#$id → $status' : '#$id';
    case 'TaskGet':
      return '#${input['taskId'] ?? ''}';
    case 'TaskList':
      return '';
    case 'TaskOutput' || 'TaskStop':
      return '#${input['task_id'] ?? ''}';
    case 'SendMessage':
      return 'to: ${input['to'] ?? ''}';
    case 'TeamCreate' || 'TeamDelete':
      return input['team_name'] as String? ?? input['name'] as String? ?? '';

    // Skill & plan
    case 'Skill':
      return input['skill'] as String? ?? input['name'] as String? ?? '';
    case 'EnterPlanMode' || 'ExitPlanMode':
      return '';

    // UI tools
    case 'UIControl' || 'UIQuery':
      return input['action'] as String? ?? input['query'] as String? ?? '';

    // Cron tools
    case 'CronCreate':
      return input['cron'] as String? ?? '';
    case 'CronDelete':
      return input['id'] as String? ?? '';
    case 'CronList':
      return '';

    // Web
    case 'WebFetch':
      final url = input['url'] as String? ?? '';
      return url.length > 50 ? '${url.substring(0, 50)}...' : url;
    case 'WebView':
      return input['action'] as String? ?? '';

    // Service & Script
    case 'ServiceCall':
      final method = input['method'] as String? ?? 'GET';
      final path = input['path'] as String? ?? '';
      final short = path.length > 40 ? '${path.substring(0, 40)}...' : path;
      return '$method $short';
    case 'Script':
      final code = input['code'] as String? ?? '';
      return code.length > 50 ? '${code.substring(0, 50)}...' : code;

    // Monitor tools
    case 'MonitorCreate':
      return input['name'] as String? ?? '';
    case 'MonitorUpdate':
      return input['id'] as String? ?? '';
    case 'MonitorDelete':
      return input['id'] as String? ?? '';
    case 'MonitorList':
      return '';

    // Echo & Environment
    case 'Echo':
      final msg = input['message'] as String? ?? '';
      return msg.length > 50 ? '${msg.substring(0, 50)}...' : msg;
    case 'Environment':
      return input['key'] as String? ?? '';
  }

  // Generic fallback
  final path =
      input['file_path'] as String? ??
      input['path'] as String? ??
      input['pattern'] as String? ??
      input['query'] as String? ??
      '';
  if (path.isNotEmpty) {
    return path.length > 40 ? '...${path.substring(path.length - 40)}' : path;
  }
  final action = input['action'] as String?;
  if (action != null) return action;
  return input.keys.take(2).join(', ');
}
