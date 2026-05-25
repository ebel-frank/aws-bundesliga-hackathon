import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket service for real-time squad communication.
/// Replace [wsUrl] with your deployed WebSocket API Gateway URL after running `sam deploy`.
class WebSocketService {
  static const String wsUrl = 'wss://aqalim0031.execute-api.us-east-1.amazonaws.com/prod';

  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of incoming messages from the WebSocket.
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Whether the WebSocket is currently connected.
  bool get isConnected => _channel != null;

  /// Connect to the WebSocket for a specific room.
  void connect({required String roomCode, required String userId}) {
    final uri = Uri.parse('$wsUrl?roomCode=$roomCode&userId=$userId');
    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      (data) {
        try {
          final message = jsonDecode(data as String) as Map<String, dynamic>;
          _messageController.add(message);
        } catch (_) {}
      },
      onDone: () {
        _channel = null;
        // Auto-reconnect after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (!_messageController.isClosed) {
            connect(roomCode: roomCode, userId: userId);
          }
        });
      },
      onError: (_) {
        _channel = null;
      },
    );
  }

  /// Send a message to all players in the room.
  void send({
    required String action,
    required String roomCode,
    Map<String, dynamic>? data,
  }) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      'action': action,
      'roomCode': roomCode,
      'data': data ?? {},
    }));
  }

  /// Broadcast that a player has joined the room.
  void sendPlayerJoined(String roomCode, String userId, String displayName) {
    send(action: 'player_joined', roomCode: roomCode, data: {
      'userId': userId,
      'displayName': displayName,
    });
  }

  /// Broadcast that the game has started.
  void sendGameStarted(String roomCode) {
    send(action: 'game_started', roomCode: roomCode);
  }

  /// Broadcast that a player has locked in their pick.
  void sendPickLocked(String roomCode, String userId) {
    send(action: 'pick_locked', roomCode: roomCode, data: {
      'userId': userId,
    });
  }

  /// Disconnect from the WebSocket.
  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  /// Dispose the service.
  void dispose() {
    disconnect();
    _messageController.close();
  }
}
