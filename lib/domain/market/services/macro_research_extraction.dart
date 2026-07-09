import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../../agent/data_fetcher/reusable_data_store.dart';
import 'macro_research_source_catalog_data.dart';

const _extractableAccessClasses = [
  'public-summary-licensed-full-report',
  'public-html-and-pdf',
  'public-html',
  'official-api',
  'official-public-source',
  'official-api-and-public-report',
  'browser-or-official-api',
  'browser-public',
];

const _blockedAccessMarkers = ['anti-bot', 'manual', 'security'];

Future<Map<String, dynamic>> macroResearchExtract(
  ReusableDataStore? store,
  Map<String, dynamic> input, {
  String basePath = '',
  http.Client? httpClient,
}) async {
  final fetchedAt = DateTime.now().toUtc().toIso8601String();
  final extracted = <Map<String, dynamic>>[];
  final failures = <Map<String, dynamic>>[];
  final client = httpClient ?? http.Client();
  final closeClient = httpClient == null;
  try {
    for (final source in _selectedSources(input)) {
      final url = _selectedUrl(source, input);
      if (!_isExtractableSource(source)) {
        failures.add(
          _failure(
            source,
            url,
            fetchedAt,
            '${source['accessClass']}',
            'Source is ${source['accessClass']}; keep as retrieval evidence until a legitimate access path or manual artifact is provided.',
          ),
        );
        continue;
      }
      try {
        final item = await _extractOneSource(
          source,
          url,
          input,
          basePath,
          fetchedAt,
          client,
        );
        extracted.addAll(_evidenceRowsForExtracted(item));
      } catch (error) {
        failures.add(
          _failure(
            source,
            url,
            fetchedAt,
            _classifyExtractionError(error),
            '$error',
          ),
        );
      }
    }
  } finally {
    if (closeClient) client.close();
  }
  final rows = [...extracted, ...failures];
  final shouldPersist = input['persist'] != false;
  if (shouldPersist && store != null && rows.isNotEmpty) {
    store.saveMarketMovingFactors(rows);
  }
  return {
    'action': 'macro_research_extract',
    'status': failures.isNotEmpty && extracted.isEmpty ? 'failed' : 'ok',
    'extracted': extracted.length,
    'failed': failures.length,
    'persisted': shouldPersist && store != null,
    'providerMatrix': macroResearchExtractionProviderMatrix(),
    'provenance': _extractionProvenance('macro_research_extract'),
    'rows': rows,
    'failures': [
      for (final row in failures)
        {
          'provider': (row['raw_json'] as Map)['source']['provider'],
          'providerName': row['source_name'],
          'url': row['source_url'],
          'failureClass': row['failure_class'],
          'message': row['summary'],
        },
    ],
  };
}

Map<String, dynamic> queryMacroResearchContent(
  ReusableDataStore? store,
  Map<String, dynamic> input,
) {
  final sourceFilter = _sourceNameFilter(input);
  final rows =
      store
          ?.queryMarketMovingFactors(
            families: const [
              'macro_research_document',
              'macro_index_event',
              'macro_policy_event',
              'macro_official_series',
              'macro_commodity_event',
              'macro_source_retrieval_evidence',
            ],
            status: _clean(input['status']),
            source: sourceFilter,
            target: _clean(input['target'] ?? input['query']),
            assets: _stringList(input['assets']),
            regions: _stringList(input['regions'] ?? input['market']),
            sectors: _stringList(input['sectors'] ?? input['industry']),
            limit: _boundedLimit(input['limit'], 80),
          )
          .where((row) {
            if (input['contentOnly'] == false) return true;
            final values = row['macro_values'];
            return values is Map && values['contentHash'] != null;
          })
          .toList() ??
      const <Map<String, dynamic>>[];
  return {
    'action': 'query_macro_research_content',
    'status': rows.isEmpty ? 'missing' : 'ok',
    'count': rows.length,
    if (rows.isEmpty)
      'missingReason':
          'No extracted macro research content rows matched the filters. Run macro_research_extract for an allowed source or inspect macro_research_extraction_status.',
    'providerMatrix': macroResearchExtractionProviderMatrix(),
    'provenance': _extractionProvenance('query_macro_research_content'),
    'readbackContract': {
      'normalUse':
          'Use contentEvidence for first-pass macro analysis. It contains title/date/source/key claims/body preview from governed readback, so local artifact files do not need to be opened.',
      'diagnosticOnly':
          'artifactPath is for audit/debug/source maintenance. Do not use file inspection to inspect macro content files in a normal first-pass analysis answer.',
    },
    'contentEvidence': rows.map(_contentEvidenceRow).toList(growable: false),
    'rows': rows,
  };
}

Map<String, dynamic> _contentEvidenceRow(Map<String, dynamic> row) {
  final values = row['macro_values'] is Map
      ? Map<String, dynamic>.from(row['macro_values'] as Map)
      : <String, dynamic>{};
  final retrieval = row['retrieval_test'] is Map
      ? Map<String, dynamic>.from(row['retrieval_test'] as Map)
      : <String, dynamic>{};
  final rawClaims = values['keyClaims'] is List
      ? (values['keyClaims'] as List).take(5)
      : const Iterable.empty();
  final claims = rawClaims
      .map((claim) {
        if (claim is Map) {
          final item = Map<String, dynamic>.from(claim);
          return {
            'claim': item['claim'] ?? item['text'],
            'category': item['claimCategory'] ?? item['category'],
            'confidence': item['confidence'],
            'limitation': item['limitation'],
            'sourceUrl': item['sourceUrl'] ?? row['source_url'],
            'sourceDate': item['sourceDate'] ?? row['source_published_at'],
          };
        }
        return {
          'claim': '$claim',
          'category': null,
          'confidence': null,
          'limitation': null,
        };
      })
      .toList(growable: false);
  return {
    'title': row['title'] ?? values['title'],
    'summary': row['summary'],
    'sourceName': row['source_name'],
    'sourceUrl': row['source_url'],
    'sourceType': row['source_type'],
    'evidenceTier': _contentEvidenceTier(row),
    'limitations': _contentEvidenceLimitations(row),
    'linkedMacroEvidenceIds':
        _stringList(row['linked_macro_evidence_ids']) ?? const <String>[],
    'sourceDataTime': row['source_published_at'] ?? values['sourcePublishedAt'],
    'fetchedAt': row['fetched_at'] ?? values['retrievedAt'],
    'family': row['family'],
    'status': row['status'],
    'affectedAssets': row['affected_assets'] ?? values['mentionedAssets'] ?? [],
    'affectedRegions':
        row['affected_regions'] ?? values['mentionedRegions'] ?? [],
    'affectedSectors':
        row['affected_sectors'] ?? values['mentionedSectors'] ?? [],
    'transmissionChannels': row['transmission_channels'] ?? [],
    'contentHash': values['contentHash'],
    'bodyPreview': values['bodyPreview'],
    'bodyLength': values['bodyLength'],
    'keyClaims': claims,
    'limitation':
        claims.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['limitation'] != null,
          orElse: () => null,
        )?['limitation'] ??
        retrieval['limitation'],
    'diagnosticArtifactPath': values['artifactPath'],
  };
}

String _contentEvidenceTier(Map<String, dynamic> row) {
  final explicit = row['evidence_tier']?.toString().trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  final sourceType = row['source_type']?.toString().toLowerCase() ?? '';
  if (RegExp(
    r'official_api|official_series|official_document',
  ).hasMatch(sourceType)) {
    return 'official_numeric_or_document';
  }
  if (RegExp(r'research|content|document|article').hasMatch(sourceType)) {
    return 'content_backed_research';
  }
  if (sourceType.contains('news')) return 'linked_news_evidence';
  if (RegExp(r'manual|licensed|fallback|retrieval').hasMatch(sourceType)) {
    return 'retrieval_or_manual_evidence';
  }
  if (row['failure_class'] != null) return 'missing_or_blocked';
  return 'governed_macro_evidence';
}

List<String> _contentEvidenceLimitations(Map<String, dynamic> row) {
  final explicit = _stringList(row['limitations']);
  if (explicit != null && explicit.isNotEmpty) return explicit;
  if (_contentEvidenceTier(row) == 'linked_news_evidence') {
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

Map<String, dynamic> macroResearchExtractionStatus(Map<String, dynamic> input) {
  final provider = _clean(input['provider'] ?? input['source']);
  final rows = macroResearchExtractionProviderMatrix().where((row) {
    if (provider == null) return true;
    return _matches(row['provider'], provider) ||
        _matches(row['providerName'], provider);
  }).toList();
  return {
    'action': 'macro_research_extraction_status',
    'status': rows.isEmpty ? 'missing' : 'ok',
    'count': rows.length,
    'provenance': _extractionProvenance('macro_research_extraction_status'),
    'rows': rows,
  };
}

List<Map<String, dynamic>> macroResearchExtractionProviderMatrix() {
  return [
    for (final source in macroResearchSourceCatalog)
      {
        'provider': source['provider'],
        'providerName': source['providerName'],
        'catalogStatus': source['testedStatus'],
        'allowedRetrievalMethod': (source['retrievalMethods'] as List).first,
        'contentExtractorStatus':
            _isExtractableSource(source) && _contentFamily(source) != null
            ? 'implemented'
            : 'not-extracted',
        'pdfExtractorStatus':
            (source['entryUrls'] as List).any(
              (url) => '$url'.toLowerCase().contains('.pdf'),
            )
            ? 'minimal-text-parser'
            : 'not-applicable',
        'keyClaimExtractorStatus':
            _isExtractableSource(source) && _contentFamily(source) != null
            ? 'bounded-structural-extraction'
            : 'not-extracted',
        'contentHashReadbackStatus':
            _isExtractableSource(source) && _contentFamily(source) != null
            ? 'supported'
            : 'retrieval-evidence-only',
        'canonicalEvidenceFamily':
            _contentFamily(source) ?? 'macro_source_retrieval_evidence',
        'limitation': source['limitation'],
      },
  ];
}

Future<Map<String, dynamic>> _extractOneSource(
  Map<String, Object?> source,
  String url,
  Map<String, dynamic> input,
  String basePath,
  String fetchedAt,
  http.Client client,
) async {
  final contentType = _contentTypeFor(source, url, input);
  final injected = _clean(
    input['content'] ??
        input['html'] ??
        input['pdfText'] ??
        input['apiPayload'],
  );
  final document = injected == null
      ? await _fetchSourceDocument(source, url, contentType, input, client)
      : _FetchedSourceDocument(text: injected, url: url);
  final raw = document.text;
  final effectiveUrl = document.url;
  final apiPayload = contentType == 'api_payload'
      ? _extractApiPayload(raw)
      : null;
  final textSource = contentType == 'html' ? _extractHtmlMainContent(raw) : raw;
  final cleanedText =
      apiPayload?['text'] ??
      (contentType == 'html'
          ? _cleanHtml(textSource)
          : _cleanDocumentText(raw));
  if (cleanedText.length < 120) {
    final sparseClass = contentType == 'html'
        ? _classifySparseHtml(raw)
        : 'extraction-too-sparse';
    throw _MacroExtractionException(
      sparseClass,
      'Extracted text too short for ${source['provider']}.',
    );
  }
  final sourcePublishedAt =
      apiPayload?['date'] ??
      _extractDate(raw) ??
      _extractDate(cleanedText) ??
      _extractDate(effectiveUrl);
  final title = apiPayload?['title'] ?? _extractTitle(raw, cleanedText, source);
  final hash = _sha256(
    '$effectiveUrl\n${sourcePublishedAt ?? ''}\n$cleanedText',
  );
  final artifactPath = _writeContentArtifact(
    basePath,
    '${source['provider']}',
    hash,
    contentType,
    cleanedText,
  );
  return {
    'source': source,
    'url': effectiveUrl,
    'listSourceUrl': document.listSourceUrl,
    'contentType': contentType,
    'title': title,
    'sourcePublishedAt': sourcePublishedAt,
    'cleanedText': cleanedText,
    'summary': _summarize(cleanedText),
    'keyClaims': _extractKeyClaims(
      cleanedText,
      source,
      effectiveUrl,
      sourcePublishedAt,
      hash,
    ),
    'mentionedAssets': _mentionedAssets(cleanedText, source),
    'mentionedRegions': _mentionedRegions(cleanedText, source),
    'mentionedSectors': _mentionedSectors(cleanedText, source),
    'contentHash': hash,
    'artifactPath': artifactPath,
    'fetchedAt': fetchedAt,
    'confidence': cleanedText.length > 1200 ? 'medium' : 'low-medium',
  };
}

class _FetchedSourceDocument {
  const _FetchedSourceDocument({
    required this.text,
    required this.url,
    this.listSourceUrl,
  });

  final String text;
  final String url;
  final String? listSourceUrl;
}

Future<_FetchedSourceDocument> _fetchSourceDocument(
  Map<String, Object?> source,
  String url,
  String contentType,
  Map<String, dynamic> input,
  http.Client client,
) async {
  final listText = await _fetchSourceText(source, url, contentType, client);
  if (contentType != 'html' ||
      input['disableDetailDiscovery'] == true ||
      !_shouldDiscoverDetailUrl(source, url)) {
    return _FetchedSourceDocument(text: listText, url: url);
  }
  final detailUrl = macroResearchSelectDetailUrlForTest(
    sourceUrl: url,
    html: listText,
    source: source,
  );
  if (detailUrl == null || detailUrl == url) {
    return _FetchedSourceDocument(text: listText, url: url);
  }
  final detailText = await _fetchSourceText(
    source,
    detailUrl,
    contentType,
    client,
  );
  return _FetchedSourceDocument(
    text: detailText,
    url: detailUrl,
    listSourceUrl: url,
  );
}

Future<String> _fetchSourceText(
  Map<String, Object?> source,
  String url,
  String contentType,
  http.Client client,
) async {
  final response = await client
      .get(
        Uri.parse(url),
        headers: {
          'User-Agent': source['defaultUserAgentRequired'] == true
              ? 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36'
              : 'FinAgentResearchProvenance/1.0',
          'Accept': contentType == 'pdf_text'
              ? 'application/pdf,*/*'
              : 'text/html,application/xhtml+xml,application/json,*/*',
        },
      )
      .timeout(const Duration(seconds: 20));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw _MacroExtractionException(
      response.statusCode == 401 || response.statusCode == 403
          ? 'security-or-permission-blocked'
          : 'http-error',
      'HTTP ${response.statusCode} while fetching $url',
    );
  }
  if (contentType == 'pdf_text') {
    return _extractTextFromPdfBytes(response.bodyBytes);
  }
  return response.body;
}

bool _shouldDiscoverDetailUrl(Map<String, Object?> source, String url) {
  final categories = (source['categories'] as List).map((item) => '$item');
  if (url.toLowerCase().contains('.pdf')) return false;
  return categories.any(
    (item) => const {
      'data_release',
      'official_policy_event',
      'policy_report',
      'open_market_operations',
      'market_structure_event',
      'central_bank_communication',
      'capital_market_policy',
    }.contains(item),
  );
}

String? macroResearchSelectDetailUrlForTest({
  required String sourceUrl,
  required String html,
  required Map<String, Object?> source,
}) {
  final base = Uri.tryParse(sourceUrl);
  if (base == null || !base.hasScheme || base.host.isEmpty) return null;
  final candidates = <_DetailLinkCandidate>[];
  final pattern = RegExp(r'<a\b([^>]*)>([\s\S]*?)</a>', caseSensitive: false);
  var order = 0;
  for (final match in pattern.allMatches(html)) {
    order += 1;
    final attrs = match.group(1) ?? '';
    final href = RegExp(
      r'''href\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(attrs)?.group(1);
    if (href == null) continue;
    final resolved = base.resolve(_htmlDecode(href));
    if (!_isSameOfficialOrigin(base, resolved) ||
        !_isAllowedDetailPath(resolved)) {
      continue;
    }
    final score = _detailLinkScore(resolved);
    if (score <= 0) continue;
    candidates.add(
      _DetailLinkCandidate(
        resolved.toString(),
        score,
        _detailPathDateScore(resolved),
        order,
      ),
    );
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final byDate = b.dateScore.compareTo(a.dateScore);
    if (byDate != 0) return byDate;
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.order.compareTo(b.order);
  });
  return candidates.first.url;
}

bool _isSameOfficialOrigin(Uri base, Uri next) =>
    next.scheme == base.scheme && next.host == base.host;

bool _isAllowedDetailPath(Uri uri) {
  final raw = uri.toString().toLowerCase();
  if (raw.contains('#') ||
      raw.startsWith('javascript:') ||
      raw.startsWith('mailto:') ||
      raw.contains('/wza/') ||
      raw.contains('/mobile/') ||
      raw.contains('rss') ||
      raw.contains('login') ||
      raw.contains('search')) {
    return false;
  }
  final segments = uri.pathSegments.where((item) => item.isNotEmpty).toList();
  if (segments.isEmpty) return false;
  final last = segments.last.toLowerCase();
  if (last == 'index.html') return segments.length >= 5;
  return last.endsWith('.html') || last.endsWith('.shtml');
}

int _detailLinkScore(Uri uri) {
  var score = 0;
  if (RegExp(r'20\d{2}').hasMatch(uri.path)) score += 3;
  if (uri.pathSegments.length >= 3 && uri.path.endsWith('.html')) score += 2;
  if (uri.path.endsWith('.shtml')) score += 1;
  if (uri.path.endsWith('index.html')) {
    score -= 4;
  }
  return score;
}

int _detailPathDateScore(Uri uri) {
  final compact = RegExp(r'(20\d{2})([01]\d)([0-3]\d)').firstMatch(uri.path);
  if (compact != null) {
    return int.tryParse(
          '${compact.group(1)}${compact.group(2)}${compact.group(3)}',
        ) ??
        0;
  }
  final yearMonth = RegExp(r'(20\d{2})([01]\d)').firstMatch(uri.path);
  if (yearMonth != null) {
    return int.tryParse('${yearMonth.group(1)}${yearMonth.group(2)}00') ?? 0;
  }
  return 0;
}

String _htmlDecode(String value) {
  return value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

class _DetailLinkCandidate {
  const _DetailLinkCandidate(this.url, this.score, this.dateScore, this.order);

  final String url;
  final int score;
  final int dateScore;
  final int order;
}

List<Map<String, dynamic>> _evidenceRowsForExtracted(
  Map<String, dynamic> item,
) {
  final source = item['source'] as Map<String, Object?>;
  final family = _contentFamily(source) ?? 'macro_research_document';
  final interfaceId = _interfaceForFamily(family);
  return [
    {
      'factor_id':
          'macro:content:${source['provider']}:${'${item['contentHash']}'.substring(0, 16)}',
      'family': family,
      'title': item['title'],
      'summary': item['summary'],
      'source_name': source['providerName'],
      'source_url': item['url'],
      'source_type': source['evidenceValue'],
      'source_published_at': item['sourcePublishedAt'],
      'fetched_at': item['fetchedAt'],
      'affected_assets': item['mentionedAssets'],
      'affected_regions': item['mentionedRegions'],
      'affected_sectors': item['mentionedSectors'],
      'transmission_channels': _transmissionChannels(source),
      'expected_direction': 'context',
      'severity': (item['keyClaims'] as List).length >= 3 ? 'medium' : 'low',
      'confidence': item['confidence'],
      'status': 'usable',
      'evidence_items': item['keyClaims'],
      'macro_values': {
        'interfaceId': interfaceId,
        if (item['listSourceUrl'] != null)
          'listSourceUrl': item['listSourceUrl'],
        'title': item['title'],
        'contentType': item['contentType'],
        'contentHash': item['contentHash'],
        'artifactPath': item['artifactPath'],
        'bodyPreview': '${item['cleanedText']}'.substring(
          0,
          '${item['cleanedText']}'.length > 1800
              ? 1800
              : '${item['cleanedText']}'.length,
        ),
        'bodyLength': '${item['cleanedText']}'.length,
        'keyClaims': item['keyClaims'],
        'mentionedAssets': item['mentionedAssets'],
        'mentionedRegions': item['mentionedRegions'],
        'mentionedSectors': item['mentionedSectors'],
        'sourceCategories': source['categories'],
        'sourcePublishedAt': item['sourcePublishedAt'],
        'retrievedAt': item['fetchedAt'],
        'parserVersion': 'macro-research-extractor-v1',
      },
      'retrieval_test': {
        'interface_id': interfaceId,
        'capability_id': '${source['provider']}.$interfaceId.extract',
        'provider': source['provider'],
        'providerName': source['providerName'],
        'status': 'extracted',
        'accessClass': source['accessClass'],
        'retrievalMethods': source['retrievalMethods'],
        'automationPolicy': source['automationPolicy'],
        'contentHash': item['contentHash'],
        'contentType': item['contentType'],
        if (item['listSourceUrl'] != null)
          'listSourceUrl': item['listSourceUrl'],
        'canonical_schema': 'market_moving_factor_v1',
        'canonical_table': 'market_moving_factor',
        'readback_action': 'query_macro_research_content',
        'fetched_at': item['fetchedAt'],
      },
      'raw_json': {
        'provider': source['provider'],
        'url': item['url'],
        if (item['listSourceUrl'] != null)
          'listSourceUrl': item['listSourceUrl'],
        'contentHash': item['contentHash'],
        'artifactPath': item['artifactPath'],
        'keyClaims': item['keyClaims'],
      },
    },
  ];
}

Map<String, dynamic> _failure(
  Map<String, Object?> source,
  String url,
  String fetchedAt,
  String failureClass,
  String message,
) {
  return {
    'factor_id': 'macro:source_extraction:${source['provider']}',
    'family': 'macro_source_retrieval_evidence',
    'title': '${source['providerName']} extraction status',
    'summary': message,
    'source_name': source['providerName'],
    'source_url': url,
    'source_type': 'source_extraction_evidence',
    'fetched_at': fetchedAt,
    'affected_assets': _mentionedAssets('', source),
    'affected_regions': _mentionedRegions('', source),
    'affected_sectors': source['categories'],
    'transmission_channels': [
      'source extraction',
      '${source['evidenceValue']}',
    ],
    'expected_direction': 'context',
    'severity': 'medium',
    'confidence': 'high',
    'status': 'blocked',
    'failure_class': failureClass,
    'evidence_items': [
      {
        'sourceUrl': url,
        'sourceTitle': '${source['providerName']} extraction status',
        'retrievalMethod': (source['retrievalMethods'] as List).first,
        'accessClass': source['accessClass'],
        'testedStatus': source['testedStatus'],
        'limitation': source['limitation'],
        'nextAction': source['nextAction'],
      },
    ],
    'macro_values': {
      'interfaceId': 'macro.source_retrieval_evidence',
      'extractionStatus': 'not-extracted',
      'failureClass': failureClass,
      'message': message,
      'retrievedAt': fetchedAt,
    },
    'retrieval_test': {
      'interface_id': 'macro.source_retrieval_evidence',
      'capability_id': '${source['provider']}.macro.source_extraction',
      'provider': source['provider'],
      'providerName': source['providerName'],
      'status': 'blocked',
      'failure_class': failureClass,
      'accessClass': source['accessClass'],
      'canonical_schema': 'market_moving_factor_v1',
      'canonical_table': 'market_moving_factor',
      'readback_action': 'query_macro_research_evidence',
      'fetched_at': fetchedAt,
    },
    'raw_json': {'source': source, 'message': message},
  };
}

List<Map<String, Object?>> _selectedSources(Map<String, dynamic> input) {
  final provider = _clean(
    input['provider'] ?? input['source'] ?? input['sourceId'],
  );
  final category = _clean(input['category'] ?? input['family']);
  final priority = _positiveInt(input['priority']);
  final limit = _boundedLimit(input['limit'], provider != null ? 20 : 80);
  var candidates = macroResearchSourceCatalog;
  if (provider != null && provider != 'all') {
    final exact = macroResearchSourceCatalog
        .where(
          (source) =>
              _equalsFold(source['provider'], provider) ||
              _equalsFold(source['providerName'], provider),
        )
        .toList();
    candidates = exact.isNotEmpty ? exact : candidates;
  }
  return candidates
      .where((source) {
        if (provider != null &&
            provider != 'all' &&
            !_matches(source['provider'], provider) &&
            !_matches(source['providerName'], provider)) {
          return false;
        }
        if (category != null &&
            !((source['categories'] as List).any(
              (item) => _matches(item, category),
            ))) {
          return false;
        }
        if (priority != null && (source['priority'] as int) > priority)
          return false;
        return true;
      })
      .take(limit)
      .toList();
}

bool _equalsFold(Object? left, String right) =>
    '$left'.trim().toLowerCase() == right.trim().toLowerCase();

String _selectedUrl(Map<String, Object?> source, Map<String, dynamic> input) {
  final explicit = _clean(input['url']);
  if (explicit != null) return explicit;
  final urls = (source['entryUrls'] as List).cast<String>();
  final index = _positiveInt(input['urlIndex']) ?? 0;
  return urls[index.clamp(0, urls.length - 1)];
}

bool _isExtractableSource(Map<String, Object?> source) {
  final accessClass = '${source['accessClass']}';
  final policy = '${source['automationPolicy']}';
  if (accessClass.contains('licensed') &&
      !accessClass.contains('public-summary')) {
    return false;
  }
  if (_blockedAccessMarkers.any(accessClass.contains)) return false;
  if (policy.contains('do-not-scrape')) return false;
  return _extractableAccessClasses.any(accessClass.contains);
}

String _contentTypeFor(
  Map<String, Object?> source,
  String url,
  Map<String, dynamic> input,
) {
  final explicit = _clean(input['contentType']);
  if (explicit == 'pdf_text' ||
      explicit == 'html' ||
      explicit == 'api_payload') {
    return explicit!;
  }
  if (url.toLowerCase().contains('.pdf') || _clean(input['pdfText']) != null) {
    return 'pdf_text';
  }
  if ((source['retrievalMethods'] as List).contains('official_api') &&
      _clean(input['apiPayload']) != null) {
    return 'api_payload';
  }
  return 'html';
}

String _cleanHtml(String html) {
  return html
      .replaceAll(
        RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<nav[\s\S]*?</nav>', caseSensitive: false), ' ')
      .replaceAll(
        RegExp(r'<footer[\s\S]*?</footer>', caseSensitive: false),
        ' ',
      )
      .replaceAll(
        RegExp(r'<header[\s\S]*?</header>', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _extractHtmlMainContent(String html) {
  final patterns = [
    RegExp(r'<article\b[^>]*>([\s\S]*?)</article>', caseSensitive: false),
    RegExp(r'<main\b[^>]*>([\s\S]*?)</main>', caseSensitive: false),
    RegExp(
      r'''<section\b[^>]*(?:class|id)=["'][^"']*(?:article|content|detail|main|text|zoom|TRS_Editor)[^"']*["'][^>]*>([\s\S]*?)</section>''',
      caseSensitive: false,
    ),
    RegExp(
      r'''<div\b[^>]*(?:class|id)=["'][^"']*(?:TRS_Editor|Custom_UnionStyle|zoom|article|content|detail|mainText|news_txt|txt|text)[^"']*["'][^>]*>([\s\S]*?)</div>''',
      caseSensitive: false,
    ),
    RegExp(
      r'''<div\b[^>]*(?:class|id)=["'][^"']*(?:TRS_Editor|Custom_UnionStyle|zoom|article|content|detail|mainText|news_txt|txt|text)[^"']*["'][^>]*>([\s\S]*)</div>''',
      caseSensitive: false,
    ),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(html)?.group(1);
    if (match != null && _cleanHtml(match).length >= 120) return match;
  }
  return html;
}

String _classifySparseHtml(String html) {
  final lower = html.toLowerCase();
  final attachmentLinks = RegExp(
    r'''<a\b[^>]*href=["'][^"']+\.(?:pdf|xls|xlsx|doc|docx|csv|zip)(?:\?[^"']*)?["'][^>]*>''',
    caseSensitive: false,
  ).allMatches(html).length;
  if (attachmentLinks > 0 ||
      lower.contains('附件') ||
      lower.contains('下载') ||
      lower.contains('download') ||
      lower.contains('attachment')) {
    return 'attachment-only-source';
  }
  final scriptCount = RegExp(
    r'<script\b',
    caseSensitive: false,
  ).allMatches(html).length;
  final linkCount = RegExp(
    r'<a\b',
    caseSensitive: false,
  ).allMatches(html).length;
  final paragraphCount = RegExp(
    r'<p\b',
    caseSensitive: false,
  ).allMatches(html).length;
  if (scriptCount >= 2 && paragraphCount == 0)
    return 'javascript-rendered-list';
  if (linkCount >= 8 && paragraphCount == 0) return 'list-page-without-detail';
  return 'extraction-too-sparse';
}

String _cleanDocumentText(String text) {
  return text
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

Map<String, String>? _extractApiPayload(String raw) {
  try {
    final decoded = jsonDecode(raw);
    final title = _firstJsonString(decoded, const [
      'title',
      'articleTitle',
      'noticeTitle',
      'headline',
      'name',
    ]);
    final dateText = _firstJsonString(decoded, const [
      'publishDate',
      'publishTime',
      'pubDate',
      'date',
      'releaseDate',
      'showTime',
      'time',
    ]);
    final parts = <String>[];
    _collectJsonText(decoded, parts);
    final text = _cleanDocumentText(parts.join('\n'));
    if (text.isEmpty) return null;
    final cleanedTitle = title == null ? null : _cleanHtml(title);
    return {
      if (cleanedTitle != null)
        'title': cleanedTitle.length > 220
            ? cleanedTitle.substring(0, 220)
            : cleanedTitle,
      if (dateText != null && _extractDate(dateText) != null)
        'date': _extractDate(dateText)!,
      'text': text,
    };
  } catch (_) {
    return null;
  }
}

String? _firstJsonString(Object? value, List<String> keys) {
  if (value is List) {
    for (final item in value) {
      final found = _firstJsonString(item, keys);
      if (found != null) return found;
    }
    return null;
  }
  if (value is! Map) return null;
  for (final key in keys) {
    for (final entry in value.entries) {
      if ('${entry.key}'.toLowerCase() == key.toLowerCase() &&
          entry.value is String &&
          '${entry.value}'.trim().isNotEmpty) {
        return '${entry.value}'.trim();
      }
    }
  }
  for (final item in value.values) {
    final found = _firstJsonString(item, keys);
    if (found != null) return found;
  }
  return null;
}

void _collectJsonText(Object? value, List<String> parts, [String key = '']) {
  if (parts.length > 80 || value == null) return;
  if (value is String) {
    final text = _cleanHtml(value);
    if (text.length >= 8 &&
        !RegExp(r'^https?://', caseSensitive: false).hasMatch(text)) {
      parts.add(key.isNotEmpty ? '$key: $text' : text);
    }
    return;
  }
  if (value is num || value is bool) {
    if (key.isNotEmpty) parts.add('$key: $value');
    return;
  }
  if (value is List) {
    for (final item in value) {
      _collectJsonText(item, parts, key);
    }
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      final childKey = '${entry.key}';
      if (RegExp(
        r'^(id|uuid|url|href|link|path|image|img|file)$',
        caseSensitive: false,
      ).hasMatch(childKey)) {
        continue;
      }
      _collectJsonText(entry.value, parts, childKey);
    }
  }
}

String _extractTextFromPdfBytes(List<int> bytes) {
  final latin = latin1.decode(bytes, allowInvalid: true);
  final pieces = <String>[];
  for (final match in RegExp(r'\(([^()]{4,})\)\s*Tj').allMatches(latin)) {
    pieces.add(match.group(1) ?? '');
  }
  for (final match in RegExp(
    r'\[((?:\([^()]*\)\s*){2,})\]\s*TJ',
  ).allMatches(latin)) {
    final body = match.group(1) ?? '';
    for (final item in RegExp(r'\(([^()]*)\)').allMatches(body)) {
      pieces.add(item.group(1) ?? '');
    }
  }
  final simple = pieces
      .join(' ')
      .replaceAll(r'\)', ')')
      .replaceAll(r'\(', '(')
      .trim();
  if (simple.length >= 120) return simple;
  try {
    final document = PdfDocument(inputBytes: bytes);
    try {
      return PdfTextExtractor(document).extractText().trim();
    } finally {
      document.dispose();
    }
  } catch (_) {
    return simple;
  }
}

String _extractTitle(String raw, String cleaned, Map<String, Object?> source) {
  final metaTitle = _extractMetaContent(raw, const [
    'ArticleTitle',
    'article:title',
    'og:title',
    'twitter:title',
    'title',
  ]);
  final h1 = RegExp(
    r'<h1[^>]*>([\s\S]*?)</h1>',
    caseSensitive: false,
  ).firstMatch(raw)?.group(1);
  final title = RegExp(
    r'<title[^>]*>([\s\S]*?)</title>',
    caseSensitive: false,
  ).firstMatch(raw)?.group(1);
  final h2 = RegExp(
    r'<h2[^>]*>([\s\S]*?)</h2>',
    caseSensitive: false,
  ).firstMatch(raw)?.group(1);
  final fallback = cleaned
      .split(RegExp(r'[.!?\n。]'))
      .firstWhere(
        (line) => line.trim().length > 8,
        orElse: () => '${source['providerName']} macro research content',
      );
  final text = _cleanHtml(h1 ?? h2 ?? metaTitle ?? title ?? fallback)
      .replaceAll(
        RegExp(
          "\\s*[-_—|]\\s*(中国人民银行|国家统计局|证监会|外汇管理局|上海证券交易所|深圳证券交易所|香港交易所|People's Bank of China|National Bureau of Statistics).*\\\$",
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'\s*(发布时间|发布日期|发文日期|更新时间|日期|时间|来源)\s*[：:].*$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  return text.length > 220 ? text.substring(0, 220) : text;
}

String? _extractDate(String text) {
  final metaDate = _extractMetaContent(text, const [
    'PubDate',
    'publishdate',
    'publishDate',
    'date',
    'article:published_time',
    'og:pubdate',
  ]);
  if (metaDate != null) {
    final parsed = _extractDateWithoutMeta(metaDate);
    if (parsed != null) return parsed;
  }
  final labeled = RegExp(
    r'(?:发布时间|发布日期|发文日期|更新时间|日期|时间)\s*[：:]\s*(20\d{2})\s*年\s*(0?[1-9]|1[0-2])\s*月\s*(0?[1-9]|[12]\d|3[01])\s*日?',
  ).firstMatch(text);
  if (labeled != null) {
    return '${labeled.group(1)}-${labeled.group(2)!.padLeft(2, '0')}-${labeled.group(3)!.padLeft(2, '0')}';
  }
  return _extractDateWithoutMeta(text);
}

String? _extractDateWithoutMeta(String text) {
  final iso = RegExp(
    r'\b(20\d{2})[-/](0?[1-9]|1[0-2])[-/](0?[1-9]|[12]\d|3[01])\b',
  ).firstMatch(text);
  if (iso != null) {
    return '${iso.group(1)}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}';
  }
  final chinese = RegExp(
    r'\b(20\d{2})\s*年\s*(0?[1-9]|1[0-2])\s*月\s*(0?[1-9]|[12]\d|3[01])\s*日?\b',
  ).firstMatch(text);
  if (chinese != null) {
    return '${chinese.group(1)}-${chinese.group(2)!.padLeft(2, '0')}-${chinese.group(3)!.padLeft(2, '0')}';
  }
  final compact = RegExp(
    r'(?:^|[^\d])(20\d{2})(0[1-9]|1[0-2])([0-3]\d)(?:[^\d]|$)',
  ).firstMatch(text);
  if (compact != null) {
    return '${compact.group(1)}-${compact.group(2)}-${compact.group(3)}';
  }
  final month = RegExp(
    r'\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+([0-3]?\d),\s+(20\d{2})\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (month == null) return null;
  const months = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];
  final m = months.indexOf(month.group(1)!.toLowerCase()) + 1;
  return '${month.group(3)}-${m.toString().padLeft(2, '0')}-${month.group(2)!.padLeft(2, '0')}';
}

String? _extractMetaContent(String raw, List<String> names) {
  for (final name in names) {
    final escaped = RegExp.escape(name);
    final nameFirst = RegExp(
      '<meta\\b[^>]*(?:name|property)=["\\\']$escaped["\\\'][^>]*content=["\\\']([^"\\\']+)["\\\'][^>]*>',
      caseSensitive: false,
    ).firstMatch(raw)?.group(1);
    final contentFirst = RegExp(
      '<meta\\b[^>]*content=["\\\']([^"\\\']+)["\\\'][^>]*(?:name|property)=["\\\']$escaped["\\\'][^>]*>',
      caseSensitive: false,
    ).firstMatch(raw)?.group(1);
    final value = nameFirst ?? contentFirst;
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

List<Map<String, dynamic>> _extractKeyClaims(
  String text,
  Map<String, Object?> source,
  String url,
  String? sourceDate,
  String contentHash,
) {
  final sentences = text
      .split(RegExp(r'(?<=[.!?。])\s+'))
      .map((item) => item.trim())
      .where((item) => item.length > 35)
      .toList();
  final picked = [
    for (var i = 0; i < sentences.take(6).length; i++)
      {'sentence': sentences[i], 'index': i},
  ];
  return [
    for (final item in picked)
      {
        'claim': '${item['sentence']}'.length > 600
            ? '${item['sentence']}'.substring(0, 600)
            : item['sentence'],
        'claimCategory': source['evidenceValue'],
        'mentionedEntities': {
          ..._affectedAssets(source),
          ..._affectedRegions(source),
        }.toList(),
        'citedSource': {'url': url, 'paragraphIndex': item['index']},
        'confidence': 'unassessed',
        'limitation': source['limitation'],
        'sourceUrl': url,
        'sourceDate': sourceDate,
        'contentHash': contentHash,
      },
  ];
}

String _summarize(String text) {
  final sentences = text
      .split(RegExp(r'(?<=[.!?。])\s+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .take(3)
      .join(' ');
  return sentences.length > 900 ? sentences.substring(0, 900) : sentences;
}

String? _writeContentArtifact(
  String basePath,
  String provider,
  String hash,
  String contentType,
  String text,
) {
  if (basePath.isEmpty) return null;
  final dir = Directory('$basePath/data/macro_research_content/$provider');
  dir.createSync(recursive: true);
  final ext = contentType == 'pdf_text' ? 'txt' : 'html.txt';
  final path = '${dir.path}/${hash.substring(0, 16)}.$ext';
  File(path).writeAsStringSync(text);
  return path;
}

String? _contentFamily(Map<String, Object?> source) {
  final value = '${source['evidenceValue']}';
  if ([
    'research_narrative',
    'allocation_regime',
    'rates_credit_context',
  ].contains(value)) {
    return 'macro_research_document';
  }
  if (value == 'official_index_event') return 'macro_index_event';
  if (value == 'official_policy_event') return 'macro_policy_event';
  if (value == 'official_macro_fact') return 'macro_official_series';
  if (value.contains('commodity') && _isExtractableSource(source)) {
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

List<String> _mentionedAssets(String _, Map<String, Object?> source) =>
    _affectedAssets(source);

List<String> _mentionedRegions(String _, Map<String, Object?> source) =>
    _affectedRegions(source);

List<String> _mentionedSectors(String _, Map<String, Object?> source) =>
    (source['categories'] as List).cast<String>();

List<String> _affectedAssets(Map<String, Object?> source) =>
    switch ('${source['evidenceValue']}') {
      'official_index_event' => const ['index/passive flows'],
      'official_policy_event' => const ['macro policy'],
      'official_macro_fact' => const ['macro indicators'],
      'commodity_supply_chain' ||
      'commodity_market_structure' => const ['commodities'],
      'rates_credit_context' => const ['rates/bonds'],
      'allocation_regime' => const ['multi-asset'],
      _ => const ['global macro'],
    };

List<String> _affectedRegions(Map<String, Object?> source) =>
    const {'bea', 'fred', 'bls'}.contains('${source['provider']}')
    ? const ['United States']
    : const ['global'];

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
  if ((source['categories'] as List).any(
    (item) => '$item'.contains('rates') || '$item'.contains('credit'),
  )) {
    channels.add('rates liquidity');
  }
  if ((source['categories'] as List).any(
    (item) => '$item'.contains('policy') || '$item'.contains('regulation'),
  )) {
    channels.add('policy/regulation');
  }
  if ((source['categories'] as List).any(
    (item) =>
        '$item'.contains('fx') ||
        '$item'.contains('capital_flow') ||
        '$item'.contains('external_balance'),
  )) {
    channels.add('fx/cross-border flows');
  }
  return channels;
}

Map<String, dynamic> _extractionProvenance(String readbackAction) {
  return {
    'interfaceId': 'macro.research_content_extraction',
    'providerId': 'local',
    'provider': 'local',
    'capabilityId': 'local.$readbackAction',
    'providerMode': 'source-specific-extraction',
    'cacheStatus': 'content-hash-readback',
    'cacheDecision':
        'reuse extracted source content when content hash/source date match',
    'canonicalSchema': 'market_moving_factor_v1',
    'canonicalTable': 'market_moving_factor',
    'readbackAction': readbackAction,
    'source': 'allowed macro research source catalog',
    'fetchedAt': DateTime.now().toUtc().toIso8601String(),
  };
}

String _classifyExtractionError(Object error) {
  if (error is _MacroExtractionException) return error.failureClass;
  if (error is TimeoutException) return 'transport-timeout';
  return 'extraction-failed';
}

class _MacroExtractionException implements Exception {
  const _MacroExtractionException(this.failureClass, this.message);

  final String failureClass;
  final String message;

  @override
  String toString() => message;
}

String _sha256(String value) {
  return sha256.convert(utf8.encode(value)).toString();
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
  if (parsed == null || parsed < 0) return null;
  return parsed;
}

bool _matches(Object? value, String filter) {
  return '${value ?? ''}'.toLowerCase().contains(filter.toLowerCase());
}
