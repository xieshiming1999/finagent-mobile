import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:meta/meta.dart' show visibleForTesting;

import '../log.dart';
import 'api_stats.dart';

import 'base_fetcher.dart';
import 'cache.dart';
import 'http_utils.dart';
import 'models.dart';

/// Normalize stock code: handle prefix (SH600519), suffix (600519.SH), or bare (600519).
String _normalizeCode(String code) {
  final s = code.replaceAll(RegExp(r'\.(SH|SZ|BJ)$', caseSensitive: false), '');
  return s.replaceAll(RegExp(r'^(SH|SZ|BJ)', caseSensitive: false), '');
}

@visibleForTesting
int tdxIndexMarketForCode(String code) {
  final c = _normalizeCode(code);
  if (c.startsWith('399')) return 0;
  return 1;
}

/// TDX (通达信) binary protocol fetcher.
/// Direct TCP connection to public quote servers. Free, no API key needed.
///
/// Server list: loaded from `<basePath>/memory/.tdx_servers.json`.
/// Initialized from assets on first run, editable via Settings UI.
///
/// Probing: concurrent TCP probe, results written back to the same file
/// with latency/reachable/lastProbe fields. Re-probes daily.
///
/// Failure memory: servers that fail during connection are tracked in-memory.
/// After 3 consecutive failures, a server is skipped for the rest of the session.
/// Successful probe clears all failure records.
class TdxFetcher extends BaseFetcher {
  @override
  String get name => '通达信';
  @override
  int get priority => 1;

  String? basePath;

  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;
  final _socketBuffer = BytesBuilder();
  Completer<void>? _dataAvailable;
  int _seqId = 0;
  bool _connected = false;
  Timer? _heartbeatTimer;
  final _circuitBreaker = CircuitBreaker();
  final _quoteCache = DataCache<List<StockQuote>>(ttl: Duration(minutes: 5));

  // Failure tracking: host:port → consecutive failure count
  final _failureCounts = <String, int>{};
  static const _maxFailures = 3;
  // Last connected server — try it first on reconnect
  String? _lastGoodServer;

  @override
  bool canHandle(String code) {
    final c = _normalizeCode(code);
    return RegExp(r'^\d{6}$').hasMatch(c);
  }

  // ─── Connection ───

  Future<void> _ensureConnected() async {
    if (_connected && _socket != null) return;
    await _connect();
  }

  Future<void> _connect() async {
    _disconnect();

    final servers = await _getOrderedServers();
    if (servers.isEmpty) {
      throw DataFetchError(
        'TDX: no servers configured. Check Settings → TDX Servers.',
      );
    }

    for (final s in servers) {
      final key = '${s.host}:${s.port}';
      // Skip servers that failed too many times this session
      if ((_failureCounts[key] ?? 0) >= _maxFailures) continue;
      // Skip servers known to be unreachable from last probe
      if (s.reachable == false) continue;

      try {
        _socket = await Socket.connect(
          s.host,
          s.port,
          timeout: const Duration(seconds: 5),
        );
        _startListening();

        await _sendHello1();
        await _sendHello2();

        _connected = true;
        _lastGoodServer = key;
        _failureCounts.remove(key);
        _startHeartbeat();
        return;
      } catch (e) {
        _socket?.destroy();
        _socket = null;
        _failureCounts[key] = (_failureCounts[key] ?? 0) + 1;
        log('TDX', 'Connect failed for $key: $e');
        // Update file when a server hits max failures
        if (_failureCounts[key] == _maxFailures) {
          _markServerUnreachable(s.host, s.port);
        }
      }
    }

    final skipped = _failureCounts.entries
        .where((e) => e.value >= _maxFailures)
        .length;
    throw DataFetchError(
      'TDX: cannot connect (tried ${servers.length} servers, $skipped blacklisted this session)',
    );
  }

  // ─── Server List + Probing ───

  String get _serverFilePath => '$basePath/memory/.tdx_servers.json';

  /// Load servers from file. Returns empty list if no file.
  List<TdxServerEntry> loadServers() {
    if (basePath == null) return [];
    final file = File(_serverFilePath);
    if (!file.existsSync()) return [];
    try {
      final list = jsonDecode(file.readAsStringSync()) as List;
      return list
          .map((item) => TdxServerEntry.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Save servers back to file.
  void saveServers(List<TdxServerEntry> servers) {
    if (basePath == null) return;
    try {
      final file = File(_serverFilePath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(servers.map((s) => s.toJson()).toList()),
      );
    } catch (_) {}
  }

  /// Get servers ordered for connection: last-good first → reachable by latency → untested → skip failed.
  Future<List<TdxServerEntry>> _getOrderedServers() async {
    var servers = loadServers();
    if (servers.isEmpty) return [];

    // Only use standard quote port (7709/7719); exclude ExQuote (7727) servers.
    servers = servers.where((s) => s.port != 7727).toList();
    if (servers.isEmpty) return [];

    // Check if probe is stale (>1 day since any lastProbe)
    final needsProbe = servers.every((s) {
      if (s.lastProbe == null) return true;
      return DateTime.now().difference(s.lastProbe!) > const Duration(days: 1);
    });

    if (needsProbe) {
      servers = await probeAllServers(servers);
    }

    // Sort: last-good first, then reachable by latency, then untested, then unreachable
    final lastGood = _lastGoodServer;
    servers.sort((a, b) {
      final aKey = '${a.host}:${a.port}';
      final bKey = '${b.host}:${b.port}';

      // Last good server always first
      if (aKey == lastGood) return -1;
      if (bKey == lastGood) return 1;

      // Reachable before untested before unreachable
      final aScore = a.reachable == true ? 0 : (a.reachable == null ? 1 : 2);
      final bScore = b.reachable == true ? 0 : (b.reachable == null ? 1 : 2);
      if (aScore != bScore) return aScore.compareTo(bScore);

      // Within same reachability, sort by latency
      final aLat = a.latency ?? 9999;
      final bLat = b.latency ?? 9999;
      return aLat.compareTo(bLat);
    });

    return servers;
  }

  /// Probe all servers concurrently. Updates entries in-place and saves to file.
  Future<List<TdxServerEntry>> probeAllServers(
    List<TdxServerEntry> servers,
  ) async {
    final futures = servers.map((s) => _probeServer(s.host, s.port));
    final results = await Future.wait(futures);

    final now = DateTime.now();
    for (var i = 0; i < servers.length; i++) {
      final r = results[i];
      servers[i] = servers[i].copyWith(
        latency: r?.$3,
        reachable: r != null,
        lastProbe: now,
      );
    }

    // Successful probe clears failure records
    _failureCounts.clear();

    saveServers(servers);
    return servers;
  }

  Future<(String, int, int)?> _probeServer(String host, int port) async {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      sw.stop();
      socket.destroy();
      return (host, port, sw.elapsedMilliseconds);
    } catch (_) {
      return null;
    }
  }

  void _disconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _socketBuffer.clear();
    _dataAvailable = null;
    _socket?.destroy();
    _socket = null;
    _connected = false;
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_connected) _sendHeartbeat();
    });
  }

  // ─── Protocol ───

  Uint8List _buildHeader(int method, Uint8List payload, {int control = 0x01}) {
    final seqBytes = _uint32LE(_seqId++);
    final bodyLen = 2 + payload.length;
    final lenBytes = _uint16LE(bodyLen);
    final methodBytes = _uint16LE(method);

    final buf = BytesBuilder();
    buf.addByte(0x0C);
    buf.add(seqBytes);
    buf.addByte(control);
    buf.add(lenBytes);
    buf.add(lenBytes);
    buf.add(methodBytes);
    buf.add(payload);
    return buf.toBytes();
  }

  Future<Uint8List> _sendAndReceive(
    int method,
    Uint8List payload, {
    int control = 0x01,
  }) async {
    final sw = Stopwatch()..start();
    for (var attempt = 0; attempt < 2; attempt++) {
      await _ensureConnected();
      try {
        final packet = _buildHeader(method, payload, control: control);
        _socket!.add(packet);
        await _socket!.flush();
        final result = await _readResponse();
        sw.stop();
        ApiStats.instance.record(
          source: '通达信',
          method: 'TCP',
          url: '0x${method.toRadixString(16)}',
          statusCode: 200,
          durationMs: sw.elapsedMilliseconds,
          success: true,
        );
        return result;
      } catch (e) {
        // First attempt failed — disconnect and retry with reconnect
        _disconnect();
        if (attempt == 0) continue;
        sw.stop();
        ApiStats.instance.record(
          source: '通达信',
          method: 'TCP',
          url: '0x${method.toRadixString(16)}',
          statusCode: 0,
          durationMs: sw.elapsedMilliseconds,
          success: false,
          error: '$e',
        );
        rethrow;
      }
    }
    throw DataFetchError('TDX: send failed after retry');
  }

  Future<Uint8List> _readResponse() async {
    final headerBuf = await _readExact(16);
    final zipLen = ByteData.sublistView(
      headerBuf,
      12,
      14,
    ).getUint16(0, Endian.little);
    final unzipLen = ByteData.sublistView(
      headerBuf,
      14,
      16,
    ).getUint16(0, Endian.little);

    final data = await _readExact(zipLen);

    if (zipLen != unzipLen && zipLen > 0) {
      try {
        return Uint8List.fromList(zlib.decode(data));
      } catch (_) {
        return data;
      }
    }
    return data;
  }

  Future<Uint8List> _readExact(int length) async {
    while (_socketBuffer.length < length) {
      _dataAvailable = Completer<void>();
      await _dataAvailable!.future.timeout(const Duration(seconds: 10));
    }
    final all = _socketBuffer.takeBytes();
    final result = Uint8List.fromList(all.sublist(0, length));
    if (all.length > length) {
      _socketBuffer.add(all.sublist(length));
    }
    return result;
  }

  void _startListening() {
    _socketBuffer.clear();
    _socketSubscription?.cancel();
    _socketSubscription = _socket!.listen(
      (data) {
        _socketBuffer.add(data);
        _dataAvailable?.complete();
        _dataAvailable = null;
      },
      onError: (e) {
        _dataAvailable?.completeError(e);
        _dataAvailable = null;
        _disconnect();
      },
      onDone: () {
        _dataAvailable?.completeError(StateError('Socket closed'));
        _dataAvailable = null;
        _connected = false;
      },
    );
  }

  Future<void> _sendHello1() async {
    final packet = _buildHeader(0x000D, Uint8List.fromList([0x01]));
    _socket!.add(packet);
    await _socket!.flush();
    await _readResponse();
  }

  Future<void> _sendHello2() async {
    final payload = _hexDecode(
      'd5d0c9ccd6a4a8af0000008fc22540130000d500c9ccbdf0d7ea00000002',
    );
    final packet = _buildHeader(0x0FDB, payload);
    _socket!.add(packet);
    await _socket!.flush();
    await _readResponse();
  }

  void _sendHeartbeat() {
    try {
      final packet = _buildHeader(0x0004, Uint8List(0));
      _socket?.add(packet);
    } catch (_) {
      _disconnect();
    }
  }

  // ─── K-Line ───

  @override
  Future<List<KlineBar>> getKline(
    String code, {
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    final c = _normalizeCode(code);
    final market = c.startsWith('6') ? 1 : 0;
    final category = switch (period) {
      'weekly' => 5,
      'monthly' => 6,
      _ => 9,
    };
    final count = 800;

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));
      payload.add(_uint16LE(category));
      payload.add(_uint16LE(1)); // times
      payload.add(_uint16LE(0)); // start (0 = latest)
      payload.add(_uint16LE(count));
      payload.add(_uint16LE(0)); // adjust
      payload.add(Uint8List(8)); // reserved

      final data = await _sendAndReceive(
        0x052D,
        payload.toBytes(),
        control: 0x00,
      );
      final bars = _parseKlineBars(data, category);

      _circuitBreaker.recordSuccess(name);

      // Filter by date if specified
      if (startDate.isNotEmpty) {
        final start = startDate.replaceAll('-', '');
        return bars
            .where((b) => b.date.replaceAll('-', '').compareTo(start) >= 0)
            .toList();
      }
      return bars;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  List<KlineBar> _parseKlineBars(Uint8List data, int category) {
    if (data.length < 2) return [];
    final count = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
    final bars = <KlineBar>[];
    final pos = [2]; // mutable position

    double lastClose = 0;
    for (var i = 0; i < count && pos[0] < data.length - 4; i++) {
      // DateTime
      String date;
      if (category >= 4 && category != 7 && category != 8) {
        // Daily: uint32 = YYYYMMDD
        final raw = ByteData.sublistView(
          data,
          pos[0],
          pos[0] + 4,
        ).getUint32(0, Endian.little);
        pos[0] += 4;
        final y = raw ~/ 10000, m = (raw % 10000) ~/ 100, d = raw % 100;
        date =
            '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      } else {
        // Minute
        final rawDate = ByteData.sublistView(
          data,
          pos[0],
          pos[0] + 2,
        ).getUint16(0, Endian.little);
        final rawTime = ByteData.sublistView(
          data,
          pos[0] + 2,
          pos[0] + 4,
        ).getUint16(0, Endian.little);
        pos[0] += 4;
        final y = (rawDate >> 11) + 2004, md = rawDate & 0x7FF;
        date =
            '$y-${(md ~/ 100).toString().padLeft(2, '0')}-${(md % 100).toString().padLeft(2, '0')} ${(rawTime ~/ 60).toString().padLeft(2, '0')}:${(rawTime % 60).toString().padLeft(2, '0')}';
      }

      // Prices (varint encoded)
      final openDelta = _getPrice(data, pos);
      final closeDelta = _getPrice(data, pos);
      final highDelta = _getPrice(data, pos);
      final lowDelta = _getPrice(data, pos);

      final openRaw = lastClose + openDelta;
      final closeRaw = openRaw + closeDelta;
      final highRaw = openRaw + highDelta;
      final lowRaw = openRaw + lowDelta;
      lastClose = closeRaw;

      // Volume and Amount (IEEE float32, 4 bytes LE each)
      final volume = pos[0] + 4 <= data.length
          ? ByteData.sublistView(
              data,
              pos[0],
              pos[0] + 4,
            ).getFloat32(0, Endian.little).toDouble()
          : 0.0;
      pos[0] += 4;
      final amount = pos[0] + 4 <= data.length
          ? ByteData.sublistView(
              data,
              pos[0],
              pos[0] + 4,
            ).getFloat32(0, Endian.little).toDouble()
          : 0.0;
      pos[0] += 4;

      final scale = 1000.0; // daily prices in 1/1000 yuan
      bars.add(
        KlineBar(
          date: date,
          open: openRaw / scale,
          close: closeRaw / scale,
          high: highRaw / scale,
          low: lowRaw / scale,
          volume: volume,
          amount: amount,
        ),
      );
    }
    return bars;
  }

  // ─── Real-time Quotes ───

  @override
  Future<List<StockQuote>> getQuotes(List<String> codes) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    if (codes.isEmpty) return [];

    // Check cache
    final cacheKey = codes.join(',');
    final cached = _quoteCache.getTracked(cacheKey);
    if (cached != null) return cached;

    try {
      final n = codes.length;
      final payload = BytesBuilder();
      payload.add(_uint16LE(5)); // fixed constant
      payload.add(Uint8List(6)); // padding
      payload.add(_uint16LE(n));
      for (final code in codes) {
        final c = _normalizeCode(code);
        payload.addByte(c.startsWith('6') ? 1 : 0); // market
        payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));
      }

      final data = await _sendAndReceive(0x053E, payload.toBytes());
      final quotes = _parseQuotes(data);

      _circuitBreaker.recordSuccess(name);
      _quoteCache.set(cacheKey, quotes);
      return quotes;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  List<StockQuote> _parseQuotes(Uint8List data) {
    if (data.length < 4) return [];
    // Skip 2 unknown bytes
    final count = ByteData.sublistView(data, 2, 4).getUint16(0, Endian.little);
    final quotes = <StockQuote>[];
    final pos = [4];

    for (var i = 0; i < count && pos[0] < data.length - 10; i++) {
      try {
        pos[0]++;
        final codeBytes = data.sublist(pos[0], pos[0] + 6);
        pos[0] += 6;
        final code = _decodeGBK(codeBytes);

        pos[0] += 2; // active1

        final basePrice = _getPrice(data, pos);
        final preCloseDiff = _getPrice(data, pos);
        final openDiff = _getPrice(data, pos);
        final highDiff = _getPrice(data, pos);
        final lowDiff = _getPrice(data, pos);

        _getPrice(data, pos); // serverTime
        _getPrice(data, pos); // negPrice

        final vol = _getPrice(data, pos);
        _getPrice(data, pos); // curVol

        // amount (IEEE float32, 4 bytes LE)
        final amount = pos[0] + 4 <= data.length
            ? ByteData.sublistView(
                data,
                pos[0],
                pos[0] + 4,
              ).getFloat32(0, Endian.little)
            : 0.0;
        pos[0] += 4;

        _getPrice(data, pos); // sVol
        _getPrice(data, pos); // bVol
        _getPrice(data, pos); // sAmount
        _getPrice(data, pos); // openAmount

        // Skip 5 bid/ask levels (4 varints each = 20 varints)
        for (var j = 0; j < 20; j++) {
          _getPrice(data, pos);
        }

        // Tail: unknown(2) + skip(4) + riseSpeed(2) + active2(2) = 10 bytes
        if (pos[0] + 10 <= data.length) pos[0] += 10;

        final price = basePrice / 100.0;
        final preClose = (basePrice + preCloseDiff) / 100.0;
        final open = (basePrice + openDiff) / 100.0;
        final high = (basePrice + highDiff) / 100.0;
        final low = (basePrice + lowDiff) / 100.0;
        final change = price - preClose;
        final changePct = preClose != 0 ? change / preClose * 100 : 0.0;

        quotes.add(
          StockQuote(
            code: code,
            name: '', // TDX protocol doesn't return names in quotes
            price: _r2(price),
            change: _r2(change),
            changePct: _r2(changePct),
            open: _r2(open),
            high: _r2(high),
            low: _r2(low),
            prevClose: _r2(preClose),
            volume: vol.toDouble(),
            amount: amount.toDouble(),
            source: name,
          ),
        );
      } catch (_) {
        break;
      }
    }
    return quotes;
  }

  @override
  Future<List<MoneyFlow>> getMoneyFlow(String code) async {
    throw DataFetchError('$name does not support money flow');
  }

  // ─── StockTickChart (分时图, 0x0537) ───

  /// Get current day minute-level time chart.
  /// Returns list of {time, price, avg, volume} for each minute.
  Future<List<Map<String, dynamic>>> getTickChart(
    String code, {
    int start = 0,
    int count = 240,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = c.startsWith('6') ? 1 : 0;

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));
      payload.add(_uint16LE(start));
      payload.add(_uint16LE(count));

      final data = await _sendAndReceive(
        0x0537,
        payload.toBytes(),
        control: 0x00,
      );
      final results = _parseTickChart(data);
      _circuitBreaker.recordSuccess(name);
      return results;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  List<Map<String, dynamic>> _parseTickChart(Uint8List data) {
    if (data.length < 4) return [];
    final count = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
    // Skip: count(2) + ignored(2) = 4 bytes
    final pos = [4];
    final results = <Map<String, dynamic>>[];
    int basePrice = 0, baseAvg = 0;

    for (var i = 0; i < count && pos[0] < data.length - 2; i++) {
      int price = _getPrice(data, pos);
      int avg = _getPrice(data, pos);
      final vol = _getPrice(data, pos);

      // First entry is absolute; subsequent are deltas from the first.
      if (basePrice != 0) price += basePrice;
      if (baseAvg != 0) avg += baseAvg;
      if (basePrice == 0) basePrice = price;
      if (baseAvg == 0) baseAvg = avg;

      // Time: A-share trading hours 9:30-11:30 (120 min) + 13:00-15:00 (120 min)
      final totalMinutes = i < 120 ? (9 * 60 + 30 + i) : (13 * 60 + (i - 120));
      final hour = totalMinutes ~/ 60;
      final minute = totalMinutes % 60;

      results.add({
        'minute': i,
        'time':
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
        'price': price / 100.0,
        'avg': avg / 10000.0,
        'volume': vol,
      });
    }
    return results;
  }

  // ─── StockTransaction (逐笔成交, 0x0fc5) ───

  /// Get tick-by-tick transactions for today.
  Future<List<Map<String, dynamic>>> getTransactions(
    String code, {
    int start = 0,
    int count = 100,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = c.startsWith('6') ? 1 : 0;

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));
      payload.add(_uint16LE(start));
      payload.add(_uint16LE(count));

      final data = await _sendAndReceive(
        0x0fc5,
        payload.toBytes(),
        control: 0x00,
      );
      final results = _parseTransactions(data, c);
      _circuitBreaker.recordSuccess(name);
      return results;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  List<Map<String, dynamic>> _parseTransactions(Uint8List data, String code) {
    if (data.length < 2) return [];
    final count = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
    final pos = [2];
    final results = <Map<String, dynamic>>[];
    int lastPrice = 0;
    // baseUnit: codes starting with 6/0/3/00 use 100, others 1000
    final baseUnit =
        (code.startsWith('6') || code.startsWith('0') || code.startsWith('3'))
        ? 100.0
        : 1000.0;

    for (var i = 0; i < count && pos[0] < data.length - 2; i++) {
      final timeRaw = pos[0] + 2 <= data.length
          ? ByteData.sublistView(
              data,
              pos[0],
              pos[0] + 2,
            ).getUint16(0, Endian.little)
          : 0;
      pos[0] += 2;
      final priceDelta = _getPrice(data, pos);
      final vol = _getPrice(data, pos);
      final num = _getPrice(data, pos);
      final buyOrSell = _getPrice(data, pos);
      _getPrice(data, pos); // ignored
      lastPrice += priceDelta;
      final hour = timeRaw ~/ 60;
      final minute = timeRaw % 60;
      results.add({
        'time':
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
        'price': lastPrice / baseUnit,
        'volume': vol,
        'trades': num,
        'direction': buyOrSell == 0
            ? 'buy'
            : buyOrSell == 1
            ? 'sell'
            : 'neutral',
      });
    }
    return results;
  }

  // ─── GetFinanceInfo (财务数据, 0x0010) ───

  /// Get financial data for a stock (EPS, assets, revenue, etc).
  Future<Map<String, dynamic>> getFinanceInfo(String code) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = c.startsWith('6') ? 1 : 0;

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(1)); // always 1
      payload.addByte(market);
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));

      final data = await _sendAndReceive(
        0x0010,
        payload.toBytes(),
        control: 0x00,
      );
      final result = _parseFinanceInfo(data);
      _circuitBreaker.recordSuccess(name);
      return result;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  Map<String, dynamic> _parseFinanceInfo(Uint8List data) {
    if (data.length < 100) return {'error': 'insufficient data'};
    // Skip: num(2) + market(1) + code(6) = 9 bytes
    var pos = 9;
    double f32() {
      if (pos + 4 > data.length) return 0;
      final v = ByteData.sublistView(
        data,
        pos,
        pos + 4,
      ).getFloat32(0, Endian.little);
      pos += 4;
      return v;
    }

    int u16() {
      if (pos + 2 > data.length) return 0;
      final v = ByteData.sublistView(
        data,
        pos,
        pos + 2,
      ).getUint16(0, Endian.little);
      pos += 2;
      return v;
    }

    int u32() {
      if (pos + 4 > data.length) return 0;
      final v = ByteData.sublistView(
        data,
        pos,
        pos + 4,
      ).getUint32(0, Endian.little);
      pos += 4;
      return v;
    }

    return {
      'floatShares': f32(),
      'province': u16(),
      'industry': u16(),
      'updatedDate': u32(),
      'ipoDate': u32(),
      'totalShares': f32(),
      'stateShares': f32(),
      'sponsorLegalShares': f32(),
      'legalShares': f32(),
      'bShares': f32(),
      'hShares': f32(),
      'eps': f32(),
      'totalAssets': f32(),
      'currentAssets': f32(),
      'fixedAssets': f32(),
      'intangibleAssets': f32(),
      'shareholderCount': f32(),
      'currentLiabilities': f32(),
      'longTermLiabilities': f32(),
      'capitalReserve': f32(),
      'totalEquity': f32(),
      'operatingRevenue': f32(),
      'operatingCost': f32(),
      'accountsReceivable': f32(),
      'operatingProfit': f32(),
      'investmentIncome': f32(),
      'netCashFlow': f32(),
      'totalCashInflow': f32(),
      'inventory': f32(),
      'totalProfit': f32(),
      'afterTaxProfit': f32(),
      'netProfit': f32(),
      'undistributedProfit': f32(),
      'netAssetsPerShare': f32(),
      'source': name,
    };
  }

  // ─── GetXDXRInfo (除权除息, 0x000f) ───

  /// Get ex-dividend/rights info (除权除息信息).
  Future<List<Map<String, dynamic>>> getXDXRInfo(String code) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = c.startsWith('6') ? 1 : 0;

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(1)); // always 1
      payload.addByte(market);
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));

      final data = await _sendAndReceive(
        0x000f,
        payload.toBytes(),
        control: 0x00,
      );
      final results = _parseXDXRInfo(data);
      _circuitBreaker.recordSuccess(name);
      return results;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  List<Map<String, dynamic>> _parseXDXRInfo(Uint8List data) {
    if (data.length < 11) return [];
    // Skip: market(1) + marketOR(2) + code(6) = 9 bytes
    final count = ByteData.sublistView(data, 9, 11).getUint16(0, Endian.little);
    final results = <Map<String, dynamic>>[];

    for (var i = 0; i < count; i++) {
      final base = 11 + i * 29;
      if (base + 29 > data.length) break;
      // Skip market(1) + code(6) + unknown(1) = 8 bytes
      final date = ByteData.sublistView(
        data,
        base + 8,
        base + 12,
      ).getUint32(0, Endian.little);
      final category = data[base + 12];
      final a = ByteData.sublistView(
        data,
        base + 13,
        base + 17,
      ).getFloat32(0, Endian.little);
      final b = ByteData.sublistView(
        data,
        base + 17,
        base + 21,
      ).getFloat32(0, Endian.little);
      final c = ByteData.sublistView(
        data,
        base + 21,
        base + 25,
      ).getFloat32(0, Endian.little);
      final d = ByteData.sublistView(
        data,
        base + 25,
        base + 29,
      ).getFloat32(0, Endian.little);

      final categoryName = _xdxrCategoryName(category);
      results.add({
        'date':
            '${date ~/ 10000}-${((date % 10000) ~/ 100).toString().padLeft(2, '0')}-${(date % 100).toString().padLeft(2, '0')}',
        'category': category,
        'categoryName': categoryName,
        'a': a,
        'b': b,
        'c': c,
        'd': d,
      });
    }
    results.sort(
      (a, b) => (b['date'] as String).compareTo(a['date'] as String),
    );
    return results;
  }

  static String _xdxrCategoryName(int cat) => switch (cat) {
    1 => '除权除息',
    2 => '送配股上市',
    3 => '非流通股上市',
    4 => '未知股本变动',
    5 => '股本变化',
    6 => '增发新股',
    7 => '股份回购',
    8 => '增发新股上市',
    9 => '转配股上市',
    10 => '可转债上市',
    11 => '扩缩股',
    12 => '非流通股缩股',
    13 => '送认购权证',
    14 => '送认沽权证',
    _ => '其他($cat)',
  };

  // ─── StockCount (证券数量, 0x044e) ───

  /// Get total number of securities in a market.
  Future<int> getStockCount({int market = 0}) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    try {
      final now = DateTime.now();
      final dateInt = now.year * 10000 + now.month * 100 + now.day;
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(_uint32LE(dateInt));

      final data = await _sendAndReceive(
        0x044e,
        payload.toBytes(),
        control: 0x01,
      );
      _circuitBreaker.recordSuccess(name);
      if (data.length < 2) return 0;
      return ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  /// Get sampled intraday chart prices for a stock.
  Future<Map<String, dynamic>> getChartSampling(String code) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = c.startsWith('6') ? 1 : 0;
    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));
      payload.add(
        Uint8List.fromList(const [
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x01,
          0x00,
          0x14,
          0x00,
          0x00,
          0x00,
          0x00,
          0x01,
          0x00,
          0x00,
          0x00,
          0x00,
        ]),
      );
      final data = await _sendAndReceive(
        0x0FD1,
        payload.toBytes(),
        control: 0x00,
      );
      _circuitBreaker.recordSuccess(name);
      return _parseChartSampling(data);
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  // ─── StockIndexInfo (指数信息, 0x051d) ───

  /// Get index information (close, open, high, low, volume, up/down counts).
  Future<Map<String, dynamic>> getIndexInfo(String code) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = tdxIndexMarketForCode(c);

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));
      payload.add(_uint32LE(0));

      final data = await _sendAndReceive(
        0x051d,
        payload.toBytes(),
        control: 0x00,
      );
      _circuitBreaker.recordSuccess(name);
      return _parseIndexInfo(data);
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  Map<String, dynamic> _parseChartSampling(Uint8List data) {
    if (data.length < 42)
      return {
        'code': '',
        'market': 0,
        'preClose': 0.0,
        'prices': const <double>[],
      };
    final market = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
    final code = utf8.decode(data.sublist(2, 8)).replaceAll('\x00', '').trim();
    final count = ByteData.sublistView(
      data,
      34,
      36,
    ).getUint16(0, Endian.little);
    final preClose = ByteData.sublistView(
      data,
      36,
      40,
    ).getFloat32(0, Endian.little).toDouble();
    final prices = <double>[];
    var pos = 42;
    for (var i = 0; i < count && pos + 4 <= data.length; i++) {
      prices.add(
        ByteData.sublistView(
          data,
          pos,
          pos + 4,
        ).getFloat32(0, Endian.little).toDouble(),
      );
      pos += 4;
    }
    return {
      'market': market,
      'code': code,
      'count': prices.length,
      'preClose': preClose,
      'prices': prices,
    };
  }

  Map<String, dynamic> _parseIndexInfo(Uint8List data) {
    if (data.length < 20) return {'error': 'insufficient data'};
    final pos = [0];
    // Skip: orderCount(4) + market(1) + code(6) + active(2) = 13 bytes
    pos[0] = 13;
    final closeRaw = _getPrice(data, pos);
    final preCloseDiff = _getPrice(data, pos);
    final openDiff = _getPrice(data, pos);
    final highDiff = _getPrice(data, pos);
    final lowDiff = _getPrice(data, pos);
    _getPrice(data, pos); // serverTime
    _getPrice(data, pos); // afterHour
    final vol = _getPrice(data, pos);
    _getPrice(data, pos); // curVol
    // amount: float32
    double amount = 0;
    if (pos[0] + 4 <= data.length) {
      amount = ByteData.sublistView(
        data,
        pos[0],
        pos[0] + 4,
      ).getFloat32(0, Endian.little);
      pos[0] += 4;
    }

    return {
      'close': closeRaw / 100.0,
      'preClose': (closeRaw + preCloseDiff) / 100.0,
      'open': (closeRaw + openDiff) / 100.0,
      'high': (closeRaw + highDiff) / 100.0,
      'low': (closeRaw + lowDiff) / 100.0,
      'volume': vol,
      'amount': amount,
      'change': -preCloseDiff / 100.0,
      'changePct': closeRaw != 0
          ? (-preCloseDiff / (closeRaw + preCloseDiff)) * 100
          : 0.0,
      'source': name,
    };
  }

  // ─── StockUnusual (盘口异动, 0x0563) ───

  /// Get unusual market activity (火箭发射/大笔买入/涨停打开 etc).
  Future<List<Map<String, dynamic>>> getUnusualActivity({
    int market = 0,
    int start = 0,
    int count = 100,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(_uint32LE(start));
      payload.add(_uint32LE(count == 0 ? 600 : count));

      final data = await _sendAndReceive(
        0x0563,
        payload.toBytes(),
        control: 0x00,
      );
      _circuitBreaker.recordSuccess(name);
      return _parseUnusual(data);
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  List<Map<String, dynamic>> _parseUnusual(Uint8List data) {
    if (data.length < 2) return [];
    final count = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
    final results = <Map<String, dynamic>>[];

    for (var i = 0; i < count; i++) {
      final base = 2 + i * 32;
      if (base + 32 > data.length) break;
      final market = ByteData.sublistView(
        data,
        base,
        base + 2,
      ).getUint16(0, Endian.little);
      final codeBytes = data.sublist(base + 2, base + 8);
      final code = _decodeGBK(codeBytes);
      final eventType = data[base + 9];
      final hour = data[base + 29];
      final minuteSec = ByteData.sublistView(
        data,
        base + 30,
        base + 32,
      ).getUint16(0, Endian.little);
      final minute = minuteSec ~/ 100;
      final second = minuteSec % 100;

      results.add({
        'code': code,
        'market': market,
        'eventType': eventType,
        'eventName': _unusualTypeName(eventType),
        'time':
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
      });
    }
    return results;
  }

  static String _unusualTypeName(int type) => switch (type) {
    0x03 => '主力买卖',
    0x04 => '加速拉升',
    0x05 => '加速下跌',
    0x06 => '低位反弹',
    0x07 => '高位回落',
    0x08 => '撑杆跳高',
    0x09 => '平台跳水',
    0x0a => '单笔冲涨',
    0x0b => '区间放量',
    0x0c => '区间缩量',
    0x10 => '大单托盘',
    0x11 => '大单压盘',
    0x12 => '大单锁盘',
    0x13 => '竞价试买',
    0x14 => '涨跌停',
    0x15 => '尾盘异动',
    0x16 => '盘中强弱',
    0x1d => '急速拉升',
    0x1e => '急速下跌',
    _ => '异动($type)',
  };

  // ─── StockList (证券列表, 0x044d) ───

  /// Get list of securities in a market.
  Future<List<Map<String, dynamic>>> getStockList({
    int market = 0,
    int start = 0,
    int count = 1000,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(_uint32LE(start));
      payload.add(_uint32LE(count));
      payload.add(_uint32LE(0));

      final data = await _sendAndReceive(
        0x044d,
        payload.toBytes(),
        control: 0x01,
      );
      _circuitBreaker.recordSuccess(name);
      return _parseStockList(data);
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  List<Map<String, dynamic>> _parseStockList(Uint8List data) {
    if (data.length < 2) return [];
    final count = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
    final results = <Map<String, dynamic>>[];
    // Each record = 37 bytes: code(6) + vol(2) + name(16) + unknown(4) + decimal(1) + preClose(4) + unknown(2) + unknown(2)
    for (var i = 0; i < count; i++) {
      final base = 2 + i * 37;
      if (base + 37 > data.length) break;
      final codeBytes = data.sublist(base, base + 6);
      final code = _decodeGBK(codeBytes);
      final vol = ByteData.sublistView(
        data,
        base + 6,
        base + 8,
      ).getUint16(0, Endian.little);
      final nameBytes = data.sublist(base + 8, base + 24);
      final stockName = _decodeGBK(nameBytes);
      final preClose = ByteData.sublistView(
        data,
        base + 29,
        base + 33,
      ).getFloat32(0, Endian.little);

      if (code.isNotEmpty) {
        results.add({
          'code': code,
          'name': stockName,
          'volUnit': vol,
          'preClose': _r2(preClose),
        });
      }
    }
    return results;
  }

  CircuitBreaker get circuitBreaker => _circuitBreaker;

  /// Mark a server as unreachable in the persisted file (called during runtime failures).
  void _markServerUnreachable(String host, int port) {
    final servers = loadServers();
    final key = '$host:$port';
    var updated = false;
    for (var i = 0; i < servers.length; i++) {
      if (servers[i].key == key) {
        servers[i] = servers[i].copyWith(
          reachable: false,
          lastProbe: DateTime.now(),
        );
        updated = true;
        break;
      }
    }
    if (updated) saveServers(servers);
  }

  // ─── VolumeProfile (筹码分布, 0x051a) ───

  /// Get volume profile (cost distribution) for a stock.
  /// Returns {close, open, high, low, preClose, vol, amount, profiles: [{price, vol, buy, sell}]}
  Future<Map<String, dynamic>> getVolumeProfile(String code) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = c.startsWith('6') ? 1 : 0;

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));

      final data = await _sendAndReceive(
        0x051a,
        payload.toBytes(),
        control: 0x00,
      );
      final result = _parseVolumeProfile(data);
      _circuitBreaker.recordSuccess(name);
      return result;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  Map<String, dynamic> _parseVolumeProfile(Uint8List data) {
    if (data.length < 20) return {'error': 'insufficient data'};
    final count = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
    final pos = [11]; // skip count(2) + market(1) + code(6) + active(2)

    final basePrice = _getPrice(data, pos);
    final preCloseDiff = _getPrice(data, pos);
    final openDiff = _getPrice(data, pos);
    final highDiff = _getPrice(data, pos);
    final lowDiff = _getPrice(data, pos);
    _getPrice(data, pos); // serverTime
    _getPrice(data, pos); // negPrice
    final vol = _getPrice(data, pos);
    _getPrice(data, pos); // curVol
    // amount is float32
    double amount = 0;
    if (pos[0] + 4 <= data.length) {
      amount = ByteData.sublistView(
        data,
        pos[0],
        pos[0] + 4,
      ).getFloat32(0, Endian.little).toDouble();
      pos[0] += 4;
    }
    _getPrice(data, pos); // inVol
    _getPrice(data, pos); // outVol
    _getPrice(data, pos); // sAmount
    _getPrice(data, pos); // openAmount

    // Skip bid/ask 3 levels (4 varints × 3 = 12)
    for (var i = 0; i < 12; i++) {
      _getPrice(data, pos);
    }
    // Skip unknown uint16
    if (pos[0] + 2 <= data.length) pos[0] += 2;

    final profiles = <Map<String, dynamic>>[];
    int profilePrice = 0;
    for (var i = 0; i < count && pos[0] < data.length - 2; i++) {
      final priceDelta = _getPrice(data, pos);
      final pVol = _getPrice(data, pos);
      final buy = _getPrice(data, pos);
      final sell = _getPrice(data, pos);
      profilePrice += priceDelta;
      profiles.add({
        'price': _r2(profilePrice / 100.0),
        'vol': pVol,
        'buy': buy,
        'sell': sell,
      });
    }

    return {
      'close': _r2(basePrice / 100.0),
      'open': _r2((basePrice + openDiff) / 100.0),
      'high': _r2((basePrice + highDiff) / 100.0),
      'low': _r2((basePrice + lowDiff) / 100.0),
      'preClose': _r2((basePrice + preCloseDiff) / 100.0),
      'vol': vol,
      'amount': amount,
      'profiles': profiles,
      'count': profiles.length,
    };
  }

  // ─── Auction (集合竞价, 0x056a) ───

  /// Get auction (pre-market) data for a stock.
  Future<List<Map<String, dynamic>>> getAuction(
    String code, {
    int start = 0,
    int count = 50,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = c.startsWith('6') ? 1 : 0;

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));
      payload.add(_uint32LE(0)); // zero1
      payload.add(_uint32LE(0)); // mode
      payload.add(_uint32LE(0)); // zero2
      payload.add(_uint32LE(start));
      payload.add(_uint32LE(count));

      final data = await _sendAndReceive(
        0x056a,
        payload.toBytes(),
        control: 0x00,
      );
      final result = _parseAuction(data);
      _circuitBreaker.recordSuccess(name);
      return result;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  List<Map<String, dynamic>> _parseAuction(Uint8List data) {
    if (data.length < 4) return [];
    final count = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
    final results = <Map<String, dynamic>>[];

    for (var i = 0; i < count; i++) {
      final base = i * 16 + 2;
      if (base + 16 > data.length) break;
      final bd = ByteData.sublistView(data, base, base + 16);
      results.add({
        'time': bd.getInt32(0, Endian.little),
        'price': _r2(bd.getInt32(4, Endian.little) / 1000.0),
        'volume': bd.getInt32(8, Endian.little),
        'index': bd.getInt32(12, Endian.little),
      });
    }
    return results;
  }

  // ─── HistoryMinuteTimeData (历史分时, 0x0feb) ───

  /// Get historical minute-level time chart for a specific date.
  Future<List<Map<String, dynamic>>> getHistoryTickChart(
    String code,
    int date,
  ) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = c.startsWith('6') ? 1 : 0;

    try {
      final payload = BytesBuilder();
      payload.add(_uint32LE(-date)); // negative encoding
      payload.add([market]);
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));

      final data = await _sendAndReceive(
        0x0feb,
        payload.toBytes(),
        control: 0x00,
      );
      final result = _parseHistoryTickChart(data);
      _circuitBreaker.recordSuccess(name);
      return result;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  List<Map<String, dynamic>> _parseHistoryTickChart(Uint8List data) {
    if (data.length < 4) return [];
    final count = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
    final pos = [4]; // skip count(2) + padding(2)
    final results = <Map<String, dynamic>>[];
    int basePrice = 0;

    for (var i = 0; i < count && pos[0] < data.length - 2; i++) {
      final price = _getPrice(data, pos);
      final avg = _getPrice(data, pos);
      final vol = _getPrice(data, pos);
      basePrice += price;
      results.add({
        'minute': i,
        'price': _r2(basePrice / 100.0),
        'avg': _r2((basePrice + avg) / 100.0),
        'volume': vol,
      });
    }
    return results;
  }

  // ─── IndexMomentum (指数动量, 0x051c) ───

  /// Get index momentum data.
  Future<Map<String, dynamic>> getIndexMomentum(String code) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = c.startsWith('6') || c.startsWith('0') && c.length == 6
        ? 1
        : 0;

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));

      final data = await _sendAndReceive(
        0x051c,
        payload.toBytes(),
        control: 0x00,
      );
      _circuitBreaker.recordSuccess(name);

      if (data.length < 4) return {'code': code, 'momentum': []};
      final count = ByteData.sublistView(
        data,
        0,
        2,
      ).getUint16(0, Endian.little);
      final pos = [2];
      final momentum = <int>[];
      for (var i = 0; i < count && pos[0] < data.length; i++) {
        momentum.add(_getPrice(data, pos));
      }
      return {'code': code, 'count': count, 'momentum': momentum};
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  // ─── HistoryTransactionData (历史逐笔, 0x0fb5) ───

  /// Get historical transaction data for a specific date.
  Future<List<Map<String, dynamic>>> getHistoryTransactions(
    String code,
    int date, {
    int start = 0,
    int count = 100,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = c.startsWith('6') ? 1 : 0;

    try {
      final payload = BytesBuilder();
      payload.add(_uint32LE(date));
      payload.add(_uint16LE(market));
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));
      payload.add(_uint16LE(start));
      payload.add(_uint16LE(count));

      final data = await _sendAndReceive(
        0x0fb5,
        payload.toBytes(),
        control: 0x00,
      );
      _circuitBreaker.recordSuccess(name);
      if (data.length < 4) return [];

      final cnt = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
      final pos = [2];
      final results = <Map<String, dynamic>>[];
      for (var i = 0; i < cnt && pos[0] < data.length - 4; i++) {
        final time = _getPrice(data, pos);
        final price = _getPrice(data, pos);
        final vol = _getPrice(data, pos);
        final buyOrSell = _getPrice(data, pos);
        results.add({
          'time': time,
          'price': _r2(price / 100.0),
          'volume': vol,
          'direction': buyOrSell == 0 ? 'buy' : 'sell',
        });
      }
      return results;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  // ─── TopBoard (排行榜, 0x053f) ───

  /// Get top board (涨幅/跌幅 ranking).
  Future<Map<String, dynamic>> getTopBoard({
    int category = 0,
    int size = 10,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    try {
      final payload = BytesBuilder();
      payload.addByte(category); // category
      payload.addByte(5); // mode, matches gotdx GetTopBoard default
      payload.add(Uint8List.fromList([0, 0, 0, 0, 1, 0, 0])); // reserved
      payload.addByte(size); // size

      final data = await _sendAndReceive(
        0x053f,
        payload.toBytes(),
        control: 0x00,
      );
      _circuitBreaker.recordSuccess(name);
      return _parseTopBoard(data);
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  Map<String, dynamic> _parseTopBoard(Uint8List data) {
    if (data.isEmpty) return {'size': 0, 'increase': [], 'decrease': []};
    final boardSize = data[0];
    var pos = 1;
    Map<String, dynamic> readItem() {
      if (pos + 15 > data.length) {
        throw const FormatException('TDX top_board response truncated');
      }
      final market = data[pos];
      final code = _decodeGBK(data.sublist(pos + 1, pos + 7));
      final price = ByteData.sublistView(
        data,
        pos + 7,
        pos + 11,
      ).getFloat32(0, Endian.little);
      final value = ByteData.sublistView(
        data,
        pos + 11,
        pos + 15,
      ).getFloat32(0, Endian.little);
      pos += 15;
      return {
        'code': code,
        'market': market,
        'price': _r2(price),
        'value': _r2(value),
      };
    }

    List<Map<String, dynamic>> readList() =>
        List.generate(boardSize, (_) => readItem(), growable: false);

    return {
      'size': boardSize,
      'increase': readList(),
      'decrease': readList(),
      'amplitude': readList(),
      'riseSpeed': readList(),
      'fallSpeed': readList(),
      'volRatio': readList(),
      'posCommissionRatio': readList(),
      'negCommissionRatio': readList(),
      'turnover': readList(),
    };
  }

  // ─── QuotesList (行情排名, 0x054b) ───

  /// Get ranked quotes list (sorted by changePct, volume, etc).
  Future<List<Map<String, dynamic>>> getQuotesList({
    int category = 0,
    int start = 0,
    int count = 80,
    int sortType = 0,
    bool reverse = false,
    int filter = 0,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(category));
      payload.add(_uint16LE(sortType));
      payload.add(_uint16LE(start));
      payload.add(_uint16LE(count));
      payload.add(_uint16LE(reverse ? 1 : 0));
      payload.add(_uint16LE(0)); // mode
      payload.add(_uint16LE(filter));
      payload.add(_uint16LE(1)); // one
      payload.add(_uint16LE(0)); // zero

      final data = await _sendAndReceive(
        0x054b,
        payload.toBytes(),
        control: 0x00,
      );
      _circuitBreaker.recordSuccess(name);
      if (data.length < 4) return [];

      final cnt = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
      final pos = [2];
      final results = <Map<String, dynamic>>[];
      for (var i = 0; i < cnt && pos[0] < data.length - 10; i++) {
        final market = data[pos[0]];
        pos[0]++;
        final codeBytes = data.sublist(pos[0], pos[0] + 6);
        pos[0] += 6;
        final code = _decodeGBK(codeBytes);
        final price = _getPrice(data, pos);
        final changePct = _getPrice(data, pos);
        results.add({
          'code': code,
          'market': market,
          'price': _r2(price / 100.0),
          'changePct': _r2(changePct / 100.0),
        });
      }
      return results;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  // ─── IndexBars (指数K线, 0x0523) ───

  /// Get index K-line bars.
  Future<List<Map<String, dynamic>>> getIndexBars(
    String code, {
    int category = 9,
    int start = 0,
    int count = 100,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = c.startsWith('0') || c.startsWith('3') ? 0 : 1;

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));
      payload.add(_uint16LE(category));
      payload.add(_uint16LE(1)); // times
      payload.add(_uint16LE(start));
      payload.add(_uint16LE(count));
      payload.add(_uint16LE(0)); // adjust
      payload.add(Uint8List(8)); // reserved

      final data = await _sendAndReceive(
        0x0523,
        payload.toBytes(),
        control: 0x00,
      );
      _circuitBreaker.recordSuccess(name);
      return _parseIndexBars(data, code, category);
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  List<Map<String, dynamic>> _parseIndexBars(
    Uint8List data,
    String code,
    int category,
  ) {
    if (data.length < 2) return [];
    final count = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
    final pos = [2];
    final results = <Map<String, dynamic>>[];

    for (var i = 0; i < count && pos[0] < data.length - 10; i++) {
      final date = _parseBarDate(data, pos, category);
      final openRaw = _getPrice(data, pos);
      final closeRaw = _getPrice(data, pos);
      final highRaw = _getPrice(data, pos);
      final lowRaw = _getPrice(data, pos);

      final volRaw = pos[0] + 4 <= data.length
          ? ByteData.sublistView(
              data,
              pos[0],
              pos[0] + 4,
            ).getUint32(0, Endian.little)
          : 0;
      pos[0] += 4;
      final amtRaw = pos[0] + 4 <= data.length
          ? ByteData.sublistView(
              data,
              pos[0],
              pos[0] + 4,
            ).getUint32(0, Endian.little)
          : 0;
      pos[0] += 4;

      final upCount = pos[0] + 2 <= data.length
          ? ByteData.sublistView(
              data,
              pos[0],
              pos[0] + 2,
            ).getUint16(0, Endian.little)
          : 0;
      pos[0] += 2;
      final downCount = pos[0] + 2 <= data.length
          ? ByteData.sublistView(
              data,
              pos[0],
              pos[0] + 2,
            ).getUint16(0, Endian.little)
          : 0;
      pos[0] += 2;

      results.add({
        'code': code,
        'date': date,
        'open': _r2(openRaw / 1000.0),
        'close': _r2(closeRaw / 1000.0),
        'high': _r2(highRaw / 1000.0),
        'low': _r2(lowRaw / 1000.0),
        'volume': _getVolume(volRaw),
        'amount': _getVolume(amtRaw),
        'upCount': upCount,
        'downCount': downCount,
      });
    }
    return results;
  }

  String _parseBarDate(Uint8List data, List<int> pos, int category) {
    if (category >= 4 && category != 7 && category != 8) {
      final raw = ByteData.sublistView(
        data,
        pos[0],
        pos[0] + 4,
      ).getUint32(0, Endian.little);
      pos[0] += 4;
      final y = raw ~/ 10000, m = (raw % 10000) ~/ 100, d = raw % 100;
      return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
    }
    final rawDate = ByteData.sublistView(
      data,
      pos[0],
      pos[0] + 2,
    ).getUint16(0, Endian.little);
    final rawTime = ByteData.sublistView(
      data,
      pos[0] + 2,
      pos[0] + 4,
    ).getUint16(0, Endian.little);
    pos[0] += 4;
    final y = (rawDate >> 11) + 2004, md = rawDate & 0x7FF;
    return '$y-${(md ~/ 100).toString().padLeft(2, '0')}-${(md % 100).toString().padLeft(2, '0')} ${(rawTime ~/ 60).toString().padLeft(2, '0')}:${(rawTime % 60).toString().padLeft(2, '0')}';
  }

  // ─── CompanyCategories (F10分类, 0x02cf) ───

  /// Get F10 company info categories.
  Future<List<Map<String, dynamic>>> getCompanyCategories(String code) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = c.startsWith('6') ? 1 : 0;

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));
      payload.add(_uint32LE(0)); // zero

      final data = await _sendAndReceive(
        0x02cf,
        payload.toBytes(),
        control: 0x00,
      );
      _circuitBreaker.recordSuccess(name);
      if (data.length < 4) return [];

      final count = ByteData.sublistView(
        data,
        0,
        2,
      ).getUint16(0, Endian.little);
      var offset = 2;
      final results = <Map<String, dynamic>>[];
      for (var i = 0; i < count && offset < data.length - 20; i++) {
        final name = _decodeGBK(data.sublist(offset, offset + 64).toList());
        offset += 64;
        final filename = _decodeGBK(data.sublist(offset, offset + 80).toList());
        offset += 80;
        final start = ByteData.sublistView(
          data,
          offset,
          offset + 4,
        ).getUint32(0, Endian.little);
        offset += 4;
        final length = ByteData.sublistView(
          data,
          offset,
          offset + 4,
        ).getUint32(0, Endian.little);
        offset += 4;
        results.add({
          'name': name,
          'filename': filename,
          'start': start,
          'length': length,
        });
      }
      return results;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  // ─── CompanyContent (F10内容, 0x02d0) ───

  /// Get F10 company info content for a specific category.
  Future<String> getCompanyContent(
    String code,
    String filename, {
    int start = 0,
    int length = 10000,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    final c = _normalizeCode(code);
    final market = c.startsWith('6') ? 1 : 0;

    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(market));
      payload.add(utf8.encode(c.padRight(6, '\x00').substring(0, 6)));
      // filename padded to 80 bytes
      final fnBytes = utf8.encode(filename);
      payload.add(
        fnBytes.length >= 80 ? fnBytes.sublist(0, 80) : Uint8List(80)
          ..setRange(0, fnBytes.length, fnBytes),
      );
      payload.add(_uint32LE(start));
      payload.add(_uint32LE(length));

      final data = await _sendAndReceive(
        0x02d0,
        payload.toBytes(),
        control: 0x00,
      );
      _circuitBreaker.recordSuccess(name);
      if (data.length < 4) return '';

      // Response: length(4) + content
      final contentLen = ByteData.sublistView(
        data,
        0,
        4,
      ).getUint32(0, Endian.little);
      if (contentLen == 0 || data.length < 4 + contentLen) return '';
      return _decodeGBK(data.sublist(4, 4 + contentLen).toList());
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getFileMeta(String filename) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    try {
      final payload = Uint8List(40);
      final fileBytes = utf8.encode(filename);
      payload.setRange(0, min(fileBytes.length, 40), fileBytes);
      final data = await _sendAndReceive(0x02c5, payload, control: 0x00);
      _circuitBreaker.recordSuccess(name);
      if (data.length < 38) {
        throw DataFetchError('TDX file meta response too short for $filename');
      }
      return {
        'filename': filename,
        'size': ByteData.sublistView(data, 0, 4).getUint32(0, Endian.little),
        'hash': data
            .sublist(5, 37)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
      };
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  Future<Uint8List> downloadFile(
    String filename, {
    int start = 0,
    int size = 0,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    try {
      final payload = BytesBuilder();
      payload.add(_uint32LE(start));
      payload.add(_uint32LE(size));
      final filenameBytes = Uint8List(300);
      final fileBytes = utf8.encode(filename);
      filenameBytes.setRange(0, min(fileBytes.length, 300), fileBytes);
      payload.add(filenameBytes);
      final data = await _sendAndReceive(
        0x06b9,
        payload.toBytes(),
        control: 0x00,
      );
      _circuitBreaker.recordSuccess(name);
      if (data.length < 4) return Uint8List(0);
      final chunkSize = ByteData.sublistView(
        data,
        0,
        4,
      ).getUint32(0, Endian.little);
      if (chunkSize == 0) return Uint8List(0);
      final end = min(4 + chunkSize, data.length);
      return Uint8List.fromList(data.sublist(4, end));
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  Future<Uint8List> downloadFullFile(String filename, {int? size}) async {
    var expectedSize = size;
    if (expectedSize == null || expectedSize <= 0) {
      final meta = await getFileMeta(filename);
      expectedSize = (meta['size'] as num?)?.toInt() ?? 0;
    }
    final bytes = BytesBuilder(copy: false);
    var start = 0;
    while (true) {
      final remaining = expectedSize > 0 ? max(expectedSize - start, 0) : 0;
      final requestSize = expectedSize > 0 ? min(0x4000, remaining) : 0x4000;
      final chunk = await downloadFile(
        filename,
        start: start,
        size: requestSize == 0 ? 0x4000 : requestSize,
      );
      if (chunk.isEmpty) break;
      bytes.add(chunk);
      start += chunk.length;
      if (expectedSize > 0 && start >= expectedSize) break;
      if (chunk.length < (requestSize == 0 ? 0x4000 : requestSize)) break;
    }
    return bytes.toBytes();
  }

  Future<List<Map<String, dynamic>>> getBlockMembers({
    String filename = 'block_gn.dat',
    String? blockName,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    try {
      final content = await downloadFullFile(filename);
      final rows = _parseBlockMembers(content, filename: filename);
      _circuitBreaker.recordSuccess(name);
      if (blockName == null || blockName.isEmpty) return rows;
      return rows.where((row) => row['block_name'] == blockName).toList();
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  List<Map<String, dynamic>> _parseBlockMembers(
    Uint8List data, {
    required String filename,
  }) {
    if (data.length < 386) return const [];
    var pos = 384;
    final total = ByteData.sublistView(
      data,
      pos,
      pos + 2,
    ).getUint16(0, Endian.little);
    pos += 2;
    final results = <Map<String, dynamic>>[];
    for (var i = 0; i < total; i++) {
      if (pos + 13 > data.length) break;
      final blockName = _decodeGBK(data.sublist(pos, pos + 9).toList());
      pos += 9;
      final stockCount = ByteData.sublistView(
        data,
        pos,
        pos + 2,
      ).getUint16(0, Endian.little);
      final blockType = ByteData.sublistView(
        data,
        pos + 2,
        pos + 4,
      ).getUint16(0, Endian.little);
      pos += 4;
      final blockStart = pos;
      final blockCode = '$filename:$blockName';
      for (var codeIndex = 0; codeIndex < stockCount; codeIndex++) {
        if (pos + 7 > data.length) break;
        final code = _decodeGBK(data.sublist(pos, pos + 7).toList());
        pos += 7;
        if (code.isEmpty) continue;
        results.add({
          'block_code': blockCode,
          'block_name': blockName,
          'block_type': '$blockType',
          'code': code,
          'code_index': codeIndex,
          'filename': filename,
        });
      }
      pos = blockStart + 2800;
    }
    return results;
  }

  // ─── Binary Helpers ───

  /// TDX custom varint: variable-length signed integer.
  int _getPrice(Uint8List data, List<int> pos) {
    if (pos[0] >= data.length) return 0;
    int bData = data[pos[0]];
    int result = bData & 0x3F;
    bool isNeg = (bData & 0x40) != 0;
    int posBit = 6;

    if ((bData & 0x80) != 0) {
      pos[0]++;
      while (pos[0] < data.length) {
        bData = data[pos[0]];
        result |= (bData & 0x7F) << posBit;
        posBit += 7;
        pos[0]++;
        if ((bData & 0x80) == 0) break;
      }
    } else {
      pos[0]++;
    }
    return isNeg ? -result : result;
  }

  /// TDX custom float encoding for volume/amount.
  double _getVolume(int val) {
    if (val == 0) return 0;
    final ivol = val.toSigned(32);
    final logpoint = (ivol >> 24) & 0xFF;
    final hleax = (ivol >> 16) & 0xFF;
    final lheax = (ivol >> 8) & 0xFF;
    final lleax = ivol & 0xFF;

    final dwEcx = logpoint * 2 - 0x7F;
    final dwEdx = logpoint * 2 - 0x86;
    final dwEsi = logpoint * 2 - 0x8E;
    final dwEax = logpoint * 2 - 0x96;

    double xmm6 = dwEcx >= 0
        ? pow(2.0, dwEcx).toDouble()
        : 1.0 / pow(2.0, -dwEcx).toDouble();

    double xmm4;
    if (hleax > 0x80) {
      xmm4 =
          pow(2.0, dwEdx).toDouble() * 128.0 +
          (hleax & 0x7F) * pow(2.0, dwEdx + 1).toDouble();
    } else {
      xmm4 = dwEdx >= 0
          ? pow(2.0, dwEdx).toDouble() * hleax
          : hleax / pow(2.0, -dwEdx).toDouble();
    }

    final scale = (hleax & 0x80) != 0 ? 2.0 : 1.0;
    final xmm3 = pow(2.0, dwEsi).toDouble() * lheax * scale;
    final xmm1 = pow(2.0, dwEax).toDouble() * lleax * scale;

    return xmm6 + xmm4 + xmm3 + xmm1;
  }

  static Uint8List _uint16LE(int v) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
  static Uint8List _uint32LE(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
  static double _r2(double v) => double.parse(v.toStringAsFixed(2));

  /// Decode GBK bytes to string (TDX servers always return GBK).
  static String _decodeGBK(List<int> bytes) {
    var end = bytes.length;
    while (end > 0 && (bytes[end - 1] == 0 || bytes[end - 1] == 0x20)) {
      end--;
    }
    if (end == 0) return '';
    try {
      return gbk.decode(bytes.sublist(0, end)).trim();
    } catch (_) {
      return String.fromCharCodes(bytes.where((b) => b > 0 && b < 128)).trim();
    }
  }

  static Uint8List _hexDecode(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  // ─── Test Helpers ───

  @visibleForTesting
  int testGetPrice(Uint8List data, List<int> pos) => _getPrice(data, pos);

  @visibleForTesting
  List<Map<String, dynamic>> testParseTickChart(Uint8List data) =>
      _parseTickChart(data);

  @visibleForTesting
  List<Map<String, dynamic>> testParseTransactions(
    Uint8List data,
    String code,
  ) => _parseTransactions(data, code);

  @visibleForTesting
  List<KlineBar> testParseKlineBars(Uint8List data, int category) =>
      _parseKlineBars(data, category);

  @visibleForTesting
  List<Map<String, dynamic>> testParseIndexBars(
    Uint8List data,
    String code,
    int category,
  ) => _parseIndexBars(data, code, category);

  @visibleForTesting
  Map<String, dynamic> testParseTopBoard(Uint8List data) =>
      _parseTopBoard(data);
}

/// A TDX server entry with probe metadata.
class TdxServerEntry {
  final String host;
  final int port;
  final String name;
  final int? latency;
  final bool? reachable;
  final DateTime? lastProbe;

  const TdxServerEntry({
    required this.host,
    required this.port,
    this.name = '',
    this.latency,
    this.reachable,
    this.lastProbe,
  });

  String get key => '$host:$port';

  TdxServerEntry copyWith({
    String? host,
    int? port,
    String? name,
    int? latency,
    bool? reachable,
    DateTime? lastProbe,
  }) => TdxServerEntry(
    host: host ?? this.host,
    port: port ?? this.port,
    name: name ?? this.name,
    latency: latency ?? this.latency,
    reachable: reachable ?? this.reachable,
    lastProbe: lastProbe ?? this.lastProbe,
  );

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'name': name,
    if (latency != null) 'latency': latency,
    if (reachable != null) 'reachable': reachable,
    if (lastProbe != null) 'lastProbe': lastProbe!.toIso8601String(),
  };

  factory TdxServerEntry.fromJson(Map<String, dynamic> json) => TdxServerEntry(
    host: json['host'] as String? ?? '',
    port: json['port'] as int? ?? 7709,
    name: json['name'] as String? ?? '',
    latency: json['latency'] as int?,
    reachable: json['reachable'] as bool?,
    lastProbe: json['lastProbe'] != null
        ? DateTime.tryParse(json['lastProbe'] as String)
        : null,
  );

  /// Parse user input like "110.41.147.114:7709" or "110.41.147.114".
  static TdxServerEntry? fromUserInput(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(':');
    final host = parts[0].trim();
    if (host.isEmpty) return null;
    final port = parts.length > 1
        ? int.tryParse(parts[1].trim()) ?? 7709
        : 7709;
    return TdxServerEntry(host: host, port: port, name: '自定义');
  }
}
