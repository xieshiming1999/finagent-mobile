part of 'dashboard_screen.dart';

void registerDashboardBridge(
  DashboardScreenState state,
  WebViewController controller, {
  String? dashboardId,
}) {
  controller.addJavaScriptChannel(
    'AgentBridge',
    onMessageReceived: (msg) async {
      if (state.widget.onBridgeMessage == null) return;

      var enrichedMessage = msg.message;
      if (dashboardId != null) {
        try {
          final parsed = jsonDecode(msg.message) as Map<String, dynamic>;
          final resolvedId =
              dashboardId == '_active' ? state._activeDashboard?.id : dashboardId;
          if (resolvedId != null) {
            parsed['_dashboardId'] = resolvedId;
            final item = state._dashboardItems
                .where((entry) => entry.id == resolvedId)
                .firstOrNull;
            if (item?.filePath != null) {
              parsed['_dashboardFile'] = item!.filePath;
            }
          }
          enrichedMessage = jsonEncode(parsed);
        } catch (_) {}
      }

      final response = await state.widget.onBridgeMessage!(enrichedMessage);
      try {
        final req = jsonDecode(msg.message) as Map<String, dynamic>;
        final id = req['id'] as String? ?? '';
        final escaped = response
            .replaceAll('\\', '\\\\')
            .replaceAll("'", "\\'")
            .replaceAll('\n', '\\n');
        controller.runJavaScript(
          "window.__bridgeCallback__&&window.__bridgeCallback__"
          "('$id', JSON.parse('$escaped'))",
        );
      } catch (e) {
        debugPrint('[DashboardScreen] Bridge callback error: $e');
      }
    },
  );
  controller.addJavaScriptChannel(
    'AgentError',
    onMessageReceived: (msg) => logDashboardJsError(state, msg.message),
  );
}

void injectDashboardErrorHandler(
  DashboardScreenState state,
  WebViewController controller,
) {
  final l10n = AppLocalizations.of(state.context);
  debugPrint(
    '[DashboardScreen] onPageFinished -> injecting error handler + Bridge API',
  );
  controller.runJavaScript('''
      if (!window.__errorHandlerInstalled__) {
        window.__errorHandlerInstalled__ = true;
        window.onerror = function(msg, src, line, col, err) {
          window.AgentError?.postMessage(JSON.stringify({
            message: msg, source: src, line: line, col: col,
            stack: err?.stack || ''
          }));
        };
        window.addEventListener('unhandledrejection', function(e) {
          window.AgentError?.postMessage(JSON.stringify({
            message: ${jsonEncode(l10n.unhandledPromiseRejectionPrefix)} + e.reason,
            source: '', line: 0, col: 0, stack: ''
          }));
        });
      }
    ''');
  injectDashboardBridgeApi(controller);
}

void injectDashboardBridgeApi(WebViewController controller) {
  final bridgeUnavailable = jsonEncode(AppLocalizations(ui.PlatformDispatcher.instance.locale).agentBridgeNotAvailable);
  final bridgeTimeout = jsonEncode(AppLocalizations(ui.PlatformDispatcher.instance.locale).bridgeTimeout);
  debugPrint('[DashboardScreen] Injecting Bridge API into WebView');
  controller.runJavaScript('''
      if (!window.Bridge) {
        window.__bridgeCallbacks__ = {};
        window.__bridgeId__ = 0;
        function __bSend(msg) {
          return new Promise(function(resolve, reject) {
            var id = 'b' + (++window.__bridgeId__);
            msg.id = id;
            window.__bridgeCallbacks__[id] = {resolve: resolve, reject: reject};
            if (window.AgentBridge) { AgentBridge.postMessage(JSON.stringify(msg)); }
            else { resolve({error: $bridgeUnavailable}); }
            setTimeout(function() {
              if (window.__bridgeCallbacks__[id]) {
                window.__bridgeCallbacks__[id].reject(new Error($bridgeTimeout));
                delete window.__bridgeCallbacks__[id];
              }
            }, 30000);
          });
        }
        window.Bridge = {
          fetch: function(p,params,m) { return __bSend({type:"http",method:m||"GET",path:p,params:params||{}}); },
          get: function(p,opts) { return __bSend({type:"http",method:"GET",path:p,params:(opts||{}).params||{}}); },
          post: function(p,body) { return __bSend({type:"http",method:"POST",path:p,params:body||{}}); },
          put: function(p,body) { return __bSend({type:"http",method:"PUT",path:p,params:body||{}}); },
          delete: function(p,opts) { return __bSend({type:"http",method:"DELETE",path:p,params:(opts||{}).params||{}}); },
          readFile: function(path) { return __bSend({type:"readFile",path:path}).then(function(r){return r.content}); },
          writeFile: function(path,content) { return __bSend({type:"writeFile",path:path,content:content}); },
          listDir: function(path) { return __bSend({type:"listDir",path:path||"."}).then(function(r){return r.entries||[]}); },
          fileExists: function(path) { return __bSend({type:"fileExists",path:path}).then(function(r){return r.exists||false}); },
          fileStat: function(path) { return __bSend({type:"fileStat",path:path}); },
          getState: function(key) { return __bSend({type:"getState",key:key}).then(function(r){return r.value}); },
          setState: function(key,value) { return __bSend({type:"setState",key:key,value:value}); },
          sendToAgent: function(msg,data) { return __bSend({type:"agent_message",message:msg,source:document.title||"dashboard",data:data||{}}); },
          sendToMonitor: function(monitorId,channel,data) { return __bSend({type:"sendToMonitor",monitorId:monitorId,channel:channel,data:data||{}}); },
          notify: function(msg) { return __bSend({type:"notify",message:msg}); },
          alert: function(msg) { return __bSend({type:"notify",message:"\\u26a0 "+msg}); },
          getConfig: function(key) { return __bSend({type:"getConfig",key:key}).then(function(r){return r.value}); },
          onPush: function(ch,fn) { if(!window.__pushHandlers__)window.__pushHandlers__={}; window.__pushHandlers__[ch]=fn; }
        };
        window.__bridgeCallback__ = function(id, result) {
          var cb = window.__bridgeCallbacks__[id];
          if (cb) {
            cb.resolve(result);
            delete window.__bridgeCallbacks__[id];
          }
        };
      }
    ''');
  controller.runJavaScript('''
      if (window.Bridge && !window.Bridge.parseCSV) {
        ${BridgeJs.dataFunctions}
        ${BridgeJs.statsFunctions}
      }
    ''');
}

String injectBridgeIntoDashboardHtml(String html) {
  final stripped = html.replaceAll(
    RegExp(
      r'<script>\s*var Bridge\s*=\s*\(function\(\)\{.*?\}\)\s*\(?\)?\s*;?\s*</script>',
      dotAll: true,
    ),
    '',
  );
  if (stripped.contains('</head>')) {
    return stripped.replaceFirst(
      '</head>',
      '${BridgeJs.webViewBridge}\n</head>',
    );
  }
  if (stripped.contains('<body>')) {
    return stripped.replaceFirst('<body>', '<body>\n${BridgeJs.webViewBridge}');
  }
  return '${BridgeJs.webViewBridge}\n$stripped';
}

void logDashboardJsError(DashboardScreenState state, String errorJson) {
  try {
    final logDir = '${state.widget.basePath}/memory/.bridge_logs';
    Directory(logDir).createSync(recursive: true);
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final logFile = File('$logDir/js_errors_$date.log');
    logFile.writeAsStringSync(
      '[${now.toIso8601String()}] $errorJson\n',
      mode: FileMode.append,
    );
    debugPrint('[DashboardScreen] JS Error: $errorJson');
  } catch (_) {}
}

void startDashboardHeartbeat(DashboardScreenState state) {
  state._heartbeatTimer?.cancel();
  state._heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
    final l10n = AppLocalizations.of(state.context);
    for (final entry in state._bgControllers.entries) {
      entry.value.runJavaScript('1+1').catchError((_) {
        state.widget.onBridgeMessage?.call(
          jsonEncode({
            'type': 'agent_message',
            'message': l10n.backgroundDashboardUnresponsive(entry.key),
            'source': 'heartbeat',
          }),
        );
      });
    }
  });
}

void persistBackgroundTasks(DashboardScreenState state) {
  try {
    final file = File(state._bgPersistPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(state._bgControllers.keys.toList()));
  } catch (_) {}
}

void restoreBackgroundTasks(DashboardScreenState state) {
  try {
    final file = File(state._bgPersistPath);
    if (!file.existsSync()) return;
    final ids = (jsonDecode(file.readAsStringSync()) as List).cast<String>();
    for (final id in ids) {
      final match = state._dashboardItems.where((item) => item.id == id);
      if (match.isNotEmpty) {
        state.startBackgroundTask(match.first);
      }
    }
  } catch (_) {}
}
