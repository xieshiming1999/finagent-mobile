import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:finagent/features/finance/webview_capture_evidence.dart';

void main() {
  test(
    'detects blank native WebView captures and renders fallback evidence',
    () async {
      final blank = Uint8List.fromList(
        img.encodePng(img.Image(width: 762, height: 1200)),
      );

      expect(WebViewCaptureEvidence.isEffectivelyBlankPng(blank), isTrue);

      final fallback = await WebViewCaptureEvidence.renderDomTextFallbackPng(
        title: 'A股市场概览',
        url: 'file:///memory/pages/a_share_overview.html',
        scrollInfo: '{"scrollY":0,"pageHeight":2251,"viewportHeight":600}',
        text: '''
A股市场概览
主要指数
上证指数 4027.26 -2.26%
热门行业板块
橡胶助剂 +5.41%
主力资金净流入
N惠科 +315.02%
''',
      );

      expect(fallback.length, greaterThan(8 * 1024));
      expect(WebViewCaptureEvidence.isEffectivelyBlankPng(fallback), isFalse);

      final decoded = img.decodePng(fallback);
      expect(decoded, isNotNull);
      expect(decoded!.width, 1000);
      expect(decoded.height, 1400);
    },
  );
}
