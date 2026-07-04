import '../shared/api_config.dart';
import 'tool.dart';
import 'tools/xueqiu_trade_tool/xueqiu_trade_tool.dart';

/// Plugin registration: dynamically load tools/skills based on available API keys.
///
/// Usage:
///   final plugins = PluginRegistry(apiConfig);
///   final extraTools = plugins.getTools();
///   final activePlugins = plugins.getActivePlugins();
///
/// A plugin is "active" when its required config keys are present.
/// When active, its tools are registered in the agent and its skills are available.
class PluginRegistry {
  final ApiConfigStore? _config;
  final List<PluginDefinition> _plugins = [];

  PluginRegistry(this._config) {
    _registerBuiltinPlugins();
  }

  void _registerBuiltinPlugins() {
    // Tushare: requires TUSHARE_TOKEN
    register(
      PluginDefinition(
        id: 'tushare',
        name: 'Tushare 数据源',
        description: 'Tushare Pro 金融数据接口（A股历史/实时/财务数据）',
        requiredKeys: ['TUSHARE_TOKEN'],
        toolFactory: (config) => [],
        skillPaths: ['bundle/skills/tushare/'],
      ),
    );

    // Brave Search: requires BRAVE_SEARCH_KEY
    register(
      PluginDefinition(
        id: 'brave_search',
        name: 'Brave Search',
        description: '高质量网页搜索（1000次/月免费）',
        requiredKeys: ['BRAVE_SEARCH_KEY'],
        toolFactory: (config) => [],
      ),
    );

    // Tavily Search: requires TAVILY_API_KEY
    register(
      PluginDefinition(
        id: 'tavily_search',
        name: 'Tavily Search',
        description: 'AI ���化搜索（1000次/月免费）',
        requiredKeys: ['TAVILY_API_KEY'],
        toolFactory: (config) => [],
      ),
    );

    // Xueqiu: requires XQ_COOKIE, XQ_PORTFOLIO optional (for trading)
    register(
      PluginDefinition(
        id: 'xueqiu',
        name: '雪球模拟交易',
        description: '雪球组合模拟交易（调仓/持仓/历史，支持多组合）',
        requiredKeys: ['XQ_COOKIE'],
        toolFactory: (config) {
          final cookie = config.get('XQ_COOKIE')!;
          final portfolioStr = config.get('XQ_PORTFOLIO') ?? '';
          final portfolios = portfolioStr
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          return [XueqiuTradeTool(cookie: cookie, portfolioCodes: portfolios)];
        },
        skillPaths: ['bundle/skills/xueqiu-trade/'],
      ),
    );
  }

  void register(PluginDefinition plugin) {
    _plugins.add(plugin);
  }

  /// Check if a plugin is active (all required keys present).
  bool isActive(String pluginId) {
    final plugin = _plugins.where((p) => p.id == pluginId).firstOrNull;
    if (plugin == null || _config == null) return false;
    return plugin.requiredKeys.every(
      (key) => _config.get(key) != null && _config.get(key)!.isNotEmpty,
    );
  }

  /// Get all active plugin IDs.
  List<String> getActivePlugins() =>
      _plugins.where((p) => isActive(p.id)).map((p) => p.id).toList();

  /// Get tools from all active plugins.
  List<Tool> getTools() {
    final tools = <Tool>[];
    for (final plugin in _plugins) {
      if (isActive(plugin.id)) {
        tools.addAll(plugin.toolFactory(_config!));
      }
    }
    return tools;
  }

  /// Get skill paths from all active plugins.
  List<String> getSkillPaths() {
    final paths = <String>[];
    for (final plugin in _plugins) {
      if (isActive(plugin.id)) {
        paths.addAll(plugin.skillPaths);
      }
    }
    return paths;
  }

  /// Get all registered plugins with their status.
  List<Map<String, dynamic>> getPluginStatus() {
    return _plugins
        .map(
          (p) => {
            'id': p.id,
            'name': p.name,
            'description': p.description,
            'active': isActive(p.id),
            'requiredKeys': p.requiredKeys,
            'missingKeys': p.requiredKeys
                .where(
                  (k) => _config?.get(k) == null || _config!.get(k)!.isEmpty,
                )
                .toList(),
          },
        )
        .toList();
  }
}

class PluginDefinition {
  final String id;
  final String name;
  final String description;
  final List<String> requiredKeys;
  final List<Tool> Function(ApiConfigStore config) toolFactory;
  final List<String> skillPaths;

  PluginDefinition({
    required this.id,
    required this.name,
    this.description = '',
    required this.requiredKeys,
    required this.toolFactory,
    this.skillPaths = const [],
  });
}
