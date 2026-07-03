import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:meta/meta.dart' show visibleForTesting;

import '../log.dart';
import 'base_fetcher.dart';
import 'http_utils.dart';
import 'models.dart';
import 'tdx_fetcher.dart' show TdxServerEntry;

/// TDX Extended Quote (扩展行情, port 7727) fetcher.
/// Provides futures, options, HK stocks, forex, international indices.
class ExTdxFetcher extends BaseFetcher {
  @override
  String get name => '通达信扩展';
  @override
  int get priority => 50;

  String? basePath;

  Socket? _socket;
  bool _connected = false;
  Timer? _heartbeatTimer;
  StreamSubscription? _socketSubscription;
  final _socketBuffer = BytesBuilder();
  Completer<void>? _dataAvailable;
  String? _lastGoodServer;
  final _failureCounts = <String, int>{};
  final _circuitBreaker = CircuitBreaker(
    failureThreshold: 3,
    cooldown: Duration(minutes: 5),
  );

  String get _serverFilePath => '$basePath/memory/.tdx_ex_servers.json';

  // ExLogin payload (40 bytes, from gotdx ex_server.go)
  static final Uint8List _exLoginPayload = _hexDecode(
    'e5bb1c2fafe525941f32c6e5d53dfb41'
    '5b734cc9cdbf0ac92021bfdd1eb06d22'
    'd008884c1611cb1378f6abd824d899d2'
    '1f32c6e5d53dfb411f32c6e5d53dfb41'
    'a9325ac935dc0837335a16e4ce17c1bb',
  );

  // ─── Connection ───

  Future<void> _ensureConnected() async {
    if (_connected && _socket != null) return;
    await _connect();
  }

  Future<void> _connect() async {
    _disconnect();
    final servers = await _getOrderedServers();
    if (servers.isEmpty) throw DataFetchError('$name: no servers available');

    for (final s in servers) {
      final key = '${s.host}:${s.port}';
      if (_failureCounts[key] != null && _failureCounts[key]! >= 3) continue;
      if (s.reachable == false) continue;

      try {
        _socket = await Socket.connect(
          s.host,
          s.port,
          timeout: const Duration(seconds: 5),
        );
        _startListening();
        await _sendExLogin();
        _connected = true;
        _lastGoodServer = key;
        _failureCounts.remove(key);
        _startHeartbeat();
        return;
      } catch (e) {
        _socket?.destroy();
        _socket = null;
        _failureCounts[key] = (_failureCounts[key] ?? 0) + 1;
        if (_failureCounts[key]! >= 3) {
          _markServerUnreachable(s.host, s.port);
        }
        log('[ExTDX] Connect failed for $key: $e');
      }
    }
    throw DataFetchError('$name: all servers unreachable');
  }

  void _disconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _socket?.destroy();
    _socket = null;
    _socketBuffer.clear();
    _dataAvailable?.completeError(StateError('disconnected'));
    _dataAvailable = null;
    _connected = false;
  }

  void _startListening() {
    _socketSubscription = _socket!.listen(
      (data) {
        _socketBuffer.add(data);
        _dataAvailable?.complete();
        _dataAvailable = null;
      },
      onError: (e) => _disconnect(),
      onDone: () => _disconnect(),
    );
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_connected) _sendHeartbeat();
    });
  }

  void _sendHeartbeat() {
    try {
      // ExServerInfo (0x2455) with no payload as keepalive
      final packet = _buildExPacket(0x2455, Uint8List(0));
      _socket!.add(packet);
    } catch (_) {
      _disconnect();
    }
  }

  // ─── ExLogin Handshake ───

  Future<void> _sendExLogin() async {
    final packet = _buildExPacket(0x2454, _exLoginPayload);
    _socket!.add(packet);
    await _socket!.flush();
    // Read response (at least 294 bytes expected, but we just consume the response)
    final header = await _readResponseHeader();
    final body = await _readExact(header.zipLen);
    if (header.zipLen != header.unzipLen && header.zipLen > 0) {
      // decompress if needed — login response is usually not compressed
      try {
        zlib.decode(body);
      } catch (_) {}
    }
    // We don't need to parse the login response fields for now
  }

  // ─── Packet Building (ExQuote protocol) ───

  /// Build an ExQuote request packet.
  /// Header: [0x01][0x00000000:4][0x01][bodyLen:2][bodyLen:2]
  /// Body: [method:2][payload]
  Uint8List _buildExPacket(int method, Uint8List payload) {
    final bodyLen = 2 + payload.length;
    final builder = BytesBuilder();
    // exReqHeader (9 bytes)
    builder.addByte(0x01); // Head
    builder.add(Uint8List(4)); // Customize = 0x00000000
    builder.addByte(0x01); // PacketType
    builder.add(_uint16LE(bodyLen)); // PkgLen1
    builder.add(_uint16LE(bodyLen)); // PkgLen2
    // Body
    builder.add(_uint16LE(method)); // Method
    builder.add(payload);
    return builder.toBytes();
  }

  // ─── Response Reading ───

  Future<_RespHeader> _readResponseHeader() async {
    final headerBytes = await _readExact(16);
    final bd = ByteData.sublistView(headerBytes);
    return _RespHeader(
      method: bd.getUint16(10, Endian.little),
      zipLen: bd.getUint16(12, Endian.little),
      unzipLen: bd.getUint16(14, Endian.little),
    );
  }

  Future<Uint8List> _readExact(int length) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (_socketBuffer.length < length) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('ExTDX read timeout waiting for $length bytes');
      }
      _dataAvailable = Completer<void>();
      await _dataAvailable!.future.timeout(
        deadline.difference(DateTime.now()),
        onTimeout: () => throw TimeoutException('ExTDX read timeout'),
      );
    }
    final all = _socketBuffer.toBytes();
    _socketBuffer.clear();
    if (all.length > length) {
      _socketBuffer.add(all.sublist(length));
    }
    return Uint8List.fromList(all.sublist(0, length));
  }

  Future<Uint8List> _sendAndReceive(int method, Uint8List payload) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _ensureConnected();
        final packet = _buildExPacket(method, payload);
        _socket!.add(packet);
        await _socket!.flush();
        final header = await _readResponseHeader();
        final body = await _readExact(header.zipLen);
        if (header.zipLen != header.unzipLen && header.zipLen > 0) {
          try {
            return Uint8List.fromList(zlib.decode(body));
          } catch (_) {
            return body;
          }
        }
        return body;
      } catch (e) {
        _disconnect();
        if (attempt == 1) rethrow;
      }
    }
    throw DataFetchError('$name: send failed');
  }

  // ─── Public APIs ───

  /// Get all available market categories.
  Future<List<ExCategoryItem>> getExCategories() async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    try {
      final data = await _sendAndReceive(0x23F4, Uint8List(0));
      final result = _parseCategories(data);
      _circuitBreaker.recordSuccess(name);
      return result;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  /// Get total count of extended securities.
  Future<int> getExCount() async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    try {
      final data = await _sendAndReceive(0x23F0, Uint8List(0));
      _circuitBreaker.recordSuccess(name);
      if (data.length >= 23) {
        return ByteData.sublistView(data, 19, 23).getUint32(0, Endian.little);
      }
      return 0;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  /// Get list of securities in extended market.
  Future<List<ExListItem>> getExList({int start = 0, int count = 100}) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    try {
      final payload = BytesBuilder();
      payload.add(_uint32LE(start));
      payload.add(_uint16LE(count));
      final data = await _sendAndReceive(0x23F5, payload.toBytes());
      final result = _parseExList(data);
      _circuitBreaker.recordSuccess(name);
      return result;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  /// Get sampled chart prices for an extended market security.
  Future<Map<String, dynamic>> getExChartSampling(int category, String code) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    try {
      final payload = BytesBuilder();
      payload.add(_uint16LE(category));
      payload.add(_makeCode22(code));
      payload.add(_uint16LE(1));
      payload.add(_uint16LE(20));
      payload.add(Uint8List(9));
      final data = await _sendAndReceive(0x254D, payload.toBytes());
      final result = _parseExChartSampling(data);
      _circuitBreaker.recordSuccess(name);
      return result;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  /// Get extended market table content.
  Future<String> getExTable({bool detail = false}) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    try {
      var start = 0;
      final buffer = StringBuffer();
      while (true) {
        final payload = BytesBuilder();
        payload.add(_uint32LE(start));
        payload.add(_uint32LE(0));
        payload.add(
          Uint8List.fromList(const [
            0x00, 0x78, 0x1f, 0x0e, 0x6a, 0x37, 0x44, 0x7b,
            0x50, 0x2b, 0x7c, 0x0d, 0x01, 0x40, 0x4c, 0x0a,
          ]),
        );
        payload.add(Uint8List(85));
        payload.addByte(detail ? 0 : 1);
        payload.add(Uint8List(16));
        final data = await _sendAndReceive(
          detail ? 0x2423 : 0x2422,
          payload.toBytes(),
        );
        final parsed = _parseExTableChunk(data);
        buffer.write(parsed['content'] as String? ?? '');
        final count = parsed['count'] as int? ?? 0;
        if (count == 0) break;
        start += count;
      }
      _circuitBreaker.recordSuccess(name);
      return buffer.toString();
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  /// Get K-line data for an extended market security.
  Future<List<ExKlineBar>> getExKline(
    int category,
    String code, {
    int period = 9,
    int start = 0,
    int count = 300,
    int times = 1,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    try {
      final payload = BytesBuilder();
      payload.addByte(category);
      payload.add(_makeCode9(code));
      payload.add(_uint16LE(period));
      payload.add(_uint16LE(times));
      payload.add(_uint32LE(start));
      payload.add(_uint16LE(count));
      final data = await _sendAndReceive(0x23FF, payload.toBytes());
      final result = _parseExKline(data, period);
      _circuitBreaker.recordSuccess(name);
      return result;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  /// Get single quote for an extended market security.
  Future<ExQuoteData> getExQuote(int category, String code) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    try {
      final payload = BytesBuilder();
      payload.addByte(category);
      payload.add(_makeCode9(code));
      final data = await _sendAndReceive(0x23FA, payload.toBytes());
      final result = _parseExQuoteItem(data, 9);
      _circuitBreaker.recordSuccess(name);
      return result;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  /// Get batch quotes for extended market securities.
  Future<List<ExQuoteData>> getExQuotes(List<ExStock> stocks) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    if (stocks.isEmpty) return [];
    try {
      final payload = BytesBuilder();
      payload.addByte(0x05); // hardcoded constant
      payload.add(Uint8List(7)); // 7 zero bytes
      payload.add(_uint16LE(stocks.length));
      for (final s in stocks) {
        payload.addByte(s.category);
        payload.add(_makeCode23(s.code));
      }
      final data = await _sendAndReceive(0x248A, payload.toBytes());
      final result = _parseExQuotesBatch(data);
      _circuitBreaker.recordSuccess(name);
      return result;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      _disconnect();
      rethrow;
    }
  }

  // ─── BaseFetcher interface (minimal, for compatibility) ───

  @override
  Future<List<StockQuote>> getQuotes(List<String> codes) async {
    throw DataFetchError(
      '$name does not support standard quotes — use getExQuote',
    );
  }

  @override
  Future<List<KlineBar>> getKline(
    String code, {
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
  }) async {
    throw DataFetchError(
      '$name does not support standard kline — use getExKline',
    );
  }

  @override
  Future<List<MoneyFlow>> getMoneyFlow(String code) async {
    throw DataFetchError('$name does not support money flow');
  }

  @override
  bool canHandle(String code) => false;

  // ─── Parsers ───

  List<ExCategoryItem> _parseCategories(Uint8List data) {
    if (data.length < 2) return [];
    final count = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
    final results = <ExCategoryItem>[];
    for (var i = 0; i < count; i++) {
      final base = 2 + i * 64;
      if (base + 64 > data.length) break;
      final name = _decodeGBK(data.sublist(base + 1, base + 33));
      final code = data[base + 33];
      final abbr = _decodeGBK(data.sublist(base + 34, base + 64));
      results.add(ExCategoryItem(category: code, name: name, abbr: abbr));
    }
    return results;
  }

  List<ExListItem> _parseExList(Uint8List data) {
    if (data.length < 6) return [];
    final count = ByteData.sublistView(data, 4, 6).getUint16(0, Endian.little);
    final results = <ExListItem>[];
    for (var i = 0; i < count; i++) {
      final base = 6 + i * 64;
      if (base + 64 > data.length) break;
      final category = data[base + 1];
      final code = _decodeGBK(data.sublist(base + 5, base + 14));
      final itemName = _decodeGBK(data.sublist(base + 14, base + 40));
      results.add(ExListItem(category: category, code: code, name: itemName));
    }
    return results;
  }

  @visibleForTesting
  List<ExKlineBar> parseExKline(Uint8List data, int period) =>
      _parseExKline(data, period);

  List<ExKlineBar> _parseExKline(Uint8List data, int period) {
    if (data.length < 20) return [];
    final count = ByteData.sublistView(
      data,
      18,
      20,
    ).getUint16(0, Endian.little);
    final results = <ExKlineBar>[];
    for (var i = 0; i < count; i++) {
      final base = 20 + i * 32;
      if (base + 32 > data.length) break;
      final bd = ByteData.sublistView(data, base, base + 32);
      final dateNum = bd.getUint32(0, Endian.little);
      final open = bd.getFloat32(4, Endian.little).toDouble();
      final high = bd.getFloat32(8, Endian.little).toDouble();
      final low = bd.getFloat32(12, Endian.little).toDouble();
      final close = bd.getFloat32(16, Endian.little).toDouble();
      final amount = bd.getFloat32(20, Endian.little).toDouble();
      final vol = bd.getUint32(24, Endian.little);
      final date = _decodeDateNum(period, dateNum);
      results.add(
        ExKlineBar(
          date: date,
          open: open,
          high: high,
          low: low,
          close: close,
          amount: amount.abs() < 1e-10 ? 0 : amount,
          volume: vol,
        ),
      );
    }
    return results;
  }

  ExQuoteData _parseExQuoteItem(Uint8List data, int codeLen) {
    var pos = 0;
    final category = data[pos];
    pos++;
    final code = _decodeGBK(data.sublist(pos, pos + codeLen));
    pos += codeLen;

    double f32() {
      final v = ByteData.sublistView(
        data,
        pos,
        pos + 4,
      ).getFloat32(0, Endian.little).toDouble();
      pos += 4;
      return v;
    }

    int u32() {
      final v = ByteData.sublistView(
        data,
        pos,
        pos + 4,
      ).getUint32(0, Endian.little);
      pos += 4;
      return v;
    }

    u32(); // Active
    f32(); // PreClose (first assignment, will be overwritten)
    final open = f32();
    final high = f32();
    final low = f32();
    final close = f32();
    final openPosition = u32();
    final addPosition = u32();
    final vol = u32();
    u32(); // CurVol
    final amount = f32();
    u32(); // InVol
    u32(); // OutVol
    u32(); // Unknown14
    final holdPosition = u32();

    // 5 bid prices + 5 bid vols + 5 ask prices + 5 ask vols
    final bidPrices = List.generate(5, (_) => f32());
    final bidVols = List.generate(5, (_) => u32());
    final askPrices = List.generate(5, (_) => f32());
    final askVols = List.generate(5, (_) => u32());

    pos += 2; // Unknown1 (uint16)
    final settlement = f32();
    u32(); // Unknown2
    f32(); // Avg
    final preSettlement = f32();
    u32();
    u32();
    u32();
    u32(); // Unknown3[0..3]
    final preClose = f32(); // SECOND assignment (overwrites first)

    final bidLevels = List.generate(
      5,
      (i) => ExLevel(price: bidPrices[i], vol: bidVols[i]),
    );
    final askLevels = List.generate(
      5,
      (i) => ExLevel(price: askPrices[i], vol: askVols[i]),
    );

    return ExQuoteData(
      category: category,
      code: code,
      name: '',
      preClose: preClose,
      open: open,
      high: high,
      low: low,
      close: close,
      settlement: settlement,
      preSettlement: preSettlement,
      vol: vol,
      openPosition: openPosition,
      addPosition: addPosition,
      holdPosition: holdPosition,
      amount: amount,
      bidLevels: bidLevels,
      askLevels: askLevels,
    );
  }

  List<ExQuoteData> _parseExQuotesBatch(Uint8List data) {
    if (data.length < 10) return [];
    final count = ByteData.sublistView(data, 8, 10).getUint16(0, Endian.little);
    final results = <ExQuoteData>[];
    for (var i = 0; i < count; i++) {
      final base = 10 + i * 314;
      if (base + 314 > data.length) break;
      try {
        results.add(_parseExQuoteItem(data.sublist(base, base + 314), 23));
      } catch (_) {
        break;
      }
    }
    return results;
  }

  Map<String, dynamic> _parseExChartSampling(Uint8List data) {
    if (data.length < 42) {
      return {'category': 0, 'code': '', 'count': 0, 'prices': const <double>[]};
    }
    final category = ByteData.sublistView(data, 0, 2).getUint16(0, Endian.little);
    final code = _decodeGBK(data.sublist(2, 24));
    final count = ByteData.sublistView(data, 40, 42).getUint16(0, Endian.little);
    final prices = <double>[];
    var pos = 42;
    for (var i = 0; i < count && pos + 4 <= data.length; i++) {
      prices.add(
        ByteData.sublistView(data, pos, pos + 4)
            .getFloat32(0, Endian.little)
            .toDouble(),
      );
      pos += 4;
    }
    return {
      'category': category,
      'code': code,
      'count': prices.length,
      'prices': prices,
    };
  }

  Map<String, dynamic> _parseExTableChunk(Uint8List data) {
    if (data.length < 169) {
      return {'start': 0, 'count': 0, 'content': ''};
    }
    return {
      'start': ByteData.sublistView(data, 35, 39).getUint32(0, Endian.little),
      'count': ByteData.sublistView(data, 161, 165).getUint32(0, Endian.little),
      'content': _decodeGBK(data.sublist(169)),
    };
  }

  // ─── Date Decoding ───

  String _decodeDateNum(int period, int num) {
    final isMinute = period < 4 || period == 7 || period == 8;
    if (isMinute) {
      final zipData = num & 0xFFFF;
      final y = (zipData >> 11) + 2004;
      final md = zipData & 0x7FF;
      final m = md ~/ 100;
      final d = md % 100;
      final totalMins = num >> 16;
      final h = totalMins ~/ 60;
      final min = totalMins % 60;
      return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')} ${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
    } else {
      final y = num ~/ 10000;
      final m = (num % 10000) ~/ 100;
      final d = num % 100;
      return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
    }
  }

  // ─── Server Management ───

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

  Future<List<TdxServerEntry>> _getOrderedServers() async {
    var servers = loadServers();
    if (servers.isEmpty) return [];

    final needsProbe = servers.every((s) {
      if (s.lastProbe == null) return true;
      return DateTime.now().difference(s.lastProbe!) > const Duration(days: 1);
    });

    if (needsProbe) {
      servers = await _probeAllServers(servers);
    }

    final lastGood = _lastGoodServer;
    servers.sort((a, b) {
      final aKey = '${a.host}:${a.port}';
      final bKey = '${b.host}:${b.port}';
      if (aKey == lastGood) return -1;
      if (bKey == lastGood) return 1;
      final aScore = a.reachable == true ? 0 : (a.reachable == null ? 1 : 2);
      final bScore = b.reachable == true ? 0 : (b.reachable == null ? 1 : 2);
      if (aScore != bScore) return aScore.compareTo(bScore);
      return (a.latency ?? 9999).compareTo(b.latency ?? 9999);
    });

    return servers;
  }

  Future<List<TdxServerEntry>> _probeAllServers(
    List<TdxServerEntry> servers,
  ) async {
    final futures = servers.map((s) => _probeServer(s.host, s.port));
    final results = await Future.wait(futures);
    final updated = <TdxServerEntry>[];
    for (var i = 0; i < servers.length; i++) {
      final r = results[i];
      updated.add(
        servers[i].copyWith(
          reachable: r != null,
          latency: r,
          lastProbe: DateTime.now(),
        ),
      );
    }
    saveServers(updated);
    _failureCounts.clear();
    return updated;
  }

  Future<int?> _probeServer(String host, int port) async {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      sw.stop();
      socket.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  void _markServerUnreachable(String host, int port) {
    final servers = loadServers();
    final key = '$host:$port';
    var updated = false;
    for (var i = 0; i < servers.length; i++) {
      if ('${servers[i].host}:${servers[i].port}' == key) {
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

  CircuitBreaker get circuitBreaker => _circuitBreaker;

  // ─── Helpers ───

  static Uint8List _uint16LE(int v) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
  static Uint8List _uint32LE(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

  static Uint8List _makeCode9(String code) {
    final bytes = Uint8List(9);
    final encoded = utf8.encode(code);
    for (var i = 0; i < encoded.length && i < 9; i++) {
      bytes[i] = encoded[i];
    }
    return bytes;
  }

  static Uint8List _makeCode23(String code) {
    final bytes = Uint8List(23);
    final encoded = utf8.encode(code);
    for (var i = 0; i < encoded.length && i < 23; i++) {
      bytes[i] = encoded[i];
    }
    return bytes;
  }

  static Uint8List _makeCode22(String code) {
    final bytes = Uint8List(22);
    final encoded = utf8.encode(code);
    for (var i = 0; i < encoded.length && i < 22; i++) {
      bytes[i] = encoded[i];
    }
    return bytes;
  }

  static String _decodeGBK(List<int> bytes) {
    // Strip trailing nulls and spaces
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
}

class _RespHeader {
  final int method;
  final int zipLen;
  final int unzipLen;
  _RespHeader({
    required this.method,
    required this.zipLen,
    required this.unzipLen,
  });
}
