import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class WebViewCaptureEvidence {
  static bool isEffectivelyBlankPng(Uint8List bytes) {
    final decoded = img.decodePng(bytes);
    if (decoded == null || decoded.width == 0 || decoded.height == 0) {
      return false;
    }
    var sampled = 0;
    var darkOrTransparent = 0;
    final stepX = (decoded.width / 32).ceil().clamp(1, decoded.width);
    final stepY = (decoded.height / 32).ceil().clamp(1, decoded.height);
    for (var y = 0; y < decoded.height; y += stepY) {
      for (var x = 0; x < decoded.width; x += stepX) {
        final pixel = decoded.getPixel(x, y);
        sampled++;
        final alpha = pixel.a.toInt();
        final brightness =
            (pixel.r.toInt() + pixel.g.toInt() + pixel.b.toInt()) / 3;
        if (alpha < 12 || brightness < 8) darkOrTransparent++;
      }
    }
    if (sampled == 0) return false;
    return darkOrTransparent / sampled > 0.985;
  }

  static Future<Uint8List> renderDomTextFallbackPng({
    required String title,
    required String url,
    required String scrollInfo,
    required String text,
  }) async {
    const width = 1000.0;
    const height = 1400.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFF10131A),
    );

    var y = 34.0;
    y = _drawWrappedText(
      canvas,
      text: title,
      x: 36,
      y: y,
      maxWidth: width - 72,
      fontSize: 30,
      color: const Color(0xFFE8ECF3),
      maxLines: 2,
      fontWeight: FontWeight.w700,
    );
    y += 12;
    y = _drawWrappedText(
      canvas,
      text: url,
      x: 36,
      y: y,
      maxWidth: width - 72,
      fontSize: 16,
      color: const Color(0xFF9BA4B5),
      maxLines: 2,
    );
    y += 8;
    y = _drawWrappedText(
      canvas,
      text: scrollInfo,
      x: 36,
      y: y,
      maxWidth: width - 72,
      fontSize: 15,
      color: const Color(0xFF9BA4B5),
      maxLines: 2,
    );
    y += 18;
    canvas.drawLine(
      Offset(36, y),
      Offset(width - 36, y),
      Paint()
        ..color = const Color(0xFF2A3040)
        ..strokeWidth = 1,
    );
    y += 24;

    final normalized = text
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
    y = _drawWrappedText(
      canvas,
      text: normalized.isEmpty ? '(DOM text is empty)' : normalized,
      x: 36,
      y: y,
      maxWidth: width - 72,
      fontSize: 22,
      color: const Color(0xFFDCE3EE),
      maxLines: 44,
      lineHeight: 1.3,
    );
    y += 18;
    _drawWrappedText(
      canvas,
      text:
          'Fallback evidence image: native macOS WebView bitmap capture was blank, so this PNG renders the current DOM text for visual verification.',
      x: 36,
      y: y,
      maxWidth: width - 72,
      fontSize: 15,
      color: const Color(0xFFFFC66D),
      maxLines: 3,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static double _drawWrappedText(
    Canvas canvas, {
    required String text,
    required double x,
    required double y,
    required double maxWidth,
    required double fontSize,
    required Color color,
    int maxLines = 1,
    FontWeight fontWeight = FontWeight.w400,
    double lineHeight = 1.2,
  }) {
    final paragraphStyle = ui.ParagraphStyle(
      fontSize: fontSize,
      height: lineHeight,
      maxLines: maxLines,
      ellipsis: text.length > 2400 ? '...' : null,
    );
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontFamily: 'PingFang SC',
        ),
      )
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(paragraph, Offset(x, y));
    return y + paragraph.height;
  }
}
