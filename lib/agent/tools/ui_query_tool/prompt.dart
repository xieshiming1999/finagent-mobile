const description =
    'Query the current UI state: tiles, layout, displayed data.';

const prompt = '''Query the current state of the app UI.

Available keys:
- tiles: List all active tiles with their current data.
- tileCount: Number of active tiles.
- tile:<id>: Get a specific tile's data (e.g., "tile:icbc_quote").
- tilesExpanded: Whether the tile area is expanded or collapsed.
- chatExpanded: Whether the chat area is expanded or collapsed.

Returns the current value as JSON.''';
