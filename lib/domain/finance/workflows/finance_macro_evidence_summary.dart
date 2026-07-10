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
    if (_hasFundContext(evidence)) {
      lines.add(
        '- 基金分类口径：消费基金关注消费复苏、居民收入、白酒/零售政策和风险偏好；科技基金关注流动性、产业政策、外部限制和成长股估值折现率；债券基金关注利率、信用、流动性和久期风险。缺失任一类别的高等级证据时，应降低对应结论置信度。',
      );
    }
    if (evidence.nonMacroLines.isNotEmpty) {
      lines.add(
        '- 非宏观证据状态：${_sortEvidenceLines(evidence.nonMacroLines).take(12).join('；')}。',
      );
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
    if (evidence.reliabilityLines.isNotEmpty) {
      lines.add(
        '- 可靠性（证据等级/新鲜度/访问/置信度）：${evidence.reliabilityLines.take(5).join('；')}。',
      );
    }
    if (evidence.assetImpactLines.isNotEmpty) {
      lines.add(
        '- 资产影响（行业/基金/策略口径）：${evidence.assetImpactLines.take(5).join('；')}。',
      );
    }
    if (evidence.decisionLines.isNotEmpty) {
      lines.add('- 置信度/下一步：${evidence.decisionLines.take(5).join('；')}。');
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
    final reliabilityLines = <String>[];
    final assetImpactLines = <String>[];
    final decisionLines = <String>[];
    final nonMacroLines = <String>[];
    var sawMacroAction = false;
    var hasNewsRefresh = false;
    final toolCallsById = <String, ToolUse>{};

    for (final message in messages.skip(turnStartIndex)) {
      if (message.role != Role.assistant) continue;
      for (final call in message.toolUses ?? const <ToolUse>[]) {
        toolCallsById[call.id] = call;
      }
    }

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
      if (!content.startsWith('{')) {
        final call = toolCallsById[result.toolUseId];
        final line = call == null
            ? _nonMacroTextResultLineFromContent(content)
            : _nonMacroTextResultLine(call, content);
        if (line.isNotEmpty) nonMacroLines.add(line);
        continue;
      }
      try {
        final decoded = jsonDecode(content);
        if (decoded is! Map<String, dynamic>) continue;
        final action = '${decoded['action'] ?? ''}';
        if (action == 'query_finance_news') {
          final line = _financeNewsPayloadLine(decoded);
          if (line.isNotEmpty) newsLines.add(line);
          reliabilityLines.addAll(
            _reliabilityRows(decoded, fallbackTier: 'linked_news_evidence'),
          );
          assetImpactLines.addAll(_assetImpactRows(decoded));
          decisionLines.addAll(
            _decisionRows(decoded, fallbackTier: 'linked_news_evidence'),
          );
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
        reliabilityLines.addAll(_reliabilityRows(decoded));
        assetImpactLines.addAll(_assetImpactRows(decoded));
        decisionLines.addAll(_decisionRows(decoded));
        switch (action) {
          case 'query_macro_factors':
          case 'query_macro_numeric_series':
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
      reliabilityLines: _dedupe(reliabilityLines),
      assetImpactLines: _dedupe(assetImpactLines),
      decisionLines: _dedupe(decisionLines),
    );
  }

  List<String> _factorRows(Map<String, dynamic> payload) {
    final rows = _macroRows(payload);
    if (rows.isEmpty) return const [];
    return rows
        .whereType<Map>()
        .map((row) {
          final title = _text(
            row['title'] ??
                row['factor_name'] ??
                row['factorId'] ??
                row['metricName'] ??
                row['seriesId'],
          );
          final family = _text(row['family']);
          final source = _text(row['source'] ?? row['provider']);
          final time = _text(row['sourceDataTime'] ?? row['source_time']);
          final value = _text(row['value']);
          final unit = _text(row['unit']);
          return [
            title,
            family,
            source,
            time,
            if (value.isNotEmpty)
              'value=$value${unit.isNotEmpty ? ' $unit' : ''}',
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
    final evidenceDetail = _structuredEvidenceDetail(action, payload);
    if (evidenceDetail.isNotEmpty) return '$label: $evidenceDetail';
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

  String _nonMacroTextResultLine(ToolUse call, String content) {
    if (RegExp(r'^\s*Skipped:', caseSensitive: false).hasMatch(content)) {
      return '';
    }
    if (call.name != 'DataStore' &&
        call.name != 'MarketData' &&
        call.name != 'DataProcess') {
      return '';
    }
    final action = _text(call.input['action']);
    final label = _actionLabel(action).isNotEmpty
        ? _actionLabel(action)
        : _dataProcessActionLabel(action);
    if (label.isEmpty) return '';
    final code = _text(call.input['code']).isNotEmpty
        ? _text(call.input['code'])
        : _text(call.input['symbol']).isNotEmpty
        ? _text(call.input['symbol'])
        : _extractCode(content);
    final provenance = _extractProvenance(content);
    final facts = _extractEvidenceFacts(action, content);
    final parts = [
      code,
      provenance,
      facts,
    ].where((value) => value.isNotEmpty).join(' / ');
    return parts.isEmpty ? '$label: 已返回工具结果' : '$label: $parts';
  }

  String _nonMacroTextResultLineFromContent(String content) {
    if (RegExp(r'^\s*Skipped:', caseSensitive: false).hasMatch(content)) {
      return '';
    }
    final action = _inferActionFromContent(content);
    if (action.isEmpty) return '';
    final label = _actionLabel(action).isNotEmpty
        ? _actionLabel(action)
        : _dataProcessActionLabel(action);
    if (label.isEmpty) return '';
    final code = _extractCode(content);
    final provenance = _extractProvenance(content);
    final facts = _extractEvidenceFacts(action, content);
    final parts = [
      code,
      provenance,
      facts,
    ].where((value) => value.isNotEmpty).join(' / ');
    return parts.isEmpty ? '$label: 已返回工具结果' : '$label: $parts';
  }

  String _inferActionFromContent(String content) {
    if (RegExp(
          r'interface:stock\.quote\b',
          caseSensitive: false,
        ).hasMatch(content) ||
        RegExp(
          r'\bquote snapshots\b',
          caseSensitive: false,
        ).hasMatch(content)) {
      return 'query_quote';
    }
    if (RegExp(
          r'interface:stock\.daily_kline\b',
          caseSensitive: false,
        ).hasMatch(content) ||
        RegExp(r'\bdaily kline\b', caseSensitive: false).hasMatch(content)) {
      return 'query_kline';
    }
    if (RegExp(
          r'interface:stock\.daily_valuation\b',
          caseSensitive: false,
        ).hasMatch(content) ||
        RegExp(r'\bfundamentals\b', caseSensitive: false).hasMatch(content)) {
      return 'query_fundamental';
    }
    if (RegExp(
          r'interface:market\.sector_ranking\b',
          caseSensitive: false,
        ).hasMatch(content) ||
        RegExp(r'\bSector ranking\b', caseSensitive: false).hasMatch(content)) {
      return 'query_sector_ranking';
    }
    return '';
  }

  String _dataProcessActionLabel(String action) {
    const labels = {
      'summary': '技术摘要',
      'indicators': '技术指标',
      'support_summary': '支撑阻力',
      'volume_analysis': '量能分析',
    };
    return labels[action] ?? '';
  }

  String _extractCode(String content) {
    return RegExp(r'\b\d{6}\b').firstMatch(content)?.group(0) ?? '';
  }

  String _extractProvenance(String content) {
    String match(String pattern) =>
        RegExp(pattern).firstMatch(content)?.group(1)?.trim() ?? '';
    final interfaceId = match(r'interface:([^|\n]+)');
    final provider = match(r'provider:([^|\n]+)');
    final cache = match(r'cacheStatus:([^|\n]+)');
    final asOf = match(r'asOf:([^|\n]+)');
    final fetchedAt = match(r'fetchedAt:([^|\n]+)');
    return [
      if (interfaceId.isNotEmpty) 'interface=$interfaceId',
      if (provider.isNotEmpty) 'provider=$provider',
      if (cache.isNotEmpty) 'cache=$cache',
      if (asOf.isNotEmpty) 'asOf=$asOf',
      if (fetchedAt.isNotEmpty) 'fetchedAt=$fetchedAt',
    ].join(' / ');
  }

  String _extractEvidenceFacts(String action, String content) {
    final compacted = _compact(content.replaceAll(RegExp(r'\s+'), ' '));
    if (action == 'query_kline' || action == 'kline') {
      final bars = RegExp(
        r'(\d+)\s+bars',
        caseSensitive: false,
      ).firstMatch(content)?.group(1);
      final window = RegExp(
        r'\((\d{4}-\d{2}-\d{2}\s*~\s*\d{4}-\d{2}-\d{2})\)',
      ).firstMatch(content)?.group(1);
      return _orFallback([
        if (bars != null) '$bars bars',
        if (window != null) window,
      ], compacted);
    }
    if (action == 'query_fundamental') {
      final pe = RegExp(r'\bPE:([^\s]+)').firstMatch(content)?.group(1);
      final pb = RegExp(r'\bPB:([^\s]+)').firstMatch(content)?.group(1);
      final roe = RegExp(r'\bROE:([^\s]+)').firstMatch(content)?.group(1);
      final report = RegExp(
        r'(\d{4}-\d{2}-\d{2})',
      ).firstMatch(content)?.group(1);
      return _orFallback([
        if (report != null) 'report=$report',
        if (pe != null) 'PE=$pe',
        if (pb != null) 'PB=$pb',
        if (roe != null) 'ROE=$roe',
      ], compacted);
    }
    if (action == 'quote' || action == 'query_quote') {
      final price = RegExp(
        r'(?:price|Price|最新价|C):\s*([0-9.]+)',
      ).firstMatch(content)?.group(1);
      final change = RegExp(
        r'(?:change|涨幅|Chg):\s*([+\-0-9.]+%?)',
      ).firstMatch(content)?.group(1);
      return _orFallback([
        if (price != null) 'price=$price',
        if (change != null) 'change=$change',
      ], compacted);
    }
    if (action == 'summary' || action == 'indicators') {
      final signal = RegExp(
        r'"overall"\s*:\s*"([^"]+)"',
      ).firstMatch(content)?.group(1);
      final rsi = RegExp(
        r'RSI(?:\(14\))?[:=]\s*([0-9.]+)',
        caseSensitive: false,
      ).firstMatch(content)?.group(1);
      return _orFallback([
        if (signal != null) 'signal=$signal',
        if (rsi != null) 'RSI=$rsi',
      ], compacted);
    }
    return compacted;
  }

  String _structuredEvidenceDetail(
    String action,
    Map<String, dynamic> payload,
  ) {
    if (action == 'score_technical') {
      return [
        _text(payload['code']),
        if (_text(payload['score']).isNotEmpty)
          'score=${_text(payload['score'])}',
        if (_text(payload['grade']).isNotEmpty)
          'grade=${_text(payload['grade'])}',
        if (_text(payload['signal']).isNotEmpty)
          'signal=${_text(payload['signal'])}',
        if (_text(payload['rsi']).isNotEmpty) 'RSI=${_text(payload['rsi'])}',
      ].where((value) => value.isNotEmpty).join(' / ');
    }
    return '';
  }

  String _actionLabel(String action) {
    const labels = {
      'quote': '个股行情',
      'kline': 'K 线/技术面',
      'money_flow': '资金流向',
      'query_quote': '个股行情',
      'query_index_quote': '指数/市场技术面',
      'query_kline': 'K 线/技术面',
      'query_fundamental': '基本面/估值',
      'query_money_flow': '资金流向',
      'query_sector_ranking': '板块热度',
      'query_flow_rank': '资金流向',
      'query_northbound_flow': '北向资金',
      'query_fund_nav': '基金净值',
      'query_fund_money_yield': '货币基金收益',
      'query_fund_holding': '基金持仓',
      'query_stock_company_info': '自选股公司信息',
      'query_fund_company_info': '基金公司信息',
      'summary': '技术摘要',
      'score_technical': '技术评分',
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
    if (RegExp(r'^consumption funds?$', caseSensitive: false).hasMatch(value)) {
      return '消费基金';
    }
    if (value.toLowerCase() == 'consumer equities') return '消费基金/消费权益';
    if (RegExp(r'^technology funds?$', caseSensitive: false).hasMatch(value)) {
      return '科技基金';
    }
    if (value.toLowerCase() == 'technology equities') return '科技基金/科技权益';
    if (RegExp(r'^equity funds?$', caseSensitive: false).hasMatch(value)) {
      return '权益基金';
    }
    if (RegExp(r'^index funds?$', caseSensitive: false).hasMatch(value)) {
      return '指数基金';
    }
    if (RegExp(r'^money funds?$', caseSensitive: false).hasMatch(value)) {
      return '货币基金';
    }
    if (RegExp(r'^industry funds?$', caseSensitive: false).hasMatch(value)) {
      return '行业基金';
    }
    if (RegExp(r'^(stock|equity)$', caseSensitive: false).hasMatch(value)) {
      return '股票/权益';
    }
    if (RegExp(r'^funds?$', caseSensitive: false).hasMatch(value)) {
      return '基金';
    }
    if (value.toLowerCase() == 'strategy') return '策略';
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
      'risk_appetite': '风险偏好',
      'macro_official_series': '官方宏观数值序列',
      'official_macro_fact': '官方宏观事实',
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

  List<String> _reliabilityRows(
    Map<String, dynamic> payload, {
    String fallbackTier = '',
  }) {
    return _evidenceCandidateRows(payload)
        .map((row) {
          final tier =
              _text(row['evidenceTier'] ?? row['evidence_tier']).isNotEmpty
              ? _text(row['evidenceTier'] ?? row['evidence_tier'])
              : fallbackTier.isNotEmpty
              ? fallbackTier
              : _tierForRow(row);
          final sourceType =
              _text(row['sourceType'] ?? row['source_type']).isNotEmpty
              ? _text(row['sourceType'] ?? row['source_type'])
              : _sourceTypeForTier(tier);
          final source =
              _text(
                row['sourceName'] ??
                    row['source_name'] ??
                    row['provider'] ??
                    row['source'],
              ).isNotEmpty
              ? _text(
                  row['sourceName'] ??
                      row['source_name'] ??
                      row['provider'] ??
                      row['source'],
                )
              : 'macro';
          final sourceTime = _text(
            row['sourceDataTime'] ??
                row['source_data_time'] ??
                row['sourceDate'] ??
                row['source_date'] ??
                row['published_at'],
          );
          final fetchedAt = _text(row['fetchedAt'] ?? row['fetched_at']);
          final access = _accessStatus(row);
          final freshness = _freshnessStatus(sourceTime, fetchedAt, access);
          final confidence =
              _text(row['confidence'] ?? row['reliability']).isNotEmpty
              ? _text(row['confidence'] ?? row['reliability'])
              : _confidenceForTier(tier, access, freshness);
          final limitation = _text(
            row['limitations'] ??
                row['limitation'] ??
                row['missingReason'] ??
                row['failureClass'] ??
                row['failure_class'],
          );
          return [
            source,
            'tier=$tier',
            if (sourceType.isNotEmpty) 'type=$sourceType',
            'freshness=$freshness',
            'access=$access',
            'confidence=$confidence',
            if (limitation.isNotEmpty) 'limit=${_compactMax(limitation, 80)}',
          ].join(' / ');
        })
        .where((line) => line.isNotEmpty)
        .toList();
  }

  List<String> _assetImpactRows(Map<String, dynamic> payload) {
    return _evidenceCandidateRows(payload)
        .map((row) {
          final title = _text(
            row['title'] ??
                row['factor_name'] ??
                row['factorId'] ??
                row['provider'] ??
                row['sourceName'],
          );
          final family = _text(row['family']);
          final assets = _listValues(
            row['affectedAssets'] ??
                row['affected_assets'] ??
                row['assetClasses'] ??
                row['asset_classes'] ??
                row['assets'],
          );
          final regions = _listValues(
            row['regions'] ??
                row['marketRegions'] ??
                row['market_regions'] ??
                row['region'],
          );
          final sectors = _listValues(
            row['sectors'] ?? row['themes'] ?? row['theme'],
          );
          final fundTypes = _listValues(row['fundTypes'] ?? row['fund_types']);
          final channels = _listValues(
            row['transmissionChannels'] ??
                row['transmission_channels'] ??
                row['strategyImpact'] ??
                row['strategy_impact'],
          );
          final target = [
            if (assets.isNotEmpty) 'asset=${assets.take(4).join(',')}',
            if (regions.isNotEmpty) 'region=${regions.take(3).join(',')}',
            if (sectors.isNotEmpty) 'sector=${sectors.take(4).join(',')}',
            if (fundTypes.isNotEmpty) 'fund=${fundTypes.take(3).join(',')}',
            if (channels.isNotEmpty) 'channel=${channels.take(4).join(',')}',
          ].join(' / ');
          return [
            if (title.isNotEmpty)
              title
            else if (family.isNotEmpty)
              family
            else
              'macro',
            'impact=${_impactDirection(row)}',
            if (target.isNotEmpty) target else 'target=needs-linking',
          ].join(' / ');
        })
        .where((line) => line.isNotEmpty)
        .toList();
  }

  List<String> _decisionRows(
    Map<String, dynamic> payload, {
    String fallbackTier = '',
  }) {
    return _evidenceCandidateRows(payload)
        .map((row) {
          final title =
              _text(
                row['title'] ??
                    row['factor_name'] ??
                    row['factorId'] ??
                    row['provider'] ??
                    row['sourceName'],
              ).isNotEmpty
              ? _text(
                  row['title'] ??
                      row['factor_name'] ??
                      row['factorId'] ??
                      row['provider'] ??
                      row['sourceName'],
                )
              : 'macro';
          final tier =
              _text(row['evidenceTier'] ?? row['evidence_tier']).isNotEmpty
              ? _text(row['evidenceTier'] ?? row['evidence_tier'])
              : fallbackTier.isNotEmpty
              ? fallbackTier
              : _tierForRow(row);
          final access = _accessStatus(row);
          final sourceTime = _text(
            row['sourceDataTime'] ??
                row['source_data_time'] ??
                row['sourceDate'] ??
                row['source_date'] ??
                row['published_at'],
          );
          final fetchedAt = _text(row['fetchedAt'] ?? row['fetched_at']);
          final freshness = _freshnessStatus(sourceTime, fetchedAt, access);
          final confidenceEffect =
              _text(
                row['confidenceEffect'] ?? row['confidence_effect'],
              ).isNotEmpty
              ? _text(row['confidenceEffect'] ?? row['confidence_effect'])
              : _confidenceEffectFor(tier, access, freshness, row);
          final missing = _text(
            row['missingEvidence'] ??
                row['missing_evidence'] ??
                row['missingReason'] ??
                row['failureClass'] ??
                row['failure_class'],
          );
          final conflict = _text(
            row['conflictingEvidence'] ?? row['conflicting_evidence'],
          );
          final next =
              _text(
                row['nextEvidenceAction'] ??
                    row['next_evidence_action'] ??
                    row['nextAction'],
              ).isNotEmpty
              ? _text(
                  row['nextEvidenceAction'] ??
                      row['next_evidence_action'] ??
                      row['nextAction'],
                )
              : _nextEvidenceAction(access, freshness, missing);
          return [
            title,
            '置信度影响=$confidenceEffect',
            if (missing.isNotEmpty) '缺失证据=${_compactMax(missing, 80)}',
            if (conflict.isNotEmpty) '冲突证据=${_compactMax(conflict, 80)}',
            '下一步/刷新策略=$next',
          ].join(' / ');
        })
        .where((line) => line.isNotEmpty)
        .toList();
  }

  List<Map> _evidenceCandidateRows(Map<String, dynamic> payload) {
    final candidates = <Map>[];
    candidates.addAll(_macroRows(payload).whereType<Map>());
    final contentEvidence = payload['contentEvidence'];
    if (contentEvidence is List)
      candidates.addAll(contentEvidence.whereType<Map>());
    final data = payload['data'];
    if (data is List) {
      for (final row in data.whereType<Map>()) {
        candidates.add({
          ...row,
          'evidenceTier': 'linked_news_evidence',
          'sourceType': 'news',
          'sourceDataTime': row['published_at'] ?? payload['sourceDataTime'],
          'fetchedAt': payload['fetchedAt'],
          'sourceName': row['source'] ?? payload['provider'] ?? 'finance_news',
          'limitations': 'news_clue_not_official_fact',
        });
      }
    }
    if (candidates.isNotEmpty) return candidates;
    final action = _text(payload['action']);
    if (action.isEmpty) return const [];
    return [
      {
        'provider': _text(payload['provider'] ?? payload['source'] ?? action),
        'sourceDataTime': payload['sourceDataTime'],
        'fetchedAt': payload['fetchedAt'],
        'status': payload['status'],
        'missingReason': payload['missingReason'],
        'evidenceTier': action == 'query_finance_news'
            ? 'linked_news_evidence'
            : '',
      },
    ];
  }

  List<Object?> _macroRows(Map<String, dynamic> payload) {
    final rows = <Object?>[];
    final directRows = payload['rows'];
    if (directRows is List) rows.addAll(directRows);
    final seriesRows = payload['series'];
    if (seriesRows is List) rows.addAll(seriesRows);
    return rows;
  }

  String _tierForRow(Map row) {
    final family = _text(row['family']).toLowerCase();
    final sourceType = _text(
      row['sourceType'] ?? row['source_type'],
    ).toLowerCase();
    final status = _text(
      row['status'] ?? row['failureClass'] ?? row['failure_class'],
    ).toLowerCase();
    if (RegExp(
      r'(blocked|gated|missing|failed|unsupported|manual|licensed)',
    ).hasMatch(status)) {
      return 'blocked/gated/missing';
    }
    if (RegExp(
      r'(official.*series|macro_official_series|numeric)',
    ).hasMatch(family)) {
      return 'official_numeric_fact';
    }
    if (RegExp(
          r'(official|policy|regulation|index_event|event|document)',
        ).hasMatch(family) ||
        sourceType.contains('official')) {
      return 'official_event_document';
    }
    if (RegExp(r'(research|content|document|asset_manager)').hasMatch(family) ||
        sourceType.contains('research')) {
      return 'content-backed_research';
    }
    if (family.contains('news') || sourceType.contains('news')) {
      return 'linked_news_evidence';
    }
    if (RegExp(r'(retrieval|provenance|extract)').hasMatch(family) ||
        sourceType.contains('retrieval')) {
      return 'retrieval_evidence';
    }
    return 'content-backed_research';
  }

  String _sourceTypeForTier(String tier) {
    if (tier.contains('official_numeric')) return 'official_data';
    if (tier.contains('official_event')) return 'official_event';
    if (tier.contains('research')) return 'research';
    if (tier.contains('news')) return 'news';
    if (tier.contains('retrieval')) return 'retrieval-only';
    if (tier.contains('blocked') || tier.contains('missing')) {
      return 'blocked_or_missing';
    }
    return '';
  }

  String _accessStatus(Map row) {
    final value = _text(
      row['accessStatus'] ??
          row['access_status'] ??
          row['accessClass'] ??
          row['automationPolicy'] ??
          row['status'] ??
          row['failureClass'] ??
          row['failure_class'],
    ).toLowerCase();
    if (value.isEmpty) return 'public';
    if (value.contains('api-key')) return 'api-key-required';
    if (value.contains('credential') || value.contains('quota')) {
      return 'credential-gated';
    }
    if (value.contains('manual')) return 'manual-browser';
    if (value.contains('anti-bot')) return 'anti-bot';
    if (value.contains('security') || value.contains('blocked')) {
      return 'security-blocked';
    }
    if (value.contains('do-not-scrape')) return 'do-not-scrape';
    if (value.contains('licensed') || value.contains('paywall')) {
      return 'licensed-needed';
    }
    return 'public';
  }

  String _freshnessStatus(String sourceTime, String fetchedAt, String access) {
    if (RegExp(
      r'(blocked|manual|anti-bot|licensed|do-not-scrape|security)',
    ).hasMatch(access)) {
      return 'blocked';
    }
    final sourceDate = DateTime.tryParse(sourceTime);
    final fetchedDate = DateTime.tryParse(fetchedAt);
    if (sourceDate == null && fetchedDate == null) return 'missing';
    if (sourceDate == null || fetchedDate == null) return 'acceptable';
    final days = fetchedDate.difference(sourceDate).inHours.abs() / 24;
    if (days <= 7) return 'fresh';
    if (days <= 60) return 'acceptable';
    return 'stale';
  }

  String _confidenceForTier(String tier, String access, String freshness) {
    if (tier.contains('blocked') ||
        access != 'public' ||
        freshness == 'blocked' ||
        freshness == 'missing') {
      return 'low';
    }
    if (tier.contains('official') && freshness != 'stale') return 'high';
    if (tier.contains('research') || tier.contains('news')) return 'medium';
    return 'low';
  }

  String _impactDirection(Map row) {
    final value = _text(
      row['expectedDirection'] ??
          row['expected_direction'] ??
          row['impact'] ??
          row['direction'],
    ).toLowerCase();
    if (RegExp(r'(positive|tailwind|利好|上行)').hasMatch(value)) {
      return 'positive tailwind';
    }
    if (RegExp(r'(negative|headwind|利空|下行)').hasMatch(value)) {
      return 'negative headwind';
    }
    if (RegExp(r'(mixed|分化|双向)').hasMatch(value)) return 'mixed';
    if (RegExp(r'(watch|monitor|观察)').hasMatch(value)) return 'watch-only';
    return 'watch-only';
  }

  String _confidenceEffectFor(
    String tier,
    String access,
    String freshness,
    Map row,
  ) {
    final status = _text(
      row['status'] ?? row['failureClass'] ?? row['failure_class'],
    ).toLowerCase();
    if (status.contains('missing') ||
        status.contains('failed') ||
        freshness == 'missing') {
      return 'insufficient evidence';
    }
    if (access != 'public' || freshness == 'blocked' || freshness == 'stale') {
      return 'lowers confidence';
    }
    if (tier.contains('official') && freshness == 'fresh') {
      return 'raises confidence';
    }
    if (tier.contains('news')) return 'neutral';
    return 'mixed';
  }

  String _nextEvidenceAction(String access, String freshness, String missing) {
    if (missing.isNotEmpty) return 'refresh or request higher-tier evidence';
    if (RegExp(
      r'(manual|anti-bot|licensed|do-not-scrape|security)',
    ).hasMatch(access)) {
      return 'manual-browser evidence or do not retry';
    }
    if (access == 'credential-gated' || access == 'api-key-required') {
      return 'configure credential then serial probe';
    }
    if (freshness == 'stale' || freshness == 'missing') {
      return 'refresh allowed source then readback';
    }
    return 'use cache/readback';
  }

  List<String> _listValues(Object? value) {
    if (value is List)
      return value
          .map(_text)
          .map(_displayMacroValue)
          .where((v) => v.isNotEmpty)
          .toList();
    final text = _text(value);
    if (text.isEmpty) return const [];
    return text
        .split(RegExp(r'[;,，、]'))
        .map((item) => item.trim())
        .map(_displayMacroValue)
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _displayMacroValue(String value) => _targetLabel(_familyLabel(value));

  bool _hasFundContext(MacroEvidence evidence) {
    final textValue = [
      ...evidence.contextLines,
      ...evidence.factorLines,
      ...evidence.assetImpactLines,
      ...evidence.decisionLines,
    ].join(' ');
    return RegExp(r'基金|fund', caseSensitive: false).hasMatch(textValue);
  }

  List<String> _sortEvidenceLines(List<String> lines) {
    final copy = [...lines];
    copy.sort((a, b) => _evidenceLineRank(a).compareTo(_evidenceLineRank(b)));
    return copy;
  }

  int _evidenceLineRank(String line) => line.contains('已请求') ? 2 : 0;

  String _compactMax(String value, int maxLength) {
    final oneLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length > maxLength
        ? '${oneLine.substring(0, maxLength - 1)}...'
        : oneLine;
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

  String _orFallback(List<String> parts, String fallback) {
    final joined = parts.where((value) => value.isNotEmpty).join(' / ');
    return joined.isEmpty ? fallback : joined;
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
    required this.reliabilityLines,
    required this.assetImpactLines,
    required this.decisionLines,
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
  final List<String> reliabilityLines;
  final List<String> assetImpactLines;
  final List<String> decisionLines;

  bool get hasActionableMacroEvidence =>
      factorLines.isNotEmpty ||
      sourceLines.isNotEmpty ||
      contentLines.isNotEmpty ||
      evidenceLines.isNotEmpty ||
      newsLines.isNotEmpty;
}
