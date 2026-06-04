import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket service for real-time squad communication.
///
/// Handles automatic reconnection (on both error and close), a periodic
/// heartbeat to defeat API Gateway's 10-minute idle timeout, and a clean
/// intentional-disconnect path that does NOT trigger a reconnect.
class WebSocketService {
  static const String wsUrl = 'wss://6a4wu4973a.execute-api.us-east-1.amazonaws.com/prod';

  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  // Connection params (kept for reconnection).
  String? _roomCode;
  String? _userId;

  // Reconnection state.
  bool _intentionalDisconnect = false;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  // API Gateway idle timeout is 10 min — ping well before that.
  static const Duration _heartbeatInterval = Duration(minutes: 4);

  /// Stream of incoming messages from the WebSocket.
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Whether the WebSocket currently has an open channel.
  bool get isConnected => _channel != null;

  /// Connect to the WebSocket for a specific room.
  void connect({required String roomCode, required String userId}) {
    _roomCode = roomCode;
    _userId = userId;
    _intentionalDisconnect = false;
    _openChannel();
  }

  void _openChannel() {
    if (_isConnecting) return;
    if (_roomCode == null || _userId == null) return;
    _isConnecting = true;

    // Tear down any previous subscription/channel before opening a new one.
    _channelSub?.cancel();
    _channelSub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}

    try {
      final uri = Uri.parse('$wsUrl?roomCode=$_roomCode&userId=$_userId');
      _channel = WebSocketChannel.connect(uri);

      _channelSub = _channel!.stream.listen(
        (data) {
          // Any inbound traffic means the connection is healthy.
          _reconnectAttempts = 0;
          _isConnecting = false;
          try {
            final decoded = jsonDecode(data as String);
            if (decoded is Map<String, dynamic>) {
              // Ignore heartbeat pong echoes.
              if (decoded['action'] == 'pong') return;
              _messageController.add(decoded);
            }
          } catch (_) {}
        },
        onDone: () {
          _isConnecting = false;
          _channel = null;
          _scheduleReconnect();
        },
        onError: (_) {
          _isConnecting = false;
          _channel = null;
          _scheduleReconnect();
        },
        cancelOnError: true,
      );

      _isConnecting = false;
      _reconnectAttempts = 0;
      _startHeartbeat();
    } catch (_) {
      _isConnecting = false;
      _channel = null;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _stopHeartbeat();
    if (_intentionalDisconnect) return;
    if (_messageController.isClosed) return;
    if (_reconnectTimer?.isActive ?? false) return;

    // Exponential backoff: 1s, 2s, 4s, 8s … capped at 15s.
    _reconnectAttempts++;
    final seconds = (1 << (_reconnectAttempts - 1)).clamp(1, 15);
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!_intentionalDisconnect && _channel == null) {
        _openChannel();
      }
    });
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_channel == null) return;
      try {
        _channel!.sink.add(jsonEncode({
          'action': 'ping',
          'roomCode': _roomCode ?? '',
          'data': {},
        }));
      } catch (_) {
        // If the ping fails, force a reconnect cycle.
        _channel = null;
        _scheduleReconnect();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Send a message to all players in the room.
  void send({
    required String action,
    required String roomCode,
    Map<String, dynamic>? data,
  }) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({
        'action': action,
        'roomCode': roomCode,
        'data': data ?? {},
      }));
    } catch (_) {
      // Sending failed — connection is likely dead; trigger reconnect.
      _channel = null;
      _scheduleReconnect();
    }
  }

  /// Broadcast that a player has joined the room.
  void sendPlayerJoined(String roomCode, String userId, String displayName) {
    send(action: 'player_joined', roomCode: roomCode, data: {
      'userId': userId,
      'displayName': displayName,
    });
  }

  /// Broadcast that the game has started. Carries the matchId so the backend
  /// can auto-stream the real match data for that fixture.
  void sendGameStarted(String roomCode, {String? matchId}) {
    send(action: 'game_started', roomCode: roomCode, data: {
      if (matchId != null) 'matchId': matchId,
    });
  }

  /// Broadcast that a player has locked in their pick.
  void sendPickLocked(String roomCode, String userId) {
    send(action: 'pick_locked', roomCode: roomCode, data: {
      'userId': userId,
    });
  }

  /// Disconnect from the WebSocket intentionally (stops auto-reconnect).
  void disconnect() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    _channelSub?.cancel();
    _channelSub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  /// Dispose the service.
  void dispose() {
    disconnect();
    _messageController.close();
  }
}
