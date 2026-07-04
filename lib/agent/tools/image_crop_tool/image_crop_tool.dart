import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../tool.dart';
import '../../message.dart';
import '../../tool_context.dart';
import '../utils/file_utils.dart';

class ImageCropTool extends Tool {
  @override
  String get name => 'ImageCrop';

  @override
  String get description =>
      'Crop a rectangular region from an image and save as a new file.';

  @override
  String get prompt =>
      'Crop a rectangular region from an image file. Use after PageRender to extract '
      'individual figures or tables from a rendered PDF page.\n'
      'Coordinates are in pixels relative to the source image.\n'
      'Parameters:\n'
      '- imagePath (required): Source image file path\n'
      '- x (required): Left edge X coordinate\n'
      '- y (required): Top edge Y coordinate\n'
      '- width (required): Crop width in pixels\n'
      '- height (required): Crop height in pixels\n'
      '- outputPath (required): Where to save the cropped image';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'imagePath': {'type': 'string', 'description': 'Source image path'},
      'x': {'type': 'integer', 'description': 'Left X coordinate'},
      'y': {'type': 'integer', 'description': 'Top Y coordinate'},
      'width': {'type': 'integer', 'description': 'Crop width'},
      'height': {'type': 'integer', 'description': 'Crop height'},
      'outputPath': {'type': 'string', 'description': 'Output file path'},
    },
    'required': ['imagePath', 'x', 'y', 'width', 'height', 'outputPath'],
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
    final imagePath = input['imagePath'] as String? ?? '';
    final x = input['x'] as int? ?? 0;
    final y = input['y'] as int? ?? 0;
    final width = input['width'] as int? ?? 0;
    final height = input['height'] as int? ?? 0;
    final outputPath = input['outputPath'] as String? ?? '';

    if (imagePath.isEmpty || outputPath.isEmpty || width <= 0 || height <= 0) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'imagePath, outputPath, and positive width/height are required',
        isError: true,
      );
    }

    final resolvedImage = normalizePath(imagePath, context.basePath);
    final resolvedOutput = normalizePath(outputPath, context.basePath);

    if (!File(resolvedImage).existsSync()) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'image not found: $imagePath',
        isError: true,
      );
    }

    try {
      final bytes = File(resolvedImage).readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'failed to decode image',
          isError: true,
        );
      }

      final cx = x.clamp(0, image.width - 1);
      final cy = y.clamp(0, image.height - 1);
      final cw = width.clamp(1, image.width - cx);
      final ch = height.clamp(1, image.height - cy);

      final clamped = cx != x || cy != y || cw != width || ch != height;
      final cropped = img.copyCrop(image, x: cx, y: cy, width: cw, height: ch);
      final pngBytes = img.encodePng(cropped);

      final outFile = File(resolvedOutput);
      outFile.parent.createSync(recursive: true);
      outFile.writeAsBytesSync(pngBytes);

      final right = image.width - cx - cw;
      final bottom = image.height - cy - ch;
      final pct = (cw * ch * 100.0 / (image.width * image.height))
          .toStringAsFixed(1);
      final buf = StringBuffer()
        ..writeln('Cropped ${cw}x$ch from ($cx,$cy) → $outputPath')
        ..writeln(
          'Original: ${image.width}x${image.height}. Crop covers $pct% of original.',
        )
        ..write(
          'Margins: left=${cx}px, top=${cy}px, right=${right}px, bottom=${bottom}px.',
        );
      if (clamped) {
        buf.write(' WARNING: coordinates were clamped to image bounds.');
      }

      return ToolResult(
        toolUseId: toolUseId,
        content: buf.toString(),
        images: [Uint8List.fromList(pngBytes)],
      );
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Crop failed: $e',
        isError: true,
      );
    }
  }
}
