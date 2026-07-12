class ProviderModuleDescriptor {
  final String provider;
  final String title;
  final String category;
  final List<String> runtimeAvailability;
  final List<String> agentPaths;
  final List<String> requiredAccess;
  final List<String> capabilityFamilies;
  final String schemaDecision;
  final String cacheReadbackContract;
  final String healthEvidence;
  final String routingPolicy;
  final String uiSurface;
  final String discovery;
  final String status;

  const ProviderModuleDescriptor({
    required this.provider,
    required this.title,
    required this.category,
    required this.runtimeAvailability,
    required this.agentPaths,
    required this.requiredAccess,
    required this.capabilityFamilies,
    required this.schemaDecision,
    required this.cacheReadbackContract,
    required this.healthEvidence,
    required this.routingPolicy,
    required this.uiSurface,
    required this.discovery,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'title': title,
    'category': category,
    'runtimeAvailability': runtimeAvailability,
    'agentPaths': agentPaths,
    'requiredAccess': requiredAccess,
    'capabilityFamilies': capabilityFamilies,
    'schemaDecision': schemaDecision,
    'cacheReadbackContract': cacheReadbackContract,
    'healthEvidence': healthEvidence,
    'routingPolicy': routingPolicy,
    'uiSurface': uiSurface,
    'discovery': discovery,
    'status': status,
  };
}

const providerModuleDescriptorVersion = 'provider-module-descriptor-v2';

const providerModuleDescriptors = <ProviderModuleDescriptor>[
  ProviderModuleDescriptor(
    provider: 'local',
    title: 'Local canonical store and reusable cache',
    category: 'local-cache',
    runtimeAvailability: ['mobile'],
    agentPaths: ['chat', 'event'],
    requiredAccess: ['runtime-data-dir'],
    capabilityFamilies: ['readback', 'cache-coverage', 'stored-evidence'],
    schemaDecision:
        'Reusable rows must already belong to a known canonical schema.',
    cacheReadbackContract:
        'Local readback is preferred when freshness and coverage satisfy the interface policy.',
    healthEvidence:
        'Cache coverage, row counts, source time, and fetched-at are exposed through query/readback results.',
    routingPolicy:
        'Use before live providers when the interface supports cache reuse.',
    uiSurface: 'Capability summaries and agent-readable provenance output.',
    discovery:
        'Use interface/query actions and ProviderRouter before spending a live provider call.',
    status: 'supported',
  ),
  ProviderModuleDescriptor(
    provider: 'eastmoneyDirect',
    title: 'EastMoney direct mobile provider',
    category: 'public-direct-http',
    runtimeAvailability: ['mobile'],
    agentPaths: ['chat', 'event'],
    requiredAccess: ['network'],
    capabilityFamilies: [
      'quote',
      'kline',
      'sector',
      'money-flow',
      'limit-pool',
      'dragon-tiger',
      'fund',
    ],
    schemaDecision:
        'Stable direct responses normalize into quote, kline, sector, flow, fund, and event schemas.',
    cacheReadbackContract:
        'Successful reusable fetches must persist and read back through canonical query actions.',
    healthEvidence:
        'Runtime API stats, data API contract rows, and provider failure queues classify transport and schema issues.',
    routingPolicy:
        'Use as mobile public fallback after local/TDX where the interface policy allows it.',
    uiSurface: 'Provider matrix, API health, and workflow provenance.',
    discovery: 'Use ProviderRouter and ToolCatalog(providerModules).',
    status: 'supported',
  ),
  ProviderModuleDescriptor(
    provider: 'tdx',
    title: 'Native TDX mobile market-data provider',
    category: 'mobile-native-provider',
    runtimeAvailability: ['mobile'],
    agentPaths: ['chat', 'event'],
    requiredAccess: ['network', 'tdx-host'],
    capabilityFamilies: ['quote', 'kline', 'index', 'tick', 'transactions'],
    schemaDecision:
        'TDX stable protocol actions normalize into canonical market tables; unstable protocol surfaces stay diagnostic.',
    cacheReadbackContract:
        'Persist stable quote/kline/intraday schemas and reuse local rows before repeat calls.',
    healthEvidence:
        'Runtime transport failures and contract probe evidence affect provider routing.',
    routingPolicy:
        'Preferred for A-share quote/kline/index paths when runtime health is good.',
    uiSurface: 'Provider matrix and API health summaries.',
    discovery: 'Use ProviderRouter before broad market refreshes.',
    status: 'supported',
  ),
  ProviderModuleDescriptor(
    provider: 'yfinance',
    title: 'Yahoo Finance direct mobile provider',
    category: 'public-direct-http',
    runtimeAvailability: ['mobile'],
    agentPaths: ['chat', 'event'],
    requiredAccess: ['network', 'global-web-access'],
    capabilityFamilies: ['global-quote', 'global-kline', 'earnings', 'options'],
    schemaDecision:
        'Global Yahoo responses normalize into quote/kline and typed Yahoo research schemas when supported.',
    cacheReadbackContract:
        'Use local readback first; live Yahoo option/earnings refresh must honor availability evidence.',
    healthEvidence:
        'Yahoo availability, 401/403 evidence, and runtime stats gate live retries.',
    routingPolicy:
        'Use for non-A-share/global workflows only; do not route China A-share data here.',
    uiSurface: 'Agent provenance and capability status output.',
    discovery: 'Use ToolCatalog(providerModules) and interface availability.',
    status: 'supported',
  ),
  ProviderModuleDescriptor(
    provider: 'wind',
    title: 'Wind AIFinMarket credential provider',
    category: 'credential-api-key-provider',
    runtimeAvailability: ['mobile'],
    agentPaths: ['chat', 'event'],
    requiredAccess: ['WIND_API_KEY', 'quota'],
    capabilityFamilies: ['quote', 'fundamental', 'fund', 'macro', 'document'],
    schemaDecision:
        'Known Wind schemas persist to canonical market, fundamental, document, and macro tables; free-form payloads remain output-only.',
    cacheReadbackContract:
        'Read cache first; live calls require configured credentials and quota.',
    healthEvidence:
        'Wind quota/key errors, runtime API stats, and capability gates block broad retries.',
    routingPolicy:
        'Use when workflow needs Wind-only evidence or explicit credential-backed refresh.',
    uiSurface: 'Provider matrix and credential/quota status.',
    discovery: 'Check ProviderRouter and BudgetGovernor before Wind calls.',
    status: 'credential-gated',
  ),
  ProviderModuleDescriptor(
    provider: 'tushare',
    title: 'Tushare credential provider',
    category: 'credential-api-key-provider',
    runtimeAvailability: ['mobile'],
    agentPaths: ['chat', 'event'],
    requiredAccess: ['TUSHARE_TOKEN', 'permission-points'],
    capabilityFamilies: ['stock-basic', 'trade-calendar', 'daily-basic'],
    schemaDecision:
        'Only registered, permission-compatible Tushare schemas persist; disabled statement/fund routes must stay blocked.',
    cacheReadbackContract:
        'Use local query/readback before spending Tushare calls.',
    healthEvidence:
        'Contract disabled rows and permission failures must be visible to ProviderRouter.',
    routingPolicy:
        'Use only for supported credentialed interfaces or explicit diagnostics.',
    uiSurface: 'Provider matrix and disabled/credential-gated rows.',
    discovery: 'Use ProviderRouter and interface availability.',
    status: 'credential-gated',
  ),
  ProviderModuleDescriptor(
    provider: 'sina',
    title: 'Sina public finance provider',
    category: 'public-direct-http',
    runtimeAvailability: ['mobile'],
    agentPaths: ['chat', 'event'],
    requiredAccess: ['network'],
    capabilityFamilies: ['quote', 'market-list', 'fundamental-lite'],
    schemaDecision:
        'Verified Sina surfaces can be promoted to reusable interfaces when schema/readback value is clear.',
    cacheReadbackContract:
        'Persist only governed reusable surfaces; keep known output-only rows explicit.',
    healthEvidence: 'Probe evidence and runtime stats classify availability.',
    routingPolicy:
        'Use as public fallback where capability status is supported.',
    uiSurface: 'Provider matrix and provenance output.',
    discovery: 'Use provider matrix before direct Sina routes.',
    status: 'supported',
  ),
  ProviderModuleDescriptor(
    provider: 'tencent',
    title: 'Tencent public finance provider',
    category: 'public-direct-http',
    runtimeAvailability: ['mobile'],
    agentPaths: ['chat', 'event'],
    requiredAccess: ['network'],
    capabilityFamilies: ['quote', 'market-list', 'research-lite'],
    schemaDecision:
        'Only tested Tencent surfaces with stable schema may become reusable; unsupported exports stay disabled.',
    cacheReadbackContract: 'Reuse only through governed interface rows.',
    healthEvidence: 'Probe evidence and runtime stats classify availability.',
    routingPolicy:
        'Use selectively as a public fallback, not as an unbounded scraper.',
    uiSurface: 'Provider matrix and API health summaries.',
    discovery: 'Use provider matrix and ProviderRouter.',
    status: 'supported',
  ),
  ProviderModuleDescriptor(
    provider: 'akshare',
    title: 'AkShare compatibility provider',
    category: 'desktop-sidecar-backed-provider',
    runtimeAvailability: ['unsupported-on-mobile'],
    agentPaths: ['chat', 'event'],
    requiredAccess: ['not-mobile-native'],
    capabilityFamilies: ['compatibility-reference'],
    schemaDecision:
        'Mobile must not assume AkShare sidecar support; use mobile-native providers or explicit unsupported state.',
    cacheReadbackContract: 'No normal mobile readback path through AkShare.',
    healthEvidence: 'Runtime unavailable should be explicit when discovered.',
    routingPolicy: 'Do not select in mobile normal workflow.',
    uiSurface: 'Capability matrix unsupported state.',
    discovery: 'Use runtime availability metadata.',
    status: 'not-supported',
  ),
  ProviderModuleDescriptor(
    provider: 'macro-official',
    title: 'Official macro numeric APIs',
    category: 'macro-official-api-provider',
    runtimeAvailability: ['mobile'],
    agentPaths: ['chat', 'event'],
    requiredAccess: ['provider-specific-api-key-or-public-access'],
    capabilityFamilies: ['BEA', 'EIA', 'FRED/BLS', 'numeric-series'],
    schemaDecision:
        'Official numeric series should persist as structured macro evidence with source time, fetched-at, and series metadata.',
    cacheReadbackContract:
        'Use cached series when fresh enough; refresh only targeted series.',
    healthEvidence:
        'Missing keys, stale cache, source errors, and extraction failures must be classified.',
    routingPolicy:
        'Use as first-class macro evidence for analysis context and invalidation, not direct buy/sell rules.',
    uiSurface: 'Macro evidence summaries and workflow artifacts.',
    discovery:
        'Use macro evidence/source-reader help before broad macro collection.',
    status: 'credential-gated',
  ),
  ProviderModuleDescriptor(
    provider: 'macro-research',
    title: 'Public macro research and report sources',
    category: 'research-source-provider',
    runtimeAvailability: ['mobile'],
    agentPaths: ['chat', 'event'],
    requiredAccess: ['network', 'browser-or-webview-when-needed'],
    capabilityFamilies: [
      'institutional-research',
      'public-pdf',
      'source-reader',
      'search-discovery',
    ],
    schemaDecision:
        'Report title/date/body/key claims/hash should become provenance-bearing macro evidence; blocked pages stay explicit.',
    cacheReadbackContract:
        'Reuse extracted evidence by source hash and freshness.',
    healthEvidence:
        'Anti-bot, extraction, stale, and missing-source states are evidence.',
    routingPolicy:
        'Use after official numeric APIs or when the workflow asks for research context.',
    uiSurface: 'Macro research evidence and source comparison artifacts.',
    discovery: 'Use SourceReader and search/research help.',
    status: 'output-only',
  ),
  ProviderModuleDescriptor(
    provider: 'search',
    title: 'Search and research discovery providers',
    category: 'search-research-provider',
    runtimeAvailability: ['mobile'],
    agentPaths: ['chat', 'event'],
    requiredAccess: ['network', 'configured-search-provider'],
    capabilityFamilies: ['macro-discovery', 'news-discovery', 'source-finding'],
    schemaDecision:
        'Search results are discovery evidence until source content is fetched, hashed, and classified.',
    cacheReadbackContract:
        'Do not treat search snippets as reusable source content.',
    healthEvidence:
        'Search provider errors and missing results are classified.',
    routingPolicy: 'Use for discovery, then fetch authoritative sources.',
    uiSurface: 'Agent evidence and source-reader artifacts.',
    discovery: 'Use Research/WebFetch/SourceReader help.',
    status: 'supported',
  ),
  ProviderModuleDescriptor(
    provider: 'xueqiu',
    title: 'Xueqiu simulated trading provider',
    category: 'cookie-account-provider',
    runtimeAvailability: ['mobile'],
    agentPaths: ['chat'],
    requiredAccess: ['cookie/account', 'explicit-user-approval-for-write'],
    capabilityFamilies: [
      'portfolio',
      'transaction-readback',
      'simulated-order',
    ],
    schemaDecision:
        'Readback evidence is reusable for trading review; write operations require explicit approval and post-action readback.',
    cacheReadbackContract:
        'Portfolio and transaction results should preserve provider time and fetched-at.',
    healthEvidence:
        'Cookie/account failures and approval state are workflow evidence.',
    routingPolicy:
        'Never execute trade side effects without explicit approval state.',
    uiSurface: 'Trade-preparation and simulated-trading artifacts.',
    discovery: 'Use Runbook and FinanceWorkflowState before trading tools.',
    status: 'credential-gated',
  ),
  ProviderModuleDescriptor(
    provider: 'ui-artifact',
    title: 'Dashboard and UI artifact producer',
    category: 'ui-artifact-provider',
    runtimeAvailability: ['mobile'],
    agentPaths: ['chat', 'event'],
    requiredAccess: ['runtime-memory', 'ui-bridge'],
    capabilityFamilies: ['dashboard', 'report', 'webview', 'artifact-readback'],
    schemaDecision:
        'UI artifacts should have structured metadata, provenance links, verification status, and path readback.',
    cacheReadbackContract:
        'Artifacts must be inspectable after creation and after restart when promised.',
    healthEvidence:
        'UI tool results and WorkflowEvidence expose render/open failures.',
    routingPolicy: 'Use only when workflow needs visible artifact output.',
    uiSurface: 'Dashboard panel, WebView, artifact registry.',
    discovery: 'Use UIControl/WebView/ArtifactRegistry help.',
    status: 'supported',
  ),
];
