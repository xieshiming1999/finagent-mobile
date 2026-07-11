import 'dart:convert';

import 'package:finagent/agent/message.dart';
import 'package:finagent/agent/tool.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/tool_catalog_tool/tool_catalog_tool.dart';
import 'package:flutter_test/flutter_test.dart';

class _ExampleTool extends Tool {
  @override
  String get name => 'Example';

  @override
  String get description => 'Example tool';

  @override
  bool get isReadOnly => false;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['run', 'help'],
      },
    },
  };

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async => ToolResult(toolUseId: toolUseId, content: 'ok');
}

class _MarketDataTool extends Tool {
  @override
  String get name => 'MarketData';

  @override
  String get description => 'Market data and strategy runtime tool';

  @override
  bool get isReadOnly => true;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'custom_strategy_help', 'custom_strategy_validate'],
      },
    },
  };

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async => ToolResult(toolUseId: toolUseId, content: 'ok');
}

void main() {
  test('ToolCatalog lists and details runtime tool capabilities', () async {
    late final List<Tool> tools;
    final catalog = ToolCatalogTool(toolsProvider: () => tools);
    tools = [_ExampleTool(), catalog];
    final context = ToolContext(
      basePath: '/tmp/tool-catalog-test',
      serviceBaseUrl: '',
    );

    final list =
        jsonDecode(
              (await catalog.call('list-1', {
                'action': 'list',
              }, context)).content,
            )
            as Map<String, dynamic>;
    expect(list['contract'], 'tool-catalog-result-v1');
    expect(list['action'], 'list');
    expect(
      list['tools'],
      containsAll([
        {
          'name': 'Example',
          'permission': 'write-or-side-effect',
          'readOnly': false,
          'canParallel': false,
          'requiresUserInteraction': false,
          'actions': ['help', 'run'],
        },
        {
          'name': 'ToolCatalog',
          'permission': 'read-only',
          'readOnly': true,
          'canParallel': true,
          'requiresUserInteraction': false,
          'actions': ['detail', 'help', 'list', 'module', 'modules'],
        },
      ]),
    );

    final detail =
        jsonDecode(
              (await catalog.call('detail-1', {
                'action': 'detail',
                'tool': 'Example',
              }, context)).content,
            )
            as Map<String, dynamic>;
    expect(detail['tool']['name'], 'Example');
    expect(detail['tool']['schema']['actionValues'], ['help', 'run']);

    final modules =
        jsonDecode(
              (await catalog.call('modules-1', {
                'action': 'modules',
              }, context)).content,
            )
            as Map<String, dynamic>;
    expect(modules['contract'], 'capability-module-result-v1');
    expect(modules['modules'], contains(containsPair('id', 'runtime-tool')));

    final module =
        jsonDecode(
              (await catalog.call('module-1', {
                'action': 'module',
                'module': 'runtime-tool',
              }, context)).content,
            )
            as Map<String, dynamic>;
    expect(module['module']['schema'], 'provider-module-descriptor-v1');
    expect(module['module']['tools'], isNotEmpty);
  });

  test('ToolCatalog exposes strategy runtime as a dedicated module', () async {
    late final List<Tool> tools;
    final catalog = ToolCatalogTool(toolsProvider: () => tools);
    tools = [_MarketDataTool(), catalog];
    final context = ToolContext(
      basePath: '/tmp/tool-catalog-strategy-test',
      serviceBaseUrl: '',
    );

    final modules =
        jsonDecode(
              (await catalog.call('modules-strategy', {
                'action': 'modules',
              }, context)).content,
            )
            as Map<String, dynamic>;
    expect(
      modules['modules'],
      contains(containsPair('id', 'strategy-runtime')),
    );

    final module =
        jsonDecode(
              (await catalog.call('module-strategy', {
                'action': 'module',
                'module': 'strategy-runtime',
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(module['module']['title'], contains('StrategySpec'));
    expect(module['module']['discovery'], contains('custom_strategy_help'));
    expect(module['module']['tools'].single['name'], 'MarketData');
  });
}
