# Requirements Document: Arena Module

## Introduction

The Arena Module is the multiplayer prediction game mode of Live Prediction Arena. It provides a competitive, real-time prediction experience where 2–6 players join a squad, answer timed football prediction questions across 5–10 rounds, earn XP, and compete for podium placement. The module spans four views (Lobby → Waiting → Prediction → End) managed by a single GetX controller, with a game-like visual identity featuring gradient borders, neon glows, and dramatic animations throughout.

## Glossary

| Term | Definition |
|------|-----------|
| **ArenaLobbyView** | Entry screen showing available rooms and room creation |
| **ArenaWaitingView** | Squad lobby where players gather before the game starts |
| **ArenaPredictionView** | Main game screen displaying prediction rounds with timer and options |
| **ArenaEndView** | Victory ceremony screen with podium, badges, and share functionality |
| **ArenaController** | Central GetX controller managing all Arena state and game lifecycle |
| **ArenaBinding** | GetX binding that lazily registers ArenaController |
| **SquadModel** | Data model representing a game room with members, status, and settings |
| **PlayerModel** | Data model representing a player with XP, streak, badges, and connection status |
| **PredictionRoundModel** | Data model representing a single prediction question with options and correct answer |
| **PlayerPickModel** | Data model representing a player's answer submission for a round |
| **ArenaScreen** | Enum defining the five screen states: lobby, waiting, prediction, roundResult, end |
| **RoomCode** | 6-character alphanumeric code used to identify and join rooms |
| **Lock-in** | The act of submitting a prediction answer (irreversible within a round) |
| **XP** | Experience points earned per round (base 10 for correct + up to 5 speed bonus) |
| **Streak** | Count of consecutive correct answers by a player |

## Requirements

### Requirement 1: Data Models

**User Story**: As a developer, I need well-defined data models so that the Arena module can represent squads, players, prediction rounds, and player picks with consistent serialization.

**Acceptance Criteria**:

- 1.1 THE system SHALL define a `SquadModel` class with fields: `roomCode` (String, 6 chars), `hostUserId` (String), `matchTitle` (String), `isPrivate` (bool), `members` (List\<PlayerModel\>, max 6), `status` (String: 'waiting' | 'playing' | 'finished'), and `totalRounds` (int, 5–10).
- 1.2 THE system SHALL define a `PlayerModel` class with fields: `userId` (String), `displayName` (String), `avatarColor` (Color), `totalXP` (int, default 0), `streak` (int, default 0), `badges` (List\<String\>, default empty), `isHost` (bool, default false), and `isConnected` (bool, default true).
- 1.3 THE system SHALL define a `PredictionRoundModel` class with fields: `roundId` (String), `roundNumber` (int, 1-based), `questionText` (String), `options` (List\<String\>, 2–4 items), `timeLimitSeconds` (int, default 15), `correctAnswer` (String, must be one of options), and `category` (String: 'goalscorer' | 'result' | 'stats' | 'cards' | 'overunder').
- 1.4 THE system SHALL define a `PlayerPickModel` class with fields: `userId` (String), `pick` (String, default empty), `hasLocked` (bool, default false), `secondsTaken` (int, default 0), `pointsAwarded` (int, default 0), and `isCorrect` (bool, default false).
- 1.5 EACH model SHALL provide a `fromJson(Map<String, dynamic>)` factory constructor and a `toJson()` method for serialization.
- 1.6 ALL model constructors SHALL use named required parameters for mandatory fields and default values for optional fields.

### Requirement 2: Routes

**User Story**: As a developer, I need route constants and GetPage registrations so that navigation between Arena screens uses named routes with proper bindings and transitions.

**Acceptance Criteria**:

- 2.1 THE system SHALL define route constants: `arenaLobby` = '/arena/lobby', `arenaWaiting` = '/arena/waiting', `arenaPrediction` = '/arena/prediction', `arenaEnd` = '/arena/end' in `AppRoutes`.
- 2.2 THE system SHALL register a `GetPage` for `arenaWaiting` with `ArenaBinding`, `Transition.rightToLeft`, and 350ms duration.
- 2.3 THE system SHALL register a `GetPage` for `arenaPrediction` with `ArenaBinding`, `Transition.rightToLeft`, and 350ms duration.
- 2.4 THE system SHALL register a `GetPage` for `arenaEnd` with `ArenaBinding`, `Transition.rightToLeft`, and 350ms duration.
- 2.5 THE existing `arenaLobby` route registration SHALL remain with `ArenaBinding`.

### Requirement 3: Arena Controller

**User Story**: As a player, I need a central controller that manages the entire Arena game lifecycle so that room creation, round progression, timer countdown, XP calculation, and screen transitions work seamlessly.

**Acceptance Criteria**:

- 3.1 THE system SHALL define an `ArenaScreen` enum with values: `lobby`, `waiting`, `prediction`, `roundResult`, `end`.
- 3.2 THE system SHALL expose reactive state for: `currentScreen`, `availableRooms`, `isLoadingRooms`, `squad`, `isCreatingRoom`, `isJoiningRoom`, `errorMessage`, `currentRoundIndex`, `totalRounds`, `rounds`, `activeRound`, `roundPicks`, `countdownSeconds`, `myPick`, `hasLockedIn`, `leaderboard`, `xpEarnedThisRound`, `wasCorrect`, `speedBonusEarned`, `newStreak`, and `earnedBadges`.
- 3.3 WHEN `fetchAvailableRooms()` is called THE system SHALL set `isLoadingRooms` to true, fetch rooms from the API, populate `availableRooms` sorted by member count descending, and set `isLoadingRooms` to false.
- 3.4 WHEN `createRoom()` is called THE system SHALL set `isCreatingRoom` to true, call the API, set `squad` with the response, navigate to `arenaWaiting`, and set `isCreatingRoom` to false.
- 3.5 WHEN `joinRoom()` is called with a valid room code THE system SHALL set `isJoiningRoom` to true, call the API, set `squad` with the response, and navigate to `arenaWaiting`.
- 3.6 WHEN `joinRoom()` fails THE system SHALL set `errorMessage` to the appropriate message ("Room not found", "Room is full", or "Invalid code") and set `isJoiningRoom` to false without navigating.
- 3.7 WHEN `startGame()` is called THE system SHALL fetch rounds from the API, set `totalRounds`, and call `_startNextRound()` to begin the first round.
- 3.8 WHEN `_startNextRound()` is called THE system SHALL increment `currentRoundIndex`, set `activeRound`, reset `hasLockedIn` and `myPick`, set `countdownSeconds` to 15, clear `roundPicks`, set `currentScreen` to `prediction`, and start the countdown timer.
- 3.9 WHEN `lockInPick()` is called AND `hasLockedIn` is false THE system SHALL set `myPick`, set `hasLockedIn` to true, and submit the pick to the API.
- 3.10 WHEN `lockInPick()` is called AND `hasLockedIn` is already true THE system SHALL perform no operation (idempotent guard).
- 3.11 WHEN the countdown timer reaches 0 THE system SHALL call `_closeRound()` to resolve the round.
- 3.12 WHEN `_closeRound()` is called THE system SHALL cancel the timer, determine correctness, calculate XP (base 10 if correct + 5 speed bonus if secondsTaken ≤ 5), update streak (increment if correct, reset to 0 if wrong), re-sort leaderboard by totalXP descending, and set `currentScreen` to `roundResult`.
- 3.13 WHEN the round result has been displayed for 4 seconds AND more rounds remain THE system SHALL call `_startNextRound()`.
- 3.14 WHEN the round result has been displayed for 4 seconds AND all rounds are complete THE system SHALL call `_endGame()`.
- 3.15 WHEN `_endGame()` is called THE system SHALL cancel the timer, finalize standings, determine earned badges, call the finalize API, and navigate to `arenaEnd`.
- 3.16 WHEN the controller is disposed THE system SHALL cancel `_countdownTimer` in `onClose()`.

### Requirement 4: Arena Lobby View

**User Story**: As a player, I want to see available game rooms and create or join rooms so that I can start or enter a multiplayer prediction game.

**Acceptance Criteria**:

- 4.1 WHEN the lobby view mounts THE system SHALL call `fetchAvailableRooms()` to load the room list.
- 4.2 THE system SHALL display available rooms as a scrollable list of `RoomCardWidget` items separated by 12px spacing.
- 4.3 WHEN `isLoadingRooms` is true THE system SHALL display a centered `CircularProgressIndicator` with `arenaAccent` color.
- 4.4 WHEN `availableRooms` is empty THE system SHALL display an empty state message: "No rooms available. Create one!".
- 4.5 THE system SHALL display a "CREATE ROOM" card with gradient border (arenaAccent → electricBlue), lightning bolt icon, and arrow forward icon.
- 4.6 WHEN the user taps "CREATE ROOM" THE system SHALL show a bottom sheet with game title input, privacy toggle, and a gradient "CREATE ROOM" button.
- 4.7 WHEN the user taps an open room card THE system SHALL call `joinRoom()` immediately.
- 4.8 WHEN the user taps a private room card THE system SHALL show a dialog with a 6-character code input and JOIN button.
- 4.9 WHEN `errorMessage` is not empty THE system SHALL display the error in red text (AppColors.error, 12px).
- 4.10 THE system SHALL animate room cards with staggered slide-up + fade-in entrance (500ms, easeOutCubic, 100ms stagger).
- 4.11 THE system SHALL display a top bar with back button and "⚔️ ARENA MODE" overline text with letterSpacing 2.

### Requirement 5: Arena Waiting View

**User Story**: As a player in a squad, I want to see who has joined, share the room code, and (as host) start the game when ready.

**Acceptance Criteria**:

- 5.1 THE system SHALL display the room code prominently using `RoomCodeWidget` with tap-to-copy functionality.
- 5.2 THE system SHALL display "Share this code with your squad" helper text below the room code.
- 5.3 THE system SHALL display a 3-column grid of 6 slots using `SquadAvatarWidget`, showing filled slots for joined players and empty placeholder slots for open positions.
- 5.4 THE system SHALL display "PLAYERS (n/6)" header above the player grid where n is the current member count.
- 5.5 THE system SHALL display game info showing total rounds and time per question (e.g., "7 rounds · 15s per question").
- 5.6 WHEN the current user is the host AND at least 2 players have joined THE system SHALL display an enabled "⚡ START GAME" gradient button.
- 5.7 WHEN the current user is the host AND fewer than 2 players have joined THE system SHALL display a disabled start button.
- 5.8 WHEN the current user is NOT the host THE system SHALL display "Waiting for host to start..." with a pulsing progress indicator.
- 5.9 WHEN a new player joins THE system SHALL animate their avatar with a scale spring animation (600ms, elasticOut).
- 5.10 THE system SHALL display a top bar with back button and "🛡️ SQUAD LOBBY" overline text.

### Requirement 6: Arena Prediction View

**User Story**: As a player in an active game, I want to see the prediction question, countdown timer, answer options, and rival status so that I can make my prediction before time runs out.

**Acceptance Criteria**:

- 6.1 THE system SHALL display round progress as "ROUND n/total" text and dot indicators for each round (filled if completed).
- 6.2 THE system SHALL display a `LeaderboardStripWidget` showing current standings.
- 6.3 THE system SHALL display a `PredictionCardWidget` containing the category badge, question text, countdown timer, and answer options.
- 6.4 THE system SHALL display a `RivalLockInRowWidget` showing each player's lock-in status.
- 6.5 WHEN `currentScreen` equals `roundResult` THE system SHALL display `RoundResultOverlayWidget` as a Stack layer with backdrop blur (sigma 6).
- 6.6 THE system SHALL display the countdown timer as a circular arc that depletes over 15 seconds with color transitions: electricBlue (>10s), amber (5–10s), error red (<5s).
- 6.7 WHEN the countdown reaches 5 seconds or less THE system SHALL activate danger mode: red text, scale pulse animation (1.0 → 1.15 → 1.0, 500ms loop).
- 6.8 WHEN the user taps an answer option AND has not locked in THE system SHALL call `lockInPick()` and show the option as selected with gradient fill and lock icon.
- 6.9 WHEN the user has locked in THE system SHALL disable all other answer options (opacity 0.3, no tap response).
- 6.10 THE system SHALL display answer options as 56px tall buttons with gradient borders, scale tap feedback (0.97 → 1.0), and a pulse animation on selection.

### Requirement 7: Arena End View

**User Story**: As a player who has completed all rounds, I want to see final standings, earned badges, and share my results so that I can celebrate and compare with my squad.

**Acceptance Criteria**:

- 7.1 THE system SHALL display a `PodiumWidget` showing 1st, 2nd, and 3rd place with rising column animations (staggered: 2nd at 0ms, 1st at 300ms, 3rd at 600ms).
- 7.2 THE system SHALL display a "🏆 GAME OVER" header with "Final Standings" subtitle.
- 7.3 THE system SHALL display a full results list showing all players with rank, avatar, name, and XP.
- 7.4 WHEN the player has earned badges THE system SHALL display a "🎖️ BADGES EARNED" section with `BadgeAwardWidget` items (staggered entrance, 200ms per badge).
- 7.5 THE system SHALL display a "SHARE RESULT" gradient button with shimmer border animation that triggers the platform share sheet on tap.
- 7.6 THE system SHALL display a "Back to Home" text button that navigates to home using `Get.offAllNamed(AppRoutes.home)`.
- 7.7 WHEN the end view mounts THE system SHALL trigger a confetti burst (50 particles, 3s duration, gold/arenaAccent/electricBlue colors).
- 7.8 THE system SHALL display the winner's crown icon (👑) with bounce animation above the 1st place podium column.

### Requirement 8: Game-Like Visual Style

**User Story**: As a player, I want the Arena module to feel like a mobile game with dramatic visuals so that the prediction experience is exciting and engaging.

**Acceptance Criteria**:

- 8.1 ALL card widgets SHALL use gradient borders (`LinearGradient` on border), `AppColors.cardSurface` background, corner radius 16–20px, and outer glow shadow (accent at 10–15% opacity, blur 8–12).
- 8.2 ALL action buttons SHALL use gradient fills (arenaAccent → electricBlue), borderRadius 14, height 52–56px, glow shadow (arenaAccent at 30% opacity, blur 12), bold uppercase white text with letterSpacing 1, and scale tap feedback (0.97 → 1.0, 150ms).
- 8.3 ALL icons SHALL use bold/filled style with game-concept mapping: shield/swords for squad, lightning for create, lock for private, fire for streak, trophy for leaderboard, crown for 1st place.
- 8.4 THE prediction card SHALL display a category badge pill with gradient background and category icon.
- 8.5 THE leaderboard SHALL use gold/silver/bronze glow for top 3 ranks, animated rank position changes (600ms), and XP count-up animations (800ms).
- 8.6 THE end screen podium SHALL use gradient column fills (gold/silver/bronze gradients), staggered rise animations, and confetti burst on the winner.
- 8.7 THE room code widget SHALL render each character in its own gradient-bordered box (44×52px, borderRadius 12).

### Requirement 9: Architecture Rules

**User Story**: As a developer, I need consistent architecture patterns so that the Arena module is maintainable, performant, and follows project conventions.

**Acceptance Criteria**:

- 9.1 THE system SHALL NOT use hardcoded color values; all colors SHALL reference `AppColors` constants.
- 9.2 THE system SHALL NOT use `setState`; all reactive state SHALL use GetX observables (`Rx`, `RxList`, `RxBool`, etc.) with `Obx` wrappers.
- 9.3 ALL navigation SHALL use `Get.toNamed()` or `Get.offAllNamed()` with route constants from `AppRoutes`.
- 9.4 THE `ArenaController` SHALL cancel `_countdownTimer` in `onClose()` to prevent memory leaks.
- 9.5 ALL views SHALL extend `GetView<ArenaController>` to access the controller via the `controller` getter.
- 9.6 THE `ArenaBinding` SHALL use `Get.lazyPut` for controller registration.
- 9.7 `Obx` wrappers SHALL be placed at the leaf widget level (not wrapping entire views) to minimize rebuilds.
- 9.8 `RepaintBoundary` SHALL be used on `BackgroundWidget` and `CountdownTimerWidget` (CustomPainter) to isolate repaints.
- 9.9 THE round result overlay SHALL be rendered as a Stack layer within `ArenaPredictionView` (not a route push).
- 9.10 ALL widget files SHALL be placed in `modules/arena/widgets/` and all view files in `modules/arena/`.
