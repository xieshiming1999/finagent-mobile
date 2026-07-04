const description = 'Search across conversation history.';

const prompt =
    '''Search across your conversation history to find past discussions, decisions, and results.

Two modes:
1. No query — Returns recent sessions with titles and timestamps.
2. With query — Full-text search across all session messages (supports Chinese).

## When to use
- User asks about something from a previous conversation
- You need context from past interactions
- User wants to find and resume a specific session

## Tips
- Specific keywords work best
- Chinese text is fully supported
- Results include session ID — use /resume to load a found session''';
