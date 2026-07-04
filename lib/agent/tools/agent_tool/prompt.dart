const description = 'Launch a sub-agent to handle a task autonomously.';

const prompt =
    '''Launch a sub-agent to handle complex, multi-step tasks autonomously.

Usage:
- Provide a clear description (3-5 words) and a detailed prompt for the sub-agent.
- The sub-agent has access to file tools (Read, Write, Edit, Glob, Grep, LS) and Skill.
- By default (fork mode), the sub-agent inherits the current conversation context.
- Use run_in_background: true to run the agent asynchronously — you can continue working while it runs.
- Use isolation: "independent" if the sub-agent does NOT need the conversation context.
- For background agents, you will receive a task notification when it completes.
- Use TaskOutput to check on or wait for a background agent's result.
- Use TaskStop to cancel a running background agent.
- **Maximum 5 concurrent background agents.** Plan your parallelism accordingly.

When NOT to use:
- For simple, single-step tasks — just do them directly.
- The sub-agent cannot spawn further sub-agents (no nesting).
- The sub-agent cannot ask the user questions.''';
