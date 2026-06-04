import 'package:dio/dio.dart';
import '../models/match_model.dart';
import '../models/prediction_round_model.dart';
import '../models/squad_model.dart';

/// Central API service for communicating with the AWS backend.
/// Replace [baseUrl] with your deployed API Gateway URL after running `sam deploy`.
class ApiService {
  static const String baseUrl = 'https://g6dqdwf5aa.execute-api.us-east-1.amazonaws.com/prod';

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Content-Type': 'application/json'},
  ));

  // ─── Matches ────────────────────────────────────────────────────

  /// Fetch all matches, optionally filtered by status ('upcoming', 'live', 'finished').
  static Future<List<MatchModel>> getMatches({String? status}) async {
    try {
      final params = status != null ? {'status': status} : null;
      final response = await _dio.get('/matches', queryParameters: params);
      final List items = response.data['matches'] ?? [];
      return items.map((json) => MatchModel.fromJson(json)).toList();
    } catch (e) {
      throw ApiException('Failed to fetch matches: $e');
    }
  }

  // ─── Rooms ──────────────────────────────────────────────────────

  /// Fetch rooms for a specific match.
  static Future<List<SquadModel>> getRooms(String matchId) async {
    try {
      final response = await _dio.get('/matches/$matchId/rooms');
      final List items = response.data['rooms'] ?? [];
      return items.map((json) => SquadModel.fromJson(json)).toList();
    } catch (e) {
      throw ApiException('Failed to fetch rooms: $e');
    }
  }

  /// Create a new room.
  static Future<SquadModel> createRoom({
    required String matchId,
    required String roomName,
    required int maxPlayers,
    required bool isPrivate,
    required String hostUserId,
    String? hostDisplayName,
  }) async {
    try {
      final response = await _dio.post('/rooms', data: {
        'matchId': matchId,
        'roomName': roomName,
        'maxPlayers': maxPlayers,
        'isPrivate': isPrivate,
        'hostUserId': hostUserId,
        'hostDisplayName': hostDisplayName ?? 'Host',
      });
      return SquadModel.fromJson(response.data['room']);
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) {
        throw ApiException(e.response?.data['error'] ?? 'Invalid request');
      }
      throw ApiException('Failed to create room: $e');
    }
  }

  /// Join an existing room.
  static Future<SquadModel> joinRoom({
    required String roomCode,
    required String userId,
    String? displayName,
    String? code,
  }) async {
    try {
      final response = await _dio.post('/rooms/join/$roomCode', data: {
        'userId': userId,
        'displayName': displayName ?? 'Player',
        if (code != null) 'code': code,
      });
      return SquadModel.fromJson(response.data['room']);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final msg = e.response?.data['error'] ?? 'Failed to join room';
      if (status == 404) throw ApiException('Room not found');
      if (status == 409) throw ApiException('Room is full');
      if (status == 403) throw ApiException('Invalid room code');
      throw ApiException(msg);
    }
  }

  // ─── Rounds ─────────────────────────────────────────────────────

  /// Fetch prediction rounds for a match.
  static Future<List<PredictionRoundModel>> getRounds(String matchId) async {
    try {
      final response = await _dio.get('/rounds/$matchId');
      final List items = response.data['rounds'] ?? [];
      return items.map((json) => PredictionRoundModel.fromJson(json)).toList();
    } catch (e) {
      throw ApiException('Failed to fetch rounds: $e');
    }
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}
