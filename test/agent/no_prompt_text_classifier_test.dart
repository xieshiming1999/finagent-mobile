import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('neutral mobile agent core does not classify workflow by prompt text', () {
    final root = Directory.current;
    final files = <File>[
      File('${root.path}/lib/agent/agent.dart'),
      File('${root.path}/lib/agent/agent_turn.dart'),
      File('${root.path}/lib/agent/domain_workflow_hooks.dart'),
    ].where((file) => file.existsSync()).toList();

    final offenders = <String>[];
    final forbidden = <RegExp>[
      RegExp(r'_currentPrompt\s*[^;\n]*\.contains\s*\('),
      RegExp(r'currentPrompt\s*[^;\n]*\.contains\s*\('),
      RegExp(r'prompt\s*[^;\n]*\.contains\s*\('),
      RegExp(r'userMessage\s*[^;\n]*\.contains\s*\('),
      RegExp(r'query\s*[^;\n]*\.contains\s*\('),
    ];

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (forbidden.any((pattern) => pattern.hasMatch(line))) {
          offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Neutral agent code must not infer workflow intent by parsing user prompt text. '
          'Use typed workflow state, explicit tool parameters, StrategySpec, or domain-owned evidence instead.',
    );
  });
}
