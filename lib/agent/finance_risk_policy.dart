enum FinanceRiskTier {
  localRead,
  externalRead,
  localWrite,
  quotaConsuming,
  notification,
  paperTrading,
  realTrading,
  irreversible,
  unknown,
}

class FinanceRiskPolicy {
  final FinanceRiskTier tier;
  final bool requiresPermission;
  final bool automationAllowed;
  final String denialBehavior;
  final String reason;

  const FinanceRiskPolicy({
    required this.tier,
    required this.requiresPermission,
    required this.automationAllowed,
    required this.denialBehavior,
    required this.reason,
  });
}

const _localReadTools = {
  'Read',
  'LS',
  'Glob',
  'Grep',
  'Environment',
  'SessionSearch',
};
const _localWriteTools = {
  'Write',
  'Edit',
  'MultiEdit',
  'FileManage',
  'Bash',
  'Script',
  'Dashboard',
  'ReportDownload',
  'WebView',
};
const _quotaTools = {
  'MarketData',
  'Research',
  'WebFetch',
  'WindMcp',
  'DataProcess',
};
const _notificationTools = {
  'UINotify',
  'CronCreate',
  'CronDelete',
  'MonitorCreate',
  'MonitorUpdate',
  'MonitorDelete',
};
const _realTradingTools = {'XueqiuTrade'};

FinanceRiskPolicy financeRiskPolicyForTool(
  String toolName, {
  Map<String, dynamic> input = const {},
}) {
  if (_realTradingTools.contains(toolName)) {
    final action = (input['action'] ?? '').toString().toLowerCase();
    if (action == 'portfolios' ||
        action == 'balance' ||
        action == 'position' ||
        action == 'history' ||
        action == 'preview_order' ||
        action == 'help') {
      return const FinanceRiskPolicy(
        tier: FinanceRiskTier.externalRead,
        requiresPermission: false,
        automationAllowed: true,
        denialBehavior: 'read_only_fallback',
        reason:
            'Xueqiu portfolio reads and preview_order provide evidence without MONI write endpoints.',
      );
    }
    return const FinanceRiskPolicy(
      tier: FinanceRiskTier.realTrading,
      requiresPermission: true,
      automationAllowed: false,
      denialBehavior: 'stop',
      reason:
          'Real broker or broker-like trading action must be explicitly gated and cannot be silently rerouted.',
    );
  }

  if (toolName == 'Portfolio') {
    final action = (input['action'] ?? '').toString().toLowerCase();
    if (action == 'trade' ||
        action == 'add' ||
        action == 'remove' ||
        action == 'clear') {
      return const FinanceRiskPolicy(
        tier: FinanceRiskTier.paperTrading,
        requiresPermission: true,
        automationAllowed: false,
        denialBehavior: 'escalate',
        reason:
            'Portfolio mutation is local paper-trading state; automation may analyze it but should not mutate it without a user action.',
      );
    }
    return const FinanceRiskPolicy(
      tier: FinanceRiskTier.localRead,
      requiresPermission: false,
      automationAllowed: true,
      denialBehavior: 'read_only_fallback',
      reason: 'Portfolio snapshot and risk reads are local analysis.',
    );
  }

  if (_notificationTools.contains(toolName)) {
    return const FinanceRiskPolicy(
      tier: FinanceRiskTier.notification,
      requiresPermission: true,
      automationAllowed: false,
      denialBehavior: 'escalate',
      reason:
          'External or user-visible notification side effects require explicit gating.',
    );
  }

  if (_quotaTools.contains(toolName)) {
    return const FinanceRiskPolicy(
      tier: FinanceRiskTier.quotaConsuming,
      requiresPermission: false,
      automationAllowed: true,
      denialBehavior: 'read_only_fallback',
      reason:
          'Provider calls may consume quota or rate limit; retry policy must prefer cache, serial probes, and stop on quota/auth errors.',
    );
  }

  if (_localWriteTools.contains(toolName)) {
    return const FinanceRiskPolicy(
      tier: FinanceRiskTier.localWrite,
      requiresPermission: true,
      automationAllowed: true,
      denialBehavior: 'stop',
      reason:
          'Local writes are allowed only inside approved runtime/project boundaries and must stop on denial.',
    );
  }

  if (_localReadTools.contains(toolName)) {
    return const FinanceRiskPolicy(
      tier: FinanceRiskTier.localRead,
      requiresPermission: false,
      automationAllowed: true,
      denialBehavior: 'read_only_fallback',
      reason:
          'Local read-only inspection is safe as a fallback after denied write or side-effect actions.',
    );
  }

  return const FinanceRiskPolicy(
    tier: FinanceRiskTier.unknown,
    requiresPermission: true,
    automationAllowed: false,
    denialBehavior: 'escalate',
    reason:
        'Unknown finance action must be treated as gated until its side effects are classified.',
  );
}
