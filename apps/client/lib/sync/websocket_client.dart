import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';

class SyncWsClient {
  final String wsUrl;
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _closed = false;
  bool _isConnected = false;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Completer<void>? _readyCompleter;

  void Function()? onOpen;
  void Function(Object e)? onError;

  SyncWsClient(this.wsUrl);

  Stream<Map<String, dynamic>> get messages => _controller.stream;

  bool get isConnected => _isConnected && _ch != null && _ch!.closeCode == null;

  Future<void> get ready {
    _readyCompleter ??= Completer<void>();
    if (_isConnected) {
      if (!(_readyCompleter!.isCompleted)) _readyCompleter!.complete();
    }
    return _readyCompleter!.future;
  }

  void connect() {
    _closed = false;
    _doConnect();
  }

  void _doConnect() {
    if (_closed) return;
    // Leaks: cancel previous subscription and close old channel before new connect
    try {
      _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    _isConnected = false;
    _readyCompleter = Completer<void>();
    try {
      _ch = WebSocketChannel.connect(Uri.parse(wsUrl));
      // Set connected immediately after connect succeeds (no artificial delay)
      _isConnected = true;
      _attempt = 0; // reset backoff only on successful open will be done via onOpen; but we also keep _isConnected true
      // Notify open immediately after connection via channel ready
      // Call onOpen after microtask to ensure channel is ready; hello will be sent after onOpen
      Future.microtask(() {
        if (_closed) return;
        _isConnected = true;
        // Backoff reset only on successful open (onOpen), not per message
        _attempt = 0;
        if (!(_readyCompleter!.isCompleted)) _readyCompleter!.complete();
        onOpen?.call();
      });

      _sub = _ch!.stream.listen((raw) {
        // Do NOT reset backoff on every message — only on open
        try {
          final m = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller.add(m);
        } catch (e) {
          onError?.call(e);
        }
      }, onDone: _scheduleReconnect, onError: (e) {
        _isConnected = false;
        onError?.call(e);
        _scheduleReconnect();
      });
    } catch (e) {
      _isConnected = false;
      onError?.call(e);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _isConnected = false;
    // Complete ready with error if not yet completed
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError(StateError('ws closed before ready'));
    }
    _reconnectTimer?.cancel();
    final jitter = Random().nextInt(1000);
    final delayMs = min(30000, (1000 * pow(2, _attempt)).toInt() + jitter);
    _attempt++;
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), _doConnect);
  }

  bool send(Map<String, dynamic> msg) {
    if (_ch == null || _ch!.closeCode != null || !_isConnected) return false;
    try {
      _ch!.sink.add(jsonEncode(msg));
      return true;
    } catch (e) {
      onError?.call(e);
      return false;
    }
  }

  Future<void> close() async {
    _closed = true;
    _isConnected = false;
    _reconnectTimer?.cancel();
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      await _ch?.sink.close();
    } catch (_) {}
    // don't close _controller — allow reconnect
  }

  void dispose() {
    _closed = true;
    _isConnected = false;
    _reconnectTimer?.cancel();
    try {
      _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      _controller.close();
    } catch (_) {}
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
  }
}
