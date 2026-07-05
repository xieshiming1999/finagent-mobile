import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../agent/anthropic_llm_client.dart';
import '../agent/data_fetcher/tdx_fetcher.dart';
import '../agent/fallback_llm_client.dart';
import '../agent/llm_client.dart';
import '../agent/log.dart';
import '../agent/openai_llm_client.dart';
import '../agent/data_processor/trading_calendar.dart';
import 'agent_factory.dart';
import 'api_config.dart';
import 'feature_config.dart';
import 'i18n/app_localizations.dart';
import 'llm_direct_config.dart';
import 'llm_config.dart';
import 'script_tool/script_tool.dart';
import 'trading_calendar.dart';

/// Manages features with lazy Agent initialization.
class FeatureManager {
  String serverUrl;
  LLMDirectConfig? _llmConfig;
  LLMConfigStore? _llmStore;
  ApiConfigStore? _apiConfig;
  final Map<String, FeatureConfig> _configs = {};
  final Map<String, FeatureRuntime> _runtimes = {};
  String _currentFeatureId = '';
  String? _docsDir;
  TradingCalendarStore? tradingCalendar;

  FeatureManager({required this.serverUrl});

  /// Base path for the first registered feature (used by Settings for TDX etc.)
  String? get basePath {
    if (_docsDir == null || _configs.isEmpty) return null;
    return '$_docsDir/agents/${_configs.keys.first}';
  }

  void updateServerUrl(String url) {
    serverUrl = url;
    for (final runtime in _runtimes.values) {
      runtime.agent.toolContext.serviceBaseUrl = url;
    }
  }

  void updateLLMConfig(LLMDirectConfig config) {
    _llmConfig = config;
    final client = _createDirectClient();
    for (final runtime in _runtimes.values) {
      runtime.agent.client = client;
    }
  }

  void updateLLMStore(LLMConfigStore store) {
    _llmStore = store;
    final client = _createClientFromStore();
    if (client == null) return;
    for (final runtime in _runtimes.values) {
      runtime.agent.client = client;
      final primary = store.primary();
      if (primary != null) {
        runtime.agent.contextWindow = primary.maxContextLength;
      }
    }
  }

  LLMClient? _createClientFromStore() {
    final store = _llmStore;
    if (store == null) return null;
    final llmConfigs = store.getByTag('llm');
    if (llmConfigs.isEmpty) return null;

    final clients = llmConfigs.map(_configToClient).toList();
    return clients.length == 1 ? clients.first : FallbackLLMClient(clients);
  }

  LLMClient _configToClient(LLMProviderConfig c) {
    return switch (c.schema) {
      'anthropic' => AnthropicLLMClient(
        model: c.model,
        apiKey: c.key,
        baseUrl: c.fullUrl,
        effort: c.extras['effort'] ?? 'medium',
        userAgent: _extraHeader(c, 'User-Agent'),
      ),
      _ => OpenAILLMClient(
        model: c.model,
        apiKey: c.key,
        baseUrl: c.fullUrl,
        reasoningEffort: c.extras['reasoning_effort'] ?? '',
        thinkingType: c.extras['thinking_type'] ?? '',
        supportsVision: c.tags.contains('multimodal'),
        userAgent: _extraHeader(c, 'User-Agent'),
      ),
    };
  }

  LLMClient _createDirectClient() {
    final config = _llmConfig;
    if (config != null && config.mode == LLMMode.openai) {
      final endpoint = config.openaiEndpoint.isNotEmpty
          ? config.openaiEndpoint
          : '/v1/chat/completions';
      final base = config.openaiUrl.endsWith('/')
          ? config.openaiUrl.substring(0, config.openaiUrl.length - 1)
          : config.openaiUrl;
      final path = endpoint.startsWith('/') ? endpoint : '/$endpoint';
      return OpenAILLMClient(
        model: config.openaiModel,
        apiKey: config.openaiKey,
        baseUrl: '$base$path',
        reasoningEffort: config.openaiEffort,
        supportsVision: false,
      );
    }
    // Default: Anthropic
    final endpoint = config?.anthropicEndpoint.isNotEmpty == true
        ? config!.anthropicEndpoint
        : '/v1/messages';
    final rawUrl = config?.anthropicUrl ?? 'https://api.anthropic.com';
    final base = rawUrl.endsWith('/')
        ? rawUrl.substring(0, rawUrl.length - 1)
        : rawUrl;
    final path = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return AnthropicLLMClient(
      model: config?.anthropicModel ?? 'claude-sonnet-4-6',
      apiKey: config?.anthropicKey ?? '',
      baseUrl: '$base$path',
      effort: config?.anthropicEffort ?? 'medium',
    );
  }

  String? _extraHeader(LLMProviderConfig c, String name) {
    final exact = c.extras['header_$name'];
    if (exact != null && exact.trim().isNotEmpty) return exact.trim();
    final target = 'header_${name.toLowerCase()}';
    for (final entry in c.extras.entries) {
      if (entry.key.toLowerCase() == target) {
        final value = entry.value.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  void register(FeatureConfig config) {
    _configs[config.id] = config;
    if (_currentFeatureId.isEmpty) _currentFeatureId = config.id;
  }

  List<FeatureConfig> get features => _configs.values.toList();
  String get currentFeatureId => _currentFeatureId;
  FeatureConfig get currentConfig => _configs[_currentFeatureId]!;
  FeatureRuntime? get currentRuntime => _runtimes[_currentFeatureId];

  Future<FeatureRuntime> switchTo(String featureId) async {
    if (!_configs.containsKey(featureId)) {
      throw ArgumentError('Feature "$featureId" not registered');
    }
    if (!_runtimes.containsKey(featureId)) {
      _runtimes[featureId] = await _createRuntime(featureId);
    }
    _currentFeatureId = featureId;
    return _runtimes[featureId]!;
  }

  Future<FeatureRuntime> _createRuntime(String featureId) async {
    final config = _configs[featureId]!;
    final docsDir = await getApplicationDocumentsDirectory();
    _docsDir = docsDir.path;
    final basePath = '${docsDir.path}/agents/$featureId';

    if (_runtimes.isEmpty) Log.init(basePath);

    await _syncBundleAssets(featureId, basePath);

    // Auto-probe TDX servers in background (first feature only)
    if (_runtimes.isEmpty) {
      _autoProbeTdx(basePath);
    }

    final apiConfig = ApiConfigStore();
    await apiConfig.load();
    _apiConfig = apiConfig;

    final tradingCal = TradingCalendarStore(basePath: basePath);
    await tradingCal.load();
    if (tradingCal.isEmpty) {
      tradingCal.fetchFromApi(); // fire-and-forget on first launch
    }
    TradingCalendar.setExternalSource(tradingCal.isTradingDay);
    tradingCalendar = tradingCal;

    final runtime = createAgentRuntime(
      basePath: basePath,
      serverUrl: serverUrl,
      featurePrompt: config.featurePrompt,
      featureId: featureId,
      extraTools: [ScriptTool()],
      excludeTools: config.excludeTools,
      maxOutputTokens: config.maxOutputTokens,
      llmClient: _createClientFromStore() ?? _createDirectClient(),
      visionClientProvider: () => _createVisionClientFromStore(),
      skipPermissions: true,
      apiConfig: apiConfig,
    );

    // Set contextWindow from LLM config (fixes bug: default 160000 was used)
    final primary = _llmStore?.primary();
    if (primary != null) {
      runtime.agent.contextWindow = primary.maxContextLength;
    }

    runtime.fileManageTool.importHandler = (fileTypes) async {
      final result = await FilePicker.platform.pickFiles(
        type: fileTypes != null && fileTypes.isNotEmpty
            ? FileType.custom
            : FileType.any,
        allowedExtensions: fileTypes != null && fileTypes.isNotEmpty
            ? fileTypes
            : null,
      );
      return result?.files.firstOrNull?.path;
    };
    runtime.fileManageTool.exportHandler = (sourcePath) async {
      final fileName = p.basename(sourcePath);
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else {
        downloadsDir = await getDownloadsDirectory();
      }
      downloadsDir ??= await getApplicationDocumentsDirectory();
      final destPath = '${downloadsDir.path}/$fileName';
      File(sourcePath).copySync(destPath);
      final locale = WidgetsBinding.instance.platformDispatcher.locale;
      return AppLocalizations(locale).exportedTo(destPath);
    };

    return FeatureRuntime(
      agent: runtime.agent,
      uiQueryTool: runtime.uiQueryTool,
      uiControlTool: runtime.uiControlTool,
      askUserQuestionTool: runtime.askUserQuestionTool,
      fileManageTool: runtime.fileManageTool,
      webViewTool: runtime.webViewTool,
      environmentTool: runtime.environmentTool,
      cronScheduler: runtime.cronScheduler,
      dataTaskEngine: runtime.dataTaskEngine,
      monitorStore: runtime.monitorStore,
      monitorScheduler: runtime.monitorScheduler,
      watchlistStore: runtime.watchlistStore,
      notificationStore: runtime.notificationStore,
    );
  }

  LLMClient? _createVisionClientFromStore() {
    final vision = _llmStore?.primary('multimodal');
    if (vision == null) return null;
    return _configToClient(vision);
  }

  Future<void> _syncBundleAssets(String feature, String basePath) async {
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final allAssets = assetManifest.listAssets();
    final prefix = 'assets/$feature/';
    final bundleDir = p.join(basePath, 'bundle');

    for (final assetPath in allAssets) {
      if (!assetPath.startsWith(prefix)) continue;
      final relativePath = assetPath.substring(prefix.length);
      if (p.basename(relativePath).startsWith('.')) continue;
      final targetPath = p.join(bundleDir, relativePath);
      Directory(p.dirname(targetPath)).createSync(recursive: true);
      try {
        final content = await rootBundle.loadString(assetPath);
        File(targetPath).writeAsStringSync(content);
      } catch (_) {}
    }

    // Merge TDX servers: bundle → memory (dedup by host:port)
    _mergeTdxServers(basePath);
  }

  void _mergeTdxServers(String basePath) {
    final bundleFile = File('$basePath/bundle/tdx_servers.json');
    if (!bundleFile.existsSync()) return;

    List<TdxServerEntry> bundleServers;
    try {
      final list = jsonDecode(bundleFile.readAsStringSync()) as List;
      bundleServers = list
          .map((e) => TdxServerEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return;
    }

    final memoryFile = File('$basePath/memory/.tdx_servers.json');
    List<TdxServerEntry> existing = [];
    if (memoryFile.existsSync()) {
      try {
        final list = jsonDecode(memoryFile.readAsStringSync()) as List;
        existing = list
            .map((e) => TdxServerEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    // Dedup: keep existing entries, append new ones from bundle
    final keys = existing.map((e) => e.key).toSet();
    for (final s in bundleServers) {
      if (!keys.contains(s.key)) {
        existing.add(s);
        keys.add(s.key);
      }
    }

    memoryFile.parent.createSync(recursive: true);
    memoryFile.writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(existing.map((e) => e.toJson()).toList()),
    );
  }

  /// Auto-probe TDX servers in background on startup.
  void _autoProbeTdx(String basePath) {
    Future(() async {
      final fetcher = TdxFetcher();
      fetcher.basePath = basePath;
      final servers = fetcher.loadServers();
      if (servers.isEmpty) return;

      // Only probe if stale (>1 day since last probe)
      final needsProbe = servers.every((s) {
        if (s.lastProbe == null) return true;
        return DateTime.now().difference(s.lastProbe!) >
            const Duration(days: 1);
      });
      if (!needsProbe) return;

      await fetcher.probeAllServers(servers);
    });
  }
}
