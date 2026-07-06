import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'features/finance/finagent_screen.dart';
import 'shared/app_shell.dart';
import 'shared/feature_config.dart';
import 'shared/feature_manager.dart';
import 'shared/feature_prompts.dart';
import 'shared/i18n/app_locale_controller.dart';
import 'shared/i18n/app_localizations.dart';
import 'shared/llm_direct_config.dart';
import 'shared/llm_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final docsDir = await getApplicationDocumentsDirectory();
  final localeController = AppLocaleController();
  await localeController.load();
  final startupLocale =
      localeController.localeOverride ??
      WidgetsBinding.instance.platformDispatcher.locale;
  final llmStore = LLMConfigStore();
  await llmStore.load(configDir: '${docsDir.path}/agents');
  await llmStore.importFinElectronDefaultIfEmpty();
  await llmStore.importFinElectronHeadersIfMissing();

  final featureManager = FeatureManager(serverUrl: '');
  if (llmStore.providers.isNotEmpty) {
    featureManager.updateLLMStore(llmStore);
  } else {
    final llmConfig = await LLMDirectConfig.load();
    featureManager.updateLLMConfig(llmConfig);
  }

  featureManager.register(
    FeatureConfig(
      id: 'finance',
      name: 'FinAgent',
      icon: Icons.trending_up,
      featurePrompt: finagentPromptForLocale(startupLocale),
      excludeTools: {'ServiceCall'},
      screenBuilder: (runtime) => FinAgentScreen(
        agent: runtime.agent,
        uiQueryTool: runtime.uiQueryTool,
        uiControlTool: runtime.uiControlTool,
        askUserQuestionTool: runtime.askUserQuestionTool,
        webViewTool: runtime.webViewTool,
        environmentTool: runtime.environmentTool,
        dataTaskEngine: runtime.dataTaskEngine,
        monitorStore: runtime.monitorStore,
        watchlistStore: runtime.watchlistStore,
        monitorScheduler: runtime.monitorScheduler,
        notificationStore: runtime.notificationStore,
        workflowAutomationEnabledOverride:
            const bool.fromEnvironment('FINAGENT_WORKFLOW_AUTOMATION') ||
            const String.fromEnvironment(
                  'FINAGENT_WORKFLOW_AUTOMATION',
                ).toLowerCase() ==
                'true',
      ),
    ),
  );

  runApp(
    FinAgentApp(
      featureManager: featureManager,
      localeController: localeController,
    ),
  );
}

class FinAgentApp extends StatelessWidget {
  final FeatureManager featureManager;
  final AppLocaleController localeController;
  const FinAgentApp({
    super.key,
    required this.featureManager,
    required this.localeController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: localeController,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'FinAgent',
        locale: localeController.localeOverride,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueGrey,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        builder: (context, child) => AppLocaleScope(
          controller: localeController,
          child: child ?? const SizedBox.shrink(),
        ),
        home: AppShell(featureManager: featureManager),
      ),
    );
  }
}
