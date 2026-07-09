import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/file_read_tool/file_read_tool.dart';
import 'package:finagent/agent/tools/ls_tool/ls_tool.dart';

void main() {
  test('file tools reject macro research artifact inspection', () async {
    final dir = Directory.systemTemp.createTempSync('finagent-macro-files-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final macroDir = Directory(
      '${dir.path}/data/macro_research_content/goldman_sachs',
    )..createSync(recursive: true);
    File('${macroDir.path}/report.md').writeAsStringSync('macro artifact body');
    final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

    final read = await FileReadTool().call('read-macro', {
      'file_path': 'data/macro_research_content/goldman_sachs/report.md',
    }, context);
    expect(read.isError, isTrue);
    expect(read.content, contains('query_macro_research_content'));

    final ls = await LSTool().call('ls-macro', {
      'path': 'data/macro_research_content',
    }, context);
    expect(ls.isError, isTrue);
    expect(ls.content, contains('query_macro_research_content'));
  });
}
