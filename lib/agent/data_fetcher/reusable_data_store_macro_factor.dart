part of 'reusable_data_store.dart';

extension ReusableDataStoreMacroFactor on ReusableDataStore {
  void saveMarketMovingFactors(List<Map<String, dynamic>> rows) {
    final db = _db;
    if (db == null) return;
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO market_moving_factor (
        factor_id,family,title,summary,source_name,source_url,source_type,
        source_published_at,fetched_at,event_at,next_catalyst_at,
        affected_assets_json,affected_regions_json,affected_sectors_json,
        transmission_channels_json,expected_direction,severity,confidence,
        status,failure_class,evidence_items_json,macro_values_json,
        retrieval_test_json,raw_json
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''');
    try {
      for (final row in rows) {
        stmt.execute([
          row['factor_id']?.toString(),
          row['family']?.toString(),
          row['title']?.toString(),
          row['summary']?.toString(),
          row['source_name']?.toString(),
          row['source_url']?.toString(),
          row['source_type']?.toString() ?? 'provider',
          row['source_published_at']?.toString(),
          row['fetched_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
          row['event_at']?.toString(),
          row['next_catalyst_at']?.toString(),
          _jsonOrNull(row['affected_assets']),
          _jsonOrNull(row['affected_regions']),
          _jsonOrNull(row['affected_sectors']),
          _jsonOrNull(row['transmission_channels']),
          row['expected_direction']?.toString(),
          row['severity']?.toString(),
          row['confidence']?.toString(),
          row['status']?.toString() ?? 'watch',
          row['failure_class']?.toString(),
          _jsonOrNull(row['evidence_items']),
          _jsonOrNull(row['macro_values']),
          _jsonOrNull(row['retrieval_test']),
          _jsonOrNull(row['raw_json'] ?? row),
        ]);
      }
    } finally {
      stmt.close();
    }
  }

  List<Map<String, dynamic>> queryMarketMovingFactors({
    String? family,
    List<String>? families,
    String? status,
    String? source,
    String? target,
    List<String>? assets,
    List<String>? regions,
    List<String>? sectors,
    int limit = 80,
  }) {
    final db = _db;
    if (db == null) return const [];
    final where = <String>['1=1'];
    final args = <Object>[];
    if (family != null && family.isNotEmpty) {
      where.add('family = ?');
      args.add(family);
    }
    final familyFilters = families
        ?.map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (familyFilters != null && familyFilters.isNotEmpty) {
      where.add(
        'family IN (${List.filled(familyFilters.length, '?').join(',')})',
      );
      args.addAll(familyFilters);
    }
    if (status != null && status.isNotEmpty) {
      where.add('status = ?');
      args.add(status);
    }
    if (source != null && source.isNotEmpty) {
      where.add('source_name = ?');
      args.add(source);
    }
    args.add(limit);
    final rows = db.select('''
      SELECT * FROM market_moving_factor
      WHERE ${where.join(' AND ')}
      ORDER BY COALESCE(event_at, source_published_at, fetched_at) DESC,
               fetched_at DESC
      LIMIT ?
      ''', args);
    return rows
        .map((row) {
          final mapped = _rowMap(row);
          for (final key in [
            'affected_assets',
            'affected_regions',
            'affected_sectors',
            'transmission_channels',
            'evidence_items',
            'macro_values',
            'retrieval_test',
          ]) {
            mapped[key] = _decodeJson(mapped.remove('${key}_json'));
          }
          mapped['raw_json'] = _decodeJson(mapped['raw_json']);
          final macroValues = mapped['macro_values'];
          final raw = mapped['raw_json'];
          if (macroValues is Map) {
            mapped['evidence_tier'] ??= macroValues['evidenceTier'];
            mapped['limitations'] ??=
                macroValues['limitations'] ??
                _limitationList(macroValues['limitation']);
            mapped['linked_macro_evidence_ids'] ??=
                macroValues['linkedMacroEvidenceIds'];
          }
          if (raw is Map) {
            mapped['evidence_tier'] ??= raw['evidence_tier'];
            mapped['limitations'] ??= raw['limitations'];
            mapped['linked_macro_evidence_ids'] ??=
                raw['linked_macro_evidence_ids'];
          }
          return mapped;
        })
        .where((row) {
          return _matchesRelevance(
            row,
            target: target,
            assets: assets,
            regions: regions,
            sectors: sectors,
          );
        })
        .toList();
  }

  List<String>? _limitationList(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return [text];
  }

  bool _matchesRelevance(
    Map<String, dynamic> row, {
    String? target,
    List<String>? assets,
    List<String>? regions,
    List<String>? sectors,
  }) {
    final needles = <String>[
      if (target != null) target,
      ...?assets,
      ...?regions,
      ...?sectors,
    ].map((item) => item.trim().toLowerCase()).where((item) => item.isNotEmpty);
    if (needles.isEmpty) return true;
    final haystack = <String>[
      '${row['factor_id'] ?? ''}',
      '${row['family'] ?? ''}',
      '${row['title'] ?? ''}',
      '${row['summary'] ?? ''}',
      '${row['source_name'] ?? ''}',
      '${row['expected_direction'] ?? ''}',
      ..._stringList(row['affected_assets']),
      ..._stringList(row['affected_regions']),
      ..._stringList(row['affected_sectors']),
      ..._stringList(row['transmission_channels']),
    ].map((item) => item.toLowerCase()).toList();
    return needles.any(
      (needle) => haystack.any((value) => value.contains(needle)),
    );
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String? _jsonOrNull(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    return jsonEncode(value);
  }

  Object? _decodeJson(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }
}
