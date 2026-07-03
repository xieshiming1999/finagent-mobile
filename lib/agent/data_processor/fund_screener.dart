/// Fund screening: 4433 rule, custom criteria, manager screening.
class FundScreener {
  /// 4433 rule screening.
  /// Input: list of funds with return data, each fund is a Map with keys:
  ///   code, name, return_1y, return_3y, return_5y, return_ytd, return_6m, return_3m, nav, aum
  static List<Map<String, dynamic>> screen4433(
    List<Map<String, dynamic>> funds, {
    int limit = 30,
  }) {
    if (funds.isEmpty) return [];

    var result = List<Map<String, dynamic>>.from(funds);

    // 4: 1-year return top 1/4
    result = _filterTopQuantile(result, 'return_1y', 0.25);
    // 4: 2/3/5-year return top 1/4
    for (final key in ['return_3y', 'return_5y', 'return_ytd']) {
      result = _filterTopQuantile(result, key, 0.25);
    }
    // 3: 6-month return top 1/3
    result = _filterTopQuantile(result, 'return_6m', 0.333);
    // 3: 3-month return top 1/3
    result = _filterTopQuantile(result, 'return_3m', 0.333);

    result.sort((a, b) => _num(b, 'return_1y').compareTo(_num(a, 'return_1y')));
    return result.take(limit).toList();
  }

  /// Custom gate screening
  static List<Map<String, dynamic>> screenCustom(
    List<Map<String, dynamic>> funds,
    List<Map<String, dynamic>> gates, {
    String? sortBy,
    int limit = 30,
  }) {
    var result = List<Map<String, dynamic>>.from(funds);

    for (final gate in gates) {
      final field = gate['field'] as String? ?? '';
      final op = gate['op'] as String? ?? '>=';
      final value = (gate['value'] as num?)?.toDouble() ?? 0;

      result = result.where((f) {
        final v = _num(f, field);
        return switch (op) {
          '>' => v > value,
          '>=' => v >= value,
          '<' => v < value,
          '<=' => v <= value,
          _ => true,
        };
      }).toList();
    }

    if (sortBy != null) {
      result.sort((a, b) => _num(b, sortBy).compareTo(_num(a, sortBy)));
    }
    return result.take(limit).toList();
  }

  /// Manager screening
  static List<Map<String, dynamic>> screenManagers(
    List<Map<String, dynamic>> managers, {
    double minExperience = 5,
    double? minAum,
    double? minReturn,
    int limit = 30,
  }) {
    var result = managers.where((m) {
      if (_num(m, 'experience') < minExperience) return false;
      if (minAum != null && _num(m, 'total_aum') < minAum) return false;
      if (minReturn != null && _num(m, 'best_return') < minReturn) return false;
      return true;
    }).toList();

    result.sort(
      (a, b) => _num(b, 'best_return').compareTo(_num(a, 'best_return')),
    );
    return result.take(limit).toList();
  }

  static List<Map<String, dynamic>> _filterTopQuantile(
    List<Map<String, dynamic>> funds,
    String field,
    double quantile,
  ) {
    final withData = funds.where((f) {
      final v = f[field];
      return v != null && v is num && !v.isNaN;
    }).toList();

    if (withData.isEmpty) return funds;

    final sorted = List<Map<String, dynamic>>.from(withData)
      ..sort((a, b) => _num(b, field).compareTo(_num(a, field)));

    final cutoff = (sorted.length * quantile).ceil();
    final threshold = _num(sorted[cutoff.clamp(0, sorted.length - 1)], field);

    return funds.where((f) {
      final v = f[field];
      if (v == null || v is! num) return true;
      return v.toDouble() >= threshold;
    }).toList();
  }

  static double _num(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
