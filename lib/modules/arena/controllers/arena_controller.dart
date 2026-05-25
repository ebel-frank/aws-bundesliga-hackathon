import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../models/match_model.dart';
import '../../../models/player_model.dart';
import '../../../models/player_pick_model.dart';
import '../../../models/prediction_round_model.dart';
import '../../../models/squad_model.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/dfl_event_service.dart';
import '../../../services/websocket_service.dart';

/// Represents the current screen/phase within the Arena module.
enum ArenaScreen { lobby, waiting, prediction, roundResult, end }

/// Central state manager for the entire Arena module.
///
/// Owns all observable state, manages screen transitions, handles the
/// prediction round lifecycle (start game → iterate rounds → end game),
/// and coordinates with the backend API.
class ArenaController extends GetxController {
  static const bool useMockData = true;

  // ── Current user helpers ──────────────────────────────────────
  String get _currentUserId => AuthService.userId;
  String get _currentDisplayName => AuthService.displayName;

  // ── WebSocket ─────────────────────────────────────────────────
  final WebSocketService _matchWs = WebSocketService(); // for room list updates
  final WebSocketService _roomWs = WebSocketService();  // for squad lobby updates
  StreamSubscription? _matchWsSub;
  StreamSubscription? _roomWsSub;

  // ── DFL Event Feed ────────────────────────────────────────────
  final DflEventService dflEventService = DflEventService();
  StreamSubscription? _dflEventSub;
  final Rx<String> latestEventSummary = ''.obs;

  // ── Screen state ──────────────────────────────────────────────
  final Rx<ArenaScreen> currentScreen = ArenaScreen.lobby.obs;

  // ── Page state (lobby uses PageView) ────────────────────────────
  final RxInt arenaPageIndex = 0.obs; // 0 = matches, 1 = rooms for match, 2 = squad lobby

  // ── Match list ────────────────────────────────────────────────
  final RxList<MatchModel> availableMatches = <MatchModel>[].obs;
  final RxBool isLoadingMatches = false.obs;
  final Rx<MatchModel?> selectedMatch = Rx<MatchModel?>(null);

  // ── Room list (lobby) ─────────────────────────────────────────
  final RxList<SquadModel> availableRooms = <SquadModel>[].obs;
  final RxBool isLoadingRooms = false.obs;
  final RxBool isPrivateToggle = false.obs;
  final RxString roomSearchQuery = ''.obs;

  /// Filtered rooms based on search query.
  List<SquadModel> get filteredRooms {
    if (roomSearchQuery.value.isEmpty) return availableRooms;
    final q = roomSearchQuery.value.toLowerCase();
    return availableRooms.where((r) => r.roomName.toLowerCase().contains(q) || r.hostDisplayName.toLowerCase().contains(q)).toList();
  }

  // ── Squad ─────────────────────────────────────────────────────
  final Rx<SquadModel?> squad = Rx<SquadModel?>(null);
  final RxString roomCodeInput = ''.obs;
  final RxBool isCreatingRoom = false.obs;
  final RxBool isJoiningRoom = false.obs;
  final RxString errorMessage = ''.obs;

  // ── Game state ────────────────────────────────────────────────
  final RxInt currentRoundIndex = 0.obs;
  final RxInt totalRounds = 0.obs;
  final RxList<PredictionRoundModel> rounds = <PredictionRoundModel>[].obs;

  // ── Active prediction round ───────────────────────────────────
  final Rx<PredictionRoundModel?> activeRound = Rx<PredictionRoundModel?>(null);
  final RxList<PlayerPickModel> roundPicks = <PlayerPickModel>[].obs;
  final RxInt countdownSeconds = 15.obs;
  final RxString myPick = ''.obs;
  final RxBool hasLockedIn = false.obs;

  // ── Leaderboard ───────────────────────────────────────────────
  final RxList<PlayerModel> leaderboard = <PlayerModel>[].obs;

  // ── Round result ──────────────────────────────────────────────
  final RxInt xpEarnedThisRound = 0.obs;
  final RxBool wasCorrect = false.obs;
  final RxBool speedBonusEarned = false.obs;
  final RxInt newStreak = 0.obs;

  // ── End of game ───────────────────────────────────────────────
  final RxList<String> earnedBadges = <String>[].obs;

  // ── Match countdown (waiting room) ─────────────────────────────
  final RxInt matchCountdownSeconds = 0.obs;
  final RxBool isMatchLive = false.obs;
  Timer? _matchCountdownTimer;

  // ── Timer ─────────────────────────────────────────────────────
  Timer? _countdownTimer;

  // ── Methods ───────────────────────────────────────────────────

  /// Fetches available matches from the API.
  Future<void> fetchMatches() async {
    isLoadingMatches.value = true;
    try {
      final matches = await ApiService.getMatches();
      availableMatches.assignAll(matches);
    } catch (e) {
      errorMessage.value = 'Failed to load matches.';
      // Fallback to mock data if API fails
      if (useMockData) {
        availableMatches.assignAll(_mockMatches);
      }
    } finally {
      isLoadingMatches.value = false;
    }
  }

  /// User selects a match to see its rooms.
  void selectMatch(MatchModel match) {
    selectedMatch.value = match;
    arenaPageIndex.value = 1;
    fetchAvailableRooms();
    _connectMatchWebSocket(match.matchId);
  }

  /// Connect to match-level WebSocket for room list updates.
  void _connectMatchWebSocket(String matchId) {
    _matchWsSub?.cancel();
    _matchWs.disconnect();
    _matchWs.connect(roomCode: 'match_$matchId', userId: _currentUserId);
    _matchWsSub = _matchWs.messages.listen((msg) {
      final action = msg['action'] as String?;
      if (action == 'room_updated') {
        // Refresh room list when a room is updated
        fetchAvailableRooms();
      }
    });
  }

  /// Connect to room-level WebSocket for squad lobby updates.
  void _connectRoomWebSocket(String roomCode) {
    _roomWsSub?.cancel();
    _roomWs.disconnect();
    _roomWs.connect(roomCode: roomCode, userId: _currentUserId);
    _roomWsSub = _roomWs.messages.listen((msg) {
      final action = msg['action'] as String?;
      if (action == 'player_joined') {
        final data = msg['data'] as Map<String, dynamic>?;
        if (data != null && data['room'] != null) {
          squad.value = SquadModel.fromJson(data['room'] as Map<String, dynamic>);
        }
      } else if (action == 'game_started') {
        startGame();
      } else if (action == 'dfl_event') {
        _handleDflWebSocketEvent(msg);
      } else if (action == 'prediction_question') {
        _handlePredictionQuestion(msg);
      }
    });
  }

  /// Handle a DFL event received via WebSocket from the backend Lambda.
  void _handleDflWebSocketEvent(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>?;
    if (data == null) return;

    final event = data['event'] as Map<String, dynamic>?;
    if (event == null) return;

    final summary = event['summary'] as String? ?? 'Match event';
    latestEventSummary.value = summary;

    Get.snackbar(
      'Match Event',
      summary,
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 3),
      backgroundColor: const Color(0xDD1A2138),
      colorText: const Color(0xFFFFFFFF),
      margin: const EdgeInsets.all(12),
      borderRadius: 10,
    );
  }

  /// Handle a prediction question received from the AI pipeline.
  void _handlePredictionQuestion(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>?;
    if (data == null) return;

    final question = data['question'] as String? ?? '';
    final options = List<String>.from(data['options'] ?? []);
    final category = data['category'] as String? ?? 'live';
    final timeLimit = data['timeLimit'] as int? ?? 15;
    final triggerType = data['triggerType'] as String? ?? '';

    if (question.isEmpty || options.isEmpty) return;

    // Create a new prediction round from the AI-generated question
    final newRound = PredictionRoundModel(
      roundId: 'ai_${DateTime.now().millisecondsSinceEpoch}',
      roundNumber: currentRoundIndex.value + 2,
      questionText: question,
      options: options,
      correctAnswer: options.first, // Placeholder — resolved later
      category: category,
      timeLimitSeconds: timeLimit,
    );

    // Add to rounds and start it
    rounds.add(newRound);
    totalRounds.value = rounds.length;

    // If we're on the placeholder round, replace it
    if (activeRound.value?.roundId == 'r1') {
      currentRoundIndex.value = rounds.length - 2;
    }

    // Start the new round
    _startNextRound();
  }

  /// Fetches available rooms from API. Sets isLoadingRooms during fetch.
  Future<void> fetchAvailableRooms() async {
    isLoadingRooms.value = true;
    errorMessage.value = '';
    try {
      final matchId = selectedMatch.value?.matchId;
      if (matchId == null) {
        availableRooms.assignAll(<SquadModel>[]);
        return;
      }
      final rooms = await ApiService.getRooms(matchId);
      availableRooms.assignAll(rooms);
    } catch (e) {
      errorMessage.value = 'Failed to load rooms. Please try again.';
    } finally {
      isLoadingRooms.value = false;
    }
  }

  /// Creates a new room. Sets isCreatingRoom, navigates to squad lobby on success.
  Future<void> createRoom({
    required String roomName,
    required int maxPlayers,
    required bool isPrivate,
  }) async {
    isCreatingRoom.value = true;
    errorMessage.value = '';
    try {
      final matchId = selectedMatch.value?.matchId;
      if (matchId == null) {
        errorMessage.value = 'No match selected.';
        return;
      }

      final createdRoom = await ApiService.createRoom(
        matchId: matchId,
        roomName: roomName,
        maxPlayers: maxPlayers,
        isPrivate: isPrivate,
        hostUserId: _currentUserId,
        hostDisplayName: _currentDisplayName,
      );

      squad.value = createdRoom;
      currentScreen.value = ArenaScreen.waiting;
      arenaPageIndex.value = 2;
      _connectRoomWebSocket(createdRoom.roomCode);
      // If match is already live, skip countdown
      if (selectedMatch.value?.status == 'live') {
        isMatchLive.value = true;
      } else {
        startMatchCountdown(seconds: 10);
      }
    } on ApiException catch (e) {
      errorMessage.value = e.message;
    } catch (e) {
      errorMessage.value = 'Failed to create room. Please try again.';
    } finally {
      isCreatingRoom.value = false;
    }
  }

  /// Joins an existing room by code. For open rooms: no code param needed.
  /// For private rooms: code param required (6 chars).
  Future<void> joinRoom(String roomCode, {String? code}) async {
    isJoiningRoom.value = true;
    errorMessage.value = '';
    try {
      final joinedRoom = await ApiService.joinRoom(
        roomCode: roomCode,
        userId: _currentUserId,
        displayName: _currentDisplayName,
        code: code,
      );

      squad.value = joinedRoom;
      currentScreen.value = ArenaScreen.waiting;
      arenaPageIndex.value = 2;
      _connectRoomWebSocket(joinedRoom.roomCode);
      // If match is already live, skip countdown
      if (selectedMatch.value?.status == 'live') {
        isMatchLive.value = true;
      } else {
        startMatchCountdown(seconds: 10);
      }
    } on ApiException catch (e) {
      errorMessage.value = e.message;
    } catch (e) {
      errorMessage.value = 'Failed to join room. Please try again.';
    } finally {
      isJoiningRoom.value = false;
    }
  }

  /// Host starts the game. Fetches rounds from API, begins first round.
  /// Navigates everyone to the prediction screen.
  void startGame() async {
    if (!isMatchLive.value) return; // Can't start until match is live

    // Load DFL event feed
    await dflEventService.loadSampleData();
    _dflEventSub?.cancel();
    _dflEventSub = dflEventService.events.listen((event) {
      latestEventSummary.value = event.summary;
      // Show toast via Get.snackbar
      Get.snackbar(
        'Match Event',
        event.summary,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xDD1A2138),
        colorText: const Color(0xFFFFFFFF),
        margin: const EdgeInsets.all(12),
        borderRadius: 10,
      );
    });

    // If rounds are empty, populate with a single placeholder round
    if (rounds.isEmpty) {
      _initMockRounds();
    }
    if (rounds.isNotEmpty) {
      totalRounds.value = rounds.length;
      currentRoundIndex.value = -1;

      // Start the first round BEFORE navigating so the view has data
      _startNextRound();

      // Start DFL event streaming
      dflEventService.startStreaming(intervalSeconds: 3);

      // Navigate to prediction screen
      Get.toNamed(AppRoutes.arenaPrediction);
    }
  }

  /// Starts the match countdown in the waiting room.
  /// Simulates waiting for the real match to begin.
  void startMatchCountdown({int seconds = 10}) {
    matchCountdownSeconds.value = seconds;
    isMatchLive.value = false;
    _matchCountdownTimer?.cancel();
    _matchCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (matchCountdownSeconds.value <= 0) {
        timer.cancel();
        isMatchLive.value = true;
      } else {
        matchCountdownSeconds.value--;
      }
    });
  }

  /// Advances to the next round. Sets activeRound, resets pick state, starts countdown.
  void _startNextRound() {
    currentRoundIndex.value++;

    if (currentRoundIndex.value >= rounds.length) {
      _endGame();
      return;
    }

    activeRound.value = rounds[currentRoundIndex.value];
    myPick.value = '';
    hasLockedIn.value = false;
    xpEarnedThisRound.value = 0;
    wasCorrect.value = false;
    speedBonusEarned.value = false;
    countdownSeconds.value = activeRound.value!.timeLimitSeconds;

    // Reset round picks for all squad members
    if (squad.value != null) {
      roundPicks.assignAll(
        squad.value!.members
            .map((m) => PlayerPickModel(userId: m.userId))
            .toList(),
      );
    }

    currentScreen.value = ArenaScreen.prediction;
    _startCountdown();
  }

  /// Player locks in their answer. Idempotent — ignored if already locked.
  /// POST /rounds/{roundId}/pick { userId, pick, secondsTaken }
  void lockInPick(String option) {
    if (hasLockedIn.value) return;

    myPick.value = option;
    hasLockedIn.value = true;

    // TODO: POST /rounds/{roundId}/pick to backend
  }

  /// Starts the 15-second countdown timer. Decrements countdownSeconds each second.
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdownSeconds.value <= 0) {
        timer.cancel();
        _closeRound();
      } else {
        countdownSeconds.value--;
      }
    });
  }

  /// Called when timer hits 0. Resolves correct answer, calculates XP,
  /// updates leaderboard, transitions to roundResult screen.
  void _closeRound() {
    _countdownTimer?.cancel();

    final round = activeRound.value;
    if (round == null) return;

    // Determine if the player's pick is correct
    final isCorrect = myPick.value == round.correctAnswer;
    wasCorrect.value = isCorrect;

    // Calculate XP: 10 base if correct + 5 speed bonus if secondsTaken ≤ 5
    int xp = 0;
    if (isCorrect) {
      xp = 10;
      final secondsTaken =
          round.timeLimitSeconds - countdownSeconds.value;
      if (secondsTaken <= 5) {
        xp += 5;
        speedBonusEarned.value = true;
      } else {
        speedBonusEarned.value = false;
      }
    } else {
      speedBonusEarned.value = false;
    }
    xpEarnedThisRound.value = xp;

    // Update streak: increment on correct, reset on wrong
    if (isCorrect) {
      newStreak.value = newStreak.value + 1;
    } else {
      newStreak.value = 0;
    }

    // Update leaderboard — find current player and update XP/streak
    // For now, update the first player in leaderboard as "self"
    if (leaderboard.isNotEmpty) {
      final updatedLeaderboard = leaderboard.map((player) {
        if (player.isHost) {
          // Assume host is the current user for now
          return player.copyWith(
            totalXP: player.totalXP + xp,
            streak: newStreak.value,
          );
        }
        return player;
      }).toList();

      // Re-sort leaderboard by totalXP descending
      updatedLeaderboard.sort((a, b) => b.totalXP.compareTo(a.totalXP));
      leaderboard.assignAll(updatedLeaderboard);
    }

    currentScreen.value = ArenaScreen.roundResult;

    // After 4 seconds, proceed to next round or end game
    Future.delayed(const Duration(seconds: 4), () {
      if (currentRoundIndex.value + 1 >= rounds.length) {
        _endGame();
      } else {
        _startNextRound();
      }
    });
  }

  /// Called after all rounds complete. Finalizes game, calculates badges,
  /// navigates to end screen.
  void _endGame() {
    _countdownTimer?.cancel();

    // Determine earned badges based on performance
    final badges = <String>[];

    // "Perfect Round" — all answers correct (streak == totalRounds)
    if (newStreak.value == totalRounds.value && totalRounds.value > 0) {
      badges.add('Perfect Round');
    }

    // "Speed Demon" — speed bonus earned at least once (simplified check)
    if (speedBonusEarned.value) {
      badges.add('Speed Demon');
    }

    // "Streak Master" — streak of 3 or more at any point
    if (newStreak.value >= 3) {
      badges.add('Streak Master');
    }

    earnedBadges.assignAll(badges);
    currentScreen.value = ArenaScreen.end;
    Get.toNamed(AppRoutes.arenaEnd);
  }

  // ── Mock Data ─────────────────────────────────────────────────

  void _initMockRounds() {
    // Single placeholder round — timer is paused (long limit).
    // Real questions will be generated from DFL events via AI.
    rounds.assignAll(const [
      PredictionRoundModel(
        roundId: 'r1',
        roundNumber: 1,
        questionText: 'Waiting for AI-generated question...',
        options: ['Option A', 'Option B', 'Option C'],
        correctAnswer: 'Option A',
        category: 'live',
        timeLimitSeconds: 9999,
      ),
    ]);

    totalRounds.value = 1;
  }

  static const _mockMatches = [
    MatchModel(
      matchId: 'm1',
      homeTeam: 'Bayern Munich',
      awayTeam: 'Borussia Dortmund',
      homeTeamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg',
      awayTeamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg',
      league: 'Bundesliga',
      matchTime: '20:30',
      matchDate: 'Today',
      status: 'live',
      roomCount: 0,
    ),
    MatchModel(
      matchId: 'm2',
      homeTeam: 'Borussia Dortmund',
      awayTeam: 'Bayern Munich',
      homeTeamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg',
      awayTeamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg',
      league: 'Bundesliga',
      matchTime: '18:30',
      matchDate: 'Tomorrow',
      status: 'upcoming',
      roomCount: 0,
    ),
    MatchModel(
      matchId: 'm3',
      homeTeam: 'RB Leipzig',
      awayTeam: 'Bayern Munich',
      homeTeamBadge: '',
      awayTeamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg',
      league: 'Bundesliga',
      matchTime: '15:30',
      matchDate: 'Sat, Jun 28',
      status: 'upcoming',
      roomCount: 0,
    ),
    MatchModel(
      matchId: 'm4',
      homeTeam: 'Bayer Leverkusen',
      awayTeam: 'Borussia Dortmund',
      homeTeamBadge: '',
      awayTeamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg',
      league: 'Bundesliga',
      matchTime: '20:30',
      matchDate: 'Sat, Jun 28',
      status: 'upcoming',
      roomCount: 0,
    ),
  ];

  @override
  void onClose() {
    _countdownTimer?.cancel();
    _matchCountdownTimer?.cancel();
    _matchWsSub?.cancel();
    _roomWsSub?.cancel();
    _dflEventSub?.cancel();
    _matchWs.disconnect();
    _roomWs.disconnect();
    dflEventService.dispose();
    super.onClose();
  }
}
