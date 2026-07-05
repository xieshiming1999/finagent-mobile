// Lightweight observable base class — pure Dart, zero Flutter dependency.
// Drop-in replacement for Flutter's ChangeNotifier in the agent/store layer.
//
// For Flutter UI: use ListenableBuilder(listenable: store.asListenable, ...)
// where asListenable is provided by observable_store_flutter.dart.

typedef StoreCallback = void Function();

class ObservableStore {
  final List<StoreCallback> _listeners = [];

  void addListener(StoreCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(StoreCallback listener) {
    _listeners.remove(listener);
  }

  void notifyListeners() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void dispose() {
    _listeners.clear();
  }
}
