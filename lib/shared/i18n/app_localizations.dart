import 'package:flutter/widgets.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('zh', 'CN')];

  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
  ];

  static AppLocalizations of(BuildContext context) {
    final value = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(value != null, 'AppLocalizations not found in context');
    return value!;
  }

  bool get isChinese => locale.languageCode.toLowerCase().startsWith('zh');

  static const _en = <String, String>{
    'settings': 'Settings',
    'switchFeature': 'Switch Feature',
    'language': 'Language',
    'languageSystem': 'System default',
    'languageEnglish': 'English',
    'languageChinese': 'Chinese (Simplified)',
    'general': 'General',
    'all': 'All',
    'menu': 'Menu',
    'chat': 'Chat',
    'tiles': 'Tiles',
    'oil': 'Oil',
    'save': 'Save',
    'saveServer': 'Save Server',
    'serviceServer': 'Service Server',
    'domainApiHint': 'Domain API (finance, paper, etc.)',
    'serverUrl': 'Server URL',
    'currentValuePrefix': 'Current',
    'defaultValuePrefix': 'Default',
    'allSettingsSaved': 'All settings saved.',
    'llmKeysTab': 'LLM & Keys',
    'tdxServersTab': 'TDX Servers',
    'tradingCalendarTab': 'Trading Calendar',
    'generalTab': 'General',
    'settingsApplied': 'Language updated.',
    'history': 'History',
    'session': 'Session',
    'noHistoryYet': 'No history yet',
    'noSessionsToResume': 'No sessions to resume',
    'resumeArchivesCurrent':
        'Resuming will archive current session and switch to the selected one.',
    'emptySession': 'Empty session',
    'searchSessions': 'Search sessions',
    'searchHistory': 'Search history',
    'sessionPreview': 'Session preview',
    'readOnlyPreview': 'Read-only preview',
    'noSessionPreview': 'No readable messages in this session preview.',
    'noResults': 'No results',
    'active': 'Active',
    'userMessages': 'User',
    'assistantMessages': 'Assistant',
    'toolMessages': 'Tool',
    'collapse': 'Collapse',
    'expand': 'Expand',
    'cancel': 'Cancel',
    'compact': 'Compact',
    'apiHealth': 'API Health',
    'factorRadar': 'Macro Research',
    'macroFactorLoading': 'Loading macro factors...',
    'macroFactorEmpty':
        'No macro research evidence yet. Refresh to load verified source families.',
    'macroFactorSources': 'Sources',
    'macroNumericSeries': 'Official numeric series',
    'macroNumericSeriesHint':
        'Official numeric series are governed facts. Check catalog status before refresh/readback and keep them separate from research narrative.',
    'macroCredentialKey': 'Credential',
    'macroNoCredentialRequired': 'No credential required',
    'macroFactorActive': 'Active',
    'macroFactorBlocked': 'Blocked',
    'macroFactorAffected': 'Affected',
    'macroFactorSendToAgent': 'Analyze',
    'macroResearchOverview': 'Overview',
    'macroResearchEvidence': 'Evidence',
    'macroResearchSourceCoverage': 'Source coverage',
    'macroResearchProvenance': 'Provenance',
    'macroResearchChannels': 'Channels',
    'macroResearchGenerated': 'Generated',
    'macroResearchFilterSource': 'Source',
    'macroResearchFilterFamily': 'Family',
    'macroResearchFilterStatus': 'Status',
    'macroResearchFilterAsset': 'Asset',
    'macroResearchFilterRegion': 'Region',
    'macroResearchFilterRetrieval': 'Retrieval',
    'macroResearchFilterAll': 'All',
    'macroResearchSearch': 'Search',
    'macroResearchSearchPlaceholder': 'Source, subject, region, asset...',
    'macroResearchFilterHint':
        'Filters use governed provenance fields. Blocked, manual, licensed, and browser-assisted rows remain visible as source limitations.',
    'macroResearchSourceStateHint':
        'Source states describe current access behavior: governed readback, browser/manual handoff, credential gate, licensed delivery, or explicit limitation.',
    'macroResearchRetrievalMode': 'Retrieval',
    'macroResearchNoFilteredEvidence':
        'No macro research evidence matches the current filters.',
    'sourceTimeLabel': 'Source time',
    'provenanceFetched': 'Fetched',
    'doctorTitle': 'Doctor',
    'doctorOk': 'OK',
    'doctorWarning': 'WARN',
    'doctorCritical': 'CRIT',
    'doctorSummaryOk': 'All local diagnostics passed.',
    'doctorCriticalCount': 'critical',
    'doctorWarningCount': 'warning',
    'runtimePaths': 'Runtime paths',
    'memoryPaths': 'Memory paths',
    'recentApiFailures': 'Recent API failures',
    'stockIdentityCache': 'Stock identity cache',
    'fundIdentityCache': 'Fund identity cache',
    'quoteCache': 'Quote cache',
    'klineCache': 'K-line cache',
    'reusableStore': 'Reusable store',
    'nextStep': 'Next step',
    'clear': 'Clear',
    'refresh': 'Refresh',
    'allRequests': 'All Requests',
    'bySource': 'By Source',
    'reusableData': 'Reusable Data',
    'dataTasks': 'Data Tasks',
    'runtimeProbeTitle': 'Runtime probe',
    'runtimeProbeRunning': 'Running',
    'runtimeProbeIdle': 'Idle',
    'runtimeProbeSummary': 'Probe summary',
    'recommendedProbeTargets': 'Recommended probe targets',
    'blockedProbeTargets': 'Blocked probe targets',
    'providerProbePacks': 'Provider probe packs',
    'recheckProbeState': 'Recheck probe state',
    'runCredentialProbes': 'Run credential probes',
    'runUnstableProbes': 'Run unstable probes',
    'runFailureProbes': 'Run failure probes',
    'runAllProbes': 'Run all probes',
    'selectedProbes': 'Selected probes',
    'lastProbeRun': 'Last probe run',
    'passedLabel': 'passed',
    'runtimeHealthQueues': 'Runtime action queues',
    'credentialQueueTitle': 'Credential / quota queue',
    'providerGapQueueTitle': 'Provider gap queue',
    'policyDisabledQueueTitle': 'Policy-disabled queue',
    'failureActionQueueTitle': 'Failure action queue',
    'whyHereLabel': 'Why here',
    'moveOutLabel': 'Moves out when',
    'retryPolicyLabel': 'Retry policy',
    'moveOutCredentialConfigured':
        'Configured credential/quota and a passing probe result.',
    'moveOutPolicyChange':
        'Policy changes or explicit reclassification away from disabled.',
    'moveOutTransportRecovered':
        'A passing probe result or reclassification after transport recovery.',
    'moveOutRetrySucceeded':
        'A successful retry, a fallback route, or a non-retry classification.',
    'moveOutImplementedOrReclassified':
        'An implemented provider path or a reclassification out of the queue.',
    'dataSurfaceContract': 'Finance Data Contract',
    'financeSchemaCensusTitle': 'Schema census artifact',
    'financeSchemaCensusDetail':
        'Code-owned surface ledger registered as a reusable data snapshot.',
    'schemaSurfaces': 'surfaces',
    'schemaReusable': 'reusable',
    'schemaFetchOnly': 'fetch-only',
    'schemaArtifactRef': 'artifact',
    'surfaceDataClassTitle': 'Data class',
    'surfaceDataClassDetail':
        'Classify the request before cache, provider, or schema behavior.',
    'surfaceCachePolicyTitle': 'Cache policy',
    'surfaceCachePolicyDetail':
        'Read reusable local rows first when fresh enough.',
    'surfaceProviderPolicyTitle': 'Provider policy',
    'surfaceProviderPolicyDetail':
        'Provider order and gates are code-owned and rate-aware.',
    'surfaceNormalizerTitle': 'Normalizer',
    'surfaceNormalizerDetail':
        'Only registered parser/normalizer code can create reusable rows.',
    'surfacePersistTargetTitle': 'Persist target',
    'surfacePersistTargetDetail':
        'Known schemas write canonical tables with source and ingest time.',
    'surfaceReadbackActionTitle': 'Readback action',
    'surfaceReadbackActionDetail':
        'Same-runtime query paths must read rows back before reuse is claimed.',
    'surfaceFailureSinkTitle': 'Failure sink',
    'surfaceFailureSinkDetail':
        'Provider failures go to API stats/task logs, not reusable tables.',
    'surfaceUiSurfaceTitle': 'UI surface',
    'surfaceUiSurfaceDetail':
        'Panels show source, freshness, failures, and next action.',
    'rowsLabel': 'Rows',
    'codesLabel': 'Codes',
    'latest': 'Latest',
    'running': 'Running',
    'pending': 'Pending',
    'failed': 'Failed',
    'completed': 'Completed',
    'cancelled': 'Cancelled',
    'progressLabel': 'Progress',
    'createdAt': 'Created',
    'completedAt': 'Completed',
    'params': 'Params',
    'result': 'Result',
    'retry': 'Retry',
    'accept': 'Accept',
    'dismiss': 'Dismiss',
    'noRequests': 'No requests',
    'noData': 'No data',
    'requestsSuffix': 'requests',
    'watchlist': 'Watchlist',
    'createNew': '+ New',
    'noWatchlists': 'No watchlists',
    'deleteList': 'Delete list',
    'watching': 'Watching',
    'entered': 'Entered',
    'exited': 'Exited',
    'emptyListPrompt':
        'Empty list. Use + to add items manually, or let the agent pick for you.',
    'tapToExpand': 'Tap to expand',
    'condition': 'Condition',
    'target': 'Target',
    'buyAt': 'Buy @',
    'stopLoss': 'Stop',
    'aiAnalysis': 'AI Analysis',
    'addToGroup': 'Add to',
    'add': 'Add',
    'createWatchlist': 'New watchlist',
    'stock': 'Stock',
    'fund': 'Fund',
    'custom': 'Custom',
    'listName': 'List name',
    'create': 'Create',
    'notificationCenter': 'Notification Center',
    'markAllRead': 'Mark all read',
    'noNotifications': 'No notifications',
    'inputMessageHint': 'Type a message...',
    'answerInputHint': 'Type your answer or select an option above...',
    'emptyChatPrompt': 'Send a message to start.\nTry: "Check NVDA quote"',
    'allowTool': 'Allow "{tool}"?',
    'resend': 'Resend',
    'copy': 'Copy',
    'copyAll': 'Copy all',
    'copiedMessages': 'Copied {count} messages',
    'youLabel': 'You',
    'agentLabel': 'Agent',
    'toolsLabel': 'Tools',
    'moveToBackground': 'Move to background',
    'justNow': 'just now',
    'minutesAgo': 'minutes ago',
    'hoursAgo': 'hours ago',
    'start': 'Start',
    'stop': 'Stop',
    'pause': 'Pause',
    'resume': 'Resume',
    'clearQueue': 'Clear queue',
    'delete': 'Delete',
    'view': 'View',
    'stopBackground': 'Stop Background',
    'runInBackground': 'Run in Background',
    'export': 'Export',
    'exportHtml': 'Export HTML',
    'recap': 'Recap',
    'urlLabel': 'URL',
    'methodLabel': 'Method',
    'statusLabel': 'Status',
    'durationLabel': 'Duration',
    'responseLabel': 'Response',
    'latestResult': 'Latest Result',
    'noDataYet': 'No data yet',
    'alertConditions': 'Alert Conditions',
    'lastUpdated': 'Last updated',
    'updateEveryMinutes': 'Update every',
    'minutesUnit': 'minutes',
    'name': 'Name',
    'price': 'Price',
    'changePct': 'Change %',
    'importFinancialReport': 'Import Financial Report',
    'importDashboard': 'Import Dashboard',
    'fullscreen': 'Fullscreen',
    'exitFullscreen': 'Exit Fullscreen',
    'close': 'Close',
    'llmProviders': 'LLM Providers',
    'showKeys': 'Show keys',
    'hideKeys': 'Hide keys',
    'noLlmConfigured': 'No LLM configured. Tap + to add one.',
    'addLlm': 'Add LLM',
    'dataSources': 'Data Sources',
    'dataSourcesHelp':
        'Configure data source tokens. They activate automatically once filled.',
    'tushareTokenHelp': 'Get it from tushare.pro',
    'windApiKeyHelp': 'aifinmarket.wind.com.cn',
    'braveSearchHelp': 'Free up to 1000 calls/month',
    'tavilySearchHelp': 'Free up to 1000 calls/month',
    'fredApiKeyHelp': 'Free registration at fred.stlouisfed.org',
    'beaApiKeyHelp': 'Optional BEA key for apps.bea.gov macro data',
    'xueqiuSimTradeHelp': 'Activates the XueqiuTrade tool when configured.',
    'xueqiuCookieHelp': 'Copy from browser DevTools',
    'portfolioCodesHelp':
        'Portfolio names are enough, for example finasimu,finhsimu,finamsim',
    'apiKeys': 'API Keys',
    'customKeyValueHelp':
        'Custom key-value pairs available through Bridge.getConfig',
    'keyName': 'KEY_NAME',
    'valueLower': 'value',
    'noModel': '(no model)',
    'duplicate': 'Duplicate',
    'disable': 'Disable',
    'enable': 'Enable',
    'enabled': 'Enabled',
    'disabled': 'Disabled',
    'paused': 'Paused',
    'runNow': 'Run now',
    'lastRun': 'Last run',
    'goalAutomation': 'Goal Automation',
    'escalationNeeded': 'escalation needed',
    'automationSuggestions': 'Automation Suggestions',
    'noAutomationSuggestions': 'No automation suggestions pending.',
    'automationSuggestionAccepted': 'Automation suggestion accepted',
    'automationSuggestionDismissed': 'Automation suggestion dismissed',
    'nextRun': 'Next run',
    'cooldown': 'Cooldown',
    'trigger': 'Trigger',
    'triggerEvidence': 'Evidence',
    'recentDecision': 'Recent decision',
    'decisionHistory': 'Decision History',
    'noDecisionHistory': 'No decisions recorded yet.',
    'checkpoint': 'Checkpoint',
    'lastResult': 'Last result',
    'currentWorkGap': 'Current work gap',
    'nextAction': 'Next action',
    'taskGoalView': 'Task / Goal View',
    'objective': 'Objective',
    'scope': 'Scope',
    'dataRequirements': 'Data requirements',
    'riskBoundary': 'Risk boundary',
    'budget': 'Budget',
    'doneCriteria': 'Done criteria',
    'verification': 'Verification',
    'escalation': 'Escalation',
    'evidence': 'Evidence',
    'advanced': 'Advanced',
    'thinking': 'Thinking',
    'tags': 'Tags',
    'vision': 'Vision',
    'audio': 'Audio',
    'llmTag': 'LLM',
    'generationTag': 'Gen',
    'defaultOption': '(default)',
    'tdxServers': 'TDX Servers',
    'testConnection': 'Test Connection',
    'noTdxServers': 'No servers. Restart the app to initialize defaults.',
    'addServersHelp': 'Add servers, one IP or IP:Port per line',
    'calendarNotLoaded': 'Calendar not loaded',
    'tradingCalendar': 'Trading Calendar',
    'fetchSuccess': 'Fetched successfully',
    'fetchFailed': 'Fetch failed. Please check your network.',
    'dataSource': 'Data Source',
    'shenzhenExchange': 'Shenzhen Stock Exchange',
    'lastUpdatedShort': 'Last updated',
    'tradingDays': 'trading days',
    'weekendFallbackRule': 'No data fetched. Using weekend rule.',
    'tradingDay': 'Trading',
    'nonTradingDay': 'Non-trading',
    'manualOverride': 'Manual override',
    'tapDayToggle': 'Tap a day to toggle trading / non-trading.',
    'waitingForInput': 'Waiting for input...',
    'watchlistNotAvailable': 'Watchlist not available',
    'strategyLibrary': 'Strategy Library',
    'strategyLibraryNotAvailable': 'Strategy library not available',
    'strategyLibraryEmpty':
        'No saved strategies yet. Ask the agent to validate and save a StrategySpec first.',
    'strategyLibraryCreate': 'Create strategy',
    'strategyCreatePrompt':
        'Help me design a governed strategy for a stock or fund, validate the StrategySpec first, then explain whether it can be backtested or saved. Do not place orders.',
    'strategyAssetClass': 'Asset',
    'strategyType': 'Type',
    'strategyTypeAll': 'All',
    'strategyTypeStock': 'Stock',
    'strategyTypeFund': 'Fund',
    'strategyTypePortfolio': 'Portfolio',
    'strategyTypeEtf': 'ETF / listed',
    'strategyTypeUnknown': 'Unknown',
    'strategyArtifactContract': 'Contract',
    'strategyArtifactContractHint':
        'Code-owned strategy artifact schema shared by agent, UI, and tools',
    'strategyArtifactCanonical': 'Canonical store',
    'strategyArtifactPerItem': 'Per strategy',
    'strategyArtifactUnavailable': 'Unavailable',
    'strategyLibraryPath': 'Library',
    'strategyItemDir': 'Items',
    'strategySymbols': 'Symbols',
    'strategyEvidenceAction': 'Evidence',
    'strategyEvidenceSummary': 'Result',
    'strategyDataSummary': 'Data',
    'strategyRiskRewardSummary': 'Risk / reward',
    'strategyAssumptionSummary': 'Assumptions',
    'strategyRerun': 'Rerun',
    'strategyReadEvidence': 'Read evidence',
    'strategyAddWatch': 'Add watch',
    'strategyCreateMonitor': 'Create monitor',
    'noEventAgent': 'No Event Agent',
    'eventAgentIdle': 'Event Agent is idle',
    'eventPanelHelp':
        'Dashboard notifications and scheduled tasks are handled here',
    'eventAgentInputHint': 'Send instructions to Event Agent...',
    'tasks': 'Tasks',
    'probeComplete': 'Probe complete',
    'addedServers': 'Added',
    'newServersUnit': 'servers',
    'noNewServers':
        'No new servers. They may already exist or the format may be invalid.',
    'reachable': 'reachable',
    'unreachable': 'unreachable',
    'untested': 'untested',
    'copied': 'Copied',
    'allow': 'Allow',
    'alwaysAllow': 'Always allow',
    'deny': 'Deny',
    'answered': 'Answered',
    'analyzeMarketHint': 'Analyze the market...',
    'noChartDataAvailable': 'No chart data available',
    'script': 'Script',
    'import': 'Import',
    'codeExample': 'Example',
    'pointsSuffix': 'pts',
    'itemsSuffix': 'items',
    'statusError': 'Error',
    'statusRunning': 'Running',
    'statusStopped': 'Stopped',
    'generating': 'Generating',
    'eventLabel': 'Event',
    'newMessage': 'new message',
    'backgroundTaskLabel': 'Background task',
    'compactedLabel': 'Compacted',
    'errorPrefix': 'Error',
    'unknown': 'unknown',
    'tokensUnit': 'tokens',
    'dashboardsUnit': 'dashboards',
    'backgroundShort': 'bg',
    'llmConfigSavedRestart': 'LLM config saved. Restart features to apply.',
    'llmConnection': 'LLM Connection',
    'saveLlmConfig': 'Save LLM Config',
    'serviceProxy': 'Service Proxy',
    'openaiProvider': 'OpenAI',
    'anthropicProvider': 'Anthropic',
    'effortLabel': 'Effort',
    'apiUrl': 'API URL',
    'endpoint': 'Endpoint',
    'apiKey': 'API Key',
    'model': 'Model',
    'off': 'Off',
    'tushareProToken': 'Tushare Pro Token',
    'windAifinMarketApiKey': 'Wind AIFinMarket API Key',
    'braveSearchApiKey': 'Brave Search API Key',
    'tavilySearchApiKey': 'Tavily Search API Key',
    'fredApiKey': 'FRED API Key',
    'beaApiKey': 'BEA API Key',
    'xueqiuCookie': 'Xueqiu Cookie',
    'portfolioCodes': 'Portfolio Codes',
    'mainView': 'Main View',
    'queuePending': 'Queue',
    'pendingItems': 'pending',
    'eventSourceTag': 'event',
    'featureFinance': 'Finance Assistant',
    'featurePaper': 'Paper Assistant',
    'featureMusic': 'Music Assistant',
  };

  static const _zh = <String, String>{
    'settings': '设置',
    'switchFeature': '切换功能',
    'language': '语言',
    'languageSystem': '跟随系统',
    'languageEnglish': 'English',
    'languageChinese': '简体中文',
    'general': '通用',
    'all': '全部',
    'menu': '菜单',
    'chat': '聊天',
    'tiles': '卡片',
    'oil': '原油',
    'save': '保存',
    'saveServer': '保存服务器',
    'serviceServer': '服务端地址',
    'domainApiHint': '领域接口服务（金融、论文等）',
    'serverUrl': '服务地址',
    'currentValuePrefix': '当前',
    'defaultValuePrefix': '默认',
    'allSettingsSaved': '设置已保存。',
    'llmKeysTab': 'LLM 与密钥',
    'tdxServersTab': 'TDX 服务器',
    'tradingCalendarTab': '交易日历',
    'generalTab': '通用',
    'settingsApplied': '语言已更新。',
    'history': '历史',
    'session': '会话',
    'noHistoryYet': '暂无历史记录',
    'noSessionsToResume': '没有可恢复的会话',
    'resumeArchivesCurrent': '恢复会归档当前会话，并切换到所选会话。',
    'emptySession': '空会话',
    'searchSessions': '搜索会话',
    'searchHistory': '搜索历史',
    'sessionPreview': '会话预览',
    'readOnlyPreview': '只读预览',
    'noSessionPreview': '此会话预览中没有可读消息。',
    'noResults': '无结果',
    'active': '当前',
    'userMessages': '用户',
    'assistantMessages': '助手',
    'toolMessages': '工具',
    'collapse': '折叠',
    'expand': '展开',
    'cancel': '取消',
    'compact': '压缩',
    'apiHealth': '接口健康',
    'factorRadar': '宏观研究',
    'macroFactorLoading': '宏观因子加载中...',
    'macroFactorEmpty': '暂无宏观研究证据。点击刷新以加载已验证来源。',
    'macroFactorSources': '来源',
    'macroNumericSeries': '官方数值序列',
    'macroNumericSeriesHint': '官方数值序列是受治理事实。刷新或读回前先看 catalog 状态，并与研究叙事分开使用。',
    'macroCredentialKey': '凭证',
    'macroNoCredentialRequired': '无需凭证',
    'macroFactorActive': '有效',
    'macroFactorBlocked': '受限',
    'macroFactorAffected': '影响对象',
    'macroFactorSendToAgent': '分析',
    'macroResearchOverview': '概览',
    'macroResearchEvidence': '证据',
    'macroResearchSourceCoverage': '来源覆盖',
    'macroResearchProvenance': '溯源',
    'macroResearchChannels': '传导路径',
    'macroResearchGenerated': '生成时间',
    'macroResearchFilterSource': '来源',
    'macroResearchFilterFamily': '类别',
    'macroResearchFilterStatus': '状态',
    'macroResearchFilterAsset': '资产',
    'macroResearchFilterRegion': '地区',
    'macroResearchFilterRetrieval': '获取方式',
    'macroResearchFilterAll': '全部',
    'macroResearchSearch': '搜索',
    'macroResearchSearchPlaceholder': '来源、主题、地区、资产...',
    'macroResearchFilterHint': '筛选条件来自受治理的溯源字段。受阻、手动、授权和浏览器辅助来源仍会显示为来源限制。',
    'macroResearchSourceStateHint':
        '来源状态说明当前访问方式：受治理读回、浏览器/手动交接、凭证门控、授权交付或明确限制。',
    'macroResearchRetrievalMode': '获取方式',
    'macroResearchNoFilteredEvidence': '当前筛选条件下没有匹配的宏观研究证据。',
    'sourceTimeLabel': '来源时间',
    'provenanceFetched': '获取时间',
    'doctorTitle': '诊断',
    'doctorOk': '正常',
    'doctorWarning': '警告',
    'doctorCritical': '严重',
    'doctorSummaryOk': '本地诊断全部通过。',
    'doctorCriticalCount': '严重',
    'doctorWarningCount': '警告',
    'runtimePaths': '运行时路径',
    'memoryPaths': '记忆路径',
    'recentApiFailures': '近期 API 失败',
    'stockIdentityCache': '股票身份缓存',
    'fundIdentityCache': '基金身份缓存',
    'quoteCache': '行情缓存',
    'klineCache': 'K 线缓存',
    'reusableStore': '可复用数据存储',
    'nextStep': '下一步',
    'clear': '清空',
    'refresh': '刷新',
    'allRequests': '全部请求',
    'bySource': '按来源',
    'reusableData': '可复用数据',
    'dataTasks': '数据任务',
    'runtimeProbeTitle': '运行时探测',
    'runtimeProbeRunning': '运行中',
    'runtimeProbeIdle': '空闲',
    'runtimeProbeSummary': '探测摘要',
    'recommendedProbeTargets': '推荐探测目标',
    'blockedProbeTargets': '已阻断探测目标',
    'providerProbePacks': 'Provider 探测包',
    'recheckProbeState': '重新检查探测状态',
    'runCredentialProbes': '运行凭证探测',
    'runUnstableProbes': '运行不稳定探测',
    'runFailureProbes': '运行失败探测',
    'runAllProbes': '运行全部探测',
    'selectedProbes': '已选探测',
    'lastProbeRun': '上次探测时间',
    'passedLabel': '通过',
    'runtimeHealthQueues': '运行时动作队列',
    'credentialQueueTitle': '凭证 / 额度队列',
    'providerGapQueueTitle': 'Provider 缺口队列',
    'policyDisabledQueueTitle': '策略禁用队列',
    'failureActionQueueTitle': '失败动作队列',
    'whyHereLabel': '为何在此',
    'moveOutLabel': '移出条件',
    'retryPolicyLabel': '重试策略',
    'moveOutCredentialConfigured': '凭证 / 额度已配置且探测通过。',
    'moveOutPolicyChange': '策略放开或该能力被重新分类为非禁用。',
    'moveOutTransportRecovered': '探测通过，或传输恢复后被重新分类。',
    'moveOutRetrySucceeded': '重试成功、切换到可用回退路径，或进入不可重试分类。',
    'moveOutImplementedOrReclassified': '能力实现完成，或该行被重新分类后移出队列。',
    'dataSurfaceContract': '金融数据合同',
    'financeSchemaCensusTitle': 'Schema 普查 artifact',
    'financeSchemaCensusDetail': '由代码维护的数据表面账本，已登记为可复用 data snapshot。',
    'schemaSurfaces': '表面',
    'schemaReusable': '可复用',
    'schemaFetchOnly': '仅获取',
    'schemaArtifactRef': 'artifact',
    'surfaceDataClassTitle': '数据类型',
    'surfaceDataClassDetail': '先识别请求类型，再决定缓存、provider 和 schema 行为。',
    'surfaceCachePolicyTitle': '缓存策略',
    'surfaceCachePolicyDetail': '新鲜度足够时，先读本地可复用数据。',
    'surfaceProviderPolicyTitle': 'Provider 策略',
    'surfaceProviderPolicyDetail': 'Provider 顺序和门禁由代码控制，并遵守限速。',
    'surfaceNormalizerTitle': 'Normalizer',
    'surfaceNormalizerDetail': '只有已登记 parser/normalizer 才能生成可复用数据。',
    'surfacePersistTargetTitle': '持久化目标',
    'surfacePersistTargetDetail': '已知 schema 写入 canonical 表，并保留来源和写入时间。',
    'surfaceReadbackActionTitle': '读回动作',
    'surfaceReadbackActionDetail': '声明可复用前，同一运行时 query 路径必须能读回数据。',
    'surfaceFailureSinkTitle': '失败归集',
    'surfaceFailureSinkDetail': 'Provider 失败进入 API 统计和任务日志，不写入可复用表。',
    'surfaceUiSurfaceTitle': 'UI 表面',
    'surfaceUiSurfaceDetail': '面板展示来源、新鲜度、失败原因和下一步动作。',
    'rowsLabel': '行数',
    'codesLabel': '代码数',
    'latest': '最新',
    'running': '运行中',
    'pending': '等待中',
    'failed': '失败',
    'completed': '已完成',
    'cancelled': '已取消',
    'progressLabel': '进度',
    'createdAt': '创建',
    'completedAt': '完成',
    'params': '参数',
    'result': '结果',
    'retry': '重试',
    'accept': '接受',
    'dismiss': '忽略',
    'noRequests': '暂无请求',
    'noData': '暂无数据',
    'requestsSuffix': '次请求',
    'watchlist': '自选股',
    'createNew': '+ 新建',
    'noWatchlists': '无自选列表',
    'deleteList': '删除列表',
    'watching': '观察中',
    'entered': '已入场',
    'exited': '已退出',
    'emptyListPrompt': '空列表，点 + 手动添加，或让 Agent 帮你选。',
    'tapToExpand': '点击展开查看',
    'condition': '条件',
    'target': '目标',
    'buyAt': '买入@',
    'stopLoss': '止损',
    'aiAnalysis': 'AI分析',
    'addToGroup': '添加到',
    'add': '添加',
    'createWatchlist': '新建自选列表',
    'stock': '股票',
    'fund': '基金',
    'custom': '自定义',
    'listName': '列表名称',
    'create': '创建',
    'notificationCenter': '消息中心',
    'markAllRead': '全部已读',
    'noNotifications': '暂无通知',
    'inputMessageHint': '输入消息...',
    'answerInputHint': '输入回答，或选择上方选项...',
    'emptyChatPrompt': '发送一条消息开始。\n试试：“查一下 NVDA 行情”',
    'allowTool': '允许使用“{tool}”？',
    'resend': '重新发送',
    'copy': '复制',
    'copyAll': '复制全部',
    'copiedMessages': '已复制 {count} 条消息',
    'youLabel': '你',
    'agentLabel': 'Agent',
    'toolsLabel': '工具',
    'moveToBackground': '移到后台',
    'justNow': '刚刚',
    'minutesAgo': '分钟前',
    'hoursAgo': '小时前',
    'start': '启动',
    'stop': '停止',
    'pause': '暂停',
    'resume': '恢复',
    'clearQueue': '清队列',
    'delete': '删除',
    'view': '查看',
    'stopBackground': '停止后台',
    'runInBackground': '后台运行',
    'export': '导出',
    'exportHtml': '导出 HTML',
    'recap': '回顾',
    'urlLabel': 'URL',
    'methodLabel': '方法',
    'statusLabel': '状态',
    'durationLabel': '耗时',
    'responseLabel': '响应',
    'latestResult': '最新结果',
    'noDataYet': '暂无数据',
    'alertConditions': '告警条件',
    'lastUpdated': '上次更新',
    'updateEveryMinutes': '每',
    'minutesUnit': '分钟',
    'name': '名称',
    'price': '价格',
    'changePct': '涨跌%',
    'importFinancialReport': '导入财报',
    'importDashboard': '导入看板',
    'fullscreen': '全屏',
    'exitFullscreen': '退出全屏',
    'close': '关闭',
    'llmProviders': 'LLM 提供商',
    'showKeys': '显示密钥',
    'hideKeys': '隐藏密钥',
    'noLlmConfigured': '尚未配置 LLM，点击 + 添加。',
    'addLlm': '添加 LLM',
    'dataSources': '数据源',
    'dataSourcesHelp': '配置数据源 Token（填写后自动激活）',
    'tushareTokenHelp': '在 tushare.pro 获取',
    'windApiKeyHelp': 'aifinmarket.wind.com.cn',
    'braveSearchHelp': '每月免费 1000 次',
    'tavilySearchHelp': '每月免费 1000 次',
    'fredApiKeyHelp': '在 fred.stlouisfed.org 免费注册',
    'beaApiKeyHelp': '可选，用于 apps.bea.gov 宏观数据',
    'xueqiuSimTradeHelp': '填写后激活 XueqiuTrade 工具',
    'xueqiuCookieHelp': '从浏览器 DevTools 复制',
    'portfolioCodesHelp': '填写组合名称即可，如 finasimu,finhsimu,finamsim',
    'apiKeys': 'API 密钥',
    'customKeyValueHelp': '自定义键值对（Bridge.getConfig 可读取）',
    'keyName': 'KEY_NAME',
    'valueLower': '值',
    'noModel': '（未配置模型）',
    'duplicate': '复制',
    'disable': '禁用',
    'enable': '启用',
    'enabled': '已启用',
    'disabled': '已禁用',
    'paused': '已暂停',
    'runNow': '立即运行',
    'lastRun': '上次运行',
    'goalAutomation': '目标自动化',
    'escalationNeeded': '需要升级处理',
    'automationSuggestions': '自动化建议',
    'noAutomationSuggestions': '暂无待处理自动化建议。',
    'automationSuggestionAccepted': '已接受自动化建议',
    'automationSuggestionDismissed': '已忽略自动化建议',
    'nextRun': '下次运行',
    'cooldown': '冷却',
    'trigger': '触发',
    'triggerEvidence': '证据',
    'recentDecision': '最近决策',
    'decisionHistory': '决策历史',
    'noDecisionHistory': '暂无决策记录。',
    'checkpoint': '检查点',
    'lastResult': '上次结果',
    'currentWorkGap': '当前工作缺口',
    'nextAction': '下一步',
    'taskGoalView': '任务 / 目标视图',
    'objective': '目标',
    'scope': '范围',
    'dataRequirements': '数据需求',
    'riskBoundary': '风险边界',
    'budget': '预算',
    'doneCriteria': '完成标准',
    'verification': '验证',
    'escalation': '升级条件',
    'evidence': '证据',
    'advanced': '高级',
    'thinking': '思考',
    'tags': '标签',
    'vision': '视觉',
    'audio': '音频',
    'llmTag': 'LLM',
    'generationTag': '生成',
    'defaultOption': '（默认）',
    'tdxServers': 'TDX 服务器',
    'testConnection': '检测连接',
    'noTdxServers': '暂无服务器，重启应用后会从默认列表初始化。',
    'addServersHelp': '添加服务器（每行一个 IP 或 IP:Port）',
    'calendarNotLoaded': '交易日历未加载',
    'tradingCalendar': '交易日历',
    'fetchSuccess': '获取成功',
    'fetchFailed': '获取失败，请检查网络',
    'dataSource': '数据源',
    'shenzhenExchange': '深交所',
    'lastUpdatedShort': '上次更新',
    'tradingDays': '个交易日',
    'weekendFallbackRule': '未获取数据（使用周末规则）',
    'tradingDay': '交易日',
    'nonTradingDay': '非交易',
    'manualOverride': '手动覆盖',
    'tapDayToggle': '点击日期可手动切换交易/非交易。',
    'waitingForInput': '等待输入...',
    'watchlistNotAvailable': '自选股不可用',
    'strategyLibrary': '策略库',
    'strategyLibraryNotAvailable': '策略库不可用',
    'strategyLibraryEmpty': '暂无已保存策略。请先让 Agent 验证并保存 StrategySpec。',
    'strategyLibraryCreate': '创建策略',
    'strategyCreatePrompt':
        '帮我为一只股票或基金设计一个受治理的策略，先验证 StrategySpec，再说明是否可以回测或保存。不要下单。',
    'strategyAssetClass': '资产',
    'strategyType': '类型',
    'strategyTypeAll': '全部',
    'strategyTypeStock': '股票',
    'strategyTypeFund': '基金',
    'strategyTypePortfolio': '组合',
    'strategyTypeEtf': 'ETF / 场内',
    'strategyTypeUnknown': '未知',
    'strategyArtifactContract': '合同',
    'strategyArtifactContractHint': 'Agent、UI 和工具共享的代码侧策略 artifact schema',
    'strategyArtifactCanonical': '规范存储',
    'strategyArtifactPerItem': '逐策略',
    'strategyArtifactUnavailable': '不可用',
    'strategyLibraryPath': '策略库',
    'strategyItemDir': '条目',
    'strategySymbols': '标的',
    'strategyEvidenceAction': '证据',
    'strategyEvidenceSummary': '结果',
    'strategyDataSummary': '数据',
    'strategyRiskRewardSummary': '风险收益',
    'strategyAssumptionSummary': '假设',
    'strategyRerun': '重跑',
    'strategyReadEvidence': '读证据',
    'strategyAddWatch': '加入观察',
    'strategyCreateMonitor': '创建监控',
    'noEventAgent': '没有 Event Agent',
    'eventAgentIdle': 'Event Agent 空闲中',
    'eventPanelHelp': 'Dashboard 通知和定时任务会在这里处理',
    'eventAgentInputHint': '发送指令给 Event Agent...',
    'tasks': '任务',
    'probeComplete': '探测完成',
    'addedServers': '已添加',
    'newServersUnit': '台服务器',
    'noNewServers': '没有新服务器（可能已存在或格式不正确）。',
    'reachable': '可达',
    'unreachable': '不可达',
    'untested': '未测试',
    'copied': '已复制',
    'allow': '允许',
    'alwaysAllow': '始终允许',
    'deny': '拒绝',
    'answered': '已响应',
    'analyzeMarketHint': '分析行情...',
    'noChartDataAvailable': '暂无图表数据',
    'script': '脚本',
    'import': '导入',
    'codeExample': '例',
    'pointsSuffix': '分',
    'itemsSuffix': '项',
    'statusError': '错误',
    'statusRunning': '运行中',
    'statusStopped': '已停止',
    'generating': '生成中',
    'eventLabel': '事件',
    'newMessage': '新消息',
    'backgroundTaskLabel': '后台任务',
    'compactedLabel': '已压缩',
    'errorPrefix': '错误',
    'unknown': '未知',
    'tokensUnit': 'tokens',
    'dashboardsUnit': '个面板',
    'backgroundShort': '后台',
    'llmConfigSavedRestart': 'LLM 配置已保存，重启功能后生效。',
    'llmConnection': 'LLM 连接',
    'saveLlmConfig': '保存 LLM 配置',
    'serviceProxy': '服务代理',
    'openaiProvider': 'OpenAI',
    'anthropicProvider': 'Anthropic',
    'effortLabel': '思考强度',
    'apiUrl': 'API 地址',
    'endpoint': '接口路径',
    'apiKey': 'API 密钥',
    'model': '模型',
    'off': '关闭',
    'tushareProToken': 'Tushare Pro Token',
    'windAifinMarketApiKey': 'Wind AIFinMarket API Key',
    'braveSearchApiKey': 'Brave Search API Key',
    'tavilySearchApiKey': 'Tavily Search API Key',
    'fredApiKey': 'FRED API Key',
    'beaApiKey': 'BEA API Key',
    'xueqiuCookie': '雪球 Cookie',
    'portfolioCodes': '组合代码',
    'mainView': '主视图',
    'queuePending': '队列',
    'pendingItems': '条待处理',
    'eventSourceTag': '事件',
    'featureFinance': '金融助手',
    'featurePaper': '论文助手',
    'featureMusic': '音乐助手',
  };

  String _value(String key) => (isChinese ? _zh[key] : _en[key]) ?? key;

  String get settings => _value('settings');
  String get switchFeature => _value('switchFeature');
  String get language => _value('language');
  String get languageSystem => _value('languageSystem');
  String get languageEnglish => _value('languageEnglish');
  String get languageChinese => _value('languageChinese');
  String get general => _value('general');
  String get all => _value('all');
  String get menu => _value('menu');
  String get chat => _value('chat');
  String get tiles => _value('tiles');
  String get oil => _value('oil');
  String get save => _value('save');
  String get saveServer => _value('saveServer');
  String get serviceServer => _value('serviceServer');
  String get domainApiHint => _value('domainApiHint');
  String get serverUrl => _value('serverUrl');
  String get currentValuePrefix => _value('currentValuePrefix');
  String get defaultValuePrefix => _value('defaultValuePrefix');
  String get allSettingsSaved => _value('allSettingsSaved');
  String get llmKeysTab => _value('llmKeysTab');
  String get tdxServersTab => _value('tdxServersTab');
  String get tradingCalendarTab => _value('tradingCalendarTab');
  String get generalTab => _value('generalTab');
  String get settingsApplied => _value('settingsApplied');
  String get history => _value('history');
  String get session => _value('session');
  String get noHistoryYet => _value('noHistoryYet');
  String get noSessionsToResume => _value('noSessionsToResume');
  String get resumeArchivesCurrent => _value('resumeArchivesCurrent');
  String get emptySession => _value('emptySession');
  String get searchSessions => _value('searchSessions');
  String get searchHistory => _value('searchHistory');
  String get sessionPreview => _value('sessionPreview');
  String get readOnlyPreview => _value('readOnlyPreview');
  String get noSessionPreview => _value('noSessionPreview');
  String get noResults => _value('noResults');
  String get active => _value('active');
  String get userMessages => _value('userMessages');
  String get assistantMessages => _value('assistantMessages');
  String get toolMessages => _value('toolMessages');
  String get collapse => _value('collapse');
  String get expand => _value('expand');
  String get cancel => _value('cancel');
  String get compact => _value('compact');
  String get apiHealth => _value('apiHealth');
  String get factorRadar => _value('factorRadar');
  String get macroFactorLoading => _value('macroFactorLoading');
  String get macroFactorEmpty => _value('macroFactorEmpty');
  String get macroFactorSources => _value('macroFactorSources');
  String get macroNumericSeries => _value('macroNumericSeries');
  String get macroNumericSeriesHint => _value('macroNumericSeriesHint');
  String get macroCredentialKey => _value('macroCredentialKey');
  String get macroNoCredentialRequired => _value('macroNoCredentialRequired');
  String get macroFactorActive => _value('macroFactorActive');
  String get macroFactorBlocked => _value('macroFactorBlocked');
  String get macroFactorAffected => _value('macroFactorAffected');
  String get macroFactorSendToAgent => _value('macroFactorSendToAgent');
  String get macroResearchOverview => _value('macroResearchOverview');
  String get macroResearchEvidence => _value('macroResearchEvidence');
  String get macroResearchSourceCoverage =>
      _value('macroResearchSourceCoverage');
  String get macroResearchProvenance => _value('macroResearchProvenance');
  String get macroResearchChannels => _value('macroResearchChannels');
  String get macroResearchGenerated => _value('macroResearchGenerated');
  String get macroResearchFilterSource => _value('macroResearchFilterSource');
  String get macroResearchFilterFamily => _value('macroResearchFilterFamily');
  String get macroResearchFilterStatus => _value('macroResearchFilterStatus');
  String get macroResearchFilterAsset => _value('macroResearchFilterAsset');
  String get macroResearchFilterRegion => _value('macroResearchFilterRegion');
  String get macroResearchFilterRetrieval =>
      _value('macroResearchFilterRetrieval');
  String get macroResearchFilterAll => _value('macroResearchFilterAll');
  String get macroResearchSearch => _value('macroResearchSearch');
  String get macroResearchSearchPlaceholder =>
      _value('macroResearchSearchPlaceholder');
  String get macroResearchFilterHint => _value('macroResearchFilterHint');
  String get macroResearchSourceStateHint =>
      _value('macroResearchSourceStateHint');
  String get macroResearchRetrievalMode => _value('macroResearchRetrievalMode');
  String get macroResearchNoFilteredEvidence =>
      _value('macroResearchNoFilteredEvidence');
  String get sourceTimeLabel => _value('sourceTimeLabel');
  String get provenanceFetched => _value('provenanceFetched');
  String get doctorTitle => _value('doctorTitle');
  String get doctorOk => _value('doctorOk');
  String get doctorWarning => _value('doctorWarning');
  String get doctorCritical => _value('doctorCritical');
  String get doctorSummaryOk => _value('doctorSummaryOk');
  String get doctorCriticalCount => _value('doctorCriticalCount');
  String get doctorWarningCount => _value('doctorWarningCount');
  String get runtimePaths => _value('runtimePaths');
  String get memoryPaths => _value('memoryPaths');
  String get recentApiFailures => _value('recentApiFailures');
  String get stockIdentityCache => _value('stockIdentityCache');
  String get fundIdentityCache => _value('fundIdentityCache');
  String get quoteCache => _value('quoteCache');
  String get klineCache => _value('klineCache');
  String get reusableStore => _value('reusableStore');
  String get nextStep => _value('nextStep');
  String get clear => _value('clear');
  String get refresh => _value('refresh');
  String get allRequests => _value('allRequests');
  String get bySource => _value('bySource');
  String get reusableData => _value('reusableData');
  String get dataTasks => _value('dataTasks');
  String get runtimeProbeTitle => _value('runtimeProbeTitle');
  String get runtimeProbeRunning => _value('runtimeProbeRunning');
  String get runtimeProbeIdle => _value('runtimeProbeIdle');
  String get runtimeProbeSummary => _value('runtimeProbeSummary');
  String get recommendedProbeTargets => _value('recommendedProbeTargets');
  String get blockedProbeTargets => _value('blockedProbeTargets');
  String get providerProbePacks => _value('providerProbePacks');
  String get recheckProbeState => _value('recheckProbeState');
  String get runCredentialProbes => _value('runCredentialProbes');
  String get runUnstableProbes => _value('runUnstableProbes');
  String get runFailureProbes => _value('runFailureProbes');
  String get runAllProbes => _value('runAllProbes');
  String get selectedProbes => _value('selectedProbes');
  String get lastProbeRun => _value('lastProbeRun');
  String get passedLabel => _value('passedLabel');
  String get runtimeHealthQueues => _value('runtimeHealthQueues');
  String get credentialQueueTitle => _value('credentialQueueTitle');
  String get providerGapQueueTitle => _value('providerGapQueueTitle');
  String get policyDisabledQueueTitle => _value('policyDisabledQueueTitle');
  String get failureActionQueueTitle => _value('failureActionQueueTitle');
  String get whyHereLabel => _value('whyHereLabel');
  String get moveOutLabel => _value('moveOutLabel');
  String get retryPolicyLabel => _value('retryPolicyLabel');
  String get moveOutCredentialConfigured =>
      _value('moveOutCredentialConfigured');
  String get moveOutPolicyChange => _value('moveOutPolicyChange');
  String get moveOutTransportRecovered => _value('moveOutTransportRecovered');
  String get moveOutRetrySucceeded => _value('moveOutRetrySucceeded');
  String get moveOutImplementedOrReclassified =>
      _value('moveOutImplementedOrReclassified');
  String get dataSurfaceContract => _value('dataSurfaceContract');
  String get financeSchemaCensusTitle => _value('financeSchemaCensusTitle');
  String get financeSchemaCensusDetail => _value('financeSchemaCensusDetail');
  String get schemaSurfaces => _value('schemaSurfaces');
  String get schemaReusable => _value('schemaReusable');
  String get schemaFetchOnly => _value('schemaFetchOnly');
  String get schemaArtifactRef => _value('schemaArtifactRef');
  String get surfaceDataClassTitle => _value('surfaceDataClassTitle');
  String get surfaceDataClassDetail => _value('surfaceDataClassDetail');
  String get surfaceCachePolicyTitle => _value('surfaceCachePolicyTitle');
  String get surfaceCachePolicyDetail => _value('surfaceCachePolicyDetail');
  String get surfaceProviderPolicyTitle => _value('surfaceProviderPolicyTitle');
  String get surfaceProviderPolicyDetail =>
      _value('surfaceProviderPolicyDetail');
  String get surfaceNormalizerTitle => _value('surfaceNormalizerTitle');
  String get surfaceNormalizerDetail => _value('surfaceNormalizerDetail');
  String get surfacePersistTargetTitle => _value('surfacePersistTargetTitle');
  String get surfacePersistTargetDetail => _value('surfacePersistTargetDetail');
  String get surfaceReadbackActionTitle => _value('surfaceReadbackActionTitle');
  String get surfaceReadbackActionDetail =>
      _value('surfaceReadbackActionDetail');
  String get surfaceFailureSinkTitle => _value('surfaceFailureSinkTitle');
  String get surfaceFailureSinkDetail => _value('surfaceFailureSinkDetail');
  String get surfaceUiSurfaceTitle => _value('surfaceUiSurfaceTitle');
  String get surfaceUiSurfaceDetail => _value('surfaceUiSurfaceDetail');
  String get rowsLabel => _value('rowsLabel');
  String get codesLabel => _value('codesLabel');
  String get latest => _value('latest');
  String get running => _value('running');
  String get pending => _value('pending');
  String get failed => _value('failed');
  String get completed => _value('completed');
  String get cancelled => _value('cancelled');
  String get progressLabel => _value('progressLabel');
  String get createdAt => _value('createdAt');
  String get completedAt => _value('completedAt');
  String get params => _value('params');
  String get result => _value('result');
  String get retry => _value('retry');
  String get accept => _value('accept');
  String get dismiss => _value('dismiss');
  String get noRequests => _value('noRequests');
  String get noData => _value('noData');
  String get requestsSuffix => _value('requestsSuffix');
  String get avgShort => _value('avgShort');
  String get failShort => _value('failShort');
  String get watchlist => _value('watchlist');
  String get createNew => _value('createNew');
  String get noWatchlists => _value('noWatchlists');
  String get deleteList => _value('deleteList');
  String get watching => _value('watching');
  String get entered => _value('entered');
  String get exited => _value('exited');
  String get emptyListPrompt => _value('emptyListPrompt');
  String get tapToExpand => _value('tapToExpand');
  String get condition => _value('condition');
  String get target => _value('target');
  String get buyAt => _value('buyAt');
  String get stopLoss => _value('stopLoss');
  String get aiAnalysis => _value('aiAnalysis');
  String get addToGroup => _value('addToGroup');
  String get add => _value('add');
  String get createWatchlist => _value('createWatchlist');
  String get stock => _value('stock');
  String get fund => _value('fund');
  String get custom => _value('custom');
  String get listName => _value('listName');
  String get create => _value('create');
  String get notificationCenter => _value('notificationCenter');
  String get markAllRead => _value('markAllRead');
  String get noNotifications => _value('noNotifications');
  String get inputMessageHint => _value('inputMessageHint');
  String get answerInputHint => _value('answerInputHint');
  String get emptyChatPrompt => _value('emptyChatPrompt');
  String allowTool(String tool) =>
      _value('allowTool').replaceAll('{tool}', tool);
  String get resend => _value('resend');
  String get copy => _value('copy');
  String get copyAll => _value('copyAll');
  String copiedMessages(int count) =>
      _value('copiedMessages').replaceAll('{count}', '$count');
  String get youLabel => _value('youLabel');
  String get agentLabel => _value('agentLabel');
  String get toolsLabel => _value('toolsLabel');
  String get moveToBackground => _value('moveToBackground');
  String get justNow => _value('justNow');
  String get minutesAgo => _value('minutesAgo');
  String get hoursAgo => _value('hoursAgo');
  String get start => _value('start');
  String get stop => _value('stop');
  String get pause => _value('pause');
  String get resume => _value('resume');
  String get clearQueue => _value('clearQueue');
  String get delete => _value('delete');
  String get view => _value('view');
  String get stopBackground => _value('stopBackground');
  String get runInBackground => _value('runInBackground');
  String get export => _value('export');
  String get exportHtml => _value('exportHtml');
  String get recap => _value('recap');
  String get urlLabel => _value('urlLabel');
  String get methodLabel => _value('methodLabel');
  String get statusLabel => _value('statusLabel');
  String get durationLabel => _value('durationLabel');
  String get responseLabel => _value('responseLabel');
  String get latestResult => _value('latestResult');
  String get noDataYet => _value('noDataYet');
  String get alertConditions => _value('alertConditions');
  String get lastUpdated => _value('lastUpdated');
  String get updateEveryMinutes => _value('updateEveryMinutes');
  String get minutesUnit => _value('minutesUnit');
  String get name => _value('name');
  String get price => _value('price');
  String get changePct => _value('changePct');
  String get importFinancialReport => _value('importFinancialReport');
  String get importDashboard => _value('importDashboard');
  String get fullscreen => _value('fullscreen');
  String get exitFullscreen => _value('exitFullscreen');
  String get close => _value('close');
  String get llmProviders => _value('llmProviders');
  String get showKeys => _value('showKeys');
  String get hideKeys => _value('hideKeys');
  String get noLlmConfigured => _value('noLlmConfigured');
  String get addLlm => _value('addLlm');
  String get dataSources => _value('dataSources');
  String get dataSourcesHelp => _value('dataSourcesHelp');
  String get tushareTokenHelp => _value('tushareTokenHelp');
  String get windApiKeyHelp => _value('windApiKeyHelp');
  String get braveSearchHelp => _value('braveSearchHelp');
  String get tavilySearchHelp => _value('tavilySearchHelp');
  String get fredApiKeyHelp => _value('fredApiKeyHelp');
  String get beaApiKeyHelp => _value('beaApiKeyHelp');
  String get xueqiuSimTradeHelp => _value('xueqiuSimTradeHelp');
  String get xueqiuCookieHelp => _value('xueqiuCookieHelp');
  String get portfolioCodesHelp => _value('portfolioCodesHelp');
  String get apiKeys => _value('apiKeys');
  String get customKeyValueHelp => _value('customKeyValueHelp');
  String get keyName => _value('keyName');
  String get valueLower => _value('valueLower');
  String get noModel => _value('noModel');
  String get duplicate => _value('duplicate');
  String get disable => _value('disable');
  String get enable => _value('enable');
  String get enabled => _value('enabled');
  String get disabled => _value('disabled');
  String get paused => _value('paused');
  String get runNow => _value('runNow');
  String get lastRun => _value('lastRun');
  String get goalAutomation => _value('goalAutomation');
  String get escalationNeeded => _value('escalationNeeded');
  String get automationSuggestions => _value('automationSuggestions');
  String get noAutomationSuggestions => _value('noAutomationSuggestions');
  String get automationSuggestionAccepted =>
      _value('automationSuggestionAccepted');
  String get automationSuggestionDismissed =>
      _value('automationSuggestionDismissed');
  String get nextRun => _value('nextRun');
  String get cooldown => _value('cooldown');
  String get trigger => _value('trigger');
  String get triggerEvidence => _value('triggerEvidence');
  String get recentDecision => _value('recentDecision');
  String get decisionHistory => _value('decisionHistory');
  String get noDecisionHistory => _value('noDecisionHistory');
  String get checkpoint => _value('checkpoint');
  String get lastResult => _value('lastResult');
  String get currentWorkGap => _value('currentWorkGap');
  String get nextAction => _value('nextAction');
  String get taskGoalView => _value('taskGoalView');
  String get objective => _value('objective');
  String get scope => _value('scope');
  String get dataRequirements => _value('dataRequirements');
  String get riskBoundary => _value('riskBoundary');
  String get budget => _value('budget');
  String get doneCriteria => _value('doneCriteria');
  String get verification => _value('verification');
  String get escalation => _value('escalation');
  String get evidence => _value('evidence');
  String get advanced => _value('advanced');
  String get thinking => _value('thinking');
  String get tags => _value('tags');
  String get vision => _value('vision');
  String get audio => _value('audio');
  String get llmTag => _value('llmTag');
  String get generationTag => _value('generationTag');
  String get defaultOption => _value('defaultOption');
  String get tdxServers => _value('tdxServers');
  String get testConnection => _value('testConnection');
  String get noTdxServers => _value('noTdxServers');
  String get addServersHelp => _value('addServersHelp');
  String get calendarNotLoaded => _value('calendarNotLoaded');
  String get tradingCalendar => _value('tradingCalendar');
  String get fetchSuccess => _value('fetchSuccess');
  String get fetchFailed => _value('fetchFailed');
  String get dataSource => _value('dataSource');
  String get shenzhenExchange => _value('shenzhenExchange');
  String get lastUpdatedShort => _value('lastUpdatedShort');
  String get tradingDays => _value('tradingDays');
  String get weekendFallbackRule => _value('weekendFallbackRule');
  String get tradingDay => _value('tradingDay');
  String get nonTradingDay => _value('nonTradingDay');
  String get manualOverride => _value('manualOverride');
  String get tapDayToggle => _value('tapDayToggle');
  String get waitingForInput => _value('waitingForInput');
  String get watchlistNotAvailable => _value('watchlistNotAvailable');
  String get strategyLibrary => _value('strategyLibrary');
  String get strategyLibraryNotAvailable =>
      _value('strategyLibraryNotAvailable');
  String get strategyLibraryEmpty => _value('strategyLibraryEmpty');
  String get strategyLibraryCreate => _value('strategyLibraryCreate');
  String get strategyCreatePrompt => _value('strategyCreatePrompt');
  String get strategyAssetClass => _value('strategyAssetClass');
  String get strategyType => _value('strategyType');
  String get strategyTypeAll => _value('strategyTypeAll');
  String get strategyTypeStock => _value('strategyTypeStock');
  String get strategyTypeFund => _value('strategyTypeFund');
  String get strategyTypePortfolio => _value('strategyTypePortfolio');
  String get strategyTypeEtf => _value('strategyTypeEtf');
  String get strategyTypeUnknown => _value('strategyTypeUnknown');
  String get strategyArtifactContract => _value('strategyArtifactContract');
  String get strategyArtifactContractHint =>
      _value('strategyArtifactContractHint');
  String get strategyArtifactCanonical => _value('strategyArtifactCanonical');
  String get strategyArtifactPerItem => _value('strategyArtifactPerItem');
  String get strategyArtifactUnavailable =>
      _value('strategyArtifactUnavailable');
  String get strategyLibraryPath => _value('strategyLibraryPath');
  String get strategyItemDir => _value('strategyItemDir');
  String get strategySymbols => _value('strategySymbols');
  String get strategyEvidenceAction => _value('strategyEvidenceAction');
  String get strategyEvidenceSummary => _value('strategyEvidenceSummary');
  String get strategyDataSummary => _value('strategyDataSummary');
  String get strategyRiskRewardSummary => _value('strategyRiskRewardSummary');
  String get strategyAssumptionSummary => _value('strategyAssumptionSummary');
  String get strategyRerun => _value('strategyRerun');
  String get strategyReadEvidence => _value('strategyReadEvidence');
  String get strategyAddWatch => _value('strategyAddWatch');
  String get strategyCreateMonitor => _value('strategyCreateMonitor');
  String get noEventAgent => _value('noEventAgent');
  String get eventAgentIdle => _value('eventAgentIdle');
  String get eventPanelHelp => _value('eventPanelHelp');
  String get eventAgentInputHint => _value('eventAgentInputHint');
  String get tasks => _value('tasks');
  String get probeComplete => _value('probeComplete');
  String get addedServers => _value('addedServers');
  String get newServersUnit => _value('newServersUnit');
  String get noNewServers => _value('noNewServers');
  String get reachable => _value('reachable');
  String get unreachable => _value('unreachable');
  String get untested => _value('untested');
  String get copied => _value('copied');
  String get allow => _value('allow');
  String get alwaysAllow => _value('alwaysAllow');
  String get deny => _value('deny');
  String get answered => _value('answered');
  String get analyzeMarketHint => _value('analyzeMarketHint');
  String get noChartDataAvailable => _value('noChartDataAvailable');
  String get script => _value('script');
  String get import => _value('import');
  String get codeExample => _value('codeExample');
  String get pointsSuffix => _value('pointsSuffix');
  String get itemsSuffix => _value('itemsSuffix');
  String get statusError => _value('statusError');
  String get statusRunning => _value('statusRunning');
  String get statusStopped => _value('statusStopped');
  String get generating => _value('generating');
  String get eventLabel => _value('eventLabel');
  String get newMessage => _value('newMessage');
  String get backgroundTaskLabel => _value('backgroundTaskLabel');
  String get compactedLabel => _value('compactedLabel');
  String get errorPrefix => _value('errorPrefix');
  String get unknown => _value('unknown');
  String get tokensUnit => _value('tokensUnit');
  String get dashboardsUnit => _value('dashboardsUnit');
  String get backgroundShort => _value('backgroundShort');
  String get llmConfigSavedRestart => _value('llmConfigSavedRestart');
  String get llmConnection => _value('llmConnection');
  String get saveLlmConfig => _value('saveLlmConfig');
  String get serviceProxy => _value('serviceProxy');
  String get openaiProvider => _value('openaiProvider');
  String get anthropicProvider => _value('anthropicProvider');
  String get effortLabel => _value('effortLabel');
  String get apiUrl => _value('apiUrl');
  String get endpoint => _value('endpoint');
  String get apiKey => _value('apiKey');
  String get model => _value('model');
  String get off => _value('off');
  String get tushareProToken => _value('tushareProToken');
  String get windAifinMarketApiKey => _value('windAifinMarketApiKey');
  String get braveSearchApiKey => _value('braveSearchApiKey');
  String get tavilySearchApiKey => _value('tavilySearchApiKey');
  String get fredApiKey => _value('fredApiKey');
  String get beaApiKey => _value('beaApiKey');
  String get xueqiuCookie => _value('xueqiuCookie');
  String get portfolioCodes => _value('portfolioCodes');
  String get mainView => _value('mainView');
  String get queuePending => _value('queuePending');
  String get pendingItems => _value('pendingItems');
  String get eventSourceTag => _value('eventSourceTag');
  String get featureFinance => _value('featureFinance');
  String get featurePaper => _value('featurePaper');
  String get featureMusic => _value('featureMusic');

  String featureName(String key, {String? fallback}) {
    final value = _value(key);
    return value == key ? (fallback ?? key) : value;
  }

  String tasksProgress(int completed, int total) =>
      isChinese ? '任务 ($completed/$total)' : 'Tasks ($completed/$total)';

  String strategyLibraryUpdatedAt(String value) =>
      isChinese ? '更新：$value' : 'Updated: $value';

  String tdxServerSummary({
    required int total,
    required int reachable,
    required int unreachable,
    required int untested,
  }) {
    if (isChinese) {
      final parts = <String>['$total 台'];
      if (reachable > 0) parts.add('$reachable ${this.reachable}');
      if (unreachable > 0) parts.add('$unreachable ${this.unreachable}');
      if (untested > 0) parts.add('$untested ${this.untested}');
      return '通达信行情服务器 (${parts.join(', ')})';
    }
    final parts = <String>['$total servers'];
    if (reachable > 0) parts.add('$reachable reachable');
    if (unreachable > 0) parts.add('$unreachable unreachable');
    if (untested > 0) parts.add('$untested untested');
    return 'TDX quote servers (${parts.join(', ')})';
  }

  String tradingCalendarStatus(DateTime lastFetched, int tradingDayCount) {
    final stamp =
        '${lastFetched.month}/${lastFetched.day} ${lastFetched.hour.toString().padLeft(2, '0')}:${lastFetched.minute.toString().padLeft(2, '0')}';
    if (isChinese) {
      return '$dataSource: $shenzhenExchange | $lastUpdatedShort: $stamp | $tradingDayCount $tradingDays';
    }
    return '$dataSource: $shenzhenExchange | $lastUpdatedShort: $stamp | $tradingDayCount $tradingDays';
  }

  String fetchTradingCalendarSuccess(int tradingDayCount) => isChinese
      ? '$fetchSuccess ($tradingDayCount $tradingDays)'
      : '$fetchSuccess ($tradingDayCount trading days)';

  String tdxProbeComplete(int reachable, int total) => isChinese
      ? '$probeComplete: $reachable/$total ${this.reachable}'
      : '$probeComplete: $reachable/$total reachable';

  String addedServersMessage(int added) => isChinese
      ? '$addedServers $added $newServersUnit'
      : '$addedServers $added ${added == 1 ? 'server' : 'servers'}';

  String dashboardItemsSummary(int total, int dashboards, int monitors) =>
      isChinese
      ? '$total 个项目 · $dashboards 个看板 · $monitors 个监控'
      : '$total items · $dashboards dashboards · $monitors monitors';

  String enteredCount(int count) => isChinese ? '$count入' : '$count in';

  String exitedCount(int count) => isChinese ? '$count出' : '$count out';

  String watchlistSectionTitle(String title, int count) =>
      isChinese ? '── $title ($count) ──' : '-- $title ($count) --';

  String codeExampleText(String example) =>
      isChinese ? '例: $example' : 'Example: $example';

  String tradingCalendarMonthLabel(int year, int month) {
    if (isChinese) return '$year年$month月';
    const monthNames = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${monthNames[month - 1]} $year';
  }

  List<String> get tradingCalendarWeekdayHeaders => isChinese
      ? const ['一', '二', '三', '四', '五', '六', '日']
      : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String watchlistMiniCount(int count) =>
      isChinese ? '$count只' : '$count stocks';

  String toolRequiresConfirmation(String toolName, String summary) => isChinese
      ? '🔐 **$toolName** 需要确认\n$summary'
      : '🔐 **$toolName** requires confirmation\n$summary';

  String importedFinancialReportPrompt(String fileName, String reportId) =>
      isChinese
      ? '已导入财报: $fileName，请解析并分析这份财报的关键内容。文件路径: memory/financeReport/$reportId/original.pdf'
      : 'Imported financial report: $fileName. Please parse and analyze the key content. File path: memory/financeReport/$reportId/original.pdf';

  String analyzeSymbolPrompt(String symbol) =>
      isChinese ? '分析 $symbol' : 'Analyze $symbol';

  String monitorNotificationPrompt(
    String name,
    String message, {
    String? dataJson,
  }) {
    if (isChinese) {
      return dataJson == null || dataJson.isEmpty
          ? '[Monitor 通知 from $name] $message'
          : '[Monitor 通知 from $name] $message\ndata: $dataJson';
    }
    return dataJson == null || dataJson.isEmpty
        ? '[Monitor notification from $name] $message'
        : '[Monitor notification from $name] $message\ndata: $dataJson';
  }

  String dashboardNotificationHeader(String source) => isChinese
      ? '[Dashboard 通知 from $source]'
      : '[Dashboard notification from $source]';

  String assetCodeLabel(String assetType) =>
      isChinese ? '$assetType代码' : '$assetType code';

  String enteredPositionSummary({
    required String buyAtLabel,
    String? actualEntryPrice,
    String? stopLossValue,
    required String stopLossLabel,
    String? targetValue,
    required String targetLabel,
  }) {
    final parts = <String>['$buyAtLabel${actualEntryPrice ?? "—"}'];
    if (stopLossValue != null) parts.add('$stopLossLabel:$stopLossValue');
    if (targetValue != null) parts.add('$targetLabel:$targetValue');
    return parts.join('  ');
  }

  String exitedPositionSummary({
    required String profitPct,
    String? actualEntryPrice,
    String? exitPrice,
  }) {
    if (isChinese) {
      return '$profitPct  买@${actualEntryPrice ?? "—"} 卖@${exitPrice ?? "—"}';
    }
    return '$profitPct  Buy @${actualEntryPrice ?? "—"}  Sell @${exitPrice ?? "—"}';
  }

  String scoreText(Object score) => '$score$pointsSuffix';

  String toolCallsText(int count) => isChinese ? '$count 次调用' : '$count calls';

  String toolProgressText(int completed, int total) =>
      isChinese ? '$completed/$total 次工具调用' : '$completed/$total tools';

  String tokenCountText(String countText) => '$countText $tokensUnit';

  String compactedSummary(int pre, int post) => isChinese
      ? '$compactedLabel：$pre → $post'
      : '$compactedLabel: $pre → $post';

  String backgroundTaskSummary(String taskId) => isChinese
      ? '$backgroundTaskLabel：$taskId'
      : '$backgroundTaskLabel: $taskId';

  String eventNewMessageSummary() =>
      isChinese ? '$eventLabel：$newMessage' : '$eventLabel: $newMessage';

  String eventDoneSummary(String durationText) => isChinese
      ? '$eventLabel完成 $durationText'
      : '$eventLabel done $durationText';

  String exportedTo(String path) =>
      isChinese ? '已导出到 $path' : 'Exported to $path';

  String get unhandledPromiseRejectionPrefix =>
      isChinese ? '未处理的 Promise 拒绝: ' : 'Unhandled Promise rejection: ';

  String get agentBridgeNotAvailable =>
      isChinese ? 'AgentBridge 不可用' : 'AgentBridge not available';

  String get bridgeTimeout => isChinese ? 'Bridge 超时' : 'Bridge timeout';

  String backgroundDashboardUnresponsive(String dashboardId) => isChinese
      ? '后台看板 $dashboardId 无响应，建议停止它。'
      : 'Background dashboard $dashboardId is unresponsive. Recommend stopping it.';

  String moreRowsText(int count) =>
      isChinese ? '... 还有 $count 行' : '... $count more rows';

  String get renderingHtml => isChinese ? '正在渲染 HTML...' : 'Rendering HTML...';

  String unknownKey(String key) => isChinese ? '未知键：$key' : 'Unknown key: $key';

  String eventAgentCannotUseAction(String action) => isChinese
      ? 'Event Agent 不能使用 $action，因为这会重新加载页面。'
      : 'Event agent cannot use $action because it reloads the page.';

  String actionNotSupportedInEventAgent(String action) => isChinese
      ? 'Event Agent 不支持操作“$action”'
      : 'Action "$action" not supported in event agent';

  String dashboardSwitchedTo(String title, String? path) => isChinese
      ? '已切换看板：$title (${path ?? ""})'
      : 'Dashboard switched to: $title (${path ?? ""})';

  String get dashboardClosed => isChinese ? '看板已关闭' : 'Dashboard closed';

  String get webViewNotActive =>
      isChinese ? 'WebView 未激活' : 'WebView not active';

  String unknownAction(String action) =>
      isChinese ? '未知操作：$action' : 'Unknown action: $action';

  String get showChartRequiresDataFile => isChinese
      ? 'showChart 需要 "dataFile" 参数（JSON 数据文件路径，而不是 HTML 文件）'
      : 'showChart requires "dataFile" param (path to JSON data file, not an HTML file)';

  String dataFileNotFound(String path) =>
      isChinese ? '数据文件不存在：$path' : 'data file not found: $path';

  String get showChartCreateJsonHint => isChinese
      ? '请先用 FileWrite 创建 JSON 文件，格式为 {columns:[...], data:[[...],...]}，再传入该路径。'
      : 'Use FileWrite to create a JSON file with {columns:[...], data:[[...],...]} format, then pass its path here.';

  String failedToParseDataFile(Object error) =>
      isChinese ? '解析数据文件失败：$error' : 'failed to parse data file: $error';

  String get showChartJsonHint => isChinese
      ? '文件必须是 JSON，格式为 {columns:[...], data:[[...],...]}（Tushare 风格）。'
      : 'File must be JSON with {columns:[...], data:[[...],...]} format (Tushare style).';

  String get webViewGetHtmlTextContentLabel =>
      isChinese ? '文本内容：' : 'Text content:';

  String webViewGetHtmlSummary({
    required String url,
    required String htmlPath,
    required String htmlSizeKb,
    required String textPath,
    required int textLength,
    required String preview,
  }) {
    if (isChinese) {
      return 'URL: $url\n'
          'HTML 已保存：$htmlPath ($htmlSizeKb KB)\n'
          '文本已保存：$textPath ($textLength 字符)\n'
          '$webViewGetHtmlTextContentLabel\n$preview';
    }
    return 'URL: $url\n'
        'HTML saved: $htmlPath ($htmlSizeKb KB)\n'
        'Text saved: $textPath ($textLength chars)\n'
        '$webViewGetHtmlTextContentLabel\n$preview';
  }

  String get showChartDataMissing => isChinese
      ? 'showChart 数据文件缺少 "data" 字段或该字段为空'
      : 'showChart data file has no "data" field or it is empty';

  String get showChartDataArrayHint => isChinese
      ? '文件必须包含 "data" 字段，并且它是 K 线记录数组。'
      : 'File must contain a "data" field with an array of K-line records.';

  String get showChartDataFormatUnrecognized =>
      isChinese ? 'showChart 数据格式无法识别' : 'showChart data format not recognized';

  String get showChartExpectedFormatsHint => isChinese
      ? '期望格式为 {columns:[...], data:[[...],...]}（Tushare）或 {data:[{date:...,open:...,close:...,high:...,low:...},...]}（对象数组）。'
      : 'Expected either {columns:[...], data:[[...],...]} (Tushare) or {data:[{date:...,open:...,close:...,high:...,low:...},...]} (object array)';

  String missingRequiredParam(String name) =>
      isChinese ? '缺少必填参数：$name' : 'missing required param: $name';

  String missingRequiredParams(String names) =>
      isChinese ? '缺少必填参数：$names' : 'missing required params: $names';

  String get expectedLabel => isChinese ? '期望' : 'expected';

  String get dashboardPageIdHelp => isChinese ? '看板页面 id' : 'dashboard page id';

  String get backgroundDashboardPageIdHelp =>
      isChinese ? '要查看的后台看板页面 id' : 'background dashboard page id to view';

  String get removePageIdHelp => isChinese
      ? '要移除的完整路径或相对路径 id'
      : 'full path or relative path of the page to remove';

  String get pushChannelNameHelp => isChinese ? '推送通道名' : 'push channel name';

  String get optionalPayloadObjectHelp =>
      isChinese ? '（可选）payload 对象' : '(optional) payload object';

  String get optionalPageTitleHelp =>
      isChinese ? '（可选）页面标题' : '(optional) Page Title';

  String get openPageFileOrIdHelp => isChinese
      ? 'memory/pages/xxx.html 或完整看板 id'
      : '"file": "memory/pages/xxx.html", "id": "(or) full dashboard id"';

  String get addPageExpectedHint => isChinese
      ? '{"file": "memory/pages/xxx.html", "title": "（可选）页面标题", "tag": "(optional)"}'
      : '{"file": "memory/pages/xxx.html", "title": "(optional) Page Title", "tag": "(optional)"}';

  String fileNotFoundShort(String path) =>
      isChinese ? '文件不存在：$path' : 'file not found: $path';

  String get createFileThenOpenPageHint => isChinese
      ? '请先用 FileWrite 创建文件，然后再调用 openPage。'
      : 'Use FileWrite to create the file first, then call openPage.';

  String get dashboardNotFound => isChinese ? '未找到看板' : 'dashboard not found';

  String get backgroundSlotsFull =>
      isChinese ? '后台槽位已满' : 'background slots full';

  String queuePendingSummary(int count) => isChinese
      ? '$queuePending: $count $pendingItems'
      : '$queuePending: $count $pendingItems';

  String clearedUsingDefault(String url) =>
      isChinese ? '已清空，改用默认值（$url）。' : 'Cleared. Using default ($url).';

  String savedNowUsing(String url) =>
      isChinese ? '已保存，当前使用：$url' : 'Saved. Now using: $url';

  String currentServer(String url) =>
      isChinese ? '$currentValuePrefix：$url' : '$currentValuePrefix: $url';

  String defaultServer(String url) =>
      isChinese ? '$defaultValuePrefix：$url' : '$defaultValuePrefix: $url';

  String llmRequestsRoutedThrough(String url) => isChinese
      ? 'LLM 请求通过服务端转发（$url）'
      : 'LLM requests routed through service server ($url)';
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'zh';

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
