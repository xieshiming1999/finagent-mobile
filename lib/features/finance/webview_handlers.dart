part of 'finagent_screen.dart';

extension _WebViewHandlers on _FinAgentScreenState {
  Future<WebViewResult> _handleFinWebView(
    String action,
    Map<String, dynamic> params,
  ) async {
    return _handleWebView(action, params, _dash?.controller, _dash);
  }

  Future<WebViewResult> _handleSearchWebView(
    String action,
    Map<String, dynamic> params,
  ) async {
    return _handleWebView(
      action,
      params,
      _dash?.searchController,
      _dash,
      isSearch: true,
    );
  }

  Future<WebViewResult> _handleWebView(
    String action,
    Map<String, dynamic> params,
    dynamic ctrl,
    DashboardScreenState? state, {
    bool isSearch = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    if (ctrl == null && state != null) {
      state.init();
      ctrl = isSearch ? state.searchController : state.controller;
    }
    if (ctrl == null) {
      return WebViewResult(content: l10n.webViewNotActive, isError: true);
    }

    switch (action) {
      case 'query' || 'javascript':
        final js = params['javascript'] as String? ?? '';
        final selector = params['selector'] as String?;
        String script;
        if (selector != null && js.isNotEmpty) {
          script =
              "(function(){ var el = document.querySelector('$selector'); "
              "if(!el) return JSON.stringify({error:'Not found: $selector', "
              "url:location.href, totalElements:document.querySelectorAll('*').length}); "
              "var fn = $js; return JSON.stringify(fn(el)); })()";
        } else if (selector != null) {
          script =
              "(function(){ var el = document.querySelector('$selector'); "
              "if(!el) return JSON.stringify({error:'Not found: $selector', "
              "url:location.href, totalElements:document.querySelectorAll('*').length}); "
              "return el.textContent; })()";
        } else if (js.isNotEmpty) {
          script =
              '(function(){ var __r = (function(){ $js })(); '
              'return JSON.stringify(__r === undefined ? null : __r); })()';
        } else {
          return WebViewResult(
            content: 'query requires javascript or selector',
            isError: true,
          );
        }
        final result = await ctrl.runJavaScriptReturningResult(script);
        return WebViewResult(content: result.toString());

      case 'verify_report':
        final result = await ctrl.runJavaScriptReturningResult(
          _reportVerificationJavascript(),
        );
        final parsed = _parseReportVerificationResult(result.toString());
        final rendered = parsed['rendered'] == true;
        final loading = parsed['loading'] == true;
        final error = parsed['error'];
        if (!rendered || error != null) {
          return WebViewResult(
            content:
                'WEBVIEW_REPORT_RENDER_FAILED: report dashboard did not render. '
                'error=${_reportErrorMessage(error)} loading=$loading. '
                'Regenerate the dashboard from the report template with corrected structured config, '
                'then call WebView(action:"verify_report") again before finalizing. '
                'payload=${const JsonEncoder.withIndent('  ').convert(parsed)}',
            isError: true,
          );
        }
        return WebViewResult(
          content: const JsonEncoder.withIndent('  ').convert(parsed),
        );

      case 'click':
        final selector = params['selector'] as String;
        final r = await ctrl.runJavaScriptReturningResult(
          "(function(){ var el = document.querySelector('$selector'); "
          "if(!el) return JSON.stringify({found:false}); el.click(); "
          "var rect = el.getBoundingClientRect(); "
          "var count = document.querySelectorAll('$selector').length; "
          "return JSON.stringify({found:true, tag:el.tagName, "
          "text:(el.textContent||'').trim().substring(0,80), "
          "rect:{x:Math.round(rect.x),y:Math.round(rect.y),w:Math.round(rect.width),h:Math.round(rect.height)}, "
          "matchCount:count}); })()",
        );
        try {
          var raw = r.toString();
          if (raw.startsWith('"') && raw.endsWith('"'))
            raw = jsonDecode(raw) as String;
          final info = jsonDecode(raw) as Map<String, dynamic>;
          if (info['found'] != true) {
            return WebViewResult(
              content: 'Element not found: $selector',
              isError: true,
            );
          }
          final rect = info['rect'] as Map<String, dynamic>;
          return WebViewResult(
            content:
                'Clicked <${info['tag']}> at (${rect['x']},${rect['y']}) '
                '${rect['w']}x${rect['h']}px. '
                'Text: "${info['text']}". '
                '${info['matchCount'] > 1 ? "Warning: ${info['matchCount']} elements match this selector, clicked the first one." : ""}',
          );
        } catch (_) {
          if (r.toString().contains('"found":false') ||
              r.toString().contains('not_found')) {
            return WebViewResult(
              content: 'Element not found: $selector',
              isError: true,
            );
          }
          return WebViewResult(
            content: 'Clicked $selector (detail parse failed)',
          );
        }

      case 'input':
        final selector = params['selector'] as String;
        final text = params['text'] as String;
        final escaped = text.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
        final r = await ctrl.runJavaScriptReturningResult(
          "(function(){ var el = document.querySelector('$selector'); "
          "if(!el) return JSON.stringify({found:false}); el.focus(); el.value='$escaped'; "
          "el.dispatchEvent(new Event('input',{bubbles:true})); "
          "return JSON.stringify({found:true, tag:el.tagName, type:el.type||'', "
          "placeholder:el.placeholder||'', name:el.name||''}); })()",
        );
        try {
          var raw = r.toString();
          if (raw.startsWith('"') && raw.endsWith('"'))
            raw = jsonDecode(raw) as String;
          final info = jsonDecode(raw) as Map<String, dynamic>;
          if (info['found'] != true) {
            return WebViewResult(
              content: 'Element not found: $selector',
              isError: true,
            );
          }
          return WebViewResult(
            content:
                'Input "$text" into <${info['tag']}> '
                '(type=${info['type']}, name="${info['name']}", placeholder="${info['placeholder']}").',
          );
        } catch (_) {
          if (r.toString().contains('"found":false') ||
              r.toString().contains('not_found')) {
            return WebViewResult(
              content: 'Element not found: $selector',
              isError: true,
            );
          }
          return WebViewResult(content: 'Input "$text" into $selector');
        }

      case 'screenshot':
        if (isSearch && state?.searchVisible != true) {
          return WebViewResult(
            content: 'Search WebView is hidden',
            isError: true,
          );
        }
        final key = isSearch
            ? state?.searchRepaintBoundaryKey
            : state?.repaintBoundaryKey;
        final boundary =
            key?.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) {
          return WebViewResult(
            content:
                'Cannot capture screenshot: WebView widget not rendered. Is the WebView visible?',
            isError: true,
          );
        }
        final image = await boundary.toImage(pixelRatio: 2.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null)
          return WebViewResult(content: 'PNG encoding failed', isError: true);
        final bytes = byteData.buffer.asUint8List();
        final url = await ctrl.currentUrl() ?? '';
        final title = await ctrl.getTitle() ?? '';
        final scrollPos = await ctrl.runJavaScriptReturningResult(
          "JSON.stringify({scrollY:Math.round(window.scrollY),"
          "pageHeight:document.documentElement.scrollHeight,"
          "viewportHeight:window.innerHeight})",
        );
        final dir = '${widget.agent.toolContext.basePath}/memory/.screenshots';
        Directory(dir).createSync(recursive: true);
        final path = '$dir/${DateTime.now().microsecondsSinceEpoch}.png';
        var outputBytes = bytes;
        var fallbackNote = '';
        if (WebViewCaptureEvidence.isEffectivelyBlankPng(bytes)) {
          final textResult = await ctrl.runJavaScriptReturningResult(
            "(function(){var c=document.body.cloneNode(true);"
            "c.querySelectorAll('script,style,svg,noscript').forEach(function(e){e.remove()});"
            "return c.innerText.replace(/\\n{3,}/g,'\\n\\n').trim();})()",
          );
          var text = textResult.toString();
          if (text.startsWith('"') && text.endsWith('"')) {
            text = jsonDecode(text) as String;
          }
          outputBytes = await WebViewCaptureEvidence.renderDomTextFallbackPng(
            title: title.isEmpty ? 'WebView evidence' : title,
            url: url,
            scrollInfo: scrollPos.toString(),
            text: text,
          );
          fallbackNote =
              'Native WebView bitmap capture was blank, so this PNG was rendered from the current DOM text as fallback visual evidence. ';
        }
        File(path).writeAsBytesSync(outputBytes);
        return WebViewResult(
          content:
              'Screenshot captured successfully.\n'
              'Size: ${image.width}x${image.height}px (${(outputBytes.length / 1024).toStringAsFixed(1)} KB)\n'
              'URL: $url\n'
              'Title: $title\n'
              'Scroll: $scrollPos\n'
              'Saved: $path\n'
              'Note: ${fallbackNote}The image is attached to this response and sent to the model for visual analysis.',
          screenshot: outputBytes,
          screenshotPath: path,
        );

      case 'navigate':
        if (!isSearch && state?.viewingBgId != null) state?.viewMainWebView();
        final navUrl = params['url'] as String;
        if (navUrl.startsWith('file://') ||
            navUrl.startsWith('/') ||
            !navUrl.contains('://')) {
          final filePath = navUrl.startsWith('file://')
              ? navUrl.substring(7)
              : navUrl;
          final basePath = widget.agent.toolContext.basePath;
          final resolved = filePath.startsWith('/')
              ? filePath
              : '$basePath/$filePath';
          // Sandbox: must be within basePath
          if (!resolved.startsWith(basePath)) {
            return WebViewResult(
              content: 'Path outside sandbox: $resolved',
              isError: true,
            );
          }
          final file = File(resolved);
          if (!file.existsSync())
            return WebViewResult(
              content: 'File not found: $resolved',
              isError: true,
            );
          await ctrl.loadHtmlString(
            file.readAsStringSync(),
            baseUrl: 'file://${file.parent.path}/',
          );
          final wasHidden =
              !isSearch && state?.webViewMode == WebViewMode.hidden;
          if (wasHidden) {
            _setState(() => state?.showWebView());
          }
          state?.refreshDashboards();
          return WebViewResult(
            content:
                'Loaded local file: $resolved (${(file.lengthSync() / 1024).toStringAsFixed(1)} KB). '
                'WebView is now ${wasHidden ? "visible (split mode)" : "showing content"}.',
          );
        }
        await ctrl.loadRequest(Uri.parse(navUrl));
        final wasHidden = !isSearch && state?.webViewMode == WebViewMode.hidden;
        if (wasHidden) {
          _setState(() => state?.showWebView());
        }
        return WebViewResult(
          content:
              'Navigating to $navUrl. '
              'WebView is now ${wasHidden ? "visible (split mode)" : "showing content"}. '
              'Use wait_for or get_info to check when page is loaded.',
        );

      case 'back':
        await ctrl.goBack();
        return WebViewResult(content: 'Back');

      case 'forward':
        await ctrl.goForward();
        return WebViewResult(content: 'Forward');

      case 'reload':
        await ctrl.reload();
        return WebViewResult(content: 'Reloaded');

      case 'refresh':
        if (isSearch || state == null) {
          return WebViewResult(
            content:
                'Refresh is only available for the main file-backed dashboard WebView. Use reload for search/URL pages.',
            isError: true,
          );
        }
        state.refreshPage();
        return WebViewResult(
          content: 'Refreshed active dashboard from its source file.',
        );

      case 'get_info':
        final url = await ctrl.currentUrl() ?? '';
        final title = await ctrl.getTitle() ?? '';
        final scrollInfo = await ctrl.runJavaScriptReturningResult(
          "JSON.stringify({scrollX:window.scrollX,scrollY:window.scrollY,"
          "viewportWidth:window.innerWidth,viewportHeight:window.innerHeight,"
          "pageWidth:document.documentElement.scrollWidth,"
          "pageHeight:document.documentElement.scrollHeight})",
        );
        return WebViewResult(
          content: 'URL: $url\nTitle: $title\nScroll: $scrollInfo',
        );

      case 'scroll':
        final x = params['x'] as int? ?? 0;
        final y = params['y'] as int? ?? 0;
        final absolute = params['absolute'] as bool? ?? false;
        final scrollScript = absolute
            ? 'window.scrollTo($x, $y);'
            : 'window.scrollBy($x, $y);';
        await ctrl.runJavaScript(scrollScript);
        final posInfo = await ctrl.runJavaScriptReturningResult(
          "JSON.stringify({scrollY:Math.round(window.scrollY),"
          "pageHeight:document.documentElement.scrollHeight,"
          "viewportHeight:window.innerHeight,"
          "remaining:document.documentElement.scrollHeight-window.scrollY-window.innerHeight})",
        );
        return WebViewResult(
          content:
              'Scrolled ${absolute ? "to" : "by"} ($x, $y). Position: $posInfo',
        );

      case 'wait_for':
        final selector = params['selector'] as String;
        final timeout = params['timeout'] as int? ?? 5000;
        final deadline = DateTime.now().add(Duration(milliseconds: timeout));
        while (DateTime.now().isBefore(deadline)) {
          final found = await ctrl.runJavaScriptReturningResult(
            "document.querySelector('$selector') !== null",
          );
          if (found == true || found.toString() == 'true') {
            return WebViewResult(content: 'Found: $selector');
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
        return WebViewResult(
          content: 'Timeout: $selector not found',
          isError: true,
        );

      case 'get_html':
        final url = await ctrl.currentUrl() ?? '';
        final htmlStr = await ctrl.runJavaScriptReturningResult(
          'document.documentElement.outerHTML',
        );
        final textStr = await ctrl.runJavaScriptReturningResult(
          "(function(){var c=document.body.cloneNode(true);"
          "c.querySelectorAll('script,style,svg,noscript').forEach(function(e){e.remove()});"
          "return c.innerText.replace(/\\n{3,}/g,'\\n\\n').trim();})()",
        );
        var html = htmlStr.toString();
        var text = textStr.toString();
        if (html.startsWith('"') && html.endsWith('"'))
          html = jsonDecode(html) as String;
        if (text.startsWith('"') && text.endsWith('"'))
          text = jsonDecode(text) as String;
        final dir = Directory(
          '${widget.agent.toolContext.basePath}/memory/webview_captures',
        );
        dir.createSync(recursive: true);
        final ts = DateTime.now().millisecondsSinceEpoch;
        File('${dir.path}/$ts.html').writeAsStringSync(html);
        File('${dir.path}/$ts.txt').writeAsStringSync(text);
        final preview = text.length > 2000
            ? '${text.substring(0, 2000)}\n\n[...truncated, ${text.length} chars total]'
            : text;
        return WebViewResult(
          content: l10n.webViewGetHtmlSummary(
            url: url,
            htmlPath: '${dir.path}/$ts.html',
            htmlSizeKb: (html.length / 1024).toStringAsFixed(1),
            textPath: '${dir.path}/$ts.txt',
            textLength: text.length,
            preview: preview,
          ),
        );

      default:
        return WebViewResult(
          content: l10n.unknownAction(action),
          isError: true,
        );
    }
  }

  // Bridge handler
  Future<String> Function(String) _makeBridgeHandler() {
    return (message) => _handleBridgeMessage(message);
  }

  Future<String> _handleBridgeMessage(String message) async {
    final basePath = widget.agent.toolContext.basePath;
    final logDir = '$basePath/memory/.bridge_logs';
    try {
      final req = jsonDecode(message) as Map<String, dynamic>;
      final type = req['type'] as String? ?? 'http';

      if (type == 'agent_message') {
        final msg = req['message'] as String? ?? '';
        final source = req['source'] as String? ?? 'dashboard';
        final dashFile = req['_dashboardFile'] as String?;
        final l10n = AppLocalizations.of(context);
        final parts = <String>[
          l10n.dashboardNotificationHeader(source),
          if (dashFile != null) '(file: $dashFile)',
          msg,
          if (req['data'] != null) 'data: ${jsonEncode(req['data'])}',
        ];
        _eventRuntime.agent.notificationQueue.enqueue(
          PendingNotification(prompt: parts.join('\n'), source: 'dashboard'),
        );
        return jsonEncode({'ok': true});
      }

      if (type == 'sendToMonitor') {
        final monitorId = req['monitorId'] as String? ?? '';
        final channel = req['channel'] as String? ?? '';
        final data = req['data'] as Map<String, dynamic>? ?? {};
        widget.monitorScheduler.pushToMonitor(monitorId, channel, data);
        return jsonEncode({'ok': true, 'type': 'sendToMonitor'});
      }

      if (type == 'notify') {
        final title = req['title'] as String? ?? '';
        final msg = req['message'] as String? ?? '';
        _setState(
          () => _items.add(ChatItem(role: 'system', content: '$title: $msg')),
        );
        return jsonEncode({'ok': true});
      }

      if (type == 'getConfig') {
        final key = req['key'] as String? ?? '';
        final store = ApiConfigStore();
        await store.load();
        final value = store.get(key);
        return jsonEncode({'ok': true, 'key': key, 'value': value});
      }

      // File operations (sandboxed to basePath)
      if (type == 'readFile') {
        final fpath = req['path'] as String? ?? '';
        final resolved = _resolveFilePath(basePath, fpath);
        if (resolved == null) return jsonEncode({'error': 'Invalid path'});
        final file = File(resolved);
        if (!file.existsSync())
          return jsonEncode({'error': 'File not found: $fpath'});
        return jsonEncode({'ok': true, 'content': file.readAsStringSync()});
      }

      if (type == 'writeFile') {
        final fpath = req['path'] as String? ?? '';
        final content = req['content'] as String? ?? '';
        final resolved = _resolveFilePath(basePath, fpath);
        if (resolved == null) return jsonEncode({'error': 'Invalid path'});
        final file = File(resolved);
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(content);
        return jsonEncode({'ok': true, 'path': fpath});
      }

      if (type == 'listDir') {
        final fpath = req['path'] as String? ?? '';
        final resolved = _resolveFilePath(
          basePath,
          fpath.isEmpty ? '.' : fpath,
        );
        if (resolved == null) return jsonEncode({'error': 'Invalid path'});
        final dir = Directory(resolved);
        if (!dir.existsSync())
          return jsonEncode({'error': 'Directory not found: $fpath'});
        final entries = dir
            .listSync()
            .map(
              (e) => {
                'name': e.path.split('/').last,
                'type': e is Directory ? 'dir' : 'file',
                'size': e is File ? e.lengthSync() : null,
              },
            )
            .toList();
        return jsonEncode({'ok': true, 'entries': entries});
      }

      if (type == 'fileExists') {
        final fpath = req['path'] as String? ?? '';
        final resolved = _resolveFilePath(basePath, fpath);
        if (resolved == null) return jsonEncode({'ok': true, 'exists': false});
        final exists =
            File(resolved).existsSync() || Directory(resolved).existsSync();
        return jsonEncode({'ok': true, 'exists': exists});
      }

      if (type == 'fileStat') {
        final fpath = req['path'] as String? ?? '';
        final resolved = _resolveFilePath(basePath, fpath);
        if (resolved == null) return jsonEncode({'error': 'Invalid path'});
        final stat = FileStat.statSync(resolved);
        if (stat.type == FileSystemEntityType.notFound) {
          return jsonEncode({'error': 'Not found: $fpath'});
        }
        return jsonEncode({
          'ok': true,
          'size': stat.size,
          'modified': stat.modified.toIso8601String(),
          'type': stat.type == FileSystemEntityType.directory ? 'dir' : 'file',
        });
      }

      // State persistence (per dashboard)
      if (type == 'getState') {
        final key = req['key'] as String? ?? '';
        final dashId = req['_dashboardId'] as String? ?? 'default';
        final stateFile = File(
          '$basePath/memory/.dashboard_state_$dashId.json',
        );
        if (!stateFile.existsSync())
          return jsonEncode({'ok': true, 'value': null});
        try {
          final stateMap =
              jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>;
          return jsonEncode({'ok': true, 'value': stateMap[key]});
        } catch (_) {
          return jsonEncode({'ok': true, 'value': null});
        }
      }

      if (type == 'setState') {
        final key = req['key'] as String? ?? '';
        final value = req['value'];
        final dashId = req['_dashboardId'] as String? ?? 'default';
        final stateFile = File(
          '$basePath/memory/.dashboard_state_$dashId.json',
        );
        Map<String, dynamic> stateMap = {};
        if (stateFile.existsSync()) {
          try {
            stateMap =
                jsonDecode(stateFile.readAsStringSync())
                    as Map<String, dynamic>;
          } catch (_) {}
        }
        stateMap[key] = value;
        stateFile.parent.createSync(recursive: true);
        stateFile.writeAsStringSync(jsonEncode(stateMap));
        return jsonEncode({'ok': true});
      }

      if (type == 'log') {
        final msg = req['message'] as String? ?? '';
        log('BridgeJS', msg);
        return jsonEncode({'ok': true});
      }

      // HTTP proxy via bridgeHttp
      final method = (req['method'] as String? ?? 'GET').toUpperCase();
      final path = req['path'] as String? ?? '';
      final params = req['params'] as Map<String, dynamic>? ?? {};
      final body = req['body'] as dynamic;
      final headers = (req['headers'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v.toString()),
      );
      final svc = widget.agent.toolContext.serviceBaseUrl;

      final response = await bridgeHttp(
        url: path,
        method: method,
        params: method == 'GET' || method == 'DELETE' ? params : null,
        body: method == 'POST' || method == 'PUT' ? (body ?? params) : null,
        headers: headers,
        serviceBaseUrl: svc.isNotEmpty ? svc : null,
      );

      _logBridge(logDir, method, path, response.statusCode);
      return response.body;
    } catch (e) {
      _logBridge(logDir, '?', message, null, error: e.toString());
      return jsonEncode({'error': e.toString()});
    }
  }

  String? _resolveFilePath(String basePath, String path) {
    if (path.contains('..')) return null;
    final resolved = path.startsWith('/') ? path : '$basePath/$path';
    if (!resolved.startsWith(basePath)) return null;
    return resolved;
  }

  String _reportVerificationJavascript() {
    return r'''
JSON.stringify((function() {
  var text = (document.body && document.body.innerText ? document.body.innerText : '').replace(/\s+/g, ' ').trim();
  var status = window.__FINAGENT_REPORT_STATUS__ || null;
  var errorNode = document.querySelector('.text-block strong');
  var visibleError = errorNode && /Report render error/i.test(errorNode.textContent || '')
    ? (errorNode.parentElement ? errorNode.parentElement.textContent : errorNode.textContent)
    : '';
  var sections = Array.from(document.querySelectorAll('.section-title')).map(function(el) {
    return (el.textContent || '').trim();
  }).filter(Boolean);
  var loading = /Loading report\.\.\./i.test(text);
  var rendered = !!(status && status.rendered === true) && !loading && !visibleError;
  return {
    contract: 'webview-report-verification-v1',
    rendered: rendered,
    loading: loading || !!(status && status.loading === true),
    error: status && status.error ? status.error : (visibleError ? { message: visibleError } : null),
    title: status && status.title ? status.title : document.title,
    url: window.location.href,
    readyState: document.readyState,
    sectionCount: sections.length || (status && status.sectionCount) || 0,
    sections: sections.slice(0, 20),
    textLength: text.length,
    textSnippet: text.slice(0, 800),
    nextAction: rendered
      ? 'Report dashboard rendered. The agent may cite this UI artifact as verified evidence.'
      : 'Regenerate or rewrite the dashboard artifact, then verify_report again before finalizing.'
  };
})())
''';
  }

  Map<String, dynamic> _parseReportVerificationResult(String raw) {
    dynamic decoded = raw;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {}
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        decoded = {'textSnippet': decoded};
      }
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return {
      'contract': 'webview-report-verification-v1',
      'rendered': false,
      'loading': false,
      'error': {'message': 'Unexpected WebView verification result'},
      'textSnippet': raw,
      'nextAction':
          'Regenerate or rewrite the dashboard artifact, then verify_report again before finalizing.',
    };
  }

  String _reportErrorMessage(dynamic error) {
    if (error is Map && error['message'] != null) {
      return error['message'].toString();
    }
    return error?.toString() ?? 'none';
  }

  void _logBridge(
    String dir,
    String method,
    String path,
    int? status, {
    String? error,
  }) {
    try {
      Directory(dir).createSync(recursive: true);
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final line = error != null
          ? '[${now.toIso8601String()}] $method $path ERROR: $error\n'
          : '[${now.toIso8601String()}] $method $path → $status\n';
      File(
        '$dir/bridge_$date.log',
      ).writeAsStringSync(line, mode: FileMode.append);
    } catch (_) {}
  }
}
