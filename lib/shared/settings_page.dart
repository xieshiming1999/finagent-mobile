import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../agent/data_fetcher/tdx_fetcher.dart';
import 'api_config.dart';
import 'feature_manager.dart';
import 'i18n/app_locale_controller.dart';
import 'i18n/app_localizations.dart';
import 'llm_config.dart';
import 'settings_page_llm_tab.dart';
import 'settings_page_calendar_tab.dart';
import 'settings_page_tdx_tab.dart';

/// Settings page — LLM multi-config + data sources.
class SettingsPage extends StatefulWidget {
  final FeatureManager featureManager;
  const SettingsPage({super.key, required this.featureManager});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  bool _showKeys = false;
  final _llmStore = LLMConfigStore();
  int _expandedIndex = -1;

  final _apiConfigStore = ApiConfigStore();
  final _newKeyCtrl = TextEditingController();
  final _newValueCtrl = TextEditingController();

  // TDX Servers
  List<TdxServerEntry> _tdxServers = [];
  bool _tdxProbing = false;
  final _tdxAddCtrl = TextEditingController();
  String? _tdxBasePath;

  // Trading Calendar
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _calendarFetching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = await getApplicationDocumentsDirectory();
    await _llmStore.load(configDir: '${dir.path}/agents');
    await _apiConfigStore.load();
    _tdxBasePath =
        widget.featureManager.basePath ?? '${dir.path}/agents/finance';
    _loadTdxServers();
    setState(() => _loading = false);
  }

  Future<void> _saveAll() async {
    await _llmStore.save();
    widget.featureManager.updateLLMStore(_llmStore);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).allSettingsSaved)),
      );
    }
  }

  @override
  void dispose() {
    _newKeyCtrl.dispose();
    _newValueCtrl.dispose();
    _tdxAddCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeController = AppLocaleScope.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.settings),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.llmKeysTab),
              Tab(text: l10n.tdxServersTab),
              Tab(text: l10n.tradingCalendarTab),
              Tab(text: l10n.generalTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            LlmKeysTab(
              llmStore: _llmStore,
              apiConfigStore: _apiConfigStore,
              showKeys: _showKeys,
              expandedIndex: _expandedIndex,
              newKeyCtrl: _newKeyCtrl,
              newValueCtrl: _newValueCtrl,
              onSaveAll: _saveAll,
              applyChange: (fn) => setState(fn),
              onShowKeysChanged: (value) => setState(() => _showKeys = value),
              onExpandedIndexChanged: (value) =>
                  setState(() => _expandedIndex = value),
            ),
            TdxSettingsTab(
              tdxProbing: _tdxProbing,
              tdxServers: _tdxServers,
              tdxAddCtrl: _tdxAddCtrl,
              onProbe: _probeTdxServers,
              onAdd: _addTdxServers,
            ),
            TradingCalendarTab(
              store: widget.featureManager.tradingCalendar,
              calendarMonth: _calendarMonth,
              calendarFetching: _calendarFetching,
              onRefresh: _fetchTradingCalendar,
              onMonthChanged: (value) => setState(() => _calendarMonth = value),
              onDayTap: (day) {
                final store = widget.featureManager.tradingCalendar;
                if (store == null) return;
                setState(() {
                  if (day.isOverride) {
                    store.removeOverride(day.date);
                  } else {
                    store.setOverride(day.date, !day.isTrading);
                  }
                });
              },
            ),
            _GeneralSettingsTab(controller: localeController),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchTradingCalendar() async {
    final store = widget.featureManager.tradingCalendar;
    if (store == null) return;
    setState(() => _calendarFetching = true);
    final ok = await store.fetchFromApi(year: _calendarMonth.year);
    if (mounted) {
      setState(() => _calendarFetching = false);
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? l10n.fetchTradingCalendarSuccess(store.tradingDayCount)
                : l10n.fetchFailed,
          ),
        ),
      );
    }
  }

  // ─── TDX Server Helpers ───

  void _loadTdxServers() {
    // Find basePath from FeatureManager — look for the finance feature's memory dir
    final basePath = widget.featureManager.basePath;
    if (basePath == null) return;
    _tdxBasePath = basePath;
    final file = File('$basePath/memory/.tdx_servers.json');
    if (!file.existsSync()) return;
    try {
      final list = jsonDecode(file.readAsStringSync()) as List;
      _tdxServers = list
          .map((e) => TdxServerEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  void _saveTdxServers() {
    if (_tdxBasePath == null) return;
    final file = File('$_tdxBasePath/memory/.tdx_servers.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(_tdxServers.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _probeTdxServers() async {
    if (_tdxProbing) return;
    setState(() => _tdxProbing = true);

    final fetcher = TdxFetcher();
    fetcher.basePath = _tdxBasePath;
    _tdxServers = await fetcher.probeAllServers(_tdxServers);

    if (mounted) {
      setState(() => _tdxProbing = false);
      final reachable = _tdxServers.where((s) => s.reachable == true).length;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tdxProbeComplete(reachable, _tdxServers.length))),
      );
    }
  }

  void _addTdxServers() {
    final text = _tdxAddCtrl.text.trim();
    if (text.isEmpty) return;

    final lines = text.split('\n');
    final existingKeys = _tdxServers.map((s) => s.key).toSet();
    var added = 0;

    for (final line in lines) {
      final entry = TdxServerEntry.fromUserInput(line);
      if (entry == null) continue;
      if (existingKeys.contains(entry.key)) continue;
      _tdxServers.add(entry);
      existingKeys.add(entry.key);
      added++;
    }

    if (added > 0) {
      _saveTdxServers();
      _tdxAddCtrl.clear();
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).addedServersMessage(added))));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).noNewServers)));
    }
  }
}

class _GeneralSettingsTab extends StatelessWidget {
  const _GeneralSettingsTab({required this.controller});

  final AppLocaleController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<AppLanguageMode>(
          initialValue: controller.mode,
          decoration: InputDecoration(
            labelText: l10n.language,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(
              value: AppLanguageMode.system,
              child: Text(l10n.languageSystem),
            ),
            DropdownMenuItem(
              value: AppLanguageMode.english,
              child: Text(l10n.languageEnglish),
            ),
            DropdownMenuItem(
              value: AppLanguageMode.chinese,
              child: Text(l10n.languageChinese),
            ),
          ],
          onChanged: (value) async {
            if (value == null) return;
            await controller.setMode(value);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.settingsApplied)),
            );
          },
        ),
      ],
    );
  }
}
