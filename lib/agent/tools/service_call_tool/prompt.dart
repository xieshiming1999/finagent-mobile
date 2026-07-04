const description = 'Call a REST API endpoint via HTTP.';

const prompt =
    '''Call a REST API endpoint. Supports both relative and absolute URLs.

Usage:
- Provide the HTTP method (GET, POST, PUT, DELETE), path, and parameters.
- Relative paths (e.g., /api/finance/bars) use the configured service base URL.
- Absolute URLs (e.g., https://api.example.com/data) are called directly.
- For GET/DELETE, params are sent as query parameters.
- For POST/PUT, params are sent as JSON body.
- Use headers for authentication (e.g., {"Authorization": "Bearer xxx"}).
- Large responses (> 50 rows) are automatically saved to file with a summary.
- The Skill will tell you which API paths and parameters are available.

Note: This tool returns a summary for large data. When writing JS code that calls
Bridge.get/post, the JS receives the full raw response — not the truncated summary.
Test API availability with ServiceCall, then write JS knowing the full data is available.''';
