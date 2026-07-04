import 'package:finagent/agent/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tool-result success is not inferred from display text', () {
    final result = ToolResult(
      toolUseId: 'tool-1',
      content: 'Error: this is source data, not runtime state',
    );

    expect(result.isError, isFalse);
    expect(result.content, 'Error: this is source data, not runtime state');
  });

  test('tool producers mark failures explicitly and preserve exact detail', () {
    final result = ToolResult(
      toolUseId: 'tool-2',
      content: 'HTTP 429: quota exhausted',
      isError: true,
    );

    expect(result.isError, isTrue);
    expect(result.content, 'HTTP 429: quota exhausted');
  });
}
