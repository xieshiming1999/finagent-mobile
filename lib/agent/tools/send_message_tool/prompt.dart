const description = 'Send a message to another agent.';

const prompt =
    '''Send a message to a running agent to continue a conversation or add instructions.

Usage:
- To send to a background agent: use its name or task ID as the "to" field.
- To send to the main/parent agent: use "main" or "parent" as the "to" field.
- The message will be delivered to the agent's notification queue.
- Use this to provide follow-up instructions, report results, or request help.

Examples:
  SendMessage(to: "stock-analyzer", message: "Also check the PE ratio trend")
  SendMessage(to: "parent", message: "Analysis complete, found 3 stocks matching criteria")
''';
