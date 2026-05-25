# Implementation Plan: Arena Module

## Overview

This plan implements the Arena multiplayer prediction game module — four views, one controller, and twelve specialized widgets. The build order follows a bottom-up approach: data models first, then routes, controller, and finally views/widgets in dependency order. Each task is self-contained and references specific requirements from the requirements document.

## Tasks

- [x] 1. Data models
  - [x] 1.1 Create lib/models/squad_model.dart
    Create the `SquadModel` class with fields: `roomCode` (String), `hostUserId` (String), `matchTitle` (String), `isPrivate` (bool), `members` (List<PlayerModel>), `status` (String), `totalRounds` (int). Include a const constructor with named required parameters, `fromJson` factory, and `toJson` method. Import `PlayerModel`. Status values: 'waiting', 'playing', 'finished'. Members list max 6.
    _Requirements: 1.1, 1.5, 1.6_

  - [x] 1.2 Create lib/models/player_model.dart
    Create the `PlayerModel` class with fields: `userId` (String), `displayName` (String), `avatarColor` (Color), `totalXP` (int, default 0), `streak` (int, default 0), `badges` (List<String>, default const []), `isHost` (bool, default false), `isConnected` (bool, default true). Include const constructor, `fromJson` factory (parse color from hex int), and `toJson` method.
    _Requirements: 1.2, 1.5, 1.6_

  - [x] 1.3 Create lib/models/prediction_round_model.dart
    Create the `PredictionRoundModel` class with fields: `roundId` (String), `roundNumber` (int), `questionText` (String), `options` (List<String>), `timeLimitSeconds` (int, default 15), `correctAnswer` (String), `category` (String). Include const constructor, `fromJson` factory, and `toJson` method. Category values: 'goalscorer', 'result', 'stats', 'cards', 'overunder'.
    _Requirements: 1.3, 1.5, 1.6_

  - [x] 1.4 Create lib/models/player_pick_model.dart
    Create the `PlayerPickModel` class with fields: `userId` (String), `pick` (String, default ''), `hasLocked` (bool, default false), `secondsTaken` (int, default 0), `pointsAwarded` (int, default 0), `isCorrect` (bool, default false). Include const constructor, `fromJson` factory, and `toJson` method.
    _Requirements: 1.4, 1.5, 1.6_

- [x] 2. Routes
  - [x] 2.1 Update lib/app/routes/app_routes.dart with new arena routes
    Add three new route constants to the `AppRoutes` abstract class: `arenaWaiting = '/arena/waiting'`, `arenaPrediction = '/arena/prediction'`, `arenaEnd = '/arena/end'`. Keep existing `arenaLobby` unchanged.
    _Requirements: 2.1_

  - [x] 2.2 Update lib/app/routes/app_pages.dart with new GetPage entries
    Add three new `GetPage` entries for `arenaWaiting`, `arenaPrediction`, and `arenaEnd`. Each uses `ArenaBinding()`, `Transition.rightToLeft`, and `transitionDuration: Duration(milliseconds: 350)`. Import the new view files (they will be created later — use placeholder imports or forward declarations). The views are: `ArenaWaitingView`, `ArenaPredictionView`, `ArenaEndView`.
    _Requirements: 2.2, 2.3, 2.4, 2.5_

- [x] 3. Arena controller and binding
  - [x] 3.1 Rewrite lib/modules/arena/controllers/arena_controller.dart
    Implement the full `ArenaController` extending `GetxController`. Define the `ArenaScreen` enum (lobby, waiting, prediction, roundResult, end). Declare all reactive state fields as specified in the design: currentScreen, availableRooms, isLoadingRooms, isPrivateToggle, squad, roomCodeInput, isCreatingRoom, isJoiningRoom, errorMessage, currentRoundIndex, totalRounds, rounds, activeRound, roundPicks, countdownSeconds, myPick, hasLockedIn, leaderboard, xpEarnedThisRound, wasCorrect, speedBonusEarned, newStreak, earnedBadges. Implement methods: `fetchAvailableRooms()`, `createRoom()`, `joinRoom()`, `startGame()`, `_startNextRound()`, `lockInPick()`, `_startCountdown()`, `_closeRound()`, `_endGame()`. Use `Timer.periodic` for countdown. XP calculation: 10 base if correct + 5 speed bonus if secondsTaken ≤ 5. Streak: increment on correct, reset on wrong. Cancel timer in `onClose()`. For now, use mock data / TODO comments for actual API calls.
    _Requirements: 3.1–3.16, 9.2, 9.3, 9.4_

  - [x] 3.2 Update lib/modules/arena/controllers/arena_binding.dart
    Ensure `ArenaBinding` uses `Get.lazyPut<ArenaController>(() => ArenaController())` in its `dependencies()` method. This file likely already exists — verify and update if needed.
    _Requirements: 9.6_

- [x] 4. Arena lobby view
  - [x] 4.1 Create lib/modules/arena/widgets/room_card_widget.dart
    Create `RoomCardWidget` (StatelessWidget) accepting a `SquadModel room` parameter. Render a game-style card with: gradient border (arenaAccent for open, fantasyAccent for private), left accent strip (3px), room title, private/open pill badge, player count as overlapping avatar circles + "n/6" text, status pill ("⏳ WAITING"), and JOIN button (gradient for open, lock icon for private). Add press animation (scale 0.98 → 1.0, 150ms). Use `AppColors` for all colors. Use `GestureDetector` for tap handling.
    _Requirements: 4.2, 4.7, 4.8, 8.1, 8.4, 9.1_

  - [x] 4.2 Rewrite lib/modules/arena/arena_lobby_view.dart
    Rewrite `ArenaLobbyView` extending `GetView<ArenaController>`. Structure: Scaffold with AppColors.background, Stack with BackgroundWidget, SafeArea Column containing: top bar (back button + "⚔️ ARENA MODE"), header ("Find a Room"), CREATE ROOM card with gradient border and lightning icon, room list header with count, Expanded ListView.separated of RoomCardWidget items, error text. Call `fetchAvailableRooms()` on init. Show CircularProgressIndicator when loading, empty state when no rooms. Implement create room bottom sheet (title input, privacy toggle, gradient create button). Implement private room join dialog (6-char code input, JOIN button). Add staggered entrance animations for room cards.
    _Requirements: 4.1–4.11, 8.1, 8.2, 9.1, 9.2, 9.3, 9.5_

- [x] 5. Arena waiting view
  - [x] 5.1 Create lib/modules/arena/widgets/squad_avatar_widget.dart
    Create `SquadAvatarWidget` (StatelessWidget) accepting optional `PlayerModel? player` and `double size` (default 64). Filled slot: circle with avatarColor, gradient border (arenaAccent → electricBlue, 2.5px), glow shadow, centered initials (22px bold white), crown icon if isHost, displayName below, green connection dot if isConnected. Empty slot: cardSurface circle, dashed border with pulsing opacity (0.3 → 0.6, 1500ms), person_add icon, "Waiting..." text below.
    _Requirements: 5.3, 8.1, 9.1_

  - [x] 5.2 Create lib/modules/arena/widgets/room_code_widget.dart
    Create `RoomCodeWidget` (StatelessWidget) accepting `String code`. Render a Row of 6 character containers: each 44×52px, cardSurface background, borderRadius 12, gradient border (arenaAccent → electricBlue, 1.5px), character centered (28px bold white), subtle inner glow. Implement tap-to-copy (copies code to clipboard, shows snackbar confirmation).
    _Requirements: 5.1, 8.7, 9.1_

  - [x] 5.3 Create lib/modules/arena/arena_waiting_view.dart
    Create `ArenaWaitingView` extending `GetView<ArenaController>`. Structure: Scaffold, Stack with BackgroundWidget, SafeArea Column containing: top bar (back button + "🛡️ SQUAD LOBBY"), RoomCodeWidget with squad.roomCode, helper text, "PLAYERS (n/6)" header, GridView.count(crossAxisCount: 3) with 6 SquadAvatarWidget slots, Spacer, game info container (rounds + time), action button area. Host sees gradient "⚡ START GAME" button (disabled if < 2 players). Non-host sees "Waiting for host to start..." with pulsing LinearProgressIndicator. New player avatars animate with scale spring (600ms, elasticOut).
    _Requirements: 5.1–5.10, 8.1, 8.2, 9.1, 9.2, 9.3, 9.5_

- [x] 6. Prediction widgets
  - [x] 6.1 Create lib/modules/arena/widgets/countdown_timer_widget.dart
    Create `CountdownTimerWidget` (StatelessWidget) accepting `int seconds` and `int totalSeconds` (default 15). Use CustomPaint with `_CountdownArcPainter`: background circle (cardBorder, strokeWidth 6), foreground arc (sweepAngle = 2π × seconds/totalSeconds). Color transitions: >10s electricBlue, 5–10s amber (0xFFFFB300), <5s error red. Glow behind arc (40% opacity, blur 4). Center text: seconds number (28px bold) + "SEC" label (9px textMuted). Danger mode (≤5s): red text, scale pulse 1.0 → 1.15 → 1.0 (500ms loop), intensified glow. Wrap in RepaintBoundary.
    _Requirements: 6.6, 6.7, 8.5, 9.1, 9.8_

  - [x] 6.2 Create lib/modules/arena/widgets/prediction_card_widget.dart
    Create `PredictionCardWidget` (StatelessWidget) using `GetView<ArenaController>` pattern (or Get.find). Render: Container with gradient border (arenaAccent → electricBlue), borderRadius 20, cardSurface background, glow shadow. Content: category badge pill (gradient background, category icon + uppercase text), question text (22px bold white, centered), CountdownTimerWidget, answer options column. Each option is an `_AnswerOptionButton` with states: unselected (gradient border, white text), selected/locked (gradient fill, lock icon, pulse), disabled (opacity 0.3). Tap calls `controller.lockInPick(option)`. Scale tap feedback (0.97 → 1.0).
    _Requirements: 6.3, 6.8, 6.9, 6.10, 8.1, 8.2, 9.1, 9.2_

  - [x] 6.3 Create lib/modules/arena/widgets/rival_lockin_row_widget.dart
    Create `RivalLockInRowWidget` (StatelessWidget) accepting `List<PlayerPickModel> picks` and `List<PlayerModel> players`. Render: Container with cardSurface, gradient border at 20% opacity, borderRadius 14. Content: "SQUAD STATUS" header (9px bold textMuted), Row of player avatars (36×36 circles with avatarColor and initials). Locked players: neonGreen border (2px) + checkmark badge (14×14 circle, neonGreen, ✓ icon). Unlocked: cardBorder (1px). First name below each avatar. Lock-in animation: border flash + checkmark scale-in (elasticOut, 400ms).
    _Requirements: 6.4, 9.1_

  - [x] 6.4 Create lib/modules/arena/widgets/leaderboard_strip_widget.dart
    Create `LeaderboardStripWidget` (StatelessWidget) using Get.find<ArenaController>. Render: Container with cardSurface, gradient border, borderRadius 16, padding 12. Header: trophy icon + "LEADERBOARD" text. Rows sorted by totalXP descending: rank badge (gold/silver/bronze gradient for top 3, cardBorder for 4+), small avatar (28×28), displayName, streak indicator (🔥n in neonGreen if streak ≥ 3), XP text (bold arenaAccent). AnimatedContainer for rank position changes (600ms). Rank 1 row has subtle gold glow border.
    _Requirements: 6.2, 8.5, 9.1, 9.2_

- [x] 7. Arena prediction view
  - [x] 7.1 Create lib/modules/arena/arena_prediction_view.dart
    Create `ArenaPredictionView` extending `GetView<ArenaController>`. Structure: Scaffold, Stack with BackgroundWidget, SafeArea Column containing: top bar with "ROUND n/total" + round progress dots, LeaderboardStripWidget, Expanded PredictionCardWidget, RivalLockInRowWidget. Overlay layer: Obx checking if currentScreen == roundResult → show RoundResultOverlayWidget with backdrop blur (BackdropFilter, sigma 6). Use Stack to layer the overlay on top of the main content.
    _Requirements: 6.1–6.5, 9.2, 9.3, 9.5, 9.9_

- [x] 8. Result and XP widgets
  - [x] 8.1 Create lib/modules/arena/widgets/xp_burst_widget.dart
    Create `XpBurstWidget` (StatefulWidget) accepting `bool isCorrect`. Correct: 64×64 circle with radial gradient (neonGreen), scale animation (0 → 1.2 → 1.0, elasticOut, 600ms), ✓ icon (32px), 8 particle lines bursting outward (CustomPainter, 2px wide, arenaAccent, fade out 500ms). Wrong: 64×64 circle with radial gradient (error), ✗ icon (32px), shake animation (x: 0 → -8 → 8 → -4 → 4 → 0, 400ms). Use AnimationController and dispose properly.
    _Requirements: 8.1, 9.1_

  - [x] 8.2 Create lib/modules/arena/widgets/round_result_overlay_widget.dart
    Create `RoundResultOverlayWidget` (StatelessWidget) using Get.find<ArenaController>. Render: full-screen container (black 60% opacity), BackdropFilter (blur sigma 6), centered card (screenWidth - 48, borderRadius 24, cardSurface, gradient border — neonGreen if correct, error if wrong, glow shadow). Content: XpBurstWidget, result text ("✓ Correct!" in neonGreen or "✗ Wrong" in error, 24px bold), correct answer reveal, XP count-up (TweenAnimationBuilder, 0 → xpEarnedThisRound, 800ms, 36px bold arenaAccent), bonus pills (speed +5, streak), divider, mini leaderboard (top 3). Entrance: scale 0.8 → 1.0 + fade, 350ms, easeOutBack. Auto-dismisses after 4 seconds (handled by controller).
    _Requirements: 6.5, 8.1, 9.1, 9.2, 9.9_

- [x] 9. End screen widgets
  - [x] 9.1 Create lib/modules/arena/widgets/podium_widget.dart
    Create `PodiumWidget` (StatefulWidget) accepting `List<PlayerModel> leaderboard`. Render: SizedBox(height: 220), Row(crossAxisAlignment: end) with three `_PodiumColumn` widgets. 2nd place (left, height 100, silver gradient), 1st place (center, height 140, gold gradient, crown), 3rd place (right, height 70, bronze gradient). Each column: crown if 1st (bounce animation), avatar (48×48, gradient border matching podium color, glow), displayName, XP text, gradient-filled column container (width 80, top borderRadius 12, rank emoji centered). Animations: columns rise from 0 → final height (staggered: 2nd at 0ms, 1st at 300ms, 3rd at 600ms, 500ms each, easeOutCubic). Crown bounces after 1st column finishes. Avatars fade in at 50% column height.
    _Requirements: 7.1, 7.8, 8.6, 9.1_

  - [x] 9.2 Create lib/modules/arena/widgets/badge_award_widget.dart
    Create `BadgeAwardWidget` (StatelessWidget) accepting `String badge`. Render: Container (100×120, borderRadius 16, gradient background arenaAccent/electricBlue at low opacity, gradient border, glow shadow). Content: badge icon (48×48, mapped from badge name — shield for "Perfect Round", lightning for "Speed Demon", fire for "Streak Master", crown for "Comeback King", star for "Consistent"), badge name text (10px bold textSecondary, centered). Entrance animation: scale 0 → 1.0 (elasticOut, 500ms) — stagger handled by parent.
    _Requirements: 7.4, 8.1, 9.1_

- [x] 10. Arena end view
  - [x] 10.1 Create lib/modules/arena/arena_end_view.dart
    Create `ArenaEndView` extending `GetView<ArenaController>`. Structure: Scaffold, Stack with BackgroundWidget + confetti overlay (50 particles, 3s, gold/arenaAccent/electricBlue). SafeArea SingleChildScrollView Column: trophy emoji (48px), "GAME OVER" overline + "Final Standings" title, PodiumWidget, "ALL PLAYERS" section with full leaderboard rows (rank badge, avatar, name, XP), "🎖️ BADGES EARNED" section with Wrap of BadgeAwardWidget items (if earnedBadges not empty), "SHARE RESULT" gradient button with shimmer animation (triggers platform share), "Back to Home" TextButton (calls Get.offAllNamed(AppRoutes.home)). Confetti triggers on mount.
    _Requirements: 7.1–7.8, 8.2, 8.6, 9.1, 9.2, 9.3, 9.5_

- [x] 11. Integration and verification
  - [x] 11.1 Wire mock data for demo (populate controller with sample rounds/players)
    Add an `_initMockData()` method to `ArenaController` (called in `onInit` when no real backend is available). Populate: 3 sample SquadModel rooms in availableRooms, a squad with 4 PlayerModel members, 5 PredictionRoundModel rounds with varied categories and options, sample leaderboard data. This enables end-to-end navigation testing without a backend. Guard with a `static const bool useMockData = true` flag.
    _Requirements: 3.3, 3.7_

  - [x] 11.2 Run flutter analyze and fix any issues
    Run `flutter analyze` on the project. Fix any lint errors, missing imports, type mismatches, or unused variable warnings introduced by the Arena module files. Ensure all files pass analysis cleanly.
    _Requirements: 9.1–9.10_

## Task Dependency Graph

```json
{
  "waves": [
    {
      "id": 1,
      "name": "Data Models",
      "tasks": ["1.1", "1.2", "1.3", "1.4"],
      "parallel": true,
      "description": "All four models can be built independently"
    },
    {
      "id": 2,
      "name": "Routes and Controller",
      "tasks": ["2.1", "2.2", "3.1", "3.2"],
      "parallel": false,
      "description": "Routes first (2.1 → 2.2), then controller (3.1 → 3.2). Routes depend on models for imports; controller depends on models and routes.",
      "order": ["2.1", "2.2", "3.1", "3.2"]
    },
    {
      "id": 3,
      "name": "Lobby Widgets + Waiting Widgets",
      "tasks": ["4.1", "5.1", "5.2"],
      "parallel": true,
      "description": "RoomCardWidget, SquadAvatarWidget, and RoomCodeWidget can be built in parallel"
    },
    {
      "id": 4,
      "name": "Lobby View + Waiting View",
      "tasks": ["4.2", "5.3"],
      "parallel": true,
      "description": "Both views can be built in parallel once their widgets exist"
    },
    {
      "id": 5,
      "name": "Prediction Widgets",
      "tasks": ["6.1", "6.2", "6.3", "6.4"],
      "parallel": true,
      "description": "All four prediction widgets can be built independently"
    },
    {
      "id": 6,
      "name": "Prediction View",
      "tasks": ["7.1"],
      "parallel": false,
      "description": "Depends on all prediction widgets being complete"
    },
    {
      "id": 7,
      "name": "Result Widgets",
      "tasks": ["8.1", "8.2"],
      "parallel": true,
      "description": "XpBurstWidget and RoundResultOverlayWidget can be built in parallel (overlay uses XpBurst, but can reference it)"
    },
    {
      "id": 8,
      "name": "End Screen Widgets",
      "tasks": ["9.1", "9.2"],
      "parallel": true,
      "description": "PodiumWidget and BadgeAwardWidget can be built independently"
    },
    {
      "id": 9,
      "name": "End View",
      "tasks": ["10.1"],
      "parallel": false,
      "description": "Depends on PodiumWidget and BadgeAwardWidget"
    },
    {
      "id": 10,
      "name": "Integration and Verification",
      "tasks": ["11.1", "11.2"],
      "parallel": false,
      "description": "Mock data first, then analyze. Depends on all previous waves.",
      "order": ["11.1", "11.2"]
    }
  ]
}
```
