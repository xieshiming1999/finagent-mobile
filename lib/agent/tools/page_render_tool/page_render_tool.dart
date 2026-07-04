import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import '../../tool.dart';
import '../../message.dart';
import '../../tool_context.dart';
import '../utils/file_utils.dart';

class PageRenderTool extends Tool {
  @override
  String get name => 'PageRender';

  @override
  String get description =>
      'Render a specific page of a PDF as a high-resolution image.';

  @override
  String get prompt =>
      'Render a specific page of a PDF file as a PNG image for visual analysis.\n'
      'Use this to examine figures, tables, and diagrams in a document.\n'
      'Parameters:\n'
      '- pdfPath (required): Absolute path to the PDF file\n'
      '- page (required): Page number (1-indexed)\n'
      '- outputPath (required): Where to save the rendered PNG image\n'
      '- scale: Resolution scale factor (default: 2.0, higher = better quality)';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'pdfPath': {
        'type': 'string',
        'description': 'Absolute path to the PDF file',
      },
      'page': {'type': 'integer', 'description': 'Page number (1-indexed)'},
      'outputPath': {'type': 'string', 'description': 'Output PNG path'},
      'scale': {'type': 'number', 'description': 'Scale factor (default 2.0)'},
    },
    'required': ['pdfPath', 'page', 'outputPath'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool get canParallel => true;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final pdfPath = input['pdfPath'] as String? ?? '';
    final page = input['page'] as int? ?? 0;
    final outputPath = input['outputPath'] as String? ?? '';
    final scale = (input['scale'] as num?)?.toDouble() ?? 2.0;

    if (pdfPath.isEmpty || page < 1 || outputPath.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'pdfPath, page (>=1), and outputPath are required',
        isError: true,
      );
    }

    final resolvedPdf = normalizePath(pdfPath, context.basePath);
    final resolvedOutput = normalizePath(outputPath, context.basePath);

    if (!File(resolvedPdf).existsSync()) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'PDF not found: $pdfPath',
        isError: true,
      );
    }

    try {
      final doc = await PdfDocument.openFile(resolvedPdf);
      if (page > doc.pages.length) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'page $page out of range (total: ${doc.pages.length})',
          isError: true,
        );
      }

      final pdfPage = doc.pages[page - 1];
      final image = await pdfPage.render(
        fullWidth: pdfPage.width * scale,
        fullHeight: pdfPage.height * scale,
      );

      if (image == null) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'failed to render page $page',
          isError: true,
        );
      }

      final pixels = image.pixels;
      final uiImage = await _createImage(pixels, image.width, image.height);
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'failed to encode PNG',
          isError: true,
        );
      }

      final outFile = File(resolvedOutput);
      outFile.parent.createSync(recursive: true);
      final pngBytes = byteData.buffer.asUint8List();
      outFile.writeAsBytesSync(pngBytes);

      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Page $page rendered to $outputPath '
            '(${image.width}x${image.height} pixels, ${pngBytes.length} bytes). '
            'Use Read tool to view the image. '
            'For ImageCrop: coordinates are in pixels, origin (0,0) is top-left. '
            'Image is ${image.width}px wide, ${image.height}px tall.',
      );
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Render failed: $e',
        isError: true,
      );
    }
  }

  Future<ui.Image> _createImage(dynamic pixels, int width, int height) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels is List<int> ? Uint8List.fromList(pixels) : pixels as Uint8List,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
