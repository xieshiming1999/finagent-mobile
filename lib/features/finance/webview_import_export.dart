part of 'finagent_screen.dart';

extension _WebViewImportExport on _FinAgentScreenState {
  Future<void> _importReport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf'],
    );
    if (result?.files.firstOrNull?.path == null) return;
    if (!mounted) return;
    final file = result!.files.first;
    final basePath = widget.agent.toolContext.basePath;
    final id = file.name
        .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^\w一-鿿\-]'), '_');
    final dir = Directory('$basePath/memory/financeReport/$id')
      ..createSync(recursive: true);
    final destPath = '${dir.path}/original.pdf';
    File(file.path!).copySync(destPath);
    _controller.text = AppLocalizations.of(context).importedFinancialReportPrompt(
      file.name,
      id,
    );
    _send();
  }

  Future<void> _importHtml() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['html', 'htm'],
    );
    if (result?.files.firstOrNull?.path == null) return;
    final file = result!.files.first;
    final basePath = widget.agent.toolContext.basePath;
    final dir = Directory('$basePath/memory/imports')..createSync(recursive: true);
    final destPath = '${dir.path}/${file.name}';
    File(file.path!).copySync(destPath);
    final title = file.name.replaceAll(RegExp(r'\.(html|htm)$'), '');
    _dash?.addDashboard(DashboardItem(
      id: destPath, title: title, filePath: destPath, modified: DateTime.now(),
    ));
    if (_dash?.webViewMode == WebViewMode.hidden) _dash?.showWebView();
    _dash?.controller?.loadHtmlString(
      File(destPath).readAsStringSync(),
      baseUrl: 'file://${File(destPath).parent.path}/',
    );
    _setState(() {});
  }

  Future<void> _exportDashboardItem(DashboardItem item) async {
    if (item.filePath == null || !File(item.filePath!).existsSync()) return;
    final l10n = AppLocalizations.of(context);
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: l10n.exportHtml,
      fileName: item.filePath!.split('/').last,
      type: FileType.custom, allowedExtensions: ['html'],
    );
    if (savePath != null) File(item.filePath!).copySync(savePath);
  }
}
