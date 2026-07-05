import 'package:flutter/material.dart';

import '../agent/agent.dart';
import '../agent/cron_scheduler.dart';
import '../agent/data_task_engine.dart';
import '../agent/monitor.dart';
import '../agent/watchlist.dart';
import '../agent/monitor_scheduler.dart';
import '../agent/ui_notification.dart';
import '../agent/tools/ask_user_question_tool/ask_user_question_tool.dart';
import '../agent/tools/environment_tool/environment_tool.dart';
import '../agent/tools/file_manage_tool/file_manage_tool.dart';
import '../agent/tools/ui_control_tool/ui_control_tool.dart';
import '../agent/tools/ui_query_tool/ui_query_tool.dart';
import '../agent/tools/webview_tool/webview_tool.dart';

/// Runtime state for a feature — Agent + UI tools + stores.
class FeatureRuntime {
  final Agent agent;
  final UIQueryTool uiQueryTool;
  final UIControlTool uiControlTool;
  final AskUserQuestionTool askUserQuestionTool;
  final FileManageTool fileManageTool;
  final WebViewTool webViewTool;
  final EnvironmentTool environmentTool;
  final CronScheduler cronScheduler;
  final DataTaskEngine dataTaskEngine;
  final MonitorStore monitorStore;
  final MonitorScheduler monitorScheduler;
  final WatchlistStore watchlistStore;
  final UINotificationStore notificationStore;

  const FeatureRuntime({
    required this.agent,
    required this.uiQueryTool,
    required this.uiControlTool,
    required this.askUserQuestionTool,
    required this.fileManageTool,
    required this.webViewTool,
    required this.environmentTool,
    required this.cronScheduler,
    required this.dataTaskEngine,
    required this.monitorStore,
    required this.monitorScheduler,
    required this.watchlistStore,
    required this.notificationStore,
  });
}

/// Declarative configuration for a feature.
class FeatureConfig {
  final String id;
  final String name;
  final IconData icon;
  final String featurePrompt;
  final int maxOutputTokens;
  final Set<String> excludeTools;
  final Widget Function(FeatureRuntime) screenBuilder;

  const FeatureConfig({
    required this.id,
    required this.name,
    required this.icon,
    required this.featurePrompt,
    this.maxOutputTokens = 8192,
    this.excludeTools = const {},
    required this.screenBuilder,
  });
}
