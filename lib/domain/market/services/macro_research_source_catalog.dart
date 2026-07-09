import '../../../agent/data_fetcher/reusable_data_store.dart';

import 'macro_research_source_catalog_data.dart';

Map<String, dynamic> macroResearchSources(Map<String, dynamic> input) {
  final provider = _clean(input['provider'] ?? input['source']);
  final categoryFilters = _sourceCategoryFilters(input);
  final accessClass = _clean(input['accessClass'] ?? input['access']);
  final priority = _positiveInt(input['priority']);
  final limit = _boundedLimit(input['limit'], 80);
  final rows = macroResearchSourceCatalog
      .where((row) {
        if (provider != null &&
            !_matches(row['provider'], provider) &&
            !_matches(row['providerName'], provider)) {
          return false;
        }
        if (categoryFilters != null &&
            !_sourceMatchesCategory(row, categoryFilters)) {
          return false;
        }
        if (accessClass != null && !_matches(row['accessClass'], accessClass)) {
          return false;
        }
        if (priority != null && (row['priority'] as int) > priority)
          return false;
        return true;
      })
      .take(limit)
      .map((row) => Map<String, dynamic>.from(row))
      .toList();

  return {
    'action': 'macro_research_sources',
    'count': rows.length,
    'status': rows.isEmpty ? 'missing' : 'ok',
    if (rows.isEmpty)
      'missingReason':
          'No macro research source catalog rows matched the requested provider/category/access filters. Treat this as a source-catalog gap, not as evidence that the source is irrelevant.',
    'provenance': {
      'interfaceId': 'macro.research_source_catalog',
      'providerId': 'local',
      'provider': 'local',
      'capabilityId': 'local.macro_research_sources',
      'providerMode': 'catalog-readback',
      'cacheStatus': 'bundled-catalog',
      'cacheDecision':
          'inspect source-specific access and category behavior before research retrieval',
      'canonicalSchema': 'macro_research_source_catalog_v1',
      'canonicalTable': null,
      'readbackAction': 'macro_research_sources',
      'source': 'bundled macro research source catalog',
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
    },
    'guidance': {
      'retrievalRule':
          'Use retrievalMethods and automationPolicy before fetching. Do not repeat blocked routes or treat anti-bot/login/security pages as retrieved evidence.',
      'evidenceRule':
          'Report provider, category, source time when available, retrieved time, retrieval method, access condition, and limitation.',
    },
    'rows': rows,
  };
}

const _macroResearchFamilies = [
  'macro_research_document',
  'macro_index_event',
  'macro_policy_event',
  'macro_official_series',
  'macro_commodity_event',
  'macro_source_retrieval_evidence',
];

Map<String, dynamic> macroResearchProvenance(
  ReusableDataStore? store,
  Map<String, dynamic> input,
) {
  final rows = _buildMacroResearchEvidenceRows(input);
  final shouldPersist = input['persist'] != false;
  if (shouldPersist && store != null && rows.isNotEmpty) {
    store.saveMarketMovingFactors(rows);
  }
  final readback = _queryMacroResearchEvidenceRows(store, input);
  return {
    'action': 'macro_research_provenance',
    'status': 'ok',
    'generatedRows': rows.length,
    'persisted': shouldPersist && store != null,
    'count': readback.length,
    'providerMatrix': _buildMacroProviderMatrix(),
    'provenance': _macroResearchProvenanceMeta('macro_research_provenance'),
    'guidance': {
      'reuseRule':
          'Use query_macro_research_evidence before repeating source retrieval. Blocked/manual/licensed sources are retrieval evidence, not reusable research content.',
      'promotionRule':
          'Only rows with stable source metadata and an allowed retrieval path are reusable macro research evidence.',
    },
    'rows': readback,
  };
}

Map<String, dynamic> queryMacroResearchEvidence(
  ReusableDataStore? store,
  Map<String, dynamic> input,
) {
  final rows = _queryMacroResearchEvidenceRows(store, input);
  return {
    'action': 'query_macro_research_evidence',
    'status': rows.isEmpty ? 'missing' : 'ok',
    'count': rows.length,
    if (rows.isEmpty)
      'missingReason':
          'No macro research evidence rows matched the requested filters. Run macro_research_provenance first or narrow provider/category filters.',
    'providerMatrix': _buildMacroProviderMatrix(),
    'provenance': _macroResearchProvenanceMeta('query_macro_research_evidence'),
    'rows': rows,
  };
}

Map<String, dynamic> queryMacroAttribution(
  ReusableDataStore? store,
  Map<String, dynamic> input,
) {
  final rows = _macroAttributionRows(store, input);
  final attributions = _dedupeRows(rows)
      .take(_boundedLimit(input['limit'], 20))
      .map(_macroAttributionRow)
      .toList(growable: false);
  final effectiveAttributions = attributions.isEmpty
      ? [_missingMacroAttribution(input)]
      : attributions;
  return {
    'action': 'query_macro_attribution',
    'status': rows.isEmpty ? 'missing' : 'ok',
    'count': effectiveAttributions.length,
    'evidenceRows': rows.length,
    if (rows.isEmpty)
      'missingReason':
          'No governed macro evidence matched the structured filters. Treat this as an attribution gap and inspect macro_research_sources or macro_numeric_series_catalog before external retrieval.',
    'updateDecision': _macroAttributionUpdateDecision(rows),
    'provenance': {
      'interfaceId': 'macro.root_cause_attribution',
      'providerId': 'local',
      'provider': 'local',
      'capabilityId': 'local.query_macro_attribution',
      'providerMode': 'local-evidence-attribution',
      'cacheStatus': 'local-readback',
      'cacheDecision':
          'build root-cause candidates from governed macro evidence before using macro context in analysis or strategy',
      'canonicalSchema': 'macro_attribution_v1',
      'canonicalTable': null,
      'evidenceSchema': 'market_moving_factor_v1',
      'evidenceTable': 'market_moving_factor',
      'readbackAction': 'query_macro_attribution',
      'source': 'local market_moving_factor + macro research evidence',
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
    },
    'guidance': {
      'analysisRule':
          'Use these rows as root-cause candidates with confidence and invalidation conditions; do not turn them into direct buy/sell signals.',
      'strategyRule':
          'A strategy may use macro attribution as regime context, risk flag, sizing guard, or invalidation condition only after technical/fundamental/backtest evidence is separately validated.',
      'updateRule':
          'If updateDecision.requiresUpdate is true, run the listed next actions before making a source-specific claim.',
    },
    'attributions': effectiveAttributions,
  };
}

List<Map<String, dynamic>> _queryMacroResearchEvidenceRows(
  ReusableDataStore? store,
  Map<String, dynamic> input,
) {
  if (store == null) return const [];
  final families = _evidenceFamilies(input);
  final sourceFilter = _sourceNameFilter(input);
  return store.queryMarketMovingFactors(
    families: families,
    status: _clean(input['status']),
    source: sourceFilter,
    target: _clean(input['target'] ?? input['query']),
    assets: _stringList(input['assets']),
    regions: _stringList(input['regions'] ?? input['market']),
    sectors: _stringList(input['sectors'] ?? input['industry']),
    limit: _boundedLimit(input['limit'], 80),
  );
}

List<Map<String, dynamic>> _macroAttributionRows(
  ReusableDataStore? store,
  Map<String, dynamic> input,
) {
  if (store == null) return const [];
  return store.queryMarketMovingFactors(
    families: _macroAttributionFamilies(input),
    status: _clean(input['status']),
    source: _sourceNameFilter(input),
    target: _clean(
      input['target'] ?? input['symbol'] ?? input['code'] ?? input['query'],
    ),
    assets: _stringList(input['assets']),
    regions: _stringList(input['regions'] ?? input['market']),
    sectors: _stringList(input['sectors'] ?? input['industry']),
    limit: _boundedLimit(input['scanLimit'] ?? input['evidenceLimit'], 80),
  );
}

List<String>? _macroAttributionFamilies(Map<String, dynamic> input) {
  final raw = _stringList(input['families']) ?? _stringList(input['family']);
  if (raw == null) return null;
  final expanded = <String>{};
  for (final item in raw) {
    expanded.add(item);
    expanded.addAll(_evidenceFamilyAliases[_normalizeKey(item)] ?? const []);
  }
  return expanded.toList(growable: false);
}

List<Map<String, dynamic>> _dedupeRows(List<Map<String, dynamic>> rows) {
  final seen = <String>{};
  final result = <Map<String, dynamic>>[];
  for (final row in rows) {
    final key = [
      row['factor_id'],
      row['family'],
      row['source_name'],
      row['source_url'],
      row['title'],
    ].map((item) => '${item ?? ''}').join('|');
    if (seen.add(key)) result.add(row);
  }
  return result;
}

Map<String, dynamic> _macroAttributionRow(Map<String, dynamic> row) {
  final retrieval = row['retrieval_test'] is Map
      ? Map<String, dynamic>.from(row['retrieval_test'] as Map)
      : <String, dynamic>{};
  final values = row['macro_values'] is Map
      ? Map<String, dynamic>.from(row['macro_values'] as Map)
      : <String, dynamic>{};
  final status = '${row['status'] ?? ''}';
  final family = '${row['family'] ?? ''}';
  final blocked =
      status == 'blocked' ||
      status == 'unsupported' ||
      status == 'licensed-needed' ||
      row['failure_class'] != null;
  return {
    'attributionId':
        row['factor_id'] ?? '$family:${row['source_name'] ?? 'macro'}',
    'category': blocked ? 'data-quality' : _macroAttributionCategory(family),
    'claim':
        row['summary'] ?? row['title'] ?? 'Macro evidence row requires review.',
    'evidence': [
      {
        'title': row['title'],
        'sourceName': row['source_name'],
        'sourceUrl': row['source_url'],
        'sourceType': row['source_type'],
        'evidenceTier': _macroEvidenceTier(row),
        'limitations': _macroEvidenceLimitations(row),
        'linkedMacroEvidenceIds':
            _stringList(row['linked_macro_evidence_ids']) ?? const <String>[],
        'sourceDataTime':
            row['source_published_at'] ??
            row['event_at'] ??
            values['sourcePeriod'],
        'fetchedAt': row['fetched_at'] ?? values['retrievedAt'],
        'status': row['status'],
        'family': row['family'],
        'affectedAssets': row['affected_assets'] ?? const [],
        'affectedRegions': row['affected_regions'] ?? const [],
        'transmissionChannels': row['transmission_channels'] ?? const [],
        'retrievalStatus': retrieval['status'],
        'failureClass': row['failure_class'],
      },
    ],
    'confidence': blocked ? 'low' : _macroAttributionConfidence(row),
    'timeWindow':
        row['source_published_at'] ?? row['event_at'] ?? values['period'],
    'contradictions': const [],
    'missingEvidence': blocked
        ? [
            'Provider/source is ${status.isEmpty ? row['failure_class'] : status}; use retrieval evidence as a limitation, not as content.',
          ]
        : _macroAttributionMissingEvidence(row),
    'invalidationCondition': _macroAttributionInvalidation(row),
    'nextUpdateAction': _macroAttributionNextAction(row),
    'provenance': {
      'interfaceId': 'macro.root_cause_attribution',
      'evidenceInterfaceId': retrieval['interface_id'] ?? values['interfaceId'],
      'provider': retrieval['provider'] ?? row['source_name'],
      'capabilityId': retrieval['capability_id'],
      'evidenceSchema': 'market_moving_factor_v1',
      'evidenceTable': 'market_moving_factor',
      'sourceStatus': status.isEmpty ? null : status,
    },
  };
}

String _macroEvidenceTier(Map<String, dynamic> row) {
  final explicit = row['evidence_tier']?.toString().trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  final sourceType = row['source_type']?.toString().toLowerCase() ?? '';
  if (RegExp(r'official_api|official_series|official_document')
      .hasMatch(sourceType)) {
    return 'official_numeric_or_document';
  }
  if (RegExp(r'research|content').hasMatch(sourceType)) {
    return 'content_backed_research';
  }
  if (sourceType.contains('news')) return 'linked_news_evidence';
  if (RegExp(r'manual|licensed|fallback').hasMatch(sourceType)) {
    return 'retrieval_or_manual_evidence';
  }
  if (row['failure_class'] != null) return 'missing_or_blocked';
  return 'governed_macro_evidence';
}

List<String> _macroEvidenceLimitations(Map<String, dynamic> row) {
  final explicit = _stringList(row['limitations']) ?? const <String>[];
  if (explicit.isNotEmpty) return explicit;
  if (_macroEvidenceTier(row) == 'linked_news_evidence') {
    return const [
      'Finance news is a current-event clue, not an official macro fact.',
      'Link to official data or content-backed research before making a root-cause conclusion.',
    ];
  }
  final failure = row['failure_class']?.toString();
  if (failure != null && failure.isNotEmpty) {
    return ['Evidence is limited by $failure.'];
  }
  return const [];
}

Map<String, dynamic> _missingMacroAttribution(Map<String, dynamic> input) {
  return {
    'attributionId': 'macro:missing',
    'category': 'data-quality',
    'claim':
        'No governed macro evidence matched the requested structured target.',
    'evidence': const [],
    'confidence': 'unknown',
    'timeWindow': null,
    'contradictions': const [],
    'missingEvidence': const [
      'No market_moving_factor_v1 rows matched the provided target/assets/regions/sectors/family filters.',
    ],
    'invalidationCondition':
        'Refresh or extract governed macro evidence, then re-run query_macro_attribution with the same structured filters.',
    'nextUpdateAction':
        'Inspect macro_research_sources and macro_numeric_series_catalog for ${_clean(input['target'] ?? input['query']) ?? 'the target'}, then refresh only allowed sources.',
    'provenance': const {
      'interfaceId': 'macro.root_cause_attribution',
      'evidenceSchema': 'market_moving_factor_v1',
      'evidenceTable': 'market_moving_factor',
    },
  };
}

String _macroAttributionCategory(String family) {
  if (family.contains('policy')) return 'policy';
  if (family.contains('commodity') || family.contains('energy')) {
    return 'commodity';
  }
  if (family.contains('index')) return 'index-flow';
  if (family.contains('official') ||
      family.contains('series') ||
      family.contains('rates') ||
      family.contains('inflation') ||
      family.contains('growth')) {
    return 'macro';
  }
  return 'macro';
}

String _macroAttributionConfidence(Map<String, dynamic> row) {
  final confidence = '${row['confidence'] ?? ''}';
  if (['high', 'medium', 'low'].contains(confidence)) return confidence;
  final retrieval = row['retrieval_test'] is Map
      ? Map<String, dynamic>.from(row['retrieval_test'] as Map)
      : <String, dynamic>{};
  final status = '${retrieval['status'] ?? row['status'] ?? ''}';
  if (status.contains('ok') ||
      status.contains('readable') ||
      status == 'active') {
    return 'high';
  }
  if (status.contains('validated') ||
      status.contains('usable') ||
      status == 'watch') {
    return 'medium';
  }
  return 'low';
}

List<String> _macroAttributionMissingEvidence(Map<String, dynamic> row) {
  final missing = <String>[];
  if (row['source_published_at'] == null && row['event_at'] == null) {
    missing.add('source/event time is missing');
  }
  if (row['source_url'] == null || '${row['source_url']}'.isEmpty) {
    missing.add('source URL is missing');
  }
  if (row['evidence_items'] == null) missing.add('evidence items are missing');
  return missing;
}

String _macroAttributionInvalidation(Map<String, dynamic> row) {
  final family = '${row['family'] ?? ''}';
  if (family.contains('policy')) {
    return 'A newer official policy document or implementation notice changes the policy direction.';
  }
  if (family.contains('commodity')) {
    return 'Updated inventory, supply, demand, or contract data contradicts this commodity pressure.';
  }
  if (family.contains('index')) {
    return 'The index provider cancels, delays, or revises the classification/rebalance event.';
  }
  if (family.contains('official') ||
      family.contains('series') ||
      family.contains('rates')) {
    return 'A newer official numeric release materially revises the series.';
  }
  return 'A newer source with better provenance contradicts the current macro evidence.';
}

String _macroAttributionNextAction(Map<String, dynamic> row) {
  final status = '${row['status'] ?? ''}';
  final retrieval = row['retrieval_test'] is Map
      ? Map<String, dynamic>.from(row['retrieval_test'] as Map)
      : <String, dynamic>{};
  final access = '${retrieval['accessClass'] ?? row['failure_class'] ?? ''}';
  if (status == 'blocked' ||
      access.contains('anti-bot') ||
      access.contains('manual')) {
    return 'Use browser/manual source validation or an official data-delivery path; do not retry broad scraping.';
  }
  if (access.contains('licensed') || status == 'licensed-needed') {
    return 'Use cached readback first; live update requires the licensed provider credential/quota.';
  }
  if (status == 'unsupported') {
    return 'Keep the row as a limitation until a governed extraction or official API path is implemented.';
  }
  return 'Use local readback; refresh only if source time is stale for the analysis horizon.';
}

Map<String, dynamic> _macroAttributionUpdateDecision(
  List<Map<String, dynamic>> rows,
) {
  final blocked = rows
      .where((row) {
        final status = '${row['status'] ?? ''}';
        return status == 'blocked' ||
            status == 'unsupported' ||
            row['failure_class'] != null;
      })
      .toList(growable: false);
  return {
    'requiresUpdate': rows.isEmpty || blocked.isNotEmpty,
    'missingCount': rows.isEmpty ? 1 : 0,
    'blockedCount': blocked.length,
    'nextActions': rows.isEmpty
        ? const ['macro_research_sources', 'macro_numeric_series_catalog']
        : blocked.map(_macroAttributionNextAction).toSet().toList(),
  };
}

String? _sourceNameFilter(Map<String, dynamic> input) {
  final raw = _clean(input['source'] ?? input['provider']);
  if (raw == null) return null;
  for (final source in macroResearchSourceCatalog) {
    if (_matches(source['provider'], raw) ||
        _matches(source['providerName'], raw)) {
      return '${source['providerName']}';
    }
  }
  return raw;
}

List<Map<String, dynamic>> _buildMacroResearchEvidenceRows(
  Map<String, dynamic> input,
) {
  final now = DateTime.now().toUtc().toIso8601String();
  final provider = _clean(input['provider'] ?? input['source']);
  final categoryFilters = _sourceCategoryFilters(input);
  final sources = macroResearchSourceCatalog.where((source) {
    if (provider != null &&
        !_matches(source['provider'], provider) &&
        !_matches(source['providerName'], provider)) {
      return false;
    }
    if (categoryFilters != null &&
        !_sourceMatchesCategory(source, categoryFilters)) {
      return false;
    }
    return true;
  });
  return [for (final source in sources) ..._macroRowsForSource(source, now)];
}

List<Map<String, dynamic>> _macroRowsForSource(
  Map<String, Object?> source,
  String fetchedAt,
) {
  final retrieval = _retrievalEvidence(source, fetchedAt);
  final content = _contentEvidence(source, fetchedAt);
  return content == null ? [retrieval] : [content, retrieval];
}

Map<String, dynamic>? _contentEvidence(
  Map<String, Object?> source,
  String fetchedAt,
) {
  final family = _contentFamily(source);
  if (family == null) return null;
  final interfaceId = _interfaceForFamily(family);
  final accessClass = '${source['accessClass'] ?? ''}';
  final status = accessClass.contains('licensed')
      ? 'licensed-needed'
      : 'usable';
  final provider = '${source['provider']}';
  final providerName = '${source['providerName']}';
  final entryUrls = (source['entryUrls'] as List).cast<String>();
  final categories = (source['categories'] as List).cast<String>();
  return {
    'factor_id': 'macro:$family:$provider',
    'family': family,
    'title': '$providerName ${_labelForFamily(family)}',
    'summary':
        '$providerName is classified as ${source['evidenceValue']}; usable fields include provider, category, source URL, source title, retrieval method, access class, limitation, and source/retrieved time where available.',
    'source_name': providerName,
    'source_url': entryUrls.isEmpty ? '' : entryUrls.first,
    'source_type': source['evidenceValue'],
    'fetched_at': fetchedAt,
    'affected_assets': _affectedAssets(source),
    'affected_regions': _affectedRegions(source),
    'affected_sectors': categories,
    'transmission_channels': _transmissionChannels(source),
    'expected_direction': 'context',
    'severity': 'medium',
    'confidence':
        '${source['testedStatus']}'.contains('readable') ||
            '${source['testedStatus']}'.contains('ok')
        ? 'medium'
        : 'low',
    'status': status,
    if (status != 'usable') 'failure_class': accessClass,
    'evidence_items': [
      for (final url in entryUrls)
        {
          'sourceUrl': url,
          'sourceTitle': '$providerName public source',
          'category': categories,
          'retrievalMethod': (source['retrievalMethods'] as List).first,
          'accessClass': accessClass,
          'limitation': source['limitation'],
        },
    ],
    'macro_values': {
      'interfaceId': interfaceId,
      'sourceCategories': categories,
      'extractableFields': _extractableFieldsForFamily(family),
      'sourcePeriod': null,
      'retrievedAt': fetchedAt,
    },
    'retrieval_test': _retrievalTest(
      source,
      interfaceId,
      '$provider.$interfaceId',
      fetchedAt,
    ),
    'raw_json': {
      'source': source,
      'interfaceId': interfaceId,
      'canonicalSchema': 'market_moving_factor_v1',
    },
  };
}

Map<String, dynamic> _retrievalEvidence(
  Map<String, Object?> source,
  String fetchedAt,
) {
  final blocked = _isBlockedSource(source);
  final provider = '${source['provider']}';
  final providerName = '${source['providerName']}';
  final entryUrls = (source['entryUrls'] as List).cast<String>();
  final categories = (source['categories'] as List).cast<String>();
  return {
    'factor_id': 'macro:source_retrieval:$provider',
    'family': 'macro_source_retrieval_evidence',
    'title': '$providerName retrieval policy',
    'summary':
        '$providerName access is ${source['accessClass']}; testedStatus=${source['testedStatus']}; nextAction=${source['nextAction']}',
    'source_name': providerName,
    'source_url': entryUrls.isEmpty ? '' : entryUrls.first,
    'source_type': 'source_retrieval_evidence',
    'fetched_at': fetchedAt,
    'affected_assets': _affectedAssets(source),
    'affected_regions': _affectedRegions(source),
    'affected_sectors': categories,
    'transmission_channels': [
      'source access',
      'retrieval policy',
      '${source['evidenceValue']}',
    ],
    'expected_direction': 'context',
    'severity': blocked ? 'high' : 'low',
    'confidence': 'high',
    'status': blocked ? 'blocked' : 'validated',
    if (blocked) 'failure_class': source['accessClass'],
    'evidence_items': [
      for (final url in entryUrls)
        {
          'sourceUrl': url,
          'sourceTitle': '$providerName entry page',
          'retrievalMethod': (source['retrievalMethods'] as List).first,
          'accessClass': source['accessClass'],
          'testedStatus': source['testedStatus'],
          'limitation': source['limitation'],
        },
    ],
    'macro_values': {
      'interfaceId': 'macro.source_retrieval_evidence',
      'retrievedAt': fetchedAt,
      'allowedRetrievalMethods': source['retrievalMethods'],
      'automationPolicy': source['automationPolicy'],
    },
    'retrieval_test': _retrievalTest(
      source,
      'macro.source_retrieval_evidence',
      '$provider.macro.source_retrieval_evidence',
      fetchedAt,
    ),
    'raw_json': {
      'source': source,
      'interfaceId': 'macro.source_retrieval_evidence',
    },
  };
}

List<Map<String, dynamic>> _buildMacroProviderMatrix() {
  return [
    for (final source in macroResearchSourceCatalog)
      {
        'provider': source['provider'],
        'providerName': source['providerName'],
        'researchDocument': _providerStatusFor(
          source,
          'macro_research_document',
        ),
        'indexEvent': _providerStatusFor(source, 'macro_index_event'),
        'policyEvent': _providerStatusFor(source, 'macro_policy_event'),
        'officialSeries': _providerStatusFor(source, 'macro_official_series'),
        'commodityEvent': _providerStatusFor(source, 'macro_commodity_event'),
        'retrievalEvidence': _isBlockedSource(source)
            ? source['accessClass']
            : 'supported',
        'reason': source['limitation'],
      },
  ];
}

Map<String, dynamic> _retrievalTest(
  Map<String, Object?> source,
  String interfaceId,
  String capabilityId,
  String fetchedAt,
) {
  return {
    'interface_id': interfaceId,
    'capability_id': capabilityId,
    'provider': source['provider'],
    'providerName': source['providerName'],
    'status': source['testedStatus'],
    'accessClass': source['accessClass'],
    'retrievalMethods': source['retrievalMethods'],
    'automationPolicy': source['automationPolicy'],
    'limitation': source['limitation'],
    'canonical_schema': 'market_moving_factor_v1',
    'canonical_table': 'market_moving_factor',
    'readback_action': 'query_macro_research_evidence',
    'fetched_at': fetchedAt,
  };
}

String _providerStatusFor(Map<String, Object?> source, String family) {
  if (_contentFamily(source) != family) return 'not-supported';
  final accessClass = '${source['accessClass']}';
  if (accessClass.contains('anti-bot')) return 'anti-bot';
  if (accessClass.contains('manual')) return 'manual-browser';
  if (accessClass.contains('official-data-delivery')) {
    return 'official-data-delivery';
  }
  if (accessClass.contains('licensed')) return 'licensed-needed';
  if (accessClass.contains('official-api')) return 'official-api';
  if (accessClass.contains('browser')) return 'browser-supported';
  final testedStatus = '${source['testedStatus']}';
  if (testedStatus.contains('ok') || testedStatus.contains('readable')) {
    return 'supported';
  }
  return 'output-only';
}

String? _contentFamily(Map<String, Object?> source) {
  final evidenceValue = '${source['evidenceValue']}';
  if ([
    'research_narrative',
    'allocation_regime',
    'rates_credit_context',
  ].contains(evidenceValue)) {
    return 'macro_research_document';
  }
  if (evidenceValue == 'official_index_event') return 'macro_index_event';
  if (evidenceValue == 'official_policy_event') return 'macro_policy_event';
  if (evidenceValue == 'official_macro_fact') return 'macro_official_series';
  if (evidenceValue.contains('commodity') && !_isBlockedSource(source)) {
    return 'macro_commodity_event';
  }
  if (evidenceValue == 'official_market_structure_context' &&
      !_isBlockedSource(source)) {
    return 'macro_commodity_event';
  }
  return null;
}

String _interfaceForFamily(String family) {
  switch (family) {
    case 'macro_research_document':
      return 'macro.research_document';
    case 'macro_index_event':
      return 'macro.index_event';
    case 'macro_policy_event':
      return 'macro.policy_event';
    case 'macro_official_series':
      return 'macro.official_series';
    case 'macro_commodity_event':
      return 'macro.commodity_event';
  }
  return 'macro.source_retrieval_evidence';
}

String _labelForFamily(String family) {
  return _interfaceForFamily(
    family,
  ).replaceFirst('macro.', '').replaceAll('_', ' ');
}

bool _isBlockedSource(Map<String, Object?> source) {
  final accessClass = '${source['accessClass']}';
  final policy = '${source['automationPolicy']}';
  return accessClass.contains('anti-bot') ||
      accessClass.contains('manual') ||
      accessClass.contains('security') ||
      accessClass.contains('licensed') ||
      policy.contains('do-not-scrape');
}

List<String> _affectedAssets(Map<String, Object?> source) {
  final text =
      '${(source['categories'] as List).join(' ')} ${source['evidenceValue']} ${(source['entryUrls'] as List).join(' ')}'
          .toLowerCase();
  final assets = <String>{};
  if (text.contains('copper')) assets.add('Copper');
  if (text.contains('commodity') ||
      text.contains('copper') ||
      text.contains('metals')) {
    assets.add('commodities');
  }
  if (text.contains('oil') || text.contains('energy')) assets.add('energy');
  if (text.contains('rates') ||
      text.contains('bonds') ||
      text.contains('credit')) {
    assets.add('bond funds');
  }
  if (text.contains('index') || text.contains('classification')) {
    assets.add('passive index flows');
  }
  if (assets.isEmpty) assets.add('global macro');
  return assets.toList();
}

List<String> _affectedRegions(Map<String, Object?> source) {
  final provider = '${source['provider']}';
  if (provider == 'bea' || provider == 'fred' || provider == 'bls') {
    return ['United States'];
  }
  return ['global'];
}

List<String> _transmissionChannels(Map<String, Object?> source) {
  final channels = <String>[
    'macro research evidence',
    '${source['evidenceValue']}',
  ];
  if (source['evidenceValue'] == 'official_index_event') {
    channels.add('passive benchmark flow');
  }
  if ('${source['evidenceValue']}'.contains('commodity')) {
    channels.add('supply demand inventory');
  }
  final categories = (source['categories'] as List).cast<String>();
  if (categories.any(
    (item) => item.contains('rates') || item.contains('credit'),
  )) {
    channels.add('rates liquidity');
  }
  return channels;
}

List<String> _extractableFieldsForFamily(String family) {
  switch (family) {
    case 'macro_research_document':
      return [
        'title',
        'provider',
        'canonicalUrl',
        'publishDate',
        'category',
        'summary',
        'keyClaims',
        'mentionedAssets',
        'limitation',
      ];
    case 'macro_index_event':
      return [
        'eventTitle',
        'provider',
        'eventType',
        'affectedMarket',
        'announcementDate',
        'effectiveDate',
        'officialDocumentUrl',
        'status',
      ];
    case 'macro_policy_event':
      return [
        'eventTitle',
        'provider',
        'policyArea',
        'affectedMarket',
        'announcementDate',
        'effectiveDate',
        'officialDocumentUrl',
        'status',
      ];
    case 'macro_official_series':
      return [
        'seriesId',
        'metricName',
        'value',
        'observationDate',
        'releaseDate',
        'frequency',
        'unit',
        'geography',
      ];
    case 'macro_commodity_event':
      return [
        'commodity',
        'measure',
        'reportPeriod',
        'releaseDate',
        'region',
        'unit',
        'sourceDocumentUrl',
      ];
  }
  return [
    'provider',
    'sourceUrl',
    'retrievalMethod',
    'accessClass',
    'testedStatus',
    'limitation',
  ];
}

Map<String, dynamic> _macroResearchProvenanceMeta(String readbackAction) {
  return {
    'interfaceId': 'macro.research_provenance',
    'providerId': 'local',
    'provider': 'local',
    'capabilityId': 'local.$readbackAction',
    'providerMode': 'catalog-normalized-readback',
    'cacheStatus': 'local-readback',
    'cacheDecision':
        'normalize catalog source behavior into market_moving_factor_v1 rows before reuse',
    'canonicalSchema': 'market_moving_factor_v1',
    'canonicalTable': 'market_moving_factor',
    'readbackAction': readbackAction,
    'source': 'bundled macro research source catalog + retrieval evidence',
    'fetchedAt': DateTime.now().toUtc().toIso8601String(),
  };
}

List<String>? _stringList(Object? value) {
  if (value is Iterable) {
    final items = value
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return items.isEmpty ? null : items;
  }
  final text = _clean(value);
  if (text == null) return null;
  final items = text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
  return items.isEmpty ? null : items;
}

const _sourceCategoryAliases = <String, List<String>>{
  'commodity_research': [
    'commodities',
    'energy_supply',
    'energy_demand',
    'inventory',
    'oil_gas',
    'warehouse_stocks',
    'metals',
    'commodity_contract_context',
    'pricing_stress',
  ],
  'commodity': [
    'commodities',
    'metals',
    'inventory',
    'oil_gas',
    'commodity_contract_context',
  ],
  'commodities': [
    'commodities',
    'metals',
    'inventory',
    'oil_gas',
    'commodity_contract_context',
  ],
  'metals': ['metals', 'warehouse_stocks', 'pricing_stress'],
  'copper': [
    'commodities',
    'metals',
    'warehouse_stocks',
    'commodity_contract_context',
    'pricing_stress',
  ],
  'rates_liquidity': [
    'rates',
    'bonds',
    'credit',
    'duration',
    'liquidity',
    'monetary_policy',
    'open_market_operations',
  ],
  'policy_regulation': [
    'china_regulation',
    'capital_market_policy',
    'listed_company_policy',
    'fund_policy',
    'monetary_policy',
    'listing_rules',
    'market_structure_event',
  ],
  'index_classification': [
    'market_classification',
    'equity_country_classification',
    'country_classification',
    'index_review',
    'rebalance_event',
  ],
  'cross_asset_stress': [
    'asset_allocation',
    'regime_view',
    'market_outlook',
    'fx_liquidity',
    'external_balance',
  ],
  'narrative_attention': [
    'macro_outlook',
    'global_outlook',
    'macro_strategy',
    'weekly_commentary',
    'market_outlook',
  ],
};

const _evidenceFamilyAliases = <String, List<String>>{
  'commodity_research': [
    'macro_commodity_event',
    'macro_research_document',
    'macro_source_retrieval_evidence',
  ],
  'commodity': [
    'macro_commodity_event',
    'macro_research_document',
    'macro_source_retrieval_evidence',
  ],
  'commodities': [
    'macro_commodity_event',
    'macro_research_document',
    'macro_source_retrieval_evidence',
  ],
  'metals': [
    'macro_commodity_event',
    'macro_research_document',
    'macro_source_retrieval_evidence',
  ],
  'copper': [
    'macro_commodity_event',
    'macro_research_document',
    'macro_source_retrieval_evidence',
  ],
  'rates_liquidity': [
    'macro_official_series',
    'macro_research_document',
    'macro_source_retrieval_evidence',
  ],
  'policy_regulation': [
    'macro_policy_event',
    'macro_source_retrieval_evidence',
  ],
  'index_classification': [
    'macro_index_event',
    'macro_source_retrieval_evidence',
  ],
  'cross_asset_stress': [
    'macro_research_document',
    'macro_official_series',
    'macro_source_retrieval_evidence',
  ],
  'narrative_attention': [
    'macro_research_document',
    'macro_source_retrieval_evidence',
  ],
};

List<String>? _sourceCategoryFilters(Map<String, dynamic> input) {
  final raw =
      _stringList(input['categories']) ??
      _stringList(input['category'] ?? input['family']);
  if (raw == null) return null;
  final expanded = <String>{};
  for (final item in raw) {
    expanded.add(item);
    expanded.addAll(_sourceCategoryAliases[_normalizeKey(item)] ?? const []);
  }
  return expanded.toList(growable: false);
}

List<String> _evidenceFamilies(Map<String, dynamic> input) {
  final raw = _stringList(input['families']) ?? _stringList(input['family']);
  if (raw == null) return _macroResearchFamilies;
  final expanded = <String>{};
  for (final item in raw) {
    if (_macroResearchFamilies.contains(item)) {
      expanded.add(item);
      continue;
    }
    expanded.addAll(_evidenceFamilyAliases[_normalizeKey(item)] ?? const []);
  }
  return expanded.isEmpty ? raw : expanded.toList(growable: false);
}

List<String>? macroFactorFamilies(Map<String, dynamic> input) {
  final raw = _stringList(input['families']) ?? _stringList(input['family']);
  if (raw == null) return null;
  final expanded = <String>{};
  for (final item in raw) {
    expanded.add(item);
    expanded.addAll(_evidenceFamilyAliases[_normalizeKey(item)] ?? const []);
  }
  return expanded.toList(growable: false);
}

bool _sourceMatchesCategory(Map<String, Object?> source, List<String> filters) {
  final family = _contentFamily(source);
  final categories = (source['categories'] as List).cast<Object?>();
  final evidenceValue = '${source['evidenceValue'] ?? ''}';
  return filters.any(
    (filter) =>
        categories.any((item) => _matches(item, filter)) ||
        _matches(evidenceValue, filter) ||
        (family != null && _matches(family, filter)),
  );
}

String? _clean(Object? value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? null : text;
}

int _boundedLimit(Object? value, int fallback) {
  final parsed = int.tryParse('${value ?? ''}');
  if (parsed == null) return fallback;
  if (parsed < 1) return 1;
  if (parsed > 80) return 80;
  return parsed;
}

int? _positiveInt(Object? value) {
  final parsed = int.tryParse('${value ?? ''}');
  if (parsed == null || parsed < 1) return null;
  return parsed;
}

bool _matches(Object? value, String filter) {
  return '${value ?? ''}'.toLowerCase().contains(filter.toLowerCase());
}

String _normalizeKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
}
