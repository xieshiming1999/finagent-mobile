import 'package:flutter/material.dart';

import 'feature_manager.dart';
import 'i18n/app_localizations.dart';
import 'settings_page.dart';

/// Provides the feature switch callback to descendant widgets.
class FeatureSwitchScope extends InheritedWidget {
  final VoidCallback onSwitchFeature;
  final VoidCallback onOpenSettings;
  final IconData currentIcon;
  final String currentName;

  const FeatureSwitchScope({
    super.key,
    required this.onSwitchFeature,
    required this.onOpenSettings,
    required this.currentIcon,
    required this.currentName,
    required super.child,
  });

  static FeatureSwitchScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeatureSwitchScope>();

  @override
  bool updateShouldNotify(covariant FeatureSwitchScope old) => true;

  /// Build trailing widget for NavigationRail: feature switch + settings at bottom.
  static Widget buildTrailing(FeatureSwitchScope scope) {
    return Builder(
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: scope.onSwitchFeature,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(scope.currentIcon, size: 24),
                        const SizedBox(height: 2),
                        Text(
                          scope.currentName,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: scope.onOpenSettings,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.settings_outlined, size: 24),
                        const SizedBox(height: 2),
                        Text(l10n.settings, style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Top-level app shell that manages feature switching.
/// Each feature gets its own screen built via FeatureConfig.screenBuilder.
class AppShell extends StatefulWidget {
  final FeatureManager featureManager;

  const AppShell({super.key, required this.featureManager});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initCurrentFeature();
  }

  Future<void> _initCurrentFeature() async {
    await widget.featureManager.switchTo(widget.featureManager.currentFeatureId);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _switchFeature(String featureId) async {
    if (featureId == widget.featureManager.currentFeatureId) return;
    setState(() => _loading = true);
    await widget.featureManager.switchTo(featureId);
    if (mounted) setState(() => _loading = false);
  }

  void _showFeaturePicker() {
    final features = widget.featureManager.features;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(AppLocalizations.of(context).switchFeature,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final feature in features)
              ListTile(
                leading: Icon(feature.icon),
                title: Text(feature.name),
                trailing: feature.id == widget.featureManager.currentFeatureId
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _switchFeature(feature.id);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsPage(
        featureManager: widget.featureManager,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final config = widget.featureManager.currentConfig;
    final runtime = widget.featureManager.currentRuntime!;

    return FeatureSwitchScope(
      onSwitchFeature: _showFeaturePicker,
      onOpenSettings: _openSettings,
      currentIcon: config.icon,
      currentName: config.name,
      child: config.screenBuilder(runtime),
    );
  }
}
