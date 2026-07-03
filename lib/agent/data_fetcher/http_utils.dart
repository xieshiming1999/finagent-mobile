import 'dart:math';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:http/http.dart' as http;

import 'api_stats.dart';

/// User-Agent pool for rotation.
const _userAgents = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
];

final _random = Random();
String? _configuredUserAgent;

void configureHttpUserAgent(String? userAgent) {
  final value = userAgent?.trim();
  _configuredUserAgent = value == null || value.isEmpty ? null : value;
}

String configuredHttpUserAgent() =>
    _configuredUserAgent ?? _userAgents[_random.nextInt(_userAgents.length)];

String randomUserAgent() => configuredHttpUserAgent();

/// HTTP GET with retry, UA rotation, and rate limiting.
Future<http.Response> fetchWithRetry(
  String url, {
  Map<String, String>? headers,
  Map<String, String>? queryParams,
  int maxAttempts = 3,
  Duration timeout = const Duration(seconds: 15),
  RateLimiter? rateLimiter,
}) async {
  await rateLimiter?.wait();

  final uri = queryParams != null && queryParams.isNotEmpty
      ? Uri.parse(url).replace(queryParameters: queryParams)
      : Uri.parse(url);

  final reqHeaders = {'User-Agent': randomUserAgent(), ...?headers};

  // EastMoney requires Referer header — without it, requests get rejected
  if (url.contains('eastmoney.com') && !reqHeaders.containsKey('Referer')) {
    reqHeaders['Referer'] = 'https://quote.eastmoney.com/';
    reqHeaders['Accept'] = 'application/json,text/plain,*/*';
    reqHeaders['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
    reqHeaders['Connection'] = 'close';
  }

  final sw = Stopwatch()..start();
  final source = ApiStats.sourceFromUrl(url);

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      final response = await http
          .get(uri, headers: reqHeaders)
          .timeout(timeout);
      if (response.statusCode == 200) {
        sw.stop();
        ApiStats.instance.record(
          source: source,
          method: 'GET',
          url: uri.toString(),
          statusCode: 200,
          durationMs: sw.elapsedMilliseconds,
          success: true,
          responseSummary: response.body.length > 200
              ? response.body.substring(0, 200)
              : response.body,
        );
        return response;
      }
      if (response.statusCode == 429 || response.statusCode >= 500) {
        if (attempt < maxAttempts - 1) {
          await Future.delayed(Duration(seconds: pow(2, attempt + 1).toInt()));
          continue;
        }
      }
      sw.stop();
      ApiStats.instance.record(
        source: source,
        method: 'GET',
        url: uri.toString(),
        statusCode: response.statusCode,
        durationMs: sw.elapsedMilliseconds,
        success: false,
        failureClass: switch (response.statusCode) {
          400 || 422 => 'invalid_parameters',
          401 || 403 => 'auth_permission',
          429 => 'quota_rate_limit',
          >= 500 => 'provider_outage',
          _ => 'unknown',
        },
        error: 'HTTP ${response.statusCode}',
      );
      return response;
    } catch (e) {
      if (attempt == maxAttempts - 1) {
        sw.stop();
        ApiStats.instance.record(
          source: source,
          method: 'GET',
          url: uri.toString(),
          statusCode: -1,
          durationMs: sw.elapsedMilliseconds,
          success: false,
          failureClass: 'transport',
          error: '$e',
        );
        rethrow;
      }
      await Future.delayed(Duration(seconds: pow(2, attempt + 1).toInt()));
    }
  }
  sw.stop();
  ApiStats.instance.record(
    source: source,
    method: 'GET',
    url: uri.toString(),
    statusCode: -1,
    durationMs: sw.elapsedMilliseconds,
    success: false,
    failureClass: 'transport',
    error: 'exhausted attempts',
  );
  throw Exception('fetchWithRetry: exhausted $maxAttempts attempts for $url');
}

/// Rate limiter with minimum interval + random jitter.
class RateLimiter {
  final Duration minInterval;
  final Duration maxJitter;
  DateTime? _lastRequest;

  RateLimiter({
    this.minInterval = const Duration(seconds: 2),
    this.maxJitter = const Duration(seconds: 3),
  });

  Future<void> wait() async {
    if (_lastRequest != null) {
      final elapsed = DateTime.now().difference(_lastRequest!);
      if (elapsed < minInterval) {
        await Future.delayed(minInterval - elapsed);
      }
    }
    await Future.delayed(
      Duration(milliseconds: _random.nextInt(maxJitter.inMilliseconds)),
    );
    _lastRequest = DateTime.now();
  }
}

/// Circuit breaker: CLOSED → OPEN (after threshold failures) → HALF_OPEN (after cooldown).
class CircuitBreaker {
  final int failureThreshold;
  final Duration cooldown;
  final Map<String, _CircuitState> _states = {};

  CircuitBreaker({
    this.failureThreshold = 3,
    this.cooldown = const Duration(minutes: 5),
  });

  bool isOpen(String source) {
    final state = _states[source];
    if (state == null) return false;
    if (state.status == _Status.open) {
      if (DateTime.now().difference(state.openedAt!) > cooldown) {
        state.status = _Status.halfOpen;
        return false;
      }
      return true;
    }
    return false;
  }

  void recordSuccess(String source) {
    _states[source] = _CircuitState(status: _Status.closed);
  }

  void recordFailure(String source) {
    final state = _states.putIfAbsent(source, () => _CircuitState());
    state.failures++;
    if (state.failures >= failureThreshold) {
      state.status = _Status.open;
      state.openedAt = DateTime.now();
    }
  }

  Map<String, String> get statusMap =>
      _states.map((k, v) => MapEntry(k, v.status.name));
}

enum _Status { closed, open, halfOpen }

class _CircuitState {
  _Status status;
  int failures;
  DateTime? openedAt;
  _CircuitState({this.status = _Status.closed}) : failures = 0;
}

/// Decode HTTP response body respecting charset from Content-Type header.
/// Handles GBK/GB2312 (common in Chinese finance APIs like qq, sina, eastmoney).
String decodeResponseBody(http.Response response) {
  final contentType = response.headers['content-type'] ?? '';
  final ctLower = contentType.toLowerCase();

  if (ctLower.contains('gbk') ||
      ctLower.contains('gb2312') ||
      ctLower.contains('gb18030')) {
    return gbk.decode(response.bodyBytes);
  }

  // Auto-detect: if UTF-8 decode produces replacement chars but GBK works, use GBK
  final body = response.body;
  if (body.contains('�') && response.bodyBytes.any((b) => b > 0x80)) {
    try {
      final gbkDecoded = gbk.decode(response.bodyBytes);
      if (!gbkDecoded.contains('�')) return gbkDecoded;
    } catch (_) {}
  }

  return body;
}
