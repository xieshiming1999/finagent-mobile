import 'llm_client.dart';
import 'log.dart';
import 'message.dart';
import 'prompt_builder.dart';
import 'session.dart';
import 'tool_context.dart';

// Reference: claude-code-best/src/query/stopHooks.ts

/// Context passed to every post-turn hook.
class PostTurnContext {
  final List<Message> messages;
  final int turnStartIndex;
  final LLMClient client;
  final ToolContext toolContext;
  final PromptBuilder promptBuilder;
  final SessionManager sessionManager;
  final int turnToolCallCount;

  const PostTurnContext({
    required this.messages,
    required this.turnStartIndex,
    required this.client,
    required this.toolContext,
    required this.promptBuilder,
    required this.sessionManager,
    required this.turnToolCallCount,
  });
}

/// A named post-turn hook. All hooks are fire-and-forget.
typedef PostTurnHookFn = Future<void> Function(PostTurnContext context);

class _HookEntry {
  final String name;
  final PostTurnHookFn fn;
  const _HookEntry(this.name, this.fn);
}

/// Registry for post-turn hooks. Hooks run in registration order,
/// all fire-and-forget (errors are caught and logged, never block the agent).
class PostTurnHookRegistry {
  final _hooks = <_HookEntry>[];

  void register(String name, PostTurnHookFn fn) {
    _hooks.removeWhere((h) => h.name == name);
    _hooks.add(_HookEntry(name, fn));
  }

  void unregister(String name) {
    _hooks.removeWhere((h) => h.name == name);
  }

  List<String> get hookNames => _hooks.map((h) => h.name).toList();

  /// Fire all hooks serially. Each runs in order; failures don't affect others.
  /// Hooks are awaited to prevent concurrent LLM calls.
  Future<void> fireAll(PostTurnContext context) async {
    for (final hook in _hooks) {
      await _fireHook(hook, context);
    }
  }

  Future<void> _fireHook(_HookEntry hook, PostTurnContext context) async {
    try {
      await hook.fn(context);
    } catch (e) {
      log('PostTurnHook', '${hook.name} failed: $e');
    }
  }
}
