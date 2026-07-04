import 'dart:convert';

import '../../data_task_engine.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class DataTaskTool extends Tool {
  final DataTaskEngine engine;

  DataTaskTool({required this.engine});

  @override
  String get name => 'DataTask';

  @override
  String get description =>
      'Submit and manage observed data tasks (market screening, batch scoring). Submit waits by default; use block:false for durable background tasks.';

  @override
  String get prompt => '''数据任务。适用于耗时较长的数据操作（全市场筛选等）。
- submit — 提交任务. 默认等待任务完成并返回结果/错误；设置 block:false 才后台执行
- status — 查看任务状态. taskId
- result — 读取完成任务的结果. taskId
- list   — 列出所有任务
- cancel — 取消任务. taskId
- help   — 帮助

任务类型:
- screen_advanced: 全市场选股(东方财富200+字段). conditions: [{field,op,value}]
  field: pe/pb/roe/changePct/marketCap/volumeRatio/price
- batch_quote: 批量拉取行情. symbols: ["600519","000858",...]
- batch_score: 批量技术评分. symbols: ["600519","000858",...]

特性:
- 自动缓存: 今天同样条件的任务直接返回缓存结果
- 可观察执行: submit 默认等待完成；失败会通过工具错误返回
- 后台任务: 大任务可传 block:false，之后用 status/result/cancel 管理
- 自动限速: 对外部API限速1.5秒/请求,防止被封
- 断点恢复: app重启后自动继续未完成的任务
- 完成通知: 任务完成后自动通知你结果''';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['submit', 'status', 'result', 'list', 'cancel', 'help'],
      },
      'type': {
        'type': 'string',
        'description': 'Task type: screen_advanced/batch_quote/batch_score',
      },
      'taskId': {'type': 'string'},
      'conditions': {
        'type': 'array',
        'items': {'type': 'object'},
        'description': '(screen_advanced) [{field,op,value}]',
      },
      'symbols': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': '(batch_quote/score) Stock symbols',
      },
      'block': {
        'type': 'boolean',
        'description': '(submit) Wait for completion. Defaults to true.',
      },
      'timeoutMs': {
        'type': 'number',
        'description':
            '(submit with block=true) Maximum wait time in milliseconds. Defaults to 60000, max 300000.',
      },
    },
    'required': ['action'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) {
    final action = input['action'] as String? ?? 'help';
    return action == 'submit';
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = input['action'] as String? ?? 'help';
    switch (action) {
      case 'help':
        return ToolResult(toolUseId: toolUseId, content: prompt);
      case 'submit':
        return _submit(toolUseId, input);
      case 'status':
        return _status(toolUseId, input);
      case 'result':
        return _result(toolUseId, input);
      case 'list':
        return _list(toolUseId);
      case 'cancel':
        return _cancel(toolUseId, input);
      default:
        return ToolResult(
          toolUseId: toolUseId,
          content: 'Unknown action "$action". Use help.',
          isError: true,
        );
    }
  }

  Future<ToolResult> _submit(
    String toolUseId,
    Map<String, dynamic> input,
  ) async {
    final type = input['type'] as String?;
    if (type == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'type required (screen_advanced/batch_quote/batch_score)',
        isError: true,
      );
    }

    final params = <String, dynamic>{};
    if (input.containsKey('conditions')) {
      params['conditions'] = input['conditions'];
    }
    if (input.containsKey('symbols')) params['symbols'] = input['symbols'];

    try {
      final task = engine.submit(type, params);
      if (task.status == DataTaskStatus.completed) {
        return _completedResult(toolUseId, task, retrievalStatus: 'cached');
      }
      if (input['block'] == false) {
        return ToolResult(
          toolUseId: toolUseId,
          content: const JsonEncoder.withIndent('  ').convert({
            'ok': true,
            'retrieval_status': 'background_started',
            'taskId': task.id,
            'type': task.type,
            'status': task.status.name,
            'progress': task.progress,
            'estimatedTime': _estimateTime(type, params),
            'next': {
              'status': 'DataTask(action:"status", taskId:"${task.id}")',
              'result': 'DataTask(action:"result", taskId:"${task.id}")',
              'cancel': 'DataTask(action:"cancel", taskId:"${task.id}")',
            },
          }),
        );
      }
      return _waitForCompletion(
        toolUseId,
        task.id,
        timeout: _timeoutFromInput(input),
      );
    } catch (e) {
      return ToolResult(toolUseId: toolUseId, content: '$e', isError: true);
    }
  }

  Future<ToolResult> _waitForCompletion(
    String toolUseId,
    String taskId, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final task = engine.get(taskId);
      if (task == null) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'task not found',
          isError: true,
        );
      }
      switch (task.status) {
        case DataTaskStatus.completed:
          return _completedResult(toolUseId, task, retrievalStatus: 'success');
        case DataTaskStatus.failed:
          return ToolResult(
            toolUseId: toolUseId,
            content: 'Task $taskId failed: ${task.error ?? 'unknown error'}',
            isError: true,
          );
        case DataTaskStatus.cancelled:
          return ToolResult(
            toolUseId: toolUseId,
            content: 'Task $taskId was cancelled',
            isError: true,
          );
        case DataTaskStatus.pending:
        case DataTaskStatus.running:
          await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }

    final task = engine.get(taskId);
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'retrieval_status': 'timeout',
        'taskId': taskId,
        if (task != null) 'status': task.status.name,
        if (task != null) 'progress': task.progress,
        'next': {
          'status': 'DataTask(action:"status", taskId:"$taskId")',
          'result': 'DataTask(action:"result", taskId:"$taskId")',
          'cancel': 'DataTask(action:"cancel", taskId:"$taskId")',
        },
      }),
      isError: true,
    );
  }

  Duration _timeoutFromInput(Map<String, dynamic> input) {
    final raw = input['timeoutMs'];
    final ms = raw is num ? raw.toInt() : 60000;
    return Duration(milliseconds: ms.clamp(1000, 300000));
  }

  ToolResult _completedResult(
    String toolUseId,
    DataTask task, {
    required String retrievalStatus,
  }) {
    final data = engine.readResult(task.id);
    if (data == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'result file not found',
        isError: true,
      );
    }

    final json = jsonDecode(data) as Map<String, dynamic>;
    final count = (json['data'] as List?)?.length ?? 0;
    final preview = (json['data'] as List?)?.take(20).toList() ?? [];
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'ok': true,
        'retrieval_status': retrievalStatus,
        'taskId': task.id,
        'type': json['type'],
        'status': task.status.name,
        'totalCount': count,
        'preview(top20)': preview,
        'resultPath': task.result,
        if (count > 20) 'note': '显示前20条,完整数据已保存',
      }),
    );
  }

  ToolResult _status(String toolUseId, Map<String, dynamic> input) {
    final taskId = input['taskId'] as String?;
    if (taskId == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'taskId required',
        isError: true,
      );
    }
    final task = engine.get(taskId);
    if (task == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'task not found',
        isError: true,
      );
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'id': task.id,
        'type': task.type,
        'status': task.status.name,
        'progress': '${task.progress.toStringAsFixed(0)}%',
        if (task.error != null) 'error': task.error,
        if (task.completedAt != null)
          'completedAt': task.completedAt!.toIso8601String(),
      }),
    );
  }

  ToolResult _result(String toolUseId, Map<String, dynamic> input) {
    final taskId = input['taskId'] as String?;
    if (taskId == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'taskId required',
        isError: true,
      );
    }
    final task = engine.get(taskId);
    if (task == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'task not found',
        isError: true,
      );
    }
    if (task.status == DataTaskStatus.failed) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Task $taskId failed: ${task.error ?? 'unknown error'}',
        isError: true,
      );
    }
    if (task.status == DataTaskStatus.cancelled) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Task $taskId was cancelled',
        isError: true,
      );
    }
    if (task.status != DataTaskStatus.completed) {
      return ToolResult(
        toolUseId: toolUseId,
        content: const JsonEncoder.withIndent('  ').convert({
          'retrieval_status': 'not_ready',
          'taskId': taskId,
          'status': task.status.name,
          'progress': task.progress,
          'next': 'Call status later, or result after completion.',
        }),
      );
    }
    return _completedResult(toolUseId, task, retrievalStatus: 'success');
  }

  ToolResult _list(String toolUseId) {
    final tasks = engine.list();
    final recent = tasks.reversed
        .take(10)
        .map(
          (t) => {
            'id': t.id,
            'type': t.type,
            'status': t.status.name,
            'progress': '${t.progress.toStringAsFixed(0)}%',
            'created': t.createdAt.toIso8601String().substring(0, 16),
          },
        )
        .toList();
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent(
        '  ',
      ).convert({'total': tasks.length, 'recent': recent}),
    );
  }

  ToolResult _cancel(String toolUseId, Map<String, dynamic> input) {
    final taskId = input['taskId'] as String?;
    if (taskId == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'taskId required',
        isError: true,
      );
    }
    engine.cancel(taskId);
    return ToolResult(toolUseId: toolUseId, content: 'Task $taskId cancelled');
  }

  String _estimateTime(String type, Map<String, dynamic> params) =>
      switch (type) {
        'screen_advanced' => '3-10分钟(取决于结果数量)',
        'batch_quote' =>
          '${((params['symbols'] as List?)?.length ?? 0) * 0.1}秒',
        'batch_score' => '${((params['symbols'] as List?)?.length ?? 0) * 2}秒',
        _ => '未知',
      };
}
