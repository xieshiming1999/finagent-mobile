import '../../agent.dart';
import '../../log.dart';
import '../../message.dart';
import '../../prompt_builder.dart';
import '../../session.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../file_read_tool/file_read_tool.dart';
import '../glob_tool/glob_tool.dart';
import '../ls_tool/ls_tool.dart';
import '../image_crop_tool/image_crop_tool.dart';

class ImageExtractTool extends Tool {
  final Agent parentAgent;

  ImageExtractTool({required this.parentAgent});

  @override
  String get name => 'ImageExtract';

  @override
  String get description =>
      'Extract a figure/table from a rendered PDF page image by description. '
      'Internally uses vision + iterative cropping to find and verify the region.';

  @override
  String get prompt =>
      'Extract a specific figure or table from a rendered PDF page image.\n'
      'The tool uses an internal vision agent to locate and crop the target, '
      'verifying the result and retrying if incomplete.\n'
      'Parameters:\n'
      '- imagePath (required): Source image file path (rendered PDF page)\n'
      '- description (required): What to extract, e.g. "Figure 1 柱状图"\n'
      '- outputPath (required): Where to save the cropped result\n'
      '- maxRounds (optional, default 5): Maximum crop attempts';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'imagePath': {
        'type': 'string',
        'description': 'Source image path (rendered PDF page)',
      },
      'description': {
        'type': 'string',
        'description': 'What to extract, e.g. "Figure 1 柱状图"',
      },
      'outputPath': {
        'type': 'string',
        'description': 'Output file path for cropped result',
      },
      'maxRounds': {
        'type': 'integer',
        'description': 'Max crop attempts (default 5)',
      },
    },
    'required': ['imagePath', 'description', 'outputPath'],
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
    final description = input['description'] as String? ?? '';
    final outputPath = input['outputPath'] as String? ?? '';
    final maxRounds = input['maxRounds'] as int? ?? 5;

    if (imagePath.isEmpty || description.isEmpty || outputPath.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'imagePath, description, and outputPath are required',
        isError: true,
      );
    }

    try {
      final client = parentAgent.client.clone();

      final subContext = ToolContext(
        basePath: context.basePath,
        serviceBaseUrl: context.serviceBaseUrl,
        skipPermissions: true,
      );

      final tools = <Tool>[
        FileReadTool(),
        ImageCropTool(),
        LSTool(),
        GlobTool(),
      ];

      final systemPrompt =
          '你是一个精确的图表裁剪助手。\n'
          '你有最多 $maxRounds 轮工具调用机会。\n\n'
          '工作流程：\n'
          '1. 先用 Read 查看源图片，分析图表位置\n'
          '2. 用 ImageCrop 裁剪目标区域（会直接返回裁剪结果图片）\n'
          '3. 检查返回的图片是否完整\n'
          '4. 如果不完整（截断、缺少标题/图例/caption、包含多余正文），调整坐标重新裁剪\n'
          '5. 满意后用文字简要说明结果\n\n'
          '注意：每次 ImageCrop 都会覆盖同一个输出文件，最终文件就是最好的结果。';

      final promptBuilder = PromptBuilder(
        basePrompt: systemPrompt,
        basePath: context.basePath,
      );

      final sessionManager = SessionManager(
        sessionsDir: '${context.basePath}/sessions/image_extract',
      );

      final subAgent = Agent(
        client: client,
        tools: tools,
        promptBuilder: promptBuilder,
        toolContext: subContext,
        sessionManager: sessionManager,
        contextWindow: parentAgent.contextWindow,
        maxOutputTokens: parentAgent.maxOutputTokens,
      );

      final userPrompt =
          '源图片: $imagePath\n'
          '请提取: "$description"\n'
          '保存到: $outputPath\n\n'
          '要求：\n'
          '1. 包含完整的图表内容（标题、图例、轴标签、caption 都要包含）\n'
          '2. 上下左右留 10-20px 的 margin，宁可多截一点也不要截断\n'
          '3. 不要包含图表之外的正文文字';

      log('ImageExtract', 'Starting: "$description" (max $maxRounds rounds)');

      final sink = context.eventSink;
      final textBuffer = StringBuffer();
      var cropCount = 0;
      await for (final event in subAgent.run(userPrompt)) {
        if (event is AgentTextDelta) {
          textBuffer.write(event.text);
        } else if (event is AgentThinking) {
          final preview = event.text.length > 80
              ? '${event.text.substring(0, 80)}...'
              : event.text;
          sink?.add(
            AgentToolProgress(
              toolName: name,
              output: 'thinking: $preview',
              elapsedMs: 0,
            ),
          );
        } else if (event is AgentToolUseStart) {
          cropCount += event.toolName == 'ImageCrop' ? 1 : 0;
          sink?.add(
            AgentToolProgress(
              toolName: name,
              output: 'tool: ${event.toolName}',
              elapsedMs: 0,
            ),
          );
        } else if (event is AgentToolResult) {
          sink?.add(
            AgentToolProgress(
              toolName: name,
              output: 'result: ${event.isError ? "error" : "ok"}',
              elapsedMs: 0,
            ),
          );
        } else if (event is AgentError) {
          throw Exception(event.message);
        }
      }

      final result = textBuffer.toString();
      log('ImageExtract', 'Done: $cropCount crop(s) for "$description"');

      return ToolResult(
        toolUseId: toolUseId,
        content: '$outputPath ($cropCount crop rounds) — $result',
      );
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'ImageExtract failed: $e',
        isError: true,
      );
    }
  }
}
