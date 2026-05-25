import 'dart:async';
import 'dart:ui';

import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../models/fantasy_entry_model.dart';
import '../../../models/fantasy_football_player_model.dart';
import '../../../models/fantasy_match_event_model.dart';
import '../../../models/match_model.dart';

/// Manages all state for the Fantasy Football module.
///
/// Flow:
///   1. User picks a match from [matches].
///   2. 22 [allPlayers] load for that match.
///   3. User selects exactly 11 → [selectedPlayerIds].
///   4. User confirms → [teamConfirmed] = true, navigates to live view.
///   5. If match status is 'live', events fire via [_eventTimer].
///   6. Events accumulate in [matchEvents] → points computed reactively.
///   7. [leaderboard] updates as events fire.
class FantasyController extends GetxController {
  // ── Navigation ─────────────────────────────────────────────────
  final RxInt pageIndex = 0.obs; // 0 = match list, 1 = squad builder

  // ── Match list ─────────────────────────────────────────────────
  final RxList<MatchModel> matches = <MatchModel>[].obs;
  final RxBool isLoadingMatches = false.obs;
  final Rx<MatchModel?> selectedMatch = Rx<MatchModel?>(null);

  // ── Players ────────────────────────────────────────────────────
  final RxList<FantasyFootballPlayer> allPlayers = <FantasyFootballPlayer>[].obs;

  // ── Selection ──────────────────────────────────────────────────
  final RxList<String> selectedPlayerIds = <String>[].obs;
  final RxBool teamConfirmed = false.obs;

  // ── Match state ────────────────────────────────────────────────
  final RxString matchStatus = 'upcoming'.obs; // 'upcoming' | 'live' | 'finished'

  // ── Events & scoring ──────────────────────────────────────────
  final RxList<FantasyMatchEvent> matchEvents = <FantasyMatchEvent>[].obs;

  // ── Leaderboard ────────────────────────────────────────────────
  final RxList<FantasyEntry> leaderboard = <FantasyEntry>[].obs;
  final Rx<FantasyEntry?> myEntry = Rx<FantasyEntry?>(null);

  // ── Internals ──────────────────────────────────────────────────
  Timer? _eventTimer;
  int _eventIndex = 0;
  List<FantasyMatchEvent> _pendingEvents = [];

  // ── Derived ────────────────────────────────────────────────────

  int get selectedCount => selectedPlayerIds.length;
  bool get canConfirm => selectedPlayerIds.length == 11;
  bool get canEdit => !teamConfirmed.value || matchStatus.value == 'upcoming';

  /// All 22 players with points computed from fired events.
  List<FantasyFootballPlayer> get playersWithPoints {
    final eventsByPlayer = <String, List<FantasyMatchEvent>>{};
    for (final e in matchEvents) {
      eventsByPlayer.putIfAbsent(e.playerId, () => []).add(e);
    }
    return allPlayers.map((p) {
      final evts = eventsByPlayer[p.id] ?? [];
      final pts = evts.fold(0, (sum, e) => sum + e.points);
      return p.copyWith(points: pts, events: evts);
    }).toList();
  }

  /// Current user's selected 11 with live points, sorted GK→DEF→MID→FWD.
  List<FantasyFootballPlayer> get mySelectedPlayers {
    const order = {'GK': 0, 'DEF': 1, 'MID': 2, 'FWD': 3};
    return playersWithPoints
        .where((p) => selectedPlayerIds.contains(p.id))
        .toList()
      ..sort((a, b) =>
          (order[a.position] ?? 4).compareTo(order[b.position] ?? 4));
  }

  int get myTotalPoints =>
      mySelectedPlayers.fold(0, (sum, p) => sum + p.points);

  // ── Lifecycle ──────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _loadMatches();
  }

  @override
  void onClose() {
    _eventTimer?.cancel();
    super.onClose();
  }

  // ── Public actions ─────────────────────────────────────────────

  Future<void> _loadMatches() async {
    isLoadingMatches.value = true;
    await Future.delayed(const Duration(milliseconds: 350));
    matches.assignAll(_mockMatches);
    isLoadingMatches.value = false;
  }

  void selectMatch(MatchModel match) {
    selectedMatch.value = match;
    _resetForMatch(match);
    pageIndex.value = 1;
  }

  void goBackToMatchList() {
    _eventTimer?.cancel();
    pageIndex.value = 0;
    selectedMatch.value = null;
    allPlayers.clear();
    selectedPlayerIds.clear();
    teamConfirmed.value = false;
    matchEvents.clear();
    leaderboard.clear();
    myEntry.value = null;
  }

  void togglePlayer(String playerId) {
    if (!canEdit) return;
    if (selectedPlayerIds.contains(playerId)) {
      selectedPlayerIds.remove(playerId);
    } else if (selectedPlayerIds.length < 11) {
      selectedPlayerIds.add(playerId);
    }
  }

  void confirmTeam() {
    if (!canConfirm) return;
    teamConfirmed.value = true;
    myEntry.value = FantasyEntry(
      userId: 'me',
      displayName: 'You',
      avatarColor: const Color(0xFF2979FF),
      selectedPlayerIds: List<String>.from(selectedPlayerIds),
      totalPoints: 0,
    );
    Get.toNamed(AppRoutes.fantasyLive);
    if (matchStatus.value == 'live') {
      _startLiveSimulation();
    }
  }

  void editTeam() {
    if (matchStatus.value != 'upcoming') return;
    teamConfirmed.value = false;
    Get.back(); // pop live view back to squad builder
  }

  /// Called from the live view once it's mounted.
  void startSimulationIfLive() {
    if (matchStatus.value == 'live' &&
        teamConfirmed.value &&
        _eventTimer == null) {
      _startLiveSimulation();
    }
  }

  // ── Internals ──────────────────────────────────────────────────

  void _resetForMatch(MatchModel match) {
    _eventTimer?.cancel();
    _eventTimer = null;
    selectedPlayerIds.clear();
    teamConfirmed.value = false;
    matchEvents.clear();
    _eventIndex = 0;

    allPlayers.assignAll(_playersForMatch(match.matchId));
    leaderboard.assignAll(_mockLeaderboard(match.matchId));
    _pendingEvents = _eventsForMatch(match.matchId);

    matchStatus.value = match.status == 'live'
        ? 'live'
        : match.status == 'finished'
            ? 'finished'
            : 'upcoming';

    if (matchStatus.value == 'finished') {
      matchEvents.assignAll(_pendingEvents);
      _rebuildLeaderboard();
    }
  }

  void _startLiveSimulation() {
    _eventTimer?.cancel();
    if (_eventIndex >= _pendingEvents.length) return;
    _eventTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_eventIndex >= _pendingEvents.length) {
        timer.cancel();
        _eventTimer = null;
        matchStatus.value = 'finished';
        _rebuildLeaderboard();
        return;
      }
      final event = _pendingEvents[_eventIndex++];
      matchEvents.add(event);
      _applyEventToLeaderboard(event);
    });
  }

  void _applyEventToLeaderboard(FantasyMatchEvent event) {
    // Update my running total
    if (myEntry.value != null &&
        myEntry.value!.selectedPlayerIds.contains(event.playerId)) {
      myEntry.value = myEntry.value!.copyWith(
        totalPoints: myEntry.value!.totalPoints + event.points,
      );
    }
    // Update competing entries and re-sort
    final updated = leaderboard.map((entry) {
      if (entry.selectedPlayerIds.contains(event.playerId)) {
        return entry.copyWith(totalPoints: entry.totalPoints + event.points);
      }
      return entry;
    }).toList()
      ..sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
    leaderboard.assignAll(updated);
  }

  void _rebuildLeaderboard() {
    final pointsByPlayer = <String, int>{};
    for (final e in _pendingEvents) {
      pointsByPlayer[e.playerId] =
          (pointsByPlayer[e.playerId] ?? 0) + e.points;
    }
    final updated = leaderboard.map((entry) {
      final pts = entry.selectedPlayerIds
          .fold(0, (sum, id) => sum + (pointsByPlayer[id] ?? 0));
      return entry.copyWith(totalPoints: pts);
    }).toList()
      ..sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
    leaderboard.assignAll(updated);
    if (myEntry.value != null) {
      final myPts = myEntry.value!.selectedPlayerIds
          .fold(0, (sum, id) => sum + (pointsByPlayer[id] ?? 0));
      myEntry.value = myEntry.value!.copyWith(totalPoints: myPts);
    }
  }

  // ── Mock match data ────────────────────────────────────────────

  static const List<MatchModel> _mockMatches = [
    MatchModel(
      matchId: 'lfc_mci',
      homeTeam: 'Liverpool',
      awayTeam: 'Man City',
      homeTeamBadge: 'assets/icons/england_liverpool.football-logos.svg',
      awayTeamBadge: 'assets/icons/england_manchester-city.football-logos.svg',
      league: 'Premier League',
      matchTime: '17:30',
      matchDate: 'Today',
      status: 'upcoming',
      roomCount: 4,
    ),
    MatchModel(
      matchId: 'bay_bvb',
      homeTeam: 'Bayern Munich',
      awayTeam: 'Borussia Dortmund',
      homeTeamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg',
      awayTeamBadge:
          'assets/icons/germany_borussia-dortmund.football-logos.svg',
      league: 'Bundesliga',
      matchTime: '18:30',
      matchDate: 'Today',
      status: 'live',
      roomCount: 7,
    ),
    MatchModel(
      matchId: 'rma_bar',
      homeTeam: 'Real Madrid',
      awayTeam: 'Barcelona',
      homeTeamBadge: 'assets/icons/real-madrid.football-logo.svg',
      awayTeamBadge: 'assets/icons/spain_barcelona.football-logo.svg',
      league: 'La Liga',
      matchTime: '21:00',
      matchDate: 'Yesterday',
      status: 'finished',
      roomCount: 0,
    ),
  ];

  List<FantasyFootballPlayer> _playersForMatch(String matchId) {
    switch (matchId) {
      case 'lfc_mci':
        return _liverpoolManCityPlayers;
      case 'bay_bvb':
        return _bayernDortmundPlayers;
      case 'rma_bar':
        return _realMadridBarcelonaPlayers;
      default:
        return [];
    }
  }

  List<FantasyMatchEvent> _eventsForMatch(String matchId) {
    switch (matchId) {
      case 'bay_bvb':
        return List<FantasyMatchEvent>.from(_bayernDortmundEvents);
      case 'rma_bar':
        return List<FantasyMatchEvent>.from(_realMadridBarcelonaEvents);
      default:
        return [];
    }
  }

  List<FantasyEntry> _mockLeaderboard(String matchId) {
    switch (matchId) {
      case 'lfc_mci':
        return [
          const FantasyEntry(userId: 'u1', displayName: 'Alex', avatarColor: Color(0xFF2979FF), selectedPlayerIds: ['lfc_1','lfc_2','lfc_3','lfc_5','lfc_6','lfc_8','lfc_9','lfc_10','mci_1','mci_9','mci_7']),
          const FantasyEntry(userId: 'u2', displayName: 'Jordan', avatarColor: Color(0xFFBF5AF2), selectedPlayerIds: ['lfc_1','lfc_3','lfc_4','lfc_6','lfc_7','lfc_8','lfc_9','mci_3','mci_6','mci_9','mci_11']),
          const FantasyEntry(userId: 'u3', displayName: 'Sam', avatarColor: Color(0xFF00FF88), selectedPlayerIds: ['lfc_1','lfc_2','lfc_3','lfc_8','lfc_9','mci_1','mci_5','mci_7','mci_9','mci_10','mci_11']),
          const FantasyEntry(userId: 'u4', displayName: 'Taylor', avatarColor: Color(0xFFFF2D78), selectedPlayerIds: ['lfc_1','lfc_3','lfc_5','lfc_6','lfc_8','lfc_10','mci_2','mci_3','mci_7','mci_9','mci_11']),
          const FantasyEntry(userId: 'u5', displayName: 'Morgan', avatarColor: Color(0xFFFF9800), selectedPlayerIds: ['lfc_1','lfc_2','lfc_3','lfc_4','lfc_8','mci_1','mci_6','mci_7','mci_9','mci_10','mci_11']),
        ];
      case 'bay_bvb':
        return [
          const FantasyEntry(userId: 'u1', displayName: 'Alex', avatarColor: Color(0xFF2979FF), selectedPlayerIds: ['bay_1','bay_2','bay_5','bay_6','bay_8','bay_9','bay_10','bvb_1','bvb_3','bvb_7','bvb_10']),
          const FantasyEntry(userId: 'u2', displayName: 'Jordan', avatarColor: Color(0xFFBF5AF2), selectedPlayerIds: ['bay_1','bay_3','bay_5','bay_6','bay_8','bay_10','bay_11','bvb_3','bvb_6','bvb_7','bvb_9']),
          const FantasyEntry(userId: 'u3', displayName: 'Sam', avatarColor: Color(0xFF00FF88), selectedPlayerIds: ['bay_1','bay_4','bay_5','bay_6','bay_8','bay_9','bay_10','bvb_4','bvb_7','bvb_9','bvb_11']),
          const FantasyEntry(userId: 'u4', displayName: 'Taylor', avatarColor: Color(0xFFFF2D78), selectedPlayerIds: ['bay_1','bay_2','bay_3','bay_6','bay_7','bay_8','bay_10','bvb_1','bvb_4','bvb_9','bvb_10']),
          const FantasyEntry(userId: 'u5', displayName: 'Morgan', avatarColor: Color(0xFFFF9800), selectedPlayerIds: ['bay_1','bay_2','bay_5','bay_8','bay_9','bay_10','bay_11','bvb_3','bvb_7','bvb_9','bvb_10']),
        ];
      case 'rma_bar':
        return [
          const FantasyEntry(userId: 'u1', displayName: 'Alex', avatarColor: Color(0xFF2979FF), selectedPlayerIds: ['rma_1','rma_2','rma_3','rma_6','rma_7','rma_9','rma_10','bar_1','bar_3','bar_8','bar_9']),
          const FantasyEntry(userId: 'u2', displayName: 'Jordan', avatarColor: Color(0xFFBF5AF2), selectedPlayerIds: ['rma_1','rma_3','rma_6','rma_7','rma_8','rma_9','rma_10','bar_1','bar_3','bar_8','bar_11']),
          const FantasyEntry(userId: 'u3', displayName: 'Sam', avatarColor: Color(0xFF00FF88), selectedPlayerIds: ['rma_1','rma_2','rma_3','rma_7','rma_9','rma_11','bar_1','bar_2','bar_3','bar_8','bar_9']),
          const FantasyEntry(userId: 'u4', displayName: 'Taylor', avatarColor: Color(0xFFFF2D78), selectedPlayerIds: ['rma_1','rma_3','rma_4','rma_7','rma_8','rma_9','rma_10','bar_3','bar_5','bar_8','bar_9']),
          const FantasyEntry(userId: 'u5', displayName: 'Morgan', avatarColor: Color(0xFFFF9800), selectedPlayerIds: ['rma_1','rma_2','rma_6','rma_7','rma_9','rma_10','rma_11','bar_1','bar_3','bar_8','bar_9']),
        ];
      default:
        return [];
    }
  }

  // ── Player rosters ─────────────────────────────────────────────

  static const List<FantasyFootballPlayer> _liverpoolManCityPlayers = [
    FantasyFootballPlayer(id: 'lfc_1', name: 'Alisson', position: 'GK', team: 'Liverpool', teamBadge: 'assets/icons/england_liverpool.football-logos.svg'),
    FantasyFootballPlayer(id: 'lfc_2', name: 'T. Alexander-Arnold', position: 'DEF', team: 'Liverpool', teamBadge: 'assets/icons/england_liverpool.football-logos.svg'),
    FantasyFootballPlayer(id: 'lfc_3', name: 'Van Dijk', position: 'DEF', team: 'Liverpool', teamBadge: 'assets/icons/england_liverpool.football-logos.svg'),
    FantasyFootballPlayer(id: 'lfc_4', name: 'Konaté', position: 'DEF', team: 'Liverpool', teamBadge: 'assets/icons/england_liverpool.football-logos.svg'),
    FantasyFootballPlayer(id: 'lfc_5', name: 'Robertson', position: 'DEF', team: 'Liverpool', teamBadge: 'assets/icons/england_liverpool.football-logos.svg'),
    FantasyFootballPlayer(id: 'lfc_6', name: 'Mac Allister', position: 'MID', team: 'Liverpool', teamBadge: 'assets/icons/england_liverpool.football-logos.svg'),
    FantasyFootballPlayer(id: 'lfc_7', name: 'Gravenberch', position: 'MID', team: 'Liverpool', teamBadge: 'assets/icons/england_liverpool.football-logos.svg'),
    FantasyFootballPlayer(id: 'lfc_8', name: 'Salah', position: 'MID', team: 'Liverpool', teamBadge: 'assets/icons/england_liverpool.football-logos.svg'),
    FantasyFootballPlayer(id: 'lfc_9', name: 'Luis Díaz', position: 'FWD', team: 'Liverpool', teamBadge: 'assets/icons/england_liverpool.football-logos.svg'),
    FantasyFootballPlayer(id: 'lfc_10', name: 'Darwin Núñez', position: 'FWD', team: 'Liverpool', teamBadge: 'assets/icons/england_liverpool.football-logos.svg'),
    FantasyFootballPlayer(id: 'lfc_11', name: 'Gakpo', position: 'FWD', team: 'Liverpool', teamBadge: 'assets/icons/england_liverpool.football-logos.svg'),
    FantasyFootballPlayer(id: 'mci_1', name: 'Ederson', position: 'GK', team: 'Man City', teamBadge: 'assets/icons/england_manchester-city.football-logos.svg'),
    FantasyFootballPlayer(id: 'mci_2', name: 'Walker', position: 'DEF', team: 'Man City', teamBadge: 'assets/icons/england_manchester-city.football-logos.svg'),
    FantasyFootballPlayer(id: 'mci_3', name: 'Rúben Dias', position: 'DEF', team: 'Man City', teamBadge: 'assets/icons/england_manchester-city.football-logos.svg'),
    FantasyFootballPlayer(id: 'mci_4', name: 'Akanji', position: 'DEF', team: 'Man City', teamBadge: 'assets/icons/england_manchester-city.football-logos.svg'),
    FantasyFootballPlayer(id: 'mci_5', name: 'Gvardiol', position: 'DEF', team: 'Man City', teamBadge: 'assets/icons/england_manchester-city.football-logos.svg'),
    FantasyFootballPlayer(id: 'mci_6', name: 'Rodri', position: 'MID', team: 'Man City', teamBadge: 'assets/icons/england_manchester-city.football-logos.svg'),
    FantasyFootballPlayer(id: 'mci_7', name: 'De Bruyne', position: 'MID', team: 'Man City', teamBadge: 'assets/icons/england_manchester-city.football-logos.svg'),
    FantasyFootballPlayer(id: 'mci_8', name: 'B. Silva', position: 'MID', team: 'Man City', teamBadge: 'assets/icons/england_manchester-city.football-logos.svg'),
    FantasyFootballPlayer(id: 'mci_9', name: 'Haaland', position: 'FWD', team: 'Man City', teamBadge: 'assets/icons/england_manchester-city.football-logos.svg'),
    FantasyFootballPlayer(id: 'mci_10', name: 'Doku', position: 'FWD', team: 'Man City', teamBadge: 'assets/icons/england_manchester-city.football-logos.svg'),
    FantasyFootballPlayer(id: 'mci_11', name: 'Foden', position: 'FWD', team: 'Man City', teamBadge: 'assets/icons/england_manchester-city.football-logos.svg'),
  ];

  static const List<FantasyFootballPlayer> _bayernDortmundPlayers = [
    FantasyFootballPlayer(id: 'bay_1', name: 'Neuer', position: 'GK', team: 'Bayern', teamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg'),
    FantasyFootballPlayer(id: 'bay_2', name: 'Mazraoui', position: 'DEF', team: 'Bayern', teamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg'),
    FantasyFootballPlayer(id: 'bay_3', name: 'Min-jae Kim', position: 'DEF', team: 'Bayern', teamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg'),
    FantasyFootballPlayer(id: 'bay_4', name: 'Upamecano', position: 'DEF', team: 'Bayern', teamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg'),
    FantasyFootballPlayer(id: 'bay_5', name: 'Davies', position: 'DEF', team: 'Bayern', teamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg'),
    FantasyFootballPlayer(id: 'bay_6', name: 'Kimmich', position: 'MID', team: 'Bayern', teamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg'),
    FantasyFootballPlayer(id: 'bay_7', name: 'Goretzka', position: 'MID', team: 'Bayern', teamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg'),
    FantasyFootballPlayer(id: 'bay_8', name: 'Musiala', position: 'MID', team: 'Bayern', teamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg'),
    FantasyFootballPlayer(id: 'bay_9', name: 'Sané', position: 'FWD', team: 'Bayern', teamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg'),
    FantasyFootballPlayer(id: 'bay_10', name: 'Kane', position: 'FWD', team: 'Bayern', teamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg'),
    FantasyFootballPlayer(id: 'bay_11', name: 'Coman', position: 'FWD', team: 'Bayern', teamBadge: 'assets/icons/germany_bayern-munchen.football-logo.svg'),
    FantasyFootballPlayer(id: 'bvb_1', name: 'Kobel', position: 'GK', team: 'Dortmund', teamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg'),
    FantasyFootballPlayer(id: 'bvb_2', name: 'Ryerson', position: 'DEF', team: 'Dortmund', teamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg'),
    FantasyFootballPlayer(id: 'bvb_3', name: 'Schlotterbeck', position: 'DEF', team: 'Dortmund', teamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg'),
    FantasyFootballPlayer(id: 'bvb_4', name: 'Hummels', position: 'DEF', team: 'Dortmund', teamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg'),
    FantasyFootballPlayer(id: 'bvb_5', name: 'Bensebaini', position: 'DEF', team: 'Dortmund', teamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg'),
    FantasyFootballPlayer(id: 'bvb_6', name: 'Emre Can', position: 'MID', team: 'Dortmund', teamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg'),
    FantasyFootballPlayer(id: 'bvb_7', name: 'Brandt', position: 'MID', team: 'Dortmund', teamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg'),
    FantasyFootballPlayer(id: 'bvb_8', name: 'Sabitzer', position: 'MID', team: 'Dortmund', teamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg'),
    FantasyFootballPlayer(id: 'bvb_9', name: 'Adeyemi', position: 'FWD', team: 'Dortmund', teamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg'),
    FantasyFootballPlayer(id: 'bvb_10', name: 'Füllkrug', position: 'FWD', team: 'Dortmund', teamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg'),
    FantasyFootballPlayer(id: 'bvb_11', name: 'Malen', position: 'FWD', team: 'Dortmund', teamBadge: 'assets/icons/germany_borussia-dortmund.football-logos.svg'),
  ];

  static const List<FantasyFootballPlayer> _realMadridBarcelonaPlayers = [
    FantasyFootballPlayer(id: 'rma_1', name: 'Courtois', position: 'GK', team: 'Real Madrid', teamBadge: 'assets/icons/real-madrid.football-logo.svg'),
    FantasyFootballPlayer(id: 'rma_2', name: 'Carvajal', position: 'DEF', team: 'Real Madrid', teamBadge: 'assets/icons/real-madrid.football-logo.svg'),
    FantasyFootballPlayer(id: 'rma_3', name: 'Militão', position: 'DEF', team: 'Real Madrid', teamBadge: 'assets/icons/real-madrid.football-logo.svg'),
    FantasyFootballPlayer(id: 'rma_4', name: 'Alaba', position: 'DEF', team: 'Real Madrid', teamBadge: 'assets/icons/real-madrid.football-logo.svg'),
    FantasyFootballPlayer(id: 'rma_5', name: 'Mendy', position: 'DEF', team: 'Real Madrid', teamBadge: 'assets/icons/real-madrid.football-logo.svg'),
    FantasyFootballPlayer(id: 'rma_6', name: 'Camavinga', position: 'MID', team: 'Real Madrid', teamBadge: 'assets/icons/real-madrid.football-logo.svg'),
    FantasyFootballPlayer(id: 'rma_7', name: 'Bellingham', position: 'MID', team: 'Real Madrid', teamBadge: 'assets/icons/real-madrid.football-logo.svg'),
    FantasyFootballPlayer(id: 'rma_8', name: 'Modric', position: 'MID', team: 'Real Madrid', teamBadge: 'assets/icons/real-madrid.football-logo.svg'),
    FantasyFootballPlayer(id: 'rma_9', name: 'Vinicius Jr', position: 'FWD', team: 'Real Madrid', teamBadge: 'assets/icons/real-madrid.football-logo.svg'),
    FantasyFootballPlayer(id: 'rma_10', name: 'Mbappé', position: 'FWD', team: 'Real Madrid', teamBadge: 'assets/icons/real-madrid.football-logo.svg'),
    FantasyFootballPlayer(id: 'rma_11', name: 'Rodrygo', position: 'FWD', team: 'Real Madrid', teamBadge: 'assets/icons/real-madrid.football-logo.svg'),
    FantasyFootballPlayer(id: 'bar_1', name: 'ter Stegen', position: 'GK', team: 'Barcelona', teamBadge: 'assets/icons/spain_barcelona.football-logo.svg'),
    FantasyFootballPlayer(id: 'bar_2', name: 'Koundé', position: 'DEF', team: 'Barcelona', teamBadge: 'assets/icons/spain_barcelona.football-logo.svg'),
    FantasyFootballPlayer(id: 'bar_3', name: 'Araujo', position: 'DEF', team: 'Barcelona', teamBadge: 'assets/icons/spain_barcelona.football-logo.svg'),
    FantasyFootballPlayer(id: 'bar_4', name: 'Christensen', position: 'DEF', team: 'Barcelona', teamBadge: 'assets/icons/spain_barcelona.football-logo.svg'),
    FantasyFootballPlayer(id: 'bar_5', name: 'Balde', position: 'DEF', team: 'Barcelona', teamBadge: 'assets/icons/spain_barcelona.football-logo.svg'),
    FantasyFootballPlayer(id: 'bar_6', name: 'Pedri', position: 'MID', team: 'Barcelona', teamBadge: 'assets/icons/spain_barcelona.football-logo.svg'),
    FantasyFootballPlayer(id: 'bar_7', name: 'Gavi', position: 'MID', team: 'Barcelona', teamBadge: 'assets/icons/spain_barcelona.football-logo.svg'),
    FantasyFootballPlayer(id: 'bar_8', name: 'De Jong', position: 'MID', team: 'Barcelona', teamBadge: 'assets/icons/spain_barcelona.football-logo.svg'),
    FantasyFootballPlayer(id: 'bar_9', name: 'Lewandowski', position: 'FWD', team: 'Barcelona', teamBadge: 'assets/icons/spain_barcelona.football-logo.svg'),
    FantasyFootballPlayer(id: 'bar_10', name: 'Yamal', position: 'FWD', team: 'Barcelona', teamBadge: 'assets/icons/spain_barcelona.football-logo.svg'),
    FantasyFootballPlayer(id: 'bar_11', name: 'Raphinha', position: 'FWD', team: 'Barcelona', teamBadge: 'assets/icons/spain_barcelona.football-logo.svg'),
  ];

  // ── Match events ───────────────────────────────────────────────

  // Bayern 3–2 Dortmund: fires one event every 4 s in live simulation
  static const List<FantasyMatchEvent> _bayernDortmundEvents = [
    FantasyMatchEvent(eventId: 'e1', playerId: 'bay_8', playerName: 'Musiala', team: 'Bayern', type: 'assist', minute: 14, points: 3),
    FantasyMatchEvent(eventId: 'e2', playerId: 'bay_10', playerName: 'Kane', team: 'Bayern', type: 'goal', minute: 14, points: 5),
    FantasyMatchEvent(eventId: 'e3', playerId: 'bvb_7', playerName: 'Brandt', team: 'Dortmund', type: 'assist', minute: 27, points: 3),
    FantasyMatchEvent(eventId: 'e4', playerId: 'bvb_10', playerName: 'Füllkrug', team: 'Dortmund', type: 'goal', minute: 27, points: 5),
    FantasyMatchEvent(eventId: 'e5', playerId: 'bvb_6', playerName: 'Emre Can', team: 'Dortmund', type: 'yellow_card', minute: 34, points: -1),
    FantasyMatchEvent(eventId: 'e6', playerId: 'bay_9', playerName: 'Sané', team: 'Bayern', type: 'assist', minute: 51, points: 3),
    FantasyMatchEvent(eventId: 'e7', playerId: 'bay_10', playerName: 'Kane', team: 'Bayern', type: 'goal', minute: 51, points: 5),
    FantasyMatchEvent(eventId: 'e8', playerId: 'bvb_3', playerName: 'Schlotterbeck', team: 'Dortmund', type: 'yellow_card', minute: 66, points: -1),
    FantasyMatchEvent(eventId: 'e9', playerId: 'bay_5', playerName: 'Davies', team: 'Bayern', type: 'assist', minute: 77, points: 3),
    FantasyMatchEvent(eventId: 'e10', playerId: 'bay_8', playerName: 'Musiala', team: 'Bayern', type: 'goal', minute: 77, points: 5),
    FantasyMatchEvent(eventId: 'e11', playerId: 'bvb_9', playerName: 'Adeyemi', team: 'Dortmund', type: 'goal', minute: 84, points: 5),
    FantasyMatchEvent(eventId: 'e12', playerId: 'bay_6', playerName: 'Kimmich', team: 'Bayern', type: 'yellow_card', minute: 89, points: -1),
  ];

  // Real Madrid 2–1 Barcelona: pre-loaded since match is finished
  static const List<FantasyMatchEvent> _realMadridBarcelonaEvents = [
    FantasyMatchEvent(eventId: 'f1', playerId: 'rma_9', playerName: 'Vinicius Jr', team: 'Real Madrid', type: 'goal', minute: 22, points: 5),
    FantasyMatchEvent(eventId: 'f2', playerId: 'rma_7', playerName: 'Bellingham', team: 'Real Madrid', type: 'assist', minute: 22, points: 3),
    FantasyMatchEvent(eventId: 'f3', playerId: 'bar_9', playerName: 'Lewandowski', team: 'Barcelona', type: 'goal', minute: 45, points: 5),
    FantasyMatchEvent(eventId: 'f4', playerId: 'bar_8', playerName: 'De Jong', team: 'Barcelona', type: 'assist', minute: 45, points: 3),
    FantasyMatchEvent(eventId: 'f5', playerId: 'bar_7', playerName: 'Gavi', team: 'Barcelona', type: 'yellow_card', minute: 58, points: -1),
    FantasyMatchEvent(eventId: 'f6', playerId: 'rma_10', playerName: 'Mbappé', team: 'Real Madrid', type: 'goal', minute: 73, points: 5),
    FantasyMatchEvent(eventId: 'f7', playerId: 'rma_7', playerName: 'Bellingham', team: 'Real Madrid', type: 'assist', minute: 73, points: 3),
    FantasyMatchEvent(eventId: 'f8', playerId: 'bar_3', playerName: 'Araujo', team: 'Barcelona', type: 'red_card', minute: 81, points: -2),
  ];
}
