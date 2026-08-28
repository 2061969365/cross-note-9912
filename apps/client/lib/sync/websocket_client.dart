import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class SyncWsClient {
  final String wsUrl;
  WebSocketChannel? _ch;
  Timer? _reconnectTimer;
  int _backoffMs = 1000;
  bool _closed = false;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  void Function()? onOpen;
  void Function(Object e)? onError;

  SyncWsClient(this.wsUrl);

  Stream<Map<String, dynamic>> get messages => _controller.stream;

  void connect() {
    _closed = false;
    _doConnect();
  }

  void _doConnect() {
    if (_closed) return;
    try {
      _ch = WebSocketChannel.connect(Uri.parse(wsUrl));
      _ch!.stream.listen((raw) {
        _backoffMs = 1000;
        try {
          final m = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller.add(m);
        } catch (e) {
          onError?.call(e);
        }
      }, onDone: _scheduleReconnect, onError: (e) { onError?.call(e); _scheduleReconnect(); });
      // slight delay to let socket open before hello
      Future.delayed(const Duration(milliseconds: 150), () => onOpen?.call());
    } catch (e) {
      onError?.call(e);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _backoffMs), _doConnect);
    _backoffMs = (_backoffMs * 2).clamp(1000, 30000);
  }

  void send(Map<String, dynamic> msg) {
    try {
      _ch?.sink.add(jsonEncode(msg));
    } catch (e) {
      onError?.call(e);
    }
  }

  Future<void> close() async {
    _closed = true;
    _reconnectTimer?.cancel();
    try { await _ch?.sink.close(); } catch (_) {}
    // don't close _controller — allow reconnect
  }

  void dispose() {
    _closed = true;
    _reconnectTimer?.cancel();
    _controller.close();
    try { _ch?.sink.close(); } catch (_) {}
  }
}
