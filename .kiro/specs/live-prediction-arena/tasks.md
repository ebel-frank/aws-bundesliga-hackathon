# Implementation Plan: Live Prediction Arena

## Overview

Build the Live Prediction Arena Flutter app from the default counter scaffold to a fully functional home screen with animated background, logo, mode cards, stub modules, and GetX routing. Implementation follows strict build order — each task depends on the previous.

## Tasks

- [x] 1. Project setup and dependencies
  - [x] 1.1 Update pubspec.yaml with all dependencies and asset declarations
    - Replace current pubspec.yaml content with: name `live_prediction_arena`, add dependencies (get: ^4.6.6, get_storage: ^2.1.1, dio: ^5.4.0, web_socket_channel: ^2.4.0, flutter_animate: ^4.5.0, shimmer: ^3.0.0)
    - Add flutter assets section declaring assets/icons/, assets/images/, assets/animations/
    - _Requirements: 1.1, 1.4_
  - [x] 1.2 Create full folder structure and asset directories
    - Create directories: lib/app/routes/, lib/app/theme/, lib/models/, lib/modules/home/controllers/, lib/modules/home/widgets/, lib/modules/arena/controllers/, lib/modules/arena/widgets/, lib/modules/fantasy/controllers/, lib/modules/fantasy/widgets/, lib/shared/widgets/
    - Create asset directories: assets/icons/, assets/images/, assets/animations/
    - Place a .gitkeep in each asset directory
    - _Requirements: 1.2, 1.3_
  - [x] 1.3 Run flutter pub get to resolve dependencies
    - Execute `flutter pub get` in the project root
    - Verify no dependency resolution errors
    - _Requirements: 1.1_

- [x] 2. Theme layer
  - [x] 2.1 Create lib/app/theme/app_colors.dart
    - Define abstract class AppColors with all static const Color fields: background (#0D1117), cardSurface (#1C2333), cardBorder (#2A3650), electricBlue (#1A56A0), electricBlueGlow (#2E7FE8), arenaAccent (#2E7FE8), fantasyAccent (#7C3AED), success (#22C55E), error (#EF4444), warning (#F59E0B), textPrimary (#FFFFFF), textSecondary (#B0BAD0), textMuted (#5A6785)
    - _Requirements: 2.1_
  - [x] 2.2 Create lib/app/theme/app_text_styles.dart
    - Define abstract class AppTextStyles with static TextStyle fields: headline (42px, bold, white, letterSpacing 6), title (24px, bold, white), subtitle (14px, w500), body (13px, regular, textSecondary), caption (12px, textMuted), overline (13px, letterSpacing 4, textSecondary), chip (10px, bold)
    - _Requirements: 2.2_
  - [x] 2.3 Create lib/app/theme/app_theme.dart
    - Define abstract class AppTheme with static ThemeData get darkTheme
    - Set scaffoldBackgroundColor to AppColors.background, appBarTheme with transparent background and white foreground, textTheme using AppTextStyles
    - _Requirements: 2.3_

- [x] 3. Data models
  - [x] 3.1 Create lib/models/game_mode_model.dart
    - Define GameModeModel class with const constructor
    - Fields: id (String), title (String), subtitle (String), description (String), iconAsset (String), accentColor (Color), glowColor (Color), featureTags (List<String>)
    - Import dart:ui for Color
    - _Requirements: 3.1, 3.2_
  - [x] 3.2 Create lib/models/user_model.dart
    - Define UserModel class with const constructor
    - Fields: id (String), username (String), avatarUrl (String?), xp (int, default 0), level (int, default 1)
    - _Requirements: 3.3, 3.4_

- [x] 4. Home controller and binding
  - [x] 4.1 Create lib/modules/home/controllers/home_controller.dart
    - Define HomeController extending GetxController with GetSingleTickerProviderStateMixin
    - Add observable state: isLoaded (RxBool false), selectedMode (RxInt -1), isNavigating (RxBool false)
    - Create logoAnimController (1200ms), logoScaleAnim (0.6→1.0, elasticOut), logoFadeAnim (0.0→1.0, easeIn)
    - Implement _triggerEntrance(): 300ms delay → forward animation, 600ms more → isLoaded = true
    - Implement onModeSelected(String modeId): guard with isNavigating, set selectedMode, 350ms delay, Get.toNamed based on modeId, reset isNavigating
    - Implement onClose(): dispose logoAnimController
    - Define gameModes list with Arena and Fantasy GameModeModel instances
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_
  - [x] 4.2 Create lib/modules/home/controllers/home_binding.dart
    - Define HomeBinding extending Bindings
    - In dependencies(): Get.lazyPut<HomeController>(() => HomeController())
    - _Requirements: 13.3_
  - [ ]* 4.3 Write property test for navigation guard
    - **Property 1: Navigation guard prevents concurrent navigation**
    - Test that calling onModeSelected multiple times rapidly results in only one navigation call
    - Use Get.testMode and mock Get.toNamed
    - **Validates: Requirements 4.2**
  - [ ]* 4.4 Write property test for mode-to-route mapping
    - **Property 2: Mode selection maps to correct route**
    - For each valid mode ID, verify the correct route is called
    - **Validates: Requirements 4.3**

- [x] 5. Background widget
  - [x] 5.1 Create lib/modules/home/widgets/background_widget.dart
    - Define BackgroundWidget as StatefulWidget with SingleTickerProviderStateMixin
    - Create AnimationController with 8000ms duration, repeat(reverse: true)
    - Initialize 10 _Particle instances with random x, y, size (2-4px), speed (0.3-0.8), opacity (0.2-0.6), color (electricBlue or fantasyAccent)
    - Define _BackgroundPainter extending CustomPainter that takes animationValue and particles
    - Paint method: fill background, draw two radial gradient blobs (blue top-left ±30px drift, purple bottom-right ±20px drift, 8% opacity), draw dot grid (1.5px dots in cardBorder color), draw particles (move upward, fade near top, wrap to bottom)
    - shouldRepaint returns true (continuous animation)
    - Dispose AnimationController in dispose()
    - _Requirements: 5.1, 5.2, 5.3, 5.4_
  - [ ]* 5.2 Write property test for particle position invariant
    - **Property 3: Particle position invariant**
    - For any animation value in [0,1], verify all particle positions remain in [0,1] after wrapping
    - **Validates: Requirements 5.3**

- [x] 6. Animated logo widget
  - [x] 6.1 Create lib/modules/home/widgets/animated_logo_widget.dart
    - Define AnimatedLogoWidget as StatelessWidget
    - Get HomeController via Get.find<HomeController>()
    - Wrap in ScaleTransition(scale: controller.logoScaleAnim) and FadeTransition(opacity: controller.logoFadeAnim)
    - Inner Column: "LIVE PREDICTION" text (overline style), "ARENA" text wrapped in Shimmer.fromColors (baseColor white, highlightColor electricBlueGlow), TweenAnimationBuilder<double> for underline (0→1 over 600ms, easeOut), "Fan Squad × Bundesliga" tagline (caption style)
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

- [x] 7. Mode card widget
  - [x] 7.1 Create lib/modules/home/widgets/mode_card_widget.dart
    - Define ModeCardWidget as StatefulWidget with TickerProviderStateMixin
    - Accept: GameModeModel mode, Duration animationDelay, bool isSelected, VoidCallback onTap
    - Create entrance AnimationController (500ms): slide Tween(Offset(0, 40) → Offset.zero) + fade Tween(0.0→1.0), curve easeOutCubic, triggered after animationDelay
    - Create tap AnimationController (150ms): scale Tween(1.0→0.96)
    - Build: SlideTransition + FadeTransition wrapping GestureDetector wrapping ScaleTransition
    - Inner: AnimatedContainer with cardSurface fill, 20px radius, 2px accent border (opacity varies with isSelected), glow BoxShadow
    - Layout: Row with Stack(icon + radial glow) and Expanded Column(title, subtitle, description, Wrap of _FeatureChip widgets)
    - Define private _FeatureChip widget for tag chips
    - Dispose both AnimationControllers in dispose()
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_
  - [ ]* 7.2 Write property test for ModeCardWidget displays all model fields
    - **Property 4: ModeCardWidget displays all model fields**
    - For any valid GameModeModel, verify rendered widget contains title, subtitle, description, and all featureTags
    - **Validates: Requirements 7.2**

- [x] 8. Home view composition
  - [x] 8.1 Create lib/modules/home/home_view.dart
    - Define HomeView extending GetView<HomeController>
    - Scaffold with AppColors.background
    - Stack: RepaintBoundary(child: BackgroundWidget()), SafeArea with Padding(horizontal: 24)
    - Column: SizedBox(48), AnimatedLogoWidget(), SizedBox(56), Obx wrapping AnimatedOpacity (opacity tied to isLoaded) containing Column of ModeCardWidgets with staggered delays (150ms * index), Spacer, version Text, SizedBox(16)
    - _Requirements: 5.5, 8.1, 8.2, 8.3_

- [x] 9. Checkpoint - Verify home screen builds
  - Ensure the app compiles without errors (`flutter build apk --debug` or `flutter analyze`)
  - Verify no import errors between modules
  - Ask the user if questions arise.

- [x] 10. Stub modules
  - [x] 10.1 Create Arena module stubs
    - lib/modules/arena/arena_lobby_view.dart: StatelessWidget Scaffold with AppColors.background, transparent AppBar titled "Arena", centered Text "Arena — coming next sprint" in textMuted
    - lib/modules/arena/controllers/arena_controller.dart: empty GetxController
    - lib/modules/arena/controllers/arena_binding.dart: Bindings with Get.lazyPut<ArenaController>
    - _Requirements: 9.1, 9.3_
  - [x] 10.2 Create Fantasy module stubs
    - lib/modules/fantasy/fantasy_picker_view.dart: StatelessWidget Scaffold with AppColors.background, transparent AppBar titled "Fantasy", centered Text "Fantasy — coming next sprint" in textMuted
    - lib/modules/fantasy/controllers/fantasy_controller.dart: empty GetxController
    - lib/modules/fantasy/controllers/fantasy_binding.dart: Bindings with Get.lazyPut<FantasyController>
    - _Requirements: 9.2, 9.3_

- [x] 11. Routing system
  - [x] 11.1 Create lib/app/routes/app_routes.dart
    - Define abstract class AppRoutes with static const: home = '/', arenaLobby = '/arena/lobby', fantasyPicker = '/fantasy/picker'
    - _Requirements: 10.1_
  - [x] 11.2 Create lib/app/routes/app_pages.dart
    - Define AppPages class with static final List<GetPage> pages
    - Home: GetPage(name: AppRoutes.home, page: HomeView, binding: HomeBinding, transition: fadeIn, duration: 400ms)
    - Arena: GetPage(name: AppRoutes.arenaLobby, page: ArenaLobbyView, binding: ArenaBinding, transition: rightToLeft, duration: 350ms)
    - Fantasy: GetPage(name: AppRoutes.fantasyPicker, page: FantasyPickerView, binding: FantasyBinding, transition: rightToLeft, duration: 350ms)
    - _Requirements: 10.2, 10.3_

- [x] 12. Shared widgets
  - [x] 12.1 Create lib/shared/widgets/glassmorphism_card.dart
    - Define GlassmorphismCard StatelessWidget with const constructor
    - Parameters: required Widget child, Color borderColor (default cardBorder), double borderRadius (default 20), double borderWidth (default 2), Color? glowColor, double glowBlurRadius (default 8)
    - Build: Container with BoxDecoration (color: cardSurface, borderRadius, border with borderColor, optional boxShadow with glowColor)
    - _Requirements: 12.1, 12.2, 12.3_
  - [ ]* 12.2 Write property test for GlassmorphismCard configuration
    - **Property 5: GlassmorphismCard renders with provided configuration**
    - For any valid borderColor, borderRadius, and glowColor, verify the rendered Container decoration matches
    - **Validates: Requirements 12.2**

- [x] 13. Main entry point
  - [x] 13.1 Update lib/main.dart
    - Replace entire file content with GetMaterialApp setup
    - Import all necessary files (theme, routes)
    - main() calls runApp(LivePredictionArenaApp())
    - LivePredictionArenaApp: const StatelessWidget returning GetMaterialApp with title, debugShowCheckedModeBanner: false, theme: AppTheme.darkTheme, initialRoute: AppRoutes.home, getPages: AppPages.pages, defaultTransition: Transition.fadeIn
    - _Requirements: 11.1, 11.2, 11.3_

- [x] 14. Final checkpoint - Full verification
  - Run `flutter analyze` to check for lint errors
  - Run `flutter build apk --debug` to verify compilation
  - Ensure all imports resolve correctly
  - Verify no cross-module widget imports exist
  - Verify no hardcoded colors outside app_colors.dart
  - Verify no setState calls exist
  - Verify no Navigator.push calls exist
  - Ensure all tests pass, ask the user if questions arise.
  - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5, 13.6_

## Task Dependency Graph

```json
{
  "waves": [
    {
      "name": "Foundation",
      "tasks": ["1. Project setup and dependencies"]
    },
    {
      "name": "Theme & Models",
      "tasks": ["2. Theme layer", "3. Data models"]
    },
    {
      "name": "Controller",
      "tasks": ["4. Home controller and binding"]
    },
    {
      "name": "Widgets",
      "tasks": ["5. Background widget", "6. Animated logo widget", "7. Mode card widget", "12. Shared widgets"]
    },
    {
      "name": "Composition",
      "tasks": ["8. Home view composition"]
    },
    {
      "name": "Verification",
      "tasks": ["9. Checkpoint - Verify home screen builds"]
    },
    {
      "name": "Modules & Routing",
      "tasks": ["10. Stub modules", "11. Routing system"]
    },
    {
      "name": "Entry Point",
      "tasks": ["13. Main entry point"]
    },
    {
      "name": "Final",
      "tasks": ["14. Final checkpoint - Full verification"]
    }
  ]
}
```

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- The build order is strict — task N depends on task N-1 completing successfully
- Asset placeholder icons (arena_icon.png, fantasy_icon.png) should be simple colored PNGs or use Image.asset errorBuilder fallback
- All AnimationControllers in StatefulWidgets must be disposed in dispose(); in GetxControllers they must be disposed in onClose()
