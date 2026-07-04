import 'llm_client.dart';
import 'log.dart';
import 'message.dart';

const _recentMessageWindow = 30;

const _recapModel = 'claude-haiku-4-5-20251001';

const _recapPrompt =
    '用户离开了一段时间现在回来了。用 1-3 句简短的中文总结最近的对话上下文：'
    '正在做什么、进展到哪里、下一步是什么。不要用"用户"这个词，直接描述任务。';

bool shouldGenerateRecap(List<Message> messages) {
  if (messages.isEmpty) return false;
  if (messages.last.isRecap) return false;

  int userMsgsSinceLastRecap = 0;
  for (var i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    if (m.isRecap) break;
    if (m.role == Role.user && !m.isCompactSummary) userMsgsSinceLastRecap++;
  }
  final should = userMsgsSinceLastRecap >= 20;
  log(
    'Recap',
    'shouldGenerateRecap: $userMsgsSinceLastRecap user msgs since last recap → $should',
  );
  return should;
}

Future<String?> generateRecap(List<Message> messages, LLMClient client) async {
  final recent = messages.length > _recentMessageWindow
      ? messages.sublist(messages.length - _recentMessageWindow)
      : List<Message>.from(messages);

  recent.add(Message(role: Role.user, content: _recapPrompt));

  final textBuffer = StringBuffer();
  try {
    final stream = client.sendMessage(
      messages: recent,
      tools: [],
      maxOutputTokens: 1000,
      model: _recapModel,
    );

    await for (final event in stream) {
      switch (event) {
        case SSETextDelta(:final text):
          textBuffer.write(text);
        default:
          break;
      }
    }
  } catch (e) {
    log('Recap', 'Generation failed: $e');
    return null;
  }

  final result = textBuffer.toString().trim();
  if (result.isEmpty) return null;
  log('Recap', 'Generated: ${result.length} chars');
  return result;
}
