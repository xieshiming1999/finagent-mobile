// Agent factory — creates Agent + tools from basePath and serverUrl.
// Pure Dart, zero Flutter dependency. Used by both Flutter app and CLI scripts.

import 'dart:io';

import '../agent/agent.dart';
import '../agent/cron_scheduler.dart';
import '../domain/finance/workflows/finance_data_budget_policy.dart';
import '../domain/finance/workflows/finance_turn_policy.dart';
import '../domain/finance/workflows/finance_workflow_hooks.dart';
import '../agent/llm_client.dart';
import '../agent/log.dart';
import '../agent/data_task_engine.dart';
import '../agent/data_fetcher/api_stats.dart';
import '../agent/data_fetcher/data_manager.dart';
import '../agent/monitor.dart';
import '../agent/plugin_registry.dart';
import '../agent/watchlist.dart';
import '../agent/watchlist_refresher.dart';
import '../agent/monitor_scheduler.dart';
import '../agent/ui_notification.dart';
import '../agent/prompt_builder.dart';
import '../agent/session.dart';
import '../agent/tool.dart';
import '../agent/tool_context.dart';
import '../agent/tools/agent_tool/agent_tool.dart';
import '../agent/tools/bash_tool/bash_tool.dart';
import '../agent/tools/cron_create_tool/cron_create_tool.dart';
import '../agent/tools/cron_delete_tool/cron_delete_tool.dart';
import '../agent/tools/cron_list_tool/cron_list_tool.dart';
import '../agent/tools/echo_tool/echo_tool.dart';
import '../agent/tools/enter_plan_mode_tool/enter_plan_mode_tool.dart';
import '../agent/tools/environment_tool/environment_tool.dart';
import '../agent/tools/exit_plan_mode_tool/exit_plan_mode_tool.dart';
import '../agent/tools/file_edit_tool/file_edit_tool.dart';
import '../agent/tools/file_manage_tool/file_manage_tool.dart';
import '../agent/tools/file_read_tool/file_read_tool.dart';
import '../agent/tools/file_write_tool/file_write_tool.dart';
import '../agent/tools/glob_tool/glob_tool.dart';
import '../agent/tools/grep_tool/grep_tool.dart';
import '../agent/tools/ls_tool/ls_tool.dart';
import '../agent/tools/monitor_create_tool/monitor_create_tool.dart';
import '../agent/tools/monitor_delete_tool/monitor_delete_tool.dart';
import '../agent/tools/monitor_list_tool/monitor_list_tool.dart';
import '../agent/tools/monitor_update_tool/monitor_update_tool.dart';
import '../agent/tools/send_message_tool/send_message_tool.dart';
import '../agent/tools/session_search_tool/session_search_tool.dart';
import '../agent/tools/skill_tool/skill_tool.dart';
import '../agent/tools/task_create_tool/task_create_tool.dart';
import '../agent/tools/task_get_tool/task_get_tool.dart';
import '../agent/tools/task_list_tool/task_list_tool.dart';
import '../agent/tools/task_output_tool/task_output_tool.dart';
import '../agent/tools/task_stop_tool/task_stop_tool.dart';
import '../agent/tools/task_update_tool/task_update_tool.dart';
import '../agent/tools/team_create_tool/team_create_tool.dart';
import '../agent/tools/team_delete_tool/team_delete_tool.dart';
import '../agent/tools/tool_catalog_tool/tool_catalog_tool.dart';
import '../agent/tools/ask_user_question_tool/ask_user_question_tool.dart';
import '../agent/tools/ui_control_tool/ui_control_tool.dart';
import '../agent/tools/ui_notify_tool/ui_notify_tool.dart';
import '../agent/tools/ui_query_tool/ui_query_tool.dart';
import '../agent/tools/watchlist_tool/watchlist_tool.dart';
import '../agent/tools/data_task_tool/data_task_tool.dart';
import '../agent/tools/webview_tool/webview_tool.dart';
import '../agent/tools/market_data_tool/market_data_tool.dart';
import '../agent/tools/wind_mcp_tool/wind_mcp_tool.dart';
import '../agent/tools/data_process_tool/data_process_tool.dart';
import '../agent/tools/portfolio_tool/portfolio_tool.dart';
import '../agent/tools/research_tool/research_tool.dart';
import '../agent/tools/report_download_tool/report_download_tool.dart';
import '../agent/tools/report_parse_tool/report_parse_tool.dart';
import '../agent/tools/page_render_tool/page_render_tool.dart';
import '../agent/tools/image_crop_tool/image_crop_tool.dart';
import '../agent/tools/image_extract_tool/image_extract_tool.dart';
import '../agent/tools/interaction_evidence_tool/interaction_evidence_tool.dart';
import '../agent/tools/workflow_evidence_tool/workflow_evidence_tool.dart';
import '../agent/tools/finance_workflow_state_tool/finance_workflow_state_tool.dart';
import '../agent/tools/capability_status_tool/capability_status_tool.dart';
import '../agent/tools/multimodal_agent_tool/multimodal_agent_tool.dart';
import '../domain/market/services/market_data_resolve_service.dart';
import 'api_config.dart';

/// All runtime objects for a feature — Agent + UI tools + stores.
class AgentRuntime {
  final Agent agent;
  final ToolContext toolContext;
  final UIQueryTool uiQueryTool;
  final UIControlTool uiControlTool;
  final AskUserQuestionTool askUserQuestionTool;
  final WebViewTool webViewTool;
  final FileManageTool fileManageTool;
  final EnvironmentTool environmentTool;
  final CronScheduler cronScheduler;
  final DataTaskEngine dataTaskEngine;
  final SessionManager sessionManager;
  final MonitorStore monitorStore;
  final MonitorScheduler monitorScheduler;
  final WatchlistStore watchlistStore;
  final UINotificationStore notificationStore;

  const AgentRuntime({
    required this.agent,
    required this.toolContext,
    required this.uiQueryTool,
    required this.uiControlTool,
    required this.askUserQuestionTool,
    required this.webViewTool,
    required this.fileManageTool,
    required this.environmentTool,
    required this.cronScheduler,
    required this.dataTaskEngine,
    required this.sessionManager,
    required this.monitorStore,
    required this.monitorScheduler,
    required this.watchlistStore,
    required this.notificationStore,
  });
}

/// Create an AgentRuntime for a feature.
///
/// Pure Dart — no Flutter dependency. Both Flutter app and CLI scripts call this.
///
/// [basePath] — root directory for this feature's data (memory/, sessions/, etc.)
/// [serverUrl] — server base URL for LLM proxy and service APIs
/// [featurePrompt] — feature-specific system prompt
/// [featureId] — feature name for session restore (e.g. "paper", "finance")
/// [sessionsDir] — custom sessions directory (defaults to $basePath/sessions)
/// [skipPermissions] — if true, skip tool permission checks (for CLI/testing)
/// [initLogger] — if true, initialize Log to basePath (first feature only)
/// [extraTools] — additional tools to include (e.g. ScriptTool which depends on flutter_js).
/// [llmClient] — optional override LLM client (direct connection). If null, uses proxy via serverUrl.
/// [excludeTools] — tool names to exclude (e.g. {'Bash'} to disable shell on screener agents).
AgentRuntime createAgentRuntime({
  required String basePath,
  required String serverUrl,
  required String featurePrompt,
  String? featureId,
  String? sessionsDir,
  String? sharedHistoryDir,
  String historySource = 'chat',
  String agentRole = 'chat',
  bool skipPermissions = false,
  bool initLogger = false,
  List<Tool> extraTools = const [],
  Set<String> excludeTools = const {},
  int maxOutputTokens = 8192,
  LLMClient? llmClient,
  LLMClient? Function()? visionClientProvider,
  bool batchDrainQueue = false,
  bool enableWatchlistRefresher = true,
  ApiConfigStore? apiConfig,
}) {
  final effectiveSessionsDir = sessionsDir ?? '$basePath/sessions';

  // Ensure directories
  Directory(basePath).createSync(recursive: true);
  Directory('$basePath/memory').createSync(recursive: true);
  Directory('$basePath/memory/$agentRole').createSync(recursive: true);
  Directory(effectiveSessionsDir).createSync(recursive: true);
  _ensureMemoryIndex(basePath);

  if (initLogger) Log.init(basePath);

  ApiStats.instance.init(basePath);

  final toolContext = ToolContext(
    basePath: basePath,
    serviceBaseUrl: serverUrl,
    approvedTools: ToolContext.loadApprovedTools(basePath),
    skipPermissions: skipPermissions,
  );

  final sessionManager = SessionManager(
    sessionsDir: effectiveSessionsDir,
    sharedHistoryDir: sharedHistoryDir,
  );
  final cronScheduler = CronScheduler(
    storagePath: '$effectiveSessionsDir/scheduled_tasks.json',
  );

  final uiQueryTool = UIQueryTool();
  final uiControlTool = UIControlTool();
  final askUserQuestionTool = AskUserQuestionTool();
  final webViewTool = WebViewTool();

  final fileManageTool = FileManageTool();
  final environmentTool = EnvironmentTool();

  final monitorStore = MonitorStore(memoryDir: effectiveSessionsDir);
  monitorStore.load();
  final watchlistStore = WatchlistStore();
  watchlistStore.load(basePath);
  final dataManager = DataManager(
    tushareToken: apiConfig?.get('TUSHARE_TOKEN'),
    basePath: basePath,
  );
  final marketDataResolveService = MarketDataResolveService(
    dataManager: dataManager,
  );
  final watchlistRefresher = WatchlistRefresher(
    watchlistStore,
    marketDataResolveService,
  );
  if (enableWatchlistRefresher) watchlistRefresher.start();
  final dataTaskEngine = DataTaskEngine(basePath: basePath);
  dataTaskEngine.load();
  dataTaskEngine.resumePending();
  final notificationStore = UINotificationStore(
    storageDir: effectiveSessionsDir,
  );
  notificationStore.load();
  final monitorScheduler = MonitorScheduler(
    store: monitorStore,
    serviceBaseUrl: serverUrl,
    basePath: basePath,
  );
  monitorScheduler.notificationStore = notificationStore;

  final researchTool = ResearchTool();
  researchTool.init(basePath, apiConfig: apiConfig);
  final windApiKey = apiConfig?.get('WIND_API_KEY')?.trim() ?? '';
  final windMcpTool = windApiKey.isEmpty
      ? null
      : WindMcpTool(basePath: basePath, apiConfig: apiConfig);

  final baseTools = <Tool>[
    EchoTool(),
    FileReadTool(),
    FileWriteTool(),
    FileEditTool(),
    fileManageTool,
    GlobTool(),
    GrepTool(),
    LSTool(),
    SkillTool(),
    environmentTool,
    InteractionEvidenceTool(),
    WorkflowEvidenceTool(),
    FinanceWorkflowStateTool(),
    ...extraTools,
    uiQueryTool,
    uiControlTool,
    askUserQuestionTool,
    webViewTool,
    CronCreateTool(scheduler: cronScheduler),
    CronDeleteTool(scheduler: cronScheduler),
    CronListTool(scheduler: cronScheduler),
    TaskCreateTool(),
    TaskGetTool(),
    TaskUpdateTool(),
    TaskListTool(),
    TaskOutputTool(),
    EnterPlanModeTool(),
    ExitPlanModeTool(),
    TeamCreateTool(),
    MonitorCreateTool(store: monitorStore, scheduler: monitorScheduler),
    MonitorDeleteTool(store: monitorStore),
    MonitorListTool(store: monitorStore),
    MonitorUpdateTool(store: monitorStore),
    WatchlistTool(store: watchlistStore),
    DataTaskTool(engine: dataTaskEngine),
    SessionSearchTool(),
    UINotifyTool()..store = notificationStore,
    MarketDataTool(dataManager: dataManager, dataTaskEngine: dataTaskEngine),
    if (windMcpTool != null) windMcpTool,
    DataProcessTool(
      dataManager: dataManager,
      resolveService: marketDataResolveService,
      watchlistStore: watchlistStore,
    ),
    PortfolioTool(
      dataManager: dataManager,
      resolveService: marketDataResolveService,
    ),
    ReportDownloadTool(),
    ReportParseTool(),
    PageRenderTool(),
    ImageCropTool(),
    researchTool,
    ...PluginRegistry(apiConfig).getTools(),
  ];

  // Platform-specific tools: Bash on desktop only
  if (Platform.isMacOS || Platform.isLinux) {
    baseTools.add(BashTool());
  }

  // Filter excluded tools
  final tools = excludeTools.isEmpty
      ? baseTools
      : baseTools.where((t) => !excludeTools.contains(t.name)).toList();
  if (!excludeTools.contains('ToolCatalog')) {
    tools.add(ToolCatalogTool(toolsProvider: () => tools));
  }
  if (!excludeTools.contains('CapabilityStatus')) {
    tools.add(CapabilityStatusTool(toolsProvider: () => tools));
  }

  final financeDataBudgetPolicy = FinanceDataBudgetPolicy();
  final agent = Agent(
    client: llmClient ?? LLMClient(baseUrl: serverUrl),
    tools: tools,
    promptBuilder: PromptBuilder(
      basePath: basePath,
      featurePrompt: featurePrompt,
      agentRole: agentRole,
    ),
    toolContext: toolContext,
    sessionManager: sessionManager,
    cronScheduler: cronScheduler,
    maxOutputTokens: maxOutputTokens,
    historySource: historySource,
    batchDrainQueue: batchDrainQueue,
    enableBackgroundHooks: !batchDrainQueue,
    domainDataBudgetPolicy: financeDataBudgetPolicy,
    domainTurnPolicy: FinanceTurnPolicy(),
    domainWorkflowHooks: FinanceWorkflowHooks(
      isBypassTool: financeDataBudgetPolicy.isBypassTool,
      availableToolNames: tools.map((tool) => tool.name).toSet(),
    ),
  );

  // Tools that need Agent reference
  agent.addTool(AgentTool(parentAgent: agent));
  agent.addTool(TaskStopTool(parentAgent: agent));
  agent.addTool(SendMessageTool(parentAgent: agent));
  agent.addTool(TeamDeleteTool(parentAgent: agent));
  agent.addTool(ImageExtractTool(parentAgent: agent));
  agent.addTool(
    MultimodalAgentTool(
      visionClientProvider: () => visionClientProvider?.call(),
    ),
  );

  // Wire DataTaskEngine notifications to agent
  dataTaskEngine.notificationQueue = agent.notificationQueue;

  // Wire WatchlistRefresher alerts to agent notification queue
  watchlistRefresher.chatQueue = agent.notificationQueue;
  watchlistRefresher.eventQueue = agent.notificationQueue;

  // Restore session + start cron + start monitor scheduler
  if (featureId != null) {
    agent.restoreSession(feature: featureId);
  }
  cronScheduler.start();

  // Auto ai_validate: daily at 15:30 (after A-share close), durable.
  const aiValidateCronKey = 'finance.ai_validate.daily';
  final hasValidateCron = cronScheduler.listTasks().any(
    (t) => t.key == aiValidateCronKey,
  );
  if (!hasValidateCron) {
    cronScheduler.addTask(
      key: aiValidateCronKey,
      schedule: '30 15 * * 1-5',
      prompt:
          'Please run DataProcess(action: "ai_validate") to verify historical prediction accuracy and update strategy win rates.',
      recurring: true,
      durable: true,
      runInBackground: true,
    );
  }

  // monitorScheduler.onAlert wired by UI layer for haptic feedback
  monitorScheduler.start();

  return AgentRuntime(
    agent: agent,
    toolContext: toolContext,
    uiQueryTool: uiQueryTool,
    uiControlTool: uiControlTool,
    askUserQuestionTool: askUserQuestionTool,
    webViewTool: webViewTool,
    fileManageTool: fileManageTool,
    environmentTool: environmentTool,
    cronScheduler: cronScheduler,
    dataTaskEngine: dataTaskEngine,
    sessionManager: sessionManager,
    monitorStore: monitorStore,
    monitorScheduler: monitorScheduler,
    watchlistStore: watchlistStore,
    notificationStore: notificationStore,
  );
}

void _ensureMemoryIndex(String basePath) {
  final memoryFile = File('$basePath/memory/MEMORY.md');
  if (memoryFile.existsSync()) return;
  memoryFile.writeAsStringSync('''# Memory Index

No durable memories saved yet.
''');
}
