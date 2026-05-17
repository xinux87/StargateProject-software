import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:uuid/uuid.dart';

class BleService {
  static const String serviceUuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
  static const String cmdUuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567891";
  static const String responseUuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567892";
  static const String statusUuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567893";

  BluetoothDevice? _device;
  BluetoothCharacteristic? _cmdChar;
  BluetoothCharacteristic? _responseChar;
  BluetoothCharacteristic? _statusChar;

  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _responseSub;
  StreamSubscription<List<int>>? _statusSub;

  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  // Chunk reassembly buffers: keyed by "response" or "status"
  final Map<String, Map<int, List<int>>> _chunkBuffers = {};

  // Pending commands: id -> Completer
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  bool _connected = false;
  bool get isConnected => _connected;

  final _uuid = const Uuid();

  // ──────────────────────────────────────────────
  // Connect / Disconnect
  // ──────────────────────────────────────────────

  Future<void> connect(BluetoothDevice device) async {
    _device = device;

    // Monitor connection state changes from the OS
    _connectionSub = device.connectionState.listen((state) {
      final nowConnected = state == BluetoothConnectionState.connected;
      if (_connected != nowConnected) {
        _connected = nowConnected;
        _connectionController.add(nowConnected);
        if (!nowConnected) {
          _failAllPending('BLE device disconnected');
        }
      }
    });

    await device.connect(timeout: const Duration(seconds: 15));
    await _discoverAndSubscribe(device);
  }

  Future<void> disconnect() async {
    await _cancelSubscriptions();
    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {}
    }
    _failAllPending('Disconnected by user');
    _device = null;
    _cmdChar = null;
    _responseChar = null;
    _statusChar = null;
    _connected = false;
    _connectionController.add(false);
  }

  // ──────────────────────────────────────────────
  // Service / Characteristic discovery
  // ──────────────────────────────────────────────

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();

    BluetoothService? targetService;
    for (final s in services) {
      if (s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
        targetService = s;
        break;
      }
    }

    if (targetService == null) {
      throw Exception('Stargate BLE service not found on device');
    }

    for (final char in targetService.characteristics) {
      final id = char.uuid.toString().toLowerCase();
      if (id == cmdUuid.toLowerCase()) {
        _cmdChar = char;
      } else if (id == responseUuid.toLowerCase()) {
        _responseChar = char;
      } else if (id == statusUuid.toLowerCase()) {
        _statusChar = char;
      }
    }

    if (_cmdChar == null) throw Exception('CMD characteristic not found');
    if (_responseChar == null) throw Exception('RESPONSE characteristic not found');
    if (_statusChar == null) throw Exception('STATUS characteristic not found');

    // Subscribe to RESPONSE notifications
    await _responseChar!.setNotifyValue(true);
    _responseSub = _responseChar!.onValueReceived.listen((data) {
      _handleChunk(data, isStatus: false);
    });

    // Subscribe to STATUS notifications
    await _statusChar!.setNotifyValue(true);
    _statusSub = _statusChar!.onValueReceived.listen((data) {
      _handleChunk(data, isStatus: true);
    });

    _connected = true;
    _connectionController.add(true);
  }

  // ──────────────────────────────────────────────
  // Chunk reassembly
  // ──────────────────────────────────────────────

  /// Reassembles chunked BLE notifications.
  ///
  /// Protocol: first byte is the chunk index (0–254) or 255 (final/only chunk).
  /// Chunks 0..N are buffered; on receiving 255 the payload bytes are assembled
  /// in order, decoded as UTF-8 JSON, and dispatched.
  void _handleChunk(List<int> data, {required bool isStatus}) {
    if (data.isEmpty) return;

    final bufKey = isStatus ? 'status' : 'response';
    _chunkBuffers[bufKey] ??= {};

    final chunkIndex = data[0];
    final payload = data.sublist(1);

    if (chunkIndex == 255) {
      // Final (or only) chunk — assemble everything
      final buffer = _chunkBuffers[bufKey]!;

      // Collect ordered keys 0..N-1 then append this final payload
      final sortedKeys = buffer.keys.toList()..sort();
      final assembled = <int>[];
      for (final k in sortedKeys) {
        assembled.addAll(buffer[k]!);
      }
      assembled.addAll(payload);

      // Clear buffer
      _chunkBuffers[bufKey] = {};

      _dispatchMessage(assembled, isStatus: isStatus);
    } else {
      // Intermediate chunk — buffer it
      _chunkBuffers[bufKey]![chunkIndex] = payload;
    }
  }

  void _dispatchMessage(List<int> bytes, {required bool isStatus}) {
    try {
      final jsonStr = utf8.decode(bytes);
      final parsed = json.decode(jsonStr) as Map<String, dynamic>;

      if (isStatus) {
        if (!_statusController.isClosed) {
          _statusController.add(parsed);
        }
      } else {
        // Match by response id
        final id = parsed['id'] as String?;
        if (id != null && _pending.containsKey(id)) {
          final completer = _pending.remove(id)!;
          if (!completer.isCompleted) {
            completer.complete(parsed);
          }
        }
      }
    } catch (e) {
      // Malformed JSON — ignore
    }
  }

  // ──────────────────────────────────────────────
  // Send command
  // ──────────────────────────────────────────────

  Future<Map<String, dynamic>> sendCommand(
    String cmd, {
    Map<String, dynamic> params = const {},
    String? id,
  }) async {
    if (!_connected || _cmdChar == null) {
      throw Exception('Not connected to Stargate');
    }

    final requestId = id ?? _uuid.v4();
    final payload = json.encode({'cmd': cmd, 'params': params, 'id': requestId});
    final bytes = utf8.encode(payload);

    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = completer;

    try {
      await _cmdChar!.write(bytes, withoutResponse: false);
    } catch (e) {
      _pending.remove(requestId);
      rethrow;
    }

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending.remove(requestId);
        throw TimeoutException('Command "$cmd" timed out after 10 seconds');
      },
    );
  }

  // ──────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────

  void _failAllPending(String reason) {
    for (final entry in _pending.entries) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(Exception(reason));
      }
    }
    _pending.clear();
  }

  Future<void> _cancelSubscriptions() async {
    await _responseSub?.cancel();
    await _statusSub?.cancel();
    await _connectionSub?.cancel();
    _responseSub = null;
    _statusSub = null;
    _connectionSub = null;
  }

  void dispose() {
    _cancelSubscriptions();
    _failAllPending('BleService disposed');
    _statusController.close();
    _connectionController.close();
  }
}
