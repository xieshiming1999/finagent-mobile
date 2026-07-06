import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/portfolio_tool/portfolio_tool.dart';

void main() {
  test(
    'Portfolio preview_trade validates order without mutating paper state',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'finagent-portfolio-preview-',
      );
      try {
        final tool = PortfolioTool();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
        final result = await tool.call('preview', {
          'action': 'preview_trade',
          'market': 'cn',
          'symbol': '600519',
          'side': 'buy',
          'shares': 100,
          'price': 1200,
        }, context);

        expect(result.isError, isFalse);
        final payload = jsonDecode(result.content) as Map<String, dynamic>;
        expect(payload['action'], 'preview_trade');
        expect(payload['sideEffect'], isFalse);
        expect(payload['executionAllowed'], isTrue);
        expect(payload['order'], containsPair('symbol', '600519'));
        expect(payload['estimated'], containsPair('cashBefore', 1000000.0));

        final portfolioFile = File('${dir.path}/memory/.portfolio_cn.json');
        expect(portfolioFile.existsSync(), isFalse);
      } finally {
        dir.deleteSync(recursive: true);
      }
    },
  );

  test('Portfolio trade returns post-trade local readback evidence', () async {
    final dir = Directory.systemTemp.createTempSync(
      'finagent-portfolio-trade-readback-',
    );
    try {
      final tool = PortfolioTool();
      final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
      final result = await tool.call('trade', {
        'action': 'trade',
        'market': 'cn',
        'symbol': '600519',
        'side': 'buy',
        'shares': 100,
        'price': 100,
      }, context);

      expect(result.isError, isFalse);
      final payload = jsonDecode(result.content) as Map<String, dynamic>;
      expect(payload['action'], 'trade');
      expect(payload['sideEffect'], isTrue);
      expect(payload['executionVenue'], 'local_paper_portfolio');
      expect(payload['externalBrokerStatus'], 'not_external_broker');

      final readback = payload['postTradeReadback'] as Map<String, dynamic>;
      expect(readback['readbackStatus'], 'verified');
      expect(readback['readbackAction'], 'portfolio_snapshot_after_trade');
      expect(readback['source'], 'local_paper_portfolio');
      expect(readback['positionsCount'], 1);
      expect(readback['tradeCount'], 1);
      expect(readback['symbol'], '600519');
      expect(readback['symbolPosition'], containsPair('shares', 100.0));

      final portfolioFile = File('${dir.path}/memory/.portfolio_cn.json');
      expect(portfolioFile.existsSync(), isTrue);
      final stored =
          jsonDecode(portfolioFile.readAsStringSync()) as Map<String, dynamic>;
      expect(stored['positions']['600519']['shares'], 100.0);
      expect((stored['trades'] as List), hasLength(1));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
