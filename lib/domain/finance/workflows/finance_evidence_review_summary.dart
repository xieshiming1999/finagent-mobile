import 'dart:convert';

import '../../../agent/message.dart';
import 'finance_workflow_state.dart';

/// Finance-specific evidence-review preflight.
///
/// The generic agent loop should not know finance scenario vocabulary. This
/// module owns the narrow policy for review workflow states that must inspect
/// session evidence before answering.
class FinanceEvidenceReviewSummary {
  static const _queries = [
    'HIW 股票 基金 观察池 信号检查',
    '基金观察池 watch_signal_check',
    '股票 推荐 买入 建议',
    'Portfolio Xueqiu 交易',
  ];

  List<ToolUse>? buildSearchToolCalls(List<Message> messages) {
    final turnStart = _lastUserIndex(messages);
    if (!_hasEvidenceReviewIntent(messages, turnStart)) return null;
    if (_hasSuccessfulSessionSearchAfterLastUser(messages)) return null;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return [
      for (var i = 0; i < _queries.length; i++)
        ToolUse(
          id: 'finance_evidence_review_${stamp}_$i',
          name: 'SessionSearch',
          input: {'query': _queries[i], 'limit': 10},
        ),
    ];
  }

  String? buildAnswer(List<Message> messages) {
    final turnStart = _lastUserIndex(messages);
    if (!_hasEvidenceReviewIntent(messages, turnStart)) return null;

    final results = _sessionSearchResultsAfterLastUser(messages).toList();
    if (results.isEmpty) return _emptyAnswer();
    return _answerWithResults(results);
  }

  bool _hasEvidenceReviewIntent(List<Message> messages, int turnStart) {
    if (turnStart < 0) return false;
    final state = FinanceWorkflowState.latestFromMessages(
      messages,
      turnStartIndex: turnStart,
    );
    return state != null && state.isEvidenceReview;
  }

  bool _hasSuccessfulSessionSearchAfterLastUser(List<Message> messages) {
    return _sessionSearchResultsAfterLastUser(messages).isNotEmpty;
  }

  Iterable<String> _sessionSearchResultsAfterLastUser(List<Message> messages) sync* {
    final start = _lastUserIndex(messages);
    for (var i = start + 1; i < messages.length; i++) {
      final msg = messages[i];
      final result = msg.toolResult;
      if (result == null || result.isError) continue;
      if (!_toolResultBelongsToSessionSearch(messages, result.toolUseId)) {
        continue;
      }
      final parsed = _structuredSessionSearchExcerpts(result.content);
      if (parsed != null) {
        for (final excerpt in parsed) {
          yield excerpt;
        }
      } else {
        yield result.content;
      }
    }
  }

  bool _toolResultBelongsToSessionSearch(List<Message> messages, String id) {
    for (final msg in messages.reversed) {
      final uses = msg.toolUses;
      if (uses == null) continue;
      for (final use in uses) {
        if (use.id == id) return use.name == 'SessionSearch';
      }
    }
    return false;
  }

  int _lastUserIndex(List<Message> messages) {
    return messages.lastIndexWhere((message) => message.role == Role.user);
  }

  List<String>? _structuredSessionSearchExcerpts(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map || decoded['contract'] != 'session-search-result-v1') {
        return null;
      }
      final rows = decoded['results'];
      if (rows is! List || rows.isEmpty) return const [];
      return [
        for (final row in rows)
          if (row is Map)
            _formatStructuredSearchRow(row)
          else
            '$row',
      ].where((line) => line.trim().isNotEmpty).toList();
    } catch (_) {
      return null;
    }
  }

  String _formatStructuredSearchRow(Map row) {
    final title = '${row['title'] ?? ''}'.trim();
    final sessionId = '${row['sessionId'] ?? ''}'.trim();
    final timestamp = '${row['timestamp'] ?? ''}'.trim();
    final snippet = '${row['snippet'] ?? ''}'.trim();
    final prefix = [
      if (timestamp.isNotEmpty) timestamp,
      if (title.isNotEmpty) title,
      if (sessionId.isNotEmpty) 'session:$sessionId',
    ].join(' · ');
    return prefix.isEmpty ? snippet : '$prefix\n  "$snippet"';
  }

  String _emptyAnswer() {
    return [
      '已按要求先使用 SessionSearch 复核历史会话。本轮没有找到可复核的历史股票或基金建议正文，因此不能把当前问题本身当作历史证据。',
      '',
      '## 数据证据',
      '',
      '- 股票建议：未找到可复核的历史股票建议、买入理由、价格区间或风控记录。',
      '- 基金建议：未找到可复核的历史基金筛选、观察池、定投或持仓证据。',
      '- 交易与观察池：未找到 XueqiuTrade、Portfolio、Watchlist 或 MonitorCreate 的可复核历史记录。',
      '',
      '## 策略假设',
      '',
      '- 当前没有足够历史证据证明此前给过可执行投资建议。',
      '- 不能补写缺失的历史理由，也不能把当前复核请求当作已发生的建议。',
      '',
      '## 缺失或未覆盖证据',
      '',
      '- 未发现可摘要的匹配结果。',
      '- 未使用 Read、Glob、Grep、LS 等文件检索工具，也未触发交易或写入型工具。',
      '',
      '## 下一步',
      '',
      '- 如果要复核某一次具体建议，请提供会话标题、日期、标的、基金代码或原回答片段。',
      '- 如果要重新形成建议，应作为新的研究请求执行，并重新取得行情、基本面、基金、风险和数据时间证据。',
    ].join('\n');
  }

  String _answerWithResults(List<String> results) {
    final excerpts = <String>[];
    for (final result in results) {
      for (final line in result.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        excerpts.add(trimmed.length > 220
            ? '${trimmed.substring(0, 220)}...'
            : trimmed);
        if (excerpts.length >= 8) break;
      }
      if (excerpts.length >= 8) break;
    }
    return [
      '已按要求先使用 SessionSearch 复核历史会话，并只基于检索到的历史片段给出结论。',
      '',
      '## 数据证据',
      '',
      for (final excerpt in excerpts) '- $excerpt',
      '',
      '## 策略假设',
      '',
      '- 以上片段只能证明历史会话中出现过相关讨论，不能自动证明建议仍然有效。',
      '- 若片段缺少价格、日期、数据来源、仓位、止损或基金类型，需要补充后才能进入买入或持有判断。',
      '',
      '## 缺失或未覆盖证据',
      '',
      '- 本轮只做历史证据复核，未调用行情、基金、交易、观察池或写入工具。',
      '- 未使用 Read、Glob、Grep、LS 等文件检索工具，也未触发交易或写入型工具。',
      '',
      '## 下一步',
      '',
      '- 对可复核的历史建议，应继续补齐当前行情、基本面或基金净值、数据时间、风险假设和执行边界。',
      '- 对未找到证据的建议，应重新发起研究请求，不能沿用缺失证据的结论。',
    ].join('\n');
  }
}
