import 'package:flutter/material.dart';

import '../../shared/app_shell.dart';
import '../../shared/i18n/app_localizations.dart';

class SideBar extends StatelessWidget {
  final bool collapsible;

  const SideBar({super.key, this.collapsible = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final scope = FeatureSwitchScope.of(context);

    return Container(
      width: 72,
      color: cs.surfaceContainerLow,
      child: Column(children: [
        const Spacer(),
        if (scope != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: GestureDetector(
              onTap: scope.onOpenSettings,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.settings_outlined, size: 22, color: cs.onSurface),
                  const SizedBox(height: 2),
                  Text(l10n.settings, style: TextStyle(fontSize: 10, color: cs.onSurface)),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}
