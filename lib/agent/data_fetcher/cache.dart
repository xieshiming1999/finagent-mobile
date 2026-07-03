/// TTL-based in-memory cache.
class DataCache<T> {
  final Duration ttl;
  final int maxEntries;
  final Map<String, _CacheEntry<T>> _cache = {};

  DataCache({this.ttl = const Duration(minutes: 20), this.maxEntries = 256});

  T? get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.time) > ttl) {
      _cache.remove(key);
      return null;
    }
    return entry.value;
  }

  void set(String key, T value) {
    if (_cache.length >= maxEntries) _evictOldest();
    _cache[key] = _CacheEntry(value: value, time: DateTime.now());
  }

  void clear() => _cache.clear();

  int get length => _cache.length;

  int get hitCount => _hits;
  int get missCount => _misses;
  int _hits = 0, _misses = 0;

  T? getTracked(String key) {
    final v = get(key);
    if (v != null) {
      _hits++;
    } else {
      _misses++;
    }
    return v;
  }

  void _evictOldest() {
    if (_cache.isEmpty) return;
    final oldest = _cache.entries.reduce(
      (a, b) => a.value.time.isBefore(b.value.time) ? a : b,
    );
    _cache.remove(oldest.key);
  }
}

class _CacheEntry<T> {
  final T value;
  final DateTime time;
  _CacheEntry({required this.value, required this.time});
}
