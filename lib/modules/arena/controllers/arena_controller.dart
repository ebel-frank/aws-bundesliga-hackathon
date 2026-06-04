import 'dart:async';
import 'dart:math';

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
import '../../../services/websocket_service.dart';
import '../widgets/live_chat_widget.dart';
import 'package:flutter/services.dart';

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

  /// Stores the user's picks: questionId → selected option
  final Map<String, String> _userPicks = {};

  // ── Active prediction round ───────────────────────────────────
  final Rx<PredictionRoundModel?> activeRound = Rx<PredictionRoundModel?>(null);
  final RxList<PlayerPickModel> roundPicks = <PlayerPickModel>[].obs;
  final RxInt countdownSeconds = 15.obs;
  final RxString myPick = ''.obs;
  final RxBool hasLockedIn = false.obs;
  // True once the live timer has elapsed but the question is still answerable
  // for minimum (catch-up) points until it resolves.
  final RxBool inCatchUp = false.obs;

  // ── Leaderboard ───────────────────────────────────────────────
  final RxList<PlayerModel> leaderboard = <PlayerModel>[].obs;

  // ── Round result ──────────────────────────────────────────────
  final RxInt xpEarnedThisRound = 0.obs;
  final RxBool wasCorrect = false.obs;
  final RxBool speedBonusEarned = false.obs;
  final RxInt newStreak = 0.obs;
  final RxBool isDeferred = true.obs; // true = answer resolved at match end

  // ── End of game ───────────────────────────────────────────────
  final RxList<String> earnedBadges = <String>[].obs;

  // ── Live chat & reactions ─────────────────────────────────────
  final RxList<ChatMessage> chatMessages = <ChatMessage>[].obs;
  final RxList<FloatingReaction> floatingReactions = <FloatingReaction>[].obs;

  // ── Match countdown (waiting room) ─────────────────────────────
  final RxInt matchCountdownSeconds = 0.obs;
  final RxBool isMatchLive = false.obs;
  Timer? _matchCountdownTimer;
  // Guards against starting the game twice (host click + its own broadcast echo).
  bool _gameStarted = false;

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
        // Another player (the host) started the game — sync into the match.
        _beginGame(broadcast: false);
      } else if (action == 'dfl_event') {
        _handleDflWebSocketEvent(msg);
      } else if (action == 'prediction_question') {
        _handlePredictionQuestion(msg);
      } else if (action == 'questions_resolved') {
        _handleQuestionsResolved(msg);
      } else if (action == 'match_ended') {
        _handleMatchEnded(msg);
      } else if (action == 'chat_message') {
        _handleChatMessage(msg);
      } else if (action == 'reaction') {
        _handleReaction(msg);
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
  }

  /// Handle a prediction question received from the AI pipeline.
  void _handlePredictionQuestion(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>?;
    if (data == null) return;

    final questionId = data['questionId'] as String? ?? '';
    final question = data['question'] as String? ?? '';
    final options = List<String>.from(data['options'] ?? []);
    final category = data['category'] as String? ?? 'live';
    final timeLimit = data['timeLimit'] as int? ?? 15;
    final triggerType = data['triggerType'] as String? ?? '';

    if (question.isEmpty || options.isEmpty) return;

    // Create a new prediction round from the AI-generated question
    final newRound = PredictionRoundModel(
      roundId: questionId.isNotEmpty ? questionId : 'ai_${DateTime.now().millisecondsSinceEpoch}',
      roundNumber: rounds.length + 1,
      questionText: question,
      options: options,
      correctAnswer: '', // Unknown until resolved at match end
      category: category,
      timeLimitSeconds: timeLimit,
    );

    // Add to rounds
    rounds.add(newRound);
    totalRounds.value = rounds.length;
    currentRoundIndex.value = rounds.length - 2; // _startNextRound increments

    // Reset pick state and start the round
    myPick.value = '';
    hasLockedIn.value = false;
    inCatchUp.value = false;
    activeRound.value = newRound;
    countdownSeconds.value = timeLimit;
    currentScreen.value = ArenaScreen.prediction;

    // Alert the user — vibrate + system sound
    _alertQuestionArrived();

    _startCountdown();
  }

  /// Handle question resolutions from the backend. Fires live (per-question)
  /// during the match and again at the final whistle. The server is the source
  /// of truth for scores and the leaderboard.
  void _handleQuestionsResolved(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>?;
    if (data == null) return;

    final results = data['results'] as List<dynamic>? ?? [];
    if (results.isEmpty) return;

    // 1. Apply the server's authoritative leaderboard if present.
    final serverLb = data['leaderboard'] as Map<String, dynamic>?;
    if (serverLb != null && serverLb.isNotEmpty) {
      _applyServerLeaderboard(serverLb);
    }

    // 2. Surface the most recent result to the player as a round-result overlay.
    //    Find a result the local user actually answered, preferring the last one.
    for (final result in results.reversed) {
      final questionId = result['questionId'] as String? ?? '';
      final myPickForQ = _userPicks[questionId];
      if (myPickForQ == null) continue;

      final scores = result['scores'] as Map<String, dynamic>?;
      final myPoints = (scores?[_currentUserId] as num?)?.toInt() ?? 0;
      // Server is authoritative: any points means the pick was correct.
      final correct = myPoints > 0;

      wasCorrect.value = correct;
      xpEarnedThisRound.value = myPoints;
      // Fast answers earn well above the catch-up minimum (100); flag a speed badge.
      speedBonusEarned.value = correct && myPoints >= 600;
      isDeferred.value = false;
      newStreak.value = correct ? newStreak.value + 1 : 0;

      // If this resolves the question currently on screen, clear it.
      if (activeRound.value?.roundId == questionId) {
        _countdownTimer?.cancel();
        inCatchUp.value = false;
        activeRound.value = null;
      }

      // Show the result overlay briefly, then return to waiting for the next Q.
      if (currentScreen.value != ArenaScreen.end) {
        currentScreen.value = ArenaScreen.roundResult;
        Future.delayed(const Duration(seconds: 3), () {
          if (currentScreen.value == ArenaScreen.roundResult) {
            currentScreen.value = ArenaScreen.prediction;
          }
        });
      }
      break;
    }
  }

  /// Replace the leaderboard XP totals with the server's authoritative values.
  void _applyServerLeaderboard(Map<String, dynamic> serverLb) {
    final members = squad.value?.members ?? [];
    if (members.isEmpty) return;
    final lb = members.map((m) {
      final xp = (serverLb[m.userId] as num?)?.toInt() ?? m.totalXP;
      return m.copyWith(totalXP: xp);
    }).toList();
    lb.sort((a, b) => b.totalXP.compareTo(a.totalXP));
    leaderboard.assignAll(lb);
  }

  /// Handle match ended signal (stream finished).
  void _handleMatchEnded(Map<String, dynamic> msg) {
    // If questions_resolved hasn't already navigated us, go to end screen
    if (currentScreen.value == ArenaScreen.end) return;

    _countdownTimer?.cancel();
    activeRound.value = null;

    // Apply final leaderboard if the match-ended payload carries one.
    final data = msg['data'] as Map<String, dynamic>?;
    final serverLb = data?['leaderboard'] as Map<String, dynamic>?;
    if (serverLb != null && serverLb.isNotEmpty) {
      _applyServerLeaderboard(serverLb);
    }

    // Fall back to current squad ordering if we somehow have no leaderboard.
    final members = squad.value?.members ?? [];
    if (leaderboard.isEmpty && members.isNotEmpty) {
      final lb = List.of(members)..sort((a, b) => b.totalXP.compareTo(a.totalXP));
      leaderboard.assignAll(lb);
    }

    // Award badges from the final standings.
    _awardEndBadges();

    currentScreen.value = ArenaScreen.end;
    Get.toNamed(AppRoutes.arenaEnd);
  }

  /// Derive end-of-match badges for the local player from final results.
  void _awardEndBadges() {
    final badges = <String>[];
    if (leaderboard.isNotEmpty && leaderboard.first.userId == _currentUserId) {
      badges.add('Champion');
    }
    if (newStreak.value >= 3) badges.add('Streak Master');
    if (speedBonusEarned.value) badges.add('Speed Demon');
    earnedBadges.assignAll(badges);
  }

  /// Handle incoming chat message from another player.
  void _handleChatMessage(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>?;
    if (data == null) return;

    final userId = data['userId'] as String? ?? '';
    final displayName = data['displayName'] as String? ?? 'Player';
    final text = data['text'] as String? ?? '';
    if (text.isEmpty) return;

    // Skip if this is our own message (already added locally)
    if (userId == _currentUserId) return;

    chatMessages.add(ChatMessage(
      userId: userId,
      displayName: displayName,
      text: text,
    ));

    // Keep only last 50 messages in memory
    if (chatMessages.length > 50) {
      chatMessages.removeRange(0, chatMessages.length - 50);
    }
  }

  /// Handle incoming emoji reaction from another player.
  void _handleReaction(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>?;
    if (data == null) return;

    final emoji = data['emoji'] as String? ?? '';
    final userId = data['userId'] as String? ?? '';
    if (emoji.isEmpty) return;

    // Skip if this is our own reaction (already added locally)
    if (userId == _currentUserId) return;

    _addFloatingReaction(emoji);
  }

  /// Send a chat message to the room.
  void sendChatMessage(String text) {
    if (text.isEmpty) return;

    final roomCode = squad.value?.roomCode ?? '';
    _roomWs.send(
      action: 'chat_message',
      roomCode: roomCode,
      data: {
        'userId': _currentUserId,
        'displayName': _currentDisplayName,
        'text': text,
      },
    );

    // Add locally immediately for instant feedback
    chatMessages.add(ChatMessage(
      userId: _currentUserId,
      displayName: _currentDisplayName,
      text: text,
    ));
    if (chatMessages.length > 50) {
      chatMessages.removeRange(0, chatMessages.length - 50);
    }
  }

  /// Send an emoji reaction to the room.
  void sendReaction(String emoji) {
    final roomCode = squad.value?.roomCode ?? '';
    _roomWs.send(
      action: 'reaction',
      roomCode: roomCode,
      data: {
        'userId': _currentUserId,
        'emoji': emoji,
      },
    );

    // Show locally immediately
    _addFloatingReaction(emoji);
  }

  /// Add a floating reaction to the list.
  void _addFloatingReaction(String emoji) {
    final reaction = FloatingReaction(
      emoji: emoji,
      startX: Random().nextDouble() * 20,
    );
    floatingReactions.add(reaction);
  }

  /// Remove a completed floating reaction.
  void removeReaction(String id) {
    floatingReactions.removeWhere((r) => r.id == id);
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

      // Update room count on the match in the list
      final matchIndex = availableMatches.indexWhere((m) => m.matchId == matchId);
      if (matchIndex != -1) {
        final updated = availableMatches[matchIndex].copyWith(roomCount: rooms.length);
        availableMatches[matchIndex] = updated;
      }
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
      _gameStarted = false;
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
      _gameStarted = false;
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

  /// Host starts the game. Broadcasts game_started to the room (which triggers
  /// the backend to auto-stream the real match data), then navigates everyone
  /// to the prediction screen. Idempotent via [_gameStarted].
  void startGame() async {
    if (!isMatchLive.value) return;
    _beginGame(broadcast: true);
  }

  /// Shared start path. [broadcast] true when this client is the initiating host.
  /// All clients (host + joiners) run the local setup + navigation exactly once.
  void _beginGame({required bool broadcast}) {
    if (_gameStarted) return;
    _gameStarted = true;

    // Host announces the start so the backend auto-streams and peers sync.
    if (broadcast) {
      final roomCode = squad.value?.roomCode ?? '';
      if (roomCode.isNotEmpty) {
        _roomWs.sendGameStarted(roomCode, matchId: selectedMatch.value?.matchId);
      }
    }

    // Clear any old rounds
    rounds.clear();
    totalRounds.value = 0;
    currentRoundIndex.value = -1;
    activeRound.value = null;
    _userPicks.clear();
    chatMessages.clear();
    floatingReactions.clear();

    // Navigate to prediction screen — questions will arrive via WebSocket.
    // The backend waits ~5s, fires the kick-off questions, then streams events.
    currentScreen.value = ArenaScreen.prediction;
    Get.toNamed(AppRoutes.arenaPrediction);
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
    isDeferred.value = false;
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

  /// Player locks in their answer. Sends the pick to the server immediately
  /// for real-time scoring. Kick-off questions (category 'kickoff') may be
  /// changed until resolved — at a points penalty applied server-side.
  void lockInPick(String option) {
    final round = activeRound.value;
    if (round == null) return;

    final isKickoff = round.category == 'kickoff';
    // Non-kickoff questions lock once; kickoff questions allow changes.
    if (hasLockedIn.value && !isKickoff) return;
    // No-op if re-selecting the same option.
    if (hasLockedIn.value && myPick.value == option) return;

    final isChange = hasLockedIn.value && myPick.value != option;

    myPick.value = option;
    hasLockedIn.value = true;
    _userPicks[round.roundId] = option;

    final secondsTaken = round.timeLimitSeconds - countdownSeconds.value;

    _roomWs.send(
      action: 'submit_pick',
      roomCode: squad.value?.roomCode ?? '',
      data: {
        'matchId': selectedMatch.value?.matchId ?? '',
        'questionId': round.roundId,
        'userId': _currentUserId,
        'pick': option,
        'secondsTaken': secondsTaken < 0 ? 0 : secondsTaken,
      },
    );

    if (isChange) {
      Get.snackbar(
        'Answer changed',
        'Changing a kick-off prediction costs a few points.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(12),
      );
    }
  }

  /// Alert the user that a new question has arrived — vibrate + system sound.
  void _alertQuestionArrived() {
    // Heavy haptic feedback (vibration)
    HapticFeedback.heavyImpact();
    // Play system click sound as audio cue
    SystemSound.play(SystemSoundType.alert);
    // Double vibrate for emphasis
    Future.delayed(const Duration(milliseconds: 200), () {
      HapticFeedback.mediumImpact();
    });
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

  /// Called when the per-question live timer hits 0. Rather than clearing the
  /// question, we enter "catch-up" mode: it stays answerable for minimum points
  /// until the server resolves it (which arrives via `questions_resolved`).
  void _closeRound() {
    _countdownTimer?.cancel();
    if (activeRound.value == null) return;
    inCatchUp.value = true;
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

  // ── Mock Data ─────────────────────────────────────────────────

  static const _mockMatches = [
    MatchModel(
      matchId: 'm1',
      homeTeam: 'Bayern Munich',
      awayTeam: 'Eintracht Frankfurt',
      homeTeamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg',
      awayTeamBadge: 'assets/icons/germany_eintracht-frankfurt.football-logos.svg',
      league: 'Bundesliga',
      matchTime: '20:30',
      matchDate: 'Today',
      status: 'live',
      roomCount: 0,
    ),
    MatchModel(
      matchId: 'm2',
      homeTeam: 'Eintracht Frankfurt',
      awayTeam: 'Bayern Munich',
      homeTeamBadge: 'assets/icons/germany_eintracht-frankfurt.football-logos.svg',
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
      homeTeamBadge: 'assets/icons/germany_rb-leipzig.football-logos.svg',
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
      awayTeam: 'Eintracht Frankfurt',
      homeTeamBadge: 'assets/icons/germany_bayer-leverkusen.football-logos.svg',
      awayTeamBadge: 'assets/icons/germany_eintracht-frankfurt.football-logos.svg',
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
    _matchWs.disconnect();
    _roomWs.disconnect();
    super.onClose();
  }
}
