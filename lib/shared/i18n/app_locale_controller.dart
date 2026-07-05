import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguageMode { system, english, chinese }

class AppLocaleController extends ChangeNotifier {
  static const prefsKey = 'app_language_mode';

  AppLanguageMode _mode = AppLanguageMode.system;

  AppLanguageMode get mode => _mode;

  Locale? get localeOverride {
    switch (_mode) {
      case AppLanguageMode.system:
        return null;
      case AppLanguageMode.english:
        return const Locale('en');
      case AppLanguageMode.chinese:
        return const Locale('zh', 'CN');
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(prefsKey);
    _mode = AppLanguageMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => AppLanguageMode.system,
    );
  }

  Future<void> setMode(AppLanguageMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, mode.name);
    notifyListeners();
  }
}

class AppLocaleScope extends InheritedNotifier<AppLocaleController> {
  const AppLocaleScope({
    super.key,
    required AppLocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLocaleController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppLocaleScope>();
    assert(scope != null, 'AppLocaleScope not found in widget tree');
    return scope!.notifier!;
  }
}
