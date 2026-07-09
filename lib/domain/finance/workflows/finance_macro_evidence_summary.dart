import 'dart:convert';

import '../../../agent/message.dart';

/// Finance-owned macro evidence summary for bounded workflow stops.
///
/// This reads structured MarketData tool results. It does not infer intent from
/// the prompt or assistant prose.
class FinanceMacroEvidenceSummary {
  String? build({
    required List<Message> messages,
    required int turnStartIndex,
    required String failureSummary,
    String? suffix,
  }) {
    final evidence = collect(messages, turnStartIndex);
    if (!evidence.hasMacroEvidence || !evidence.hasActionableMacroEvidence) {
      return null;
    }
    final lines = <String>[
      '已达到本轮受控数据调用预算，下面直接使用已经取得的宏观证据作答；未继续调用更多 provider、文件、脚本或交易工具。',
      '',
      ...buildSection(evidence),
      '',
      '## 回测 / 策略边界',
      '',
      '- 宏观研究、政策、商品、利率和资金流证据只能作为策略假设、观察条件或失效条件。',
      '- 这些证据不能直接编译成可执行交易信号；如果要进入回测，需要先把可量化变量改写为 StrategySpec 支持的指标、阈值、数据窗口和风险规则。',
      '- 本轮没有执行下单、保存策略或把宏观观点硬塞进交易信号。',
      '',
      '## 本轮限制',
      '',
      '- $failureSummary',
      if (suffix != null && suffix.trim().isNotEmpty) '- ${suffix.trim()}',
    ];
    return lines.join('\n');
  }

  List<String> buildSection(MacroEvidence evidence) {
    final lines = <String>['## 宏观证据与来源状态', ''];
    if (evidence.factorLines.isEmpty) {
      lines.add(
        '- 宏观因子：本轮没有命中可复用 `market_moving_factor_v1` 行；这表示证据缺口，不表示宏观因素无关。',
      );
    } else {
      lines.add('- 宏观因子：${evidence.factorLines.take(3).join('；')}。');
    }
    if (evidence.contextLines.isNotEmpty) {
      lines.add('- 分析对象/口径：${evidence.contextLines.take(4).join('；')}。');
    }
    if (evidence.nonMacroLines.isNotEmpty) {
      lines.add('- 非宏观证据状态：${evidence.nonMacroLines.take(6).join('；')}。');
    }
    if (evidence.sourceLines.isNotEmpty) {
      lines.add('- 来源目录读回：${evidence.sourceLines.take(4).join('；')}。');
    }
    if (evidence.contentLines.isNotEmpty) {
      lines.add('- 内容证据：${evidence.contentLines.take(3).join('；')}。');
    }
    if (evidence.evidenceLines.isNotEmpty) {
      lines.add('- 访问/检索证据：${evidence.evidenceLines.take(4).join('；')}。');
    }
    if (evidence.newsLines.isNotEmpty) {
      final newsLabel = evidence.hasNewsRefresh ? '新闻刷新与读回' : '新闻线索读回';
      lines.add(
        '- $newsLabel：${evidence.newsLines.take(4).join('；')}。新闻只作为发现和当前事件线索，不能替代官方数据或内容级研究证据。',
      );
    }
    if (evidence.missingLines.isNotEmpty) {
      lines.add('- 不确定性/数据缺口：${evidence.missingLines.take(4).join('；')}。');
    }
    lines.addAll([
      '',
      '## 宏观假设和失效条件',
      '',
      '- 利率/流动性：如果政策利率、资金利率或期限利差与当前假设相反，股票、债券基金或策略结论需要重新验证。',
      '- 信用：如果信用利差、违约风险、融资环境或评级迁移证据与当前假设相反，债券基金和信用类资产结论需要重新验证。',
      '- 商品/能源：如果商品库存、关税、供需或能源价格出现反向变化，资源品、制造业成本和风险偏好判断需要重估。',
      '- 外资/指数事件：如果指数公司调整、被动资金流或跨境流动证据缺失，应把相关结论降级为观察假设。',
      '- 政策/监管：官方政策和交易所规则应作为独立证据层，不能用研究文章替代。',
      '- 更新要求：在保存、复跑或监控策略前，应先更新宏观来源目录、新闻线索和可用官方/研究证据，并重新读回证据层级。',
    ]);
    return lines;
  }

  MacroEvidence collect(List<Message> messages, int turnStartIndex) {
    final factorLines = <String>[];
    final contextLines = <String>[];
    final sourceLines = <String>[];
    final contentLines = <String>[];
    final evidenceLines = <String>[];
    final newsLines = <String>[];
    final missingLines = <String>[];
    final nonMacroLines = <String>[];
    var sawMacroAction = false;
    var hasNewsRefresh = false;

    for (final message in messages.skip(turnStartIndex)) {
      if (message.role == Role.assistant) {
        for (final call in message.toolUses ?? const <ToolUse>[]) {
          final action = _text(call.input['action']);
          if (action.contains('macro')) {
            contextLines.addAll(_callContextLines(call.input));
          } else if (action == 'finance_news') {
            hasNewsRefresh = true;
            contextLines.addAll(_callContextLines(call.input));
          } else {
            final line = _nonMacroCallLine(call.name, call.input);
            if (line.isNotEmpty) nonMacroLines.add(line);
          }
        }
        continue;
      }
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final content = result.content.trim();
      final financeNewsLine = _financeNewsResultLine(content);
      if (financeNewsLine.isNotEmpty) {
        hasNewsRefresh = true;
        newsLines.add(financeNewsLine);
        continue;
      }
      if (!content.startsWith('{')) continue;
      try {
        final decoded = jsonDecode(content);
        if (decoded is! Map<String, dynamic>) continue;
        final action = '${decoded['action'] ?? ''}';
        if (action == 'query_finance_news') {
          final line = _financeNewsPayloadLine(decoded);
          if (line.isNotEmpty) newsLines.add(line);
          continue;
        }
        if (!action.contains('macro')) {
          final line = _nonMacroResultLine(decoded);
          if (line.isNotEmpty) nonMacroLines.add(line);
          continue;
        }
        sawMacroAction = true;
        final status = '${decoded['status'] ?? ''}';
        if (status == 'missing') {
          final reason = _text(decoded['missingReason']);
          if (reason.isNotEmpty) missingLines.add('$action: $reason');
        }
        switch (action) {
          case 'query_macro_factors':
            factorLines.addAll(_factorRows(decoded));
            break;
          case 'macro_research_sources':
            sourceLines.addAll(_sourceRows(decoded));
            break;
          case 'query_macro_research_content':
            contentLines.addAll(_contentRows(decoded));
            break;
          case 'query_macro_research_evidence':
          case 'macro_research_provenance':
          case 'macro_research_extract':
          case 'macro_research_extraction_status':
            evidenceLines.addAll(_evidenceRows(decoded));
            break;
        }
      } catch (_) {
        continue;
      }
    }
    return MacroEvidence(
      hasMacroEvidence: sawMacroAction,
      hasNewsRefresh: hasNewsRefresh,
      contextLines: _dedupe(contextLines),
      nonMacroLines: _dedupe(nonMacroLines),
      factorLines: _dedupe(factorLines),
      sourceLines: _dedupe(sourceLines),
      contentLines: _dedupe(contentLines),
      evidenceLines: _dedupe(evidenceLines),
      newsLines: _dedupe(newsLines),
      missingLines: _dedupe(missingLines),
    );
  }

  List<String> _factorRows(Map<String, dynamic> payload) {
    final rows = payload['rows'];
    if (rows is! List || rows.isEmpty) return const [];
    return rows
        .whereType<Map>()
        .map((row) {
          final title = _text(
            row['title'] ?? row['factor_name'] ?? row['factorId'],
          );
          final family = _text(row['family']);
          final source = _text(row['source'] ?? row['provider']);
          final time = _text(row['sourceDataTime'] ?? row['source_time']);
          return [
            title,
            family,
            source,
            time,
          ].where((v) => v.isNotEmpty).join(' / ');
        })
        .where((line) => line.isNotEmpty)
        .toList();
  }

  List<String> _callContextLines(Map<String, dynamic> input) {
    return [
      _targetLabel(_text(input['target'])),
      _targetLabel(_text(input['assets'])),
      _targetLabel(_text(input['symbol'])),
      _targetLabel(_text(input['code'])),
      _familyLabel(_text(input['family'])),
      _familyLabel(_text(input['category'])),
    ].where((value) => value.isNotEmpty).toList();
  }

  String _nonMacroCallLine(String toolName, Map<String, dynamic> input) {
    if (toolName == 'Watchlist') {
      final action = _text(input['action']);
      if (action == 'list' || action == 'list_groups') {
        return '自选股: 已请求 $action，需以工具结果或本地读回为准';
      }
      return '';
    }
    if (toolName != 'DataStore' && toolName != 'MarketData') return '';
    final action = _text(input['action']);
    final label = _actionLabel(action);
    if (label.isEmpty) return '';
    final target = _text(input['code']).isNotEmpty
        ? _text(input['code'])
        : _text(input['symbol']).isNotEmpty
        ? _text(input['symbol'])
        : _listText(input['symbols']).isNotEmpty
        ? _listText(input['symbols'])
        : _listText(input['codes']).isNotEmpty
        ? _listText(input['codes'])
        : _text(input['type']);
    return '$label: 已请求${target.isNotEmpty ? ' $target' : ''}，需以工具结果或本地读回为准';
  }

  String _nonMacroResultLine(Map<String, dynamic> payload) {
    final action = _text(payload['action']);
    final label = _actionLabel(action);
    if (label.isEmpty) return '';
    final rows = payload['rows'];
    final count = _text(payload['count']).isNotEmpty
        ? _text(payload['count'])
        : rows is List
        ? '${rows.length}'
        : '';
    final status = _text(payload['status']);
    final source = _text(payload['source'] ?? payload['provider']);
    final code = _text(payload['code'] ?? payload['symbol']);
    final detail = [
      code,
      if (source.isNotEmpty) 'source=$source',
      if (status.isNotEmpty) 'status=$status',
      if (count.isNotEmpty) 'count=$count',
    ].where((value) => value.isNotEmpty).join(' / ');
    return detail.isEmpty ? '$label: 已返回结构化结果' : '$label: $detail';
  }

  String _actionLabel(String action) {
    const labels = {
      'query_quote': '个股行情',
      'query_index_quote': '指数/市场技术面',
      'query_kline': 'K 线/技术面',
      'query_sector_ranking': '板块热度',
      'query_flow_rank': '资金流向',
      'query_northbound_flow': '北向资金',
      'query_fund_nav': '基金净值',
      'query_fund_money_yield': '货币基金收益',
      'query_fund_holding': '基金持仓',
      'query_stock_company_info': '自选股公司信息',
      'query_fund_company_info': '基金公司信息',
    };
    if (labels.containsKey(action)) return labels[action]!;
    if (action == 'fetch') return '数据刷新';
    return '';
  }

  String _listText(Object? value) {
    return value is List
        ? value.map(_text).where((v) => v.isNotEmpty).join(',')
        : '';
  }

  String _targetLabel(String value) {
    if (value.isEmpty) return '';
    if (value.contains(',')) {
      return value
          .split(',')
          .map((item) => _targetLabel(item.trim()))
          .where((item) => item.isNotEmpty)
          .join('；');
    }
    if (RegExp(r'^a[-_ ]?shares$', caseSensitive: false).hasMatch(value)) {
      return 'A 股';
    }
    if (value.toLowerCase() == 'china equities') return '中国股票 / A 股相关';
    if (RegExp(r'^bond funds?$', caseSensitive: false).hasMatch(value)) {
      return '债券基金';
    }
    if (value.toLowerCase() == 'moutai' ||
        value.toLowerCase() == 'kweichow moutai') {
      return '贵州茅台 / Moutai';
    }
    if (value == '600519') return '贵州茅台 600519';
    if (value.toLowerCase() == 'chinese spirits') return '白酒';
    if (value.toLowerCase() == 'china consumption') return '中国消费';
    if (value.toLowerCase() == 'china liquor regulation') return '白酒监管';
    return value;
  }

  String _familyLabel(String value) {
    const labels = {
      'rates_liquidity': '利率/流动性',
      'policy_regulation': '政策/监管',
      'narrative_attention': '叙事/关注度',
      'commodity_research': '商品/能源',
      'index_classification': '指数/被动资金',
    };
    return labels[value] ?? value;
  }

  List<String> _sourceRows(Map<String, dynamic> payload) {
    final rows = payload['rows'];
    if (rows is! List || rows.isEmpty) return const [];
    return rows
        .whereType<Map>()
        .map((row) {
          final name = _text(row['providerName'] ?? row['provider']);
          final access = _text(row['accessClass'] ?? row['automationPolicy']);
          final categories = row['categories'] is List
              ? (row['categories'] as List).take(3).join(',')
              : _text(row['category']);
          final bucket = _sourceBucket(row);
          return [
            bucket,
            name,
            categories,
            access,
          ].where((v) => v.isNotEmpty).join(' / ');
        })
        .where((line) => line.isNotEmpty)
        .toList();
  }

  String _sourceBucket(Map row) {
    final values = [
      row['provider'],
      row['providerName'],
      row['accessClass'],
      row['automationPolicy'],
      row['sourceType'],
      row['kind'],
      row['category'],
      if (row['categories'] is List) ...(row['categories'] as List),
    ].map(_text).join(' ').toLowerCase();
    final restricted = RegExp(
      r'(licensed|blocked|manual|anti[- ]?bot|security|restricted|gated|paywall)',
    ).hasMatch(values);
    final research = RegExp(
      r'(research|insight|public-html|pdf|institutional|blackrock|pimco|jpmorgan|goldman|msci|ftse|s&p|cme)',
    ).hasMatch(values);
    if (RegExp(
      r'(official|government|central bank|regulator|exchange|api|pbo[c]?|nbs|safe|csrc|fred|bea|world bank|imf|bis|eia|opec|iea)',
    ).hasMatch(values)) {
      return '官方来源';
    }
    if (RegExp(r'(news|feed|search)').hasMatch(values)) return '新闻来源';
    if (research && restricted) return '研究来源(受限)';
    if (research) {
      return '研究来源';
    }
    if (restricted) return '受限来源';
    return '来源';
  }

  List<String> _contentRows(Map<String, dynamic> payload) {
    final rows =
        payload['contentEvidence'] is List &&
            (payload['contentEvidence'] as List).isNotEmpty
        ? payload['contentEvidence']
        : payload['rows'];
    if (rows is! List || rows.isEmpty) return const [];
    return rows
        .whereType<Map>()
        .map((row) {
          final title = _text(row['title'] ?? row['factor_name']);
          final provider = _text(
            row['provider'] ?? row['source'] ?? row['sourceName'],
          );
          final date = _text(row['sourceDate'] ?? row['sourceDataTime']);
          final hash = _text(row['contentHash']);
          final claims = row['keyClaims'] is List
              ? (row['keyClaims'] as List).take(2).join('；')
              : _text(row['keyClaims']);
          final preview = _text(row['bodyPreview']);
          return [
            if (title.isNotEmpty) title,
            if (provider.isNotEmpty) provider,
            if (date.isNotEmpty) date,
            if (hash.isNotEmpty)
              'hash=${hash.length > 12 ? hash.substring(0, 12) : hash}',
            if (claims.isNotEmpty) claims,
            if (preview.isNotEmpty)
              'preview=${preview.length > 120 ? preview.substring(0, 119) : preview}',
          ].join(' / ');
        })
        .where((line) => line.isNotEmpty)
        .toList();
  }

  List<String> _evidenceRows(Map<String, dynamic> payload) {
    final rows = payload['rows'];
    final lines = <String>[];
    if (rows is List) {
      for (final row in rows.whereType<Map>().take(8)) {
        final provider = _text(row['provider'] ?? row['source']);
        final family = _text(row['family']);
        final status = _text(row['status'] ?? row['failure_class']);
        final limitation = _text(row['limitation'] ?? row['missingReason']);
        final line = [
          provider,
          family,
          status,
          limitation,
        ].where((v) => v.isNotEmpty).join(' / ');
        if (line.isNotEmpty) lines.add(line);
      }
    }
    final generated = _text(payload['generatedRows']);
    if (generated.isNotEmpty)
      lines.add('${payload['action']}: generatedRows=$generated');
    final extracted = _text(payload['extracted']);
    if (extracted.isNotEmpty)
      lines.add('${payload['action']}: extracted=$extracted');
    return lines;
  }

  String _financeNewsResultLine(String content) {
    final lines = content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty || !lines.first.startsWith('finance_news |')) return '';
    final header = lines.first;
    final source = _headerValue(header, 'provider');
    final asOf = _headerValue(header, 'asOf');
    final fetchedAt = _headerValue(header, 'fetchedAt');
    final headlines = lines.skip(1).take(2).map(_compact).join('；');
    return [
      if (source.isNotEmpty) 'provider=$source' else 'provider=finance_news',
      if (asOf.isNotEmpty) 'sourceTime=$asOf',
      if (fetchedAt.isNotEmpty) 'fetchedAt=$fetchedAt / 获取时间=$fetchedAt',
      'evidenceTier=linked_news_evidence',
      'limitation=news_clue_not_official_fact',
      if (headlines.isNotEmpty) headlines,
    ].join(' / ');
  }

  String _financeNewsPayloadLine(Map<String, dynamic> payload) {
    final rows = payload['data'] is List
        ? (payload['data'] as List).whereType<Map>().toList(growable: false)
        : const <Map>[];
    final sourceDataTime = _text(payload['sourceDataTime']);
    final fetchedAt = _text(payload['fetchedAt']);
    final query = _text(payload['query'] ?? payload['keyword']);
    final headlines = rows
        .take(2)
        .map((row) {
          return _compact(
            [
              _text(row['published_at']),
              if (_text(row['source']).isNotEmpty) '[${_text(row['source'])}]',
              _text(row['title']),
              _text(row['url']),
            ].where((value) => value.isNotEmpty).join(' '),
          );
        })
        .join('；');
    if (rows.isEmpty && sourceDataTime.isEmpty && fetchedAt.isEmpty) {
      return query.isNotEmpty
          ? 'query=$query / cacheStatus=${_text(payload['cacheStatus'])} / evidenceTier=linked_news_evidence / limitation=target_news_query_miss'
          : '';
    }
    return [
      if (query.isNotEmpty) 'query=$query',
      if (sourceDataTime.isNotEmpty) 'sourceTime=$sourceDataTime',
      if (fetchedAt.isNotEmpty) 'fetchedAt=$fetchedAt / 获取时间=$fetchedAt',
      'count=${_text(payload['count']).isNotEmpty ? _text(payload['count']) : rows.length}',
      'evidenceTier=linked_news_evidence',
      'limitation=news_clue_not_official_fact',
      if (headlines.isNotEmpty) headlines,
    ].join(' / ');
  }

  String _headerValue(String header, String key) {
    final match = RegExp('\\|\\s*$key:([^|]+)').firstMatch(header);
    return match?.group(1)?.trim() ?? '';
  }

  String _compact(String value) {
    final oneLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length > 120 ? '${oneLine.substring(0, 119)}...' : oneLine;
  }

  List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (value.trim().isNotEmpty && seen.add(value.trim())) value.trim(),
    ];
  }

  String _text(Object? value) => '${value ?? ''}'.trim();
}

class MacroEvidence {
  const MacroEvidence({
    required this.hasMacroEvidence,
    required this.hasNewsRefresh,
    required this.contextLines,
    required this.nonMacroLines,
    required this.factorLines,
    required this.sourceLines,
    required this.contentLines,
    required this.evidenceLines,
    required this.newsLines,
    required this.missingLines,
  });

  final bool hasMacroEvidence;
  final bool hasNewsRefresh;
  final List<String> contextLines;
  final List<String> nonMacroLines;
  final List<String> factorLines;
  final List<String> sourceLines;
  final List<String> contentLines;
  final List<String> evidenceLines;
  final List<String> newsLines;
  final List<String> missingLines;

  bool get hasActionableMacroEvidence =>
      factorLines.isNotEmpty ||
      sourceLines.isNotEmpty ||
      contentLines.isNotEmpty ||
      evidenceLines.isNotEmpty ||
      newsLines.isNotEmpty;
}
