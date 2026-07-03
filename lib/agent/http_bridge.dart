import 'dart:convert';
import 'package:http/http.dart' as http;

/// Unified HTTP bridge function used by WebView handler, Monitor scheduler,
/// ScriptTool, and ServiceCall tool.
Future<http.Response> bridgeHttp({
  required String url,
  String method = 'GET',
  Map<String, dynamic>? params,
  Map<String, String>? headers,
  dynamic body,
  String? serviceBaseUrl,
}) async {
  final resolvedUrl = url.startsWith('http')
      ? url
      : '${serviceBaseUrl ?? ''}$url';

  final defaultHeaders = <String, String>{
    if (method == 'POST' || method == 'PUT') 'Content-Type': 'application/json',
    ...?headers,
  };

  switch (method.toUpperCase()) {
    case 'POST':
      return http.post(
        Uri.parse(resolvedUrl),
        headers: defaultHeaders,
        body: body is String ? body : jsonEncode(body ?? params ?? {}),
      );
    case 'PUT':
      return http.put(
        Uri.parse(resolvedUrl),
        headers: defaultHeaders,
        body: body is String ? body : jsonEncode(body ?? params ?? {}),
      );
    case 'DELETE':
      final uri = params != null && params.isNotEmpty
          ? Uri.parse(resolvedUrl).replace(
              queryParameters: params.map((k, v) => MapEntry(k, v.toString())),
            )
          : Uri.parse(resolvedUrl);
      return http.delete(uri, headers: defaultHeaders);
    default: // GET
      final uri = params != null && params.isNotEmpty
          ? Uri.parse(resolvedUrl).replace(
              queryParameters: params.map((k, v) => MapEntry(k, v.toString())),
            )
          : Uri.parse(resolvedUrl);
      return http.get(uri, headers: headers);
  }
}
