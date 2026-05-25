# Live Prediction Arena — Kiro Spec: Arena Module

## Scope

This spec covers the complete `modules/arena/` module — five screens, one controller, all widgets. The home screen is already built. This module activates when the user taps the Arena card.

---

## Arena Screen Flow

```
ArenaLobbyView          ← user creates or joins a squad room
      ↓
ArenaWaitingView        ← lobby: waiting for all players to join
      ↓
ArenaMatchView          ← live match screen (leaderboard + match events)
      ↓  (event fires)
ArenaPredictionView     ← 20-second prediction round overlay
      ↓  (round closes)
ArenaRoundResultView    ← result reveal + XP awarded (overlay)
      ↓  (match ends)
ArenaEndView            ← final ceremony: podium + badges + share
```

Navigation between `ArenaMatchView`, `ArenaPredictionView`, and `ArenaRoundResultView` uses **overlay stacking inside the same route** (not `Get.toNamed`), controlled by `ArenaController` state. The other transitions use `Get.toNamed`.

---

## Module Structure

```
modules/arena/
├── arena_lobby_view.dart
├── arena_waiting_view.dart
├── arena_match_view.dart        ← hosts prediction + result overlays
├── arena_end_view.dart
├── controllers/
│   ├── arena_controller.dart
│   └── arena_binding.dart
└── widgets/
    ├── squad_avatar_widget.dart
    ├── room_code_widget.dart
    ├── match_scoreboard_widget.dart
    ├── leaderboard_strip_widget.dart
    ├── prediction_card_widget.dart
    ├── countdown_timer_widget.dart
    ├── rival_lockin_row_widget.dart
    ├── round_result_overlay_widget.dart
    ├── xp_burst_widget.dart
    ├── badge_award_widget.dart
    └── podium_widget.dart
```

---

## Models — add to `models/`

### `squad_model.dart`
```dart
class SquadModel {
  final String roomCode;
  final String hostUserId;
  final List<PlayerModel> members;   // max 6
  final SquadStatus status;          // waiting | live | ended
}

enum SquadStatus { waiting, live, ended }
```

### `player_model.dart`
```dart
class PlayerModel {
  final String userId;
  final String displayName;
  final Color avatarColor;
  final int totalXP;
  final int streak;              // current consecutive correct answers
  final List<String> badges;     // badge ids earned this match
  final bool isHost;
  final bool isConnected;
}
```

### `match_event_model.dart`
```dart
class MatchEventModel {
  final String eventId;
  final MatchEventType type;
  final int minute;
  final String? teamName;
  final String? playerName;
  final String? detail;
}

enum MatchEventType { goal, yellowCard, redCard, substitution, halftime, matchEnd, possession }
```

### `prediction_round_model.dart`
```dart
class PredictionRoundModel {
  final String roundId;
  final String questionText;
  final List<String> options;        // 2–4 answer options
  final int timeLimitSeconds;        // always 20
  final MatchEventType triggerEvent;
  final String? correctAnswer;       // null until round closes
  final DateTime expiresAt;
}
```

### `player_pick_model.dart`
```dart
class PlayerPickModel {
  final String userId;
  final String? pick;           // null = not answered yet
  final bool hasLocked;
  final int? secondsTaken;
  final int? pointsAwarded;
  final bool? isCorrect;
}
```

---

## Arena Controller — `controllers/arena_controller.dart`

```dart
enum ArenaScreen { lobby, waiting, match, prediction, roundResult, end }

class ArenaController extends GetxController {

  // ── Screen state ──────────────────────────────────────────────
  final Rx<ArenaScreen> currentScreen = ArenaScreen.lobby.obs;

  // ── Squad ─────────────────────────────────────────────────────
  final Rx<SquadModel?> squad       = Rx(null);
  final RxString roomCodeInput      = ''.obs;
  final RxBool isCreatingRoom       = false.obs;
  final RxBool isJoiningRoom        = false.obs;
  final RxString errorMessage       = ''.obs;

  // ── Match ─────────────────────────────────────────────────────
  final RxInt homeScore             = 0.obs;
  final RxInt awayScore             = 0.obs;
  final RxInt matchMinute           = 0.obs;
  final RxString homeTeam           = 'BVB'.obs;
  final RxString awayTeam           = 'FCB'.obs;
  final RxList<MatchEventModel> eventLog = <MatchEventModel>[].obs;

  // ── Prediction round ──────────────────────────────────────────
  final Rx<PredictionRoundModel?> activeRound   = Rx(null);
  final RxList<PlayerPickModel> roundPicks       = <PlayerPickModel>[].obs;
  final RxInt countdownSeconds                   = 20.obs;
  final RxString? myPick                         = RxString('');
  final RxBool hasLockedIn                       = false.obs;

  // ── Leaderboard ───────────────────────────────────────────────
  final RxList<PlayerModel> leaderboard          = <PlayerModel>[].obs;

  // ── Round result ──────────────────────────────────────────────
  final RxInt xpEarnedThisRound                  = 0.obs;
  final RxBool wasCorrect                        = false.obs;
  final RxBool speedBonusEarned                  = false.obs;
  final RxInt newStreak                          = 0.obs;

  // ── End of match ──────────────────────────────────────────────
  final RxList<String> earnedBadges              = <String>[].obs;

  // ── Timers ────────────────────────────────────────────────────
  Timer? _countdownTimer;
  Timer? _matchEmitterTimer;

  // ── Methods ───────────────────────────────────────────────────

  // Lobby
  Future<void> createRoom() async { ... }   // POST /squads, get roomCode
  Future<void> joinRoom(String code) async { ... }  // POST /squads/{code}/join

  // Match emitter (replay DFL XML for demo)
  void startMatchEmitter() { ... }          // fires mock events on timer
  void _handleMatchEvent(MatchEventModel event) { ... }  // routes event to prediction

  // Prediction
  void openPredictionRound(PredictionRoundModel round) {
    activeRound.value = round;
    hasLockedIn.value = false;
    myPick.value = '';
    countdownSeconds.value = 20;
    currentScreen.value = ArenaScreen.prediction;
    _startCountdown();
  }

  void lockInPick(String option) {
    if (hasLockedIn.value) return;
    myPick.value = option;
    hasLockedIn.value = true;
    // POST pick to API
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (countdownSeconds.value <= 0) {
        t.cancel();
        _closeRound();
      } else {
        countdownSeconds.value--;
      }
    });
  }

  void _closeRound() {
    // Resolve correct answer, calculate XP, update leaderboard
    currentScreen.value = ArenaScreen.roundResult;
    Future.delayed(const Duration(seconds: 4), () {
      currentScreen.value = ArenaScreen.match;
    });
  }

  void endMatch() {
    currentScreen.value = ArenaScreen.end;
  }

  @override
  void onClose() {
    _countdownTimer?.cancel();
    _matchEmitterTimer?.cancel();
    super.onClose();
  }
}
```

### `controllers/arena_binding.dart`
```dart
class ArenaBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ArenaController>(() => ArenaController());
  }
}
```

---

## Screen 1 — `arena_lobby_view.dart`

**Purpose:** User chooses to create a new room or join an existing one with a code.

### Visual layout (top to bottom):
```
SafeArea
└── Column
    ├── Back arrow (top-left)
    ├── SizedBox(height: 32)
    ├── Text 'ARENA MODE' (12px, letterSpacing 4, textMuted)
    ├── Text 'Join the Squad' (32px bold white)
    ├── SizedBox(height: 8)
    ├── Text 'Create a room or enter a code to join your friends'
    │       (14px textSecondary, centered)
    ├── SizedBox(height: 48)
    │
    ├── ── CREATE ROOM CARD ──────────────────────────────────────
    │   GlassmorphismCard (accent: arenaAccent)
    │   └── Column
    │       ├── Icon: shield/lightning (48px, arenaAccent)
    │       ├── Text 'Create Room' (20px bold white)
    │       ├── Text 'Start a new squad. Share the code.' (13px muted)
    │       └── ElevatedButton 'CREATE ROOM'
    │             style: filled arenaAccent, full width, height 52,
    │             borderRadius 14, onPressed: controller.createRoom()
    │
    ├── SizedBox(height: 20)
    │
    ├── Row: [Divider] [Text 'or join with code'] [Divider]  ← textMuted 12px
    │
    ├── SizedBox(height: 20)
    │
    ├── ── JOIN ROOM ────────────────────────────────────────────
    │   RoomCodeInputWidget (6-char code input, see widget spec below)
    │
    ├── SizedBox(height: 16)
    ├── ElevatedButton 'JOIN ROOM'
    │     style: outlined arenaAccent border, full width, height 52
    │     enabled only when roomCodeInput.length == 6
    │     onPressed: controller.joinRoom(controller.roomCodeInput.value)
    │
    └── Obx: error message text in AppColors.error (12px) if errorMessage != ''
```

### Animations:
- Cards and inputs **slide up from +60px + fade in** on view mount using `flutter_animate`:
  ```dart
  widget.animate().slideY(begin: 0.3, duration: 500.ms, curve: Curves.easeOutCubic).fadeIn()
  ```
- CREATE ROOM button has a **shimmer sweep** on the button surface (looping, subtle)
- Loading spinner replaces button text during `isCreatingRoom` / `isJoiningRoom`

---

## Screen 2 — `arena_waiting_view.dart`

**Purpose:** Squad lobby — shows who has joined, waiting for host to start.

### Visual layout:
```
SafeArea
└── Column
    ├── Text 'SQUAD LOBBY' (12px, letterSpacing 4, textMuted)
    ├── SizedBox(height: 8)
    ├── RoomCodeWidget(code: squad.roomCode)    ← large shareable code display
    ├── Text 'Share this code with your friends' (12px textMuted)
    ├── SizedBox(height: 40)
    ├── Text 'PLAYERS (n/6)' (11px, bold, textMuted)
    ├── SizedBox(height: 16)
    ├── GridView 2×3: SquadAvatarWidget for each slot (filled or empty)
    ├── SizedBox(height: 40)
    ├── Obx: if isHost → 'START MATCH' button (arenaAccent, full width)
    │         else → pulsing Text 'Waiting for host to start...'
    └── SizedBox(height: 24)
```

### `widgets/room_code_widget.dart` spec:
```
Container
└── Row(mainAxisAlignment: center)
    └── [each character of roomCode as individual styled letter]
        Each letter:
          Container(
            width: 44, height: 52,
            margin: EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.arenaAccent.withOpacity(0.5), width: 1.5),
            ),
            child: Center(child: Text(char, style: 28px bold white, letterSpacing: 2))
          )
```

### `widgets/squad_avatar_widget.dart` spec:
```
// Filled slot:
Column
├── Container(
│     width: 64, height: 64,
│     decoration: BoxDecoration(
│       shape: BoxShape.circle,
│       color: player.avatarColor,
│       border: Border.all(color: arenaAccent, width: 2),
│       boxShadow: [BoxShadow(color: arenaAccent.withOpacity(0.3), blurRadius: 8)]
│     ),
│     child: Center(child: Text(initials, style: 22px bold white))
│   )
└── Text(player.displayName, 11px textSecondary)

// Empty slot:
Column
├── Container(
│     width: 64, height: 64,
│     decoration: BoxDecoration(
│       shape: BoxShape.circle,
│       color: AppColors.cardSurface,
│       border: Border.all(color: AppColors.cardBorder, width: 1.5, style: BorderStyle.dashed... 
│               // use DashedBorder or simulate with CustomPainter)
│     ),
│     child: Icon(Icons.add, color: AppColors.textMuted, size: 24)
│   )
└── Text('Empty', 11px textMuted)
```

### Animations:
- When a new player joins, their avatar slot **pops in** with a scale 0→1 spring animation (`elasticOut`, 600ms)
- 'Waiting for host' text **pulses opacity** 1.0↔0.4 on a 1200ms loop
- START MATCH button: **ripple glow** on the border (animated border opacity 0.4→1.0→0.4 loop)

---

## Screen 3 — `arena_match_view.dart`

**Purpose:** The main live match screen. Hosts all three states: match idle, prediction round, and round result (as overlays).

### Visual layout:
```
Scaffold
└── Stack
    ├── BackgroundWidget (same as home, reused from shared/widgets)
    │
    ├── SafeArea
    │   └── Column
    │       ├── MatchScoreboardWidget
    │       ├── SizedBox(height: 16)
    │       ├── Expanded: LeaderboardStripWidget
    │       └── SizedBox(height: 16)
    │
    ├── Obx: if currentScreen == prediction
    │         → PredictionCardWidget (full-screen animated overlay)
    │
    └── Obx: if currentScreen == roundResult
              → RoundResultOverlayWidget (full-screen animated overlay)
```

### `widgets/match_scoreboard_widget.dart` spec:
```
Container(
  margin: EdgeInsets.all(16),
  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  decoration: BoxDecoration(
    color: AppColors.cardSurface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: AppColors.cardBorder, width: 1),
  ),
  child: Row(mainAxisAlignment: spaceBetween)
    ├── Column: [Text(homeTeam, 13px bold white), Text('HOME', 10px muted)]
    ├── Column:
    │   ├── Row: [Text(homeScore, 36px bold white), Text(' – ', 24px muted), Text(awayScore, 36px bold white)]
    │   └── Row: [Icon(circle, 8px green), SizedBox(4), Text('LIVE · {minute}\'', 11px success bold)]
    └── Column: [Text(awayTeam, 13px bold white), Text('AWAY', 10px muted)]
)
```

Score animation: when score changes, the updated number plays a **CountUp animation** (scale 1.0→1.4→1.0 with color flash to `AppColors.success`, 400ms).

### `widgets/leaderboard_strip_widget.dart` spec:
```
Column
├── Text('SQUAD LEADERBOARD', 11px bold textMuted, letterSpacing 2)
├── SizedBox(height: 12)
└── ListView (non-scrollable, shows all members sorted by totalXP desc)
    └── each item: AnimatedContainer (slides/fades on rank change)
        └── Row
            ├── Container(24×24, circle, rank background color):
            │   Text(rank, 12px bold)            ← gold/silver/bronze/grey
            ├── SizedBox(8)
            ├── Container(36×36, circle, avatarColor): Text(initials)
            ├── SizedBox(8)
            ├── Expanded: Text(displayName, 14px white)
            ├── if streak >= 3: Text('🔥 {streak}', 12px warning)
            ├── SizedBox(8)
            └── Text('{totalXP} XP', 14px bold arenaAccent)
```

Leaderboard animation: when XP values change (after a round), rows **animate to new positions** using `AnimatedList` or `implicitly_animated_list`. Each row's XP value counts up with a `TweenAnimationBuilder`.

---

## Screen 4 — Prediction Round (overlay inside `arena_match_view.dart`)

### `widgets/prediction_card_widget.dart` spec:

**Entrance animation:** slides up from bottom of screen (y: +100% → 0) with `easeOutCubic` over 400ms. Simultaneously dims the match screen behind it with a `BackdropFilter` blur (sigma 4→8).

```
// Full-screen overlay
Container(color: Colors.black.withOpacity(0.7))
└── BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6))
    └── SafeArea
        └── Column(mainAxisAlignment: end)   ← card rises from bottom
            └── Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(top: BorderSide(color: arenaAccent, width: 2)),
                    boxShadow: [BoxShadow(color: arenaAccent.withOpacity(0.3), blurRadius: 32, offset: Offset(0, -8))]
                  )
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 40)
                )
                └── Column
                    ├── // Event badge pill
                    │   Container(
                    │     padding: symmetric(h:14, v:6),
                    │     decoration: BoxDecoration(
                    │       gradient: LinearGradient([arenaAccent.withOpacity(0.3), arenaAccent.withOpacity(0.1)]),
                    │       borderRadius: circular(20),
                    │       border: Border.all(arenaAccent.withOpacity(0.6))
                    │     ),
                    │     child: Row [Icon(event icon, 16px), SizedBox(6), Text('GOAL · 54\'', 12px bold arenaAccent)]
                    │   )
                    │
                    ├── SizedBox(height: 20)
                    │
                    ├── // Question
                    │   Text(round.questionText, 22px bold white, textAlign: center)
                    │
                    ├── SizedBox(height: 8)
                    │
                    ├── // Countdown timer
                    │   CountdownTimerWidget(seconds: countdownSeconds)
                    │
                    ├── SizedBox(height: 24)
                    │
                    ├── // Answer options
                    │   Column: round.options.map((opt) =>
                    │     Padding(bottom: 12,
                    │       child: AnswerOptionButton(
                    │         label: opt,
                    │         isSelected: myPick == opt,
                    │         isLocked: hasLockedIn,
                    │         onTap: () => controller.lockInPick(opt)
                    │       )
                    │     )
                    │   )
                    │
                    └── SizedBox(height: 16)
                    └── RivalLockInRowWidget(picks: roundPicks)
```

### `widgets/countdown_timer_widget.dart` spec:
```
Stack(alignment: center)
├── SizedBox(80×80)
│   CustomPaint: arc timer
│     - Background circle: AppColors.cardBorder, strokeWidth 6
│     - Foreground arc: arenaAccent, strokeWidth 6
│       sweepAngle = 2π × (seconds / 20)
│       Color transitions: arenaAccent → warning → error as seconds decrease
│       (green >10s, amber 5–10s, red <5s)
└── Column(center)
    ├── Text(seconds, 28px bold white)
    └── Text('SEC', 9px textMuted)

// Animation: CustomPainter repaints on every second tick
// When seconds <= 5: Text color shifts to AppColors.error + slight scale pulse (1.0→1.1→1.0)
```

### `AnswerOptionButton` spec:
```dart
// Unselected state:
AnimatedContainer(
  duration: 200ms,
  height: 56,
  decoration: BoxDecoration(
    color: AppColors.cardSurface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: AppColors.cardBorder, width: 1.5),
  ),
  child: Center(child: Text(label, 15px bold white))
)

// Selected (locked in) state:
AnimatedContainer(
  decoration: BoxDecoration(
    color: arenaAccent.withOpacity(0.2),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: arenaAccent, width: 2),
    boxShadow: [BoxShadow(color: arenaAccent.withOpacity(0.4), blurRadius: 12)]
  ),
  child: Row(center) [
    Icon(Icons.lock, 14px arenaAccent),
    SizedBox(6),
    Text(label, 15px bold arenaAccent)
  ]
)

// Disabled (another option locked): opacity 0.4
// On tap: scale 0.97 → 1.0 spring, 150ms
```

### `widgets/rival_lockin_row_widget.dart` spec:
```
Column
├── Text('SQUAD', 10px bold textMuted, letterSpacing 2)
├── SizedBox(6)
└── Row(mainAxisAlignment: center)
    └── for each player in squad:
        Padding(horizontal: 6)
        └── Column
            ├── Stack
            │   ├── Container(32×32 circle, player.avatarColor)
            │   │   Text(initials, 11px bold white)
            │   └── if hasLocked: Positioned(bottom:0, right:0)
            │         Container(12×12 circle, arenaAccent)
            │         Icon(Icons.lock, 8px white)
            └── SizedBox(4)
            └── // No text — keep it compact
```

---

## Screen 5 — Round Result (overlay inside `arena_match_view.dart`)

### `widgets/round_result_overlay_widget.dart` spec:

**Entrance:** scales in from 0.8→1.0 + fades in, center of screen, 350ms `easeOutBack`. Behind it: blurred match screen.

```
// Centered modal card
Center
└── Container(
      width: screenWidth - 48,
      padding: EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: resultBorderColor, width: 2),
        // resultBorderColor: success if correct, error if wrong
        boxShadow: [BoxShadow(color: resultBorderColor.withOpacity(0.4), blurRadius: 32)]
      )
    )
    └── Column
        ├── // Result icon — animates in with bounce
        │   XpBurstWidget(isCorrect: wasCorrect)
        │
        ├── SizedBox(16)
        │
        ├── Text(wasCorrect ? '✓ Correct!' : '✗ Wrong', 24px bold, resultColor)
        │
        ├── SizedBox(8)
        │
        ├── Text('Correct answer: {correctAnswer}', 14px textSecondary)
        │
        ├── SizedBox(20)
        │
        ├── // XP earned — counts up from 0
        │   TweenAnimationBuilder<int>(
        │     tween: IntTween(begin: 0, end: xpEarnedThisRound),
        │     duration: 800ms,
        │     builder: (_, val, __) => Text('+$val XP', 36px bold arenaAccent)
        │   )
        │
        ├── SizedBox(8)
        │
        ├── // Bonuses row
        │   Row(center, spacing: 12) [
        │     if speedBonusEarned: _BonusChip('⚡ Speed Bonus +5'),
        │     if newStreak >= 3:   _BonusChip('🔥 ${newStreak}× Streak'),
        │   ]
        │
        ├── SizedBox(24)
        │
        └── // Mini leaderboard (top 3 only)
            Column: leaderboard.take(3).map((p) => leaderboard row)
```

### `widgets/xp_burst_widget.dart` spec:
```dart
// Correct: large ✓ icon in a circle
// - Circle scales 0→1.2→1.0 with elasticOut, 600ms
// - 8 particle lines burst outward from center (CustomPainter)
//   each line: 2px wide, arenaAccent color, length 20px, fades out over 500ms
// - Circle fill: success green radial gradient

// Wrong: large ✗ icon
// - Shake animation: translate x: 0 → -8 → 8 → -4 → 4 → 0, 400ms
// - Circle fill: error red
```

---

## Screen 6 — `arena_end_view.dart`

**Purpose:** Final ceremony. Celebrates the winner, awards badges, allows sharing.

### Visual layout:
```
Scaffold
└── Stack
    ├── BackgroundWidget
    └── SafeArea
        └── SingleChildScrollView
            └── Column
                ├── SizedBox(height: 24)
                ├── Text 'MATCH OVER' (11px letterSpacing 4 textMuted)
                ├── Text 'Final Standings' (28px bold white)
                ├── SizedBox(height: 32)
                │
                ├── PodiumWidget(leaderboard: leaderboard)
                │
                ├── SizedBox(height: 32)
                │
                ├── // Full leaderboard
                │   Text('FULL SQUAD RESULTS', 11px bold textMuted)
                │   SizedBox(12)
                │   Column: all players ranked with XP
                │
                ├── SizedBox(height: 32)
                │
                ├── // Badge shelf
                │   Text('BADGES EARNED', 11px bold textMuted)
                │   SizedBox(12)
                │   BadgeAwardWidget(earnedBadges: earnedBadges)
                │
                ├── SizedBox(height: 40)
                │
                ├── // Share button
                │   ElevatedButton.icon(
                │     icon: Icon(Icons.share),
                │     label: Text('SHARE RESULT'),
                │     style: gradient button (arenaAccent → electricBlueGlow),
                │            full width, height 56, borderRadius 16
                │     onPressed: _shareResult
                │   )
                │
                ├── SizedBox(height: 12)
                │
                └── TextButton('Back to Home', onPressed: Get.offAllNamed(AppRoutes.home))
```

### `widgets/podium_widget.dart` spec:
```
// Three-column podium layout
Row(mainAxisAlignment: center, crossAxisAlignment: end)
├── _PodiumColumn(rank: 2, player: leaderboard[1], height: 80,  color: Color(0xFF9CA3AF))  // silver
├── _PodiumColumn(rank: 1, player: leaderboard[0], height: 110, color: Color(0xFFF59E0B))  // gold
└── _PodiumColumn(rank: 3, player: leaderboard[2], height: 60,  color: Color(0xFFB45309))  // bronze

// Each _PodiumColumn:
Column(mainAxisAlignment: end)
├── // Crown icon above 1st place only (animated spin-in)
├── SquadAvatarWidget(player, size: 52)
├── Text(player.displayName, 11px white)
├── Text('{xp} XP', 12px bold accentColor)
└── Container(
      width: 80, height: columnHeight,
      decoration: BoxDecoration(
        color: rankColor.withOpacity(0.3),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        border: Border.all(color: rankColor, width: 1.5)
      ),
      child: Center(child: Text('#{rank}', 20px bold rankColor))
    )
```

### `widgets/badge_award_widget.dart` spec:
```
// All possible badges: Oracle, Red Mist, Iron Wall, Speed Demon, Hat-trick Hero
// Each badge is a 72×72 card

Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center)
└── for each badge in allBadges:
    _BadgeCard(
      badgeId: badge.id,
      isEarned: earnedBadges.contains(badge.id),
    )

// Earned badge card:
Container(
  width: 72, height: 84,
  decoration: BoxDecoration(
    color: AppColors.cardSurface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: arenaAccent, width: 1.5),
    boxShadow: [BoxShadow(color: arenaAccent.withOpacity(0.3), blurRadius: 12)]
  ),
  child: Column [Icon(48px, arenaAccent), Text(badge.name, 9px white, center)]
)

// Unearned: same but grayscale filter + opacity 0.35
// Earned badge entrance: scale 0→1 with elasticOut, staggered by 200ms per badge
```

### End screen entrance animations:
- Podium columns **rise from bottom** one at a time (3rd → 2nd → 1st), each 300ms apart, `easeOutCubic`
- 1st place avatar: **confetti burst** using a simple CustomPainter (20 colored rectangles scatter from avatar center)
- Badges: stagger scale-in with `elasticOut`, 200ms delay per badge
- Share button: pulsing glow border (opacity loop 0.4→1.0→0.4, 1500ms)

---

## Route Registration — update `app/routes/app_pages.dart`

```dart
GetPage(
  name: AppRoutes.arenaLobby,
  page: () => const ArenaLobbyView(),
  binding: ArenaBinding(),
  transition: Transition.rightToLeft,
  transitionDuration: const Duration(milliseconds: 350),
),
GetPage(
  name: AppRoutes.arenaWaiting,
  page: () => const ArenaWaitingView(),
  binding: ArenaBinding(),
  transition: Transition.rightToLeft,
  transitionDuration: const Duration(milliseconds: 350),
),
GetPage(
  name: AppRoutes.arenaMatch,
  page: () => const ArenaMatchView(),
  binding: ArenaBinding(),
  transition: Transition.fadeIn,
  transitionDuration: const Duration(milliseconds: 400),
),
GetPage(
  name: AppRoutes.arenaEnd,
  page: () => const ArenaEndView(),
  binding: ArenaBinding(),
  transition: Transition.fadeIn,
  transitionDuration: const Duration(milliseconds: 400),
),
```

Add to `app_routes.dart`:
```dart
static const arenaWaiting = '/arena/waiting';
static const arenaMatch   = '/arena/match';
static const arenaEnd     = '/arena/end';
```

---

## Animation Master Table — Arena Module

| Screen | Element | Animation | Duration | Curve |
|---|---|---|---|---|
| Lobby | Cards entrance | Slide up + fade in | 500ms | `easeOutCubic` |
| Lobby | Create button | Shimmer sweep loop | 2000ms | `linear` |
| Waiting | New player join | Scale 0→1 pop | 600ms | `elasticOut` |
| Waiting | Waiting text | Opacity pulse 1↔0.4 | 1200ms | `easeInOut` loop |
| Waiting | Start button | Border glow pulse | 1500ms | `easeInOut` loop |
| Match | Score update | Scale flash 1→1.4→1 + color | 400ms | `easeOut` |
| Match | Leaderboard reorder | Row slide to new rank | 600ms | `easeInOut` |
| Match | XP count-up | IntTween 0→value | 800ms | `easeOut` |
| Prediction card | Entrance | Slide up from bottom | 400ms | `easeOutCubic` |
| Prediction card | Backdrop blur | Sigma 0→6 | 300ms | `easeOut` |
| Answer button | Tap press | Scale 1→0.97→1 | 150ms | `easeIn` |
| Answer button | Lock-in | Border + fill animate | 200ms | `easeOut` |
| Countdown arc | Tick | Sweep angle decrease | 1000ms | `linear` |
| Countdown arc | Danger (<5s) | Scale pulse + color red | 500ms | `easeInOut` loop |
| Round result | Entrance | Scale 0.8→1 + fade | 350ms | `easeOutBack` |
| XP burst (correct) | Circle pop | Scale 0→1.2→1 | 600ms | `elasticOut` |
| XP burst (correct) | Particles | Burst outward + fade | 500ms | `easeOut` |
| XP burst (wrong) | Shake | Translate x ±8px | 400ms | `linear` |
| End screen | Podium rise | Slide up staggered | 300ms each | `easeOutCubic` |
| End screen | Confetti | Scatter from center | 1200ms | `easeOut` |
| End screen | Badges | Scale 0→1 staggered | 600ms each | `elasticOut` |
| End screen | Share button | Border glow pulse | 1500ms | `easeInOut` loop |

---

## Kiro Build Order — Arena Module

1. **Models** — add `squad_model.dart`, `player_model.dart`, `match_event_model.dart`, `prediction_round_model.dart`, `player_pick_model.dart` to `models/`.
2. **Routes** — add arena route constants and `GetPage` entries.
3. **Controller + Binding** — `arena_controller.dart` and `arena_binding.dart` with all observable state and stub method bodies.
4. **Lobby screen** — `arena_lobby_view.dart` with `RoomCodeInputWidget` (the 6-box input).
5. **Waiting screen** — `arena_waiting_view.dart` with `RoomCodeWidget` and `SquadAvatarWidget`.
6. **Scoreboard + Leaderboard widgets** — `match_scoreboard_widget.dart` and `leaderboard_strip_widget.dart`.
7. **Match view shell** — `arena_match_view.dart` with Stack structure and Obx overlay switching.
8. **Countdown timer** — `countdown_timer_widget.dart` with `CustomPainter` arc.
9. **Rival lock-in row** — `rival_lockin_row_widget.dart`.
10. **Prediction card** — `prediction_card_widget.dart` with `AnswerOptionButton` and all sub-widgets.
11. **XP burst** — `xp_burst_widget.dart` with particle CustomPainter.
12. **Round result overlay** — `round_result_overlay_widget.dart`.
13. **Podium + badge widgets** — `podium_widget.dart` and `badge_award_widget.dart`.
14. **End view** — `arena_end_view.dart` composing all end-screen widgets.
15. **Wire mock match emitter** — implement `startMatchEmitter()` in controller with a hardcoded sequence of `MatchEventModel` events firing every 8–15 seconds for demo purposes.
16. **Verify full flow** — Lobby → Waiting (2 users) → Match → Prediction round fires → Result overlay → Back to match → Second round → Match end → End ceremony → Share → Home.

---

## Kiro Rules (carry over from home spec)

- No hardcoded colors — `AppColors.*` only
- No `setState` — all state is `Rx` + `Obx`
- No `Navigator.push` — `Get.toNamed` only
- `PredictionCardWidget` and `RoundResultOverlayWidget` are overlays rendered inside `ArenaMatchView`'s Stack — they are NOT separate routes
- `RepaintBoundary` wraps every `CustomPainter` widget (countdown arc, XP burst particles, confetti)
- `ArenaBinding` uses `Get.lazyPut` — controller is shared across all arena routes via `Get.find<ArenaController>()`
- All `AnimationController` instances owned by widgets (not the GetX controller) must be disposed in that widget's `dispose()`
