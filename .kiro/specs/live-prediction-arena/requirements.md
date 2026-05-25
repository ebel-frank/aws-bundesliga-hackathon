# Requirements Document

## Introduction

Live Prediction Arena is a Flutter mobile application providing a game-like hub for live sports prediction. This document specifies the requirements for the initial build: project setup, theme layer, data models, home screen with animations, stub modules for Arena and Fantasy, and routing infrastructure. The app targets iOS and Android using Flutter 3.x with GetX for state management and navigation.

## Glossary

- **App**: The Live Prediction Arena Flutter application
- **Home_Screen**: The initial landing screen displaying the logo and game mode cards
- **HomeController**: The GetxController managing home screen state and animations
- **BackgroundWidget**: The full-screen animated background with gradient blobs and particles
- **AnimatedLogoWidget**: The animated branding widget with scale, fade, and shimmer effects
- **ModeCardWidget**: The interactive game mode selection card with glassmorphism styling
- **GlassmorphismCard**: A reusable shared widget providing frosted glass card styling
- **GameModeModel**: Data class representing a selectable game mode (Arena or Fantasy)
- **Theme_Layer**: The centralized color, typography, and ThemeData configuration
- **Routing_System**: GetX named route definitions and navigation constants
- **Particle_System**: The floating particle animation within BackgroundWidget
- **GetX**: State management, dependency injection, and routing framework
- **Binding**: GetX class that registers controller dependencies via lazyPut

## Requirements

### Requirement 1: Project Setup

**User Story:** As a developer, I want the project configured with all necessary dependencies and folder structure, so that I can begin implementing features immediately.

#### Acceptance Criteria

1. THE App SHALL have a `pubspec.yaml` with dependencies: get ^4.6.6, get_storage ^2.1.1, dio ^5.4.0, web_socket_channel ^2.4.0, flutter_animate ^4.5.0, shimmer ^3.0.0
2. THE App SHALL have the complete folder structure matching the module-based MVC architecture with directories for app/routes, app/theme, models, modules/home, modules/arena, modules/fantasy, and shared/widgets
3. THE App SHALL have asset placeholder directories at assets/icons/, assets/images/, and assets/animations/
4. THE App SHALL declare asset directories in pubspec.yaml flutter assets section

### Requirement 2: Theme Layer

**User Story:** As a developer, I want a centralized theme system, so that all UI components use consistent colors and typography without hardcoded values.

#### Acceptance Criteria

1. THE Theme_Layer SHALL define all color constants in `AppColors` with background #0D1117, cardSurface #1C2333, cardBorder #2A3650, electricBlue #1A56A0, electricBlueGlow #2E7FE8, arenaAccent #2E7FE8, fantasyAccent #7C3AED, success #22C55E, error #EF4444, warning #F59E0B, textPrimary #FFFFFF, textSecondary #B0BAD0, textMuted #5A6785
2. THE Theme_Layer SHALL define typography styles in `AppTextStyles` including headline (42px bold), title (24px bold), subtitle (14px medium), body (13px regular), caption (12px), overline (13px letterSpacing 4), and chip (10px bold)
3. THE Theme_Layer SHALL provide a `darkTheme` ThemeData with scaffold background color, transparent AppBar, and appropriate text theme
4. WHEN any widget references a color, THE widget SHALL use `AppColors.*` constants exclusively — no hardcoded Color values outside app_colors.dart

### Requirement 3: Data Models

**User Story:** As a developer, I want well-defined data models, so that game mode information and user data have a consistent structure across the app.

#### Acceptance Criteria

1. THE GameModeModel SHALL contain fields: id (String), title (String), subtitle (String), description (String), iconAsset (String), accentColor (Color), glowColor (Color), featureTags (List of String)
2. THE GameModeModel SHALL use a const constructor for immutability
3. THE App SHALL define a UserModel with fields: id (String), username (String), avatarUrl (nullable String), xp (int), level (int)
4. THE UserModel SHALL use a const constructor with default values xp=0 and level=1

### Requirement 4: Home Controller

**User Story:** As a user, I want the home screen to manage animations and navigation state, so that interactions feel smooth and responsive.

#### Acceptance Criteria

1. THE HomeController SHALL use GetSingleTickerProviderStateMixin and create a logoAnimController with 1200ms duration and elasticOut curve for scale animation (0.6→1.0) and easeIn curve for fade animation (0.0→1.0)
2. THE HomeController SHALL guard against concurrent navigation by checking `isNavigating` before processing a mode selection
3. WHEN a user selects a game mode, THE HomeController SHALL set selectedMode to the matching index, wait 350ms for exit animation, then navigate to the correct route using Get.toNamed
4. WHEN the home screen initializes, THE HomeController SHALL trigger the logo animation after 300ms delay and set isLoaded to true after an additional 600ms
5. WHEN the HomeController is closed, THE HomeController SHALL dispose the logoAnimController in onClose()

### Requirement 5: Background Widget

**User Story:** As a user, I want an immersive animated background, so that the app feels dynamic and game-like.

#### Acceptance Criteria

1. THE BackgroundWidget SHALL render two radial gradient blobs: blue (#1A56A0 at 8% opacity, radius 300px) drifting ±30px from top-left, and purple (#7C3AED at 8% opacity, radius 250px) drifting ±20px from bottom-right, over an 8-second reversing loop
2. THE BackgroundWidget SHALL render a dot grid overlay with dots of 1.5px radius in cardBorder color
3. THE BackgroundWidget SHALL animate 10 floating particles that move upward and fade as they approach the top, wrapping back to the bottom when they exit
4. THE BackgroundWidget SHALL use CustomPainter for rendering and its own AnimationController with 8000ms duration repeating in reverse
5. WHEN placed in the widget tree, THE BackgroundWidget SHALL be wrapped in a RepaintBoundary to isolate repaints

### Requirement 6: Animated Logo Widget

**User Story:** As a user, I want an animated app logo on the home screen, so that the brand identity is memorable and the entrance feels polished.

#### Acceptance Criteria

1. THE AnimatedLogoWidget SHALL display "LIVE PREDICTION" as overline text (13px, letterSpacing 4, textSecondary color) and "ARENA" as headline text (42px bold white, letterSpacing 6)
2. THE AnimatedLogoWidget SHALL apply a shimmer effect on the "ARENA" text using the shimmer package with infinite loop
3. THE AnimatedLogoWidget SHALL animate an underline from 0 to full width using TweenAnimationBuilder over 600ms with easeOut curve
4. THE AnimatedLogoWidget SHALL display "Fan Squad × Bundesliga" as tagline text (12px textMuted)
5. THE AnimatedLogoWidget SHALL read scale and fade animations from HomeController and wrap content in ScaleTransition and FadeTransition

### Requirement 7: Mode Card Widget

**User Story:** As a user, I want visually appealing game mode cards with smooth interactions, so that I can easily understand and select my preferred game mode.

#### Acceptance Criteria

1. THE ModeCardWidget SHALL display a glassmorphism card with cardSurface fill, 20px border radius, 2px border in accent color, and a glow box shadow
2. THE ModeCardWidget SHALL show the mode icon (64x64) with a radial gradient glow behind it, plus title (24px bold), subtitle (14px accent color), description (13px textSecondary), and feature tag chips
3. WHEN the card enters the screen, THE ModeCardWidget SHALL animate with slide up 40px and fade in over 500ms with easeOutCubic curve, delayed by the provided animationDelay
4. WHEN a user presses the card, THE ModeCardWidget SHALL scale from 1.0 to 0.96 over 150ms, and reverse to 1.0 over 200ms on release
5. WHEN the card is selected, THE ModeCardWidget SHALL brighten its border glow from 0.35 to 1.0 opacity and increase blur radius

### Requirement 8: Home View Composition

**User Story:** As a user, I want a cohesive home screen that combines all visual elements, so that I have a complete and polished first impression of the app.

#### Acceptance Criteria

1. THE Home_Screen SHALL compose BackgroundWidget (in RepaintBoundary), AnimatedLogoWidget, ModeCardWidgets, and version text in a layered Stack layout
2. THE Home_Screen SHALL show mode cards with staggered entrance (150ms delay per card) triggered after isLoaded becomes true
3. THE Home_Screen SHALL display version text "v1.0.0 · Fan Squad Challenge" at the bottom in caption style

### Requirement 9: Stub Modules

**User Story:** As a developer, I want placeholder modules for Arena and Fantasy, so that navigation targets exist and the routing system can be verified.

#### Acceptance Criteria

1. THE Arena module SHALL contain arena_lobby_view.dart (Scaffold with "Arena — coming next sprint" text), arena_controller.dart (empty GetxController), and arena_binding.dart (Bindings with lazyPut)
2. THE Fantasy module SHALL contain fantasy_picker_view.dart (Scaffold with "Fantasy — coming next sprint" text), fantasy_controller.dart (empty GetxController), and fantasy_binding.dart (Bindings with lazyPut)
3. THE stub views SHALL use AppColors.background as scaffold background and display centered placeholder text in textMuted color

### Requirement 10: Routing System

**User Story:** As a developer, I want centralized route definitions, so that navigation is consistent and type-safe across the app.

#### Acceptance Criteria

1. THE Routing_System SHALL define route constants: home = '/', arenaLobby = '/arena/lobby', fantasyPicker = '/fantasy/picker'
2. THE Routing_System SHALL register GetPage entries for each route with appropriate view, binding, and transition
3. THE home route SHALL use Transition.fadeIn with 400ms duration, and arena/fantasy routes SHALL use Transition.rightToLeft with 350ms duration

### Requirement 11: Main Entry Point

**User Story:** As a user, I want the app to launch correctly into the home screen with proper theming, so that I immediately see the intended dark game-like interface.

#### Acceptance Criteria

1. THE App SHALL use GetMaterialApp with AppTheme.darkTheme, initialRoute set to AppRoutes.home, and all pages from AppPages.pages
2. THE App SHALL disable the debug banner
3. THE App SHALL set defaultTransition to Transition.fadeIn

### Requirement 12: Shared Widgets

**User Story:** As a developer, I want reusable shared widgets, so that common visual patterns are consistent and not duplicated across modules.

#### Acceptance Criteria

1. THE GlassmorphismCard SHALL accept child widget, borderColor, borderRadius, borderWidth, optional glowColor, and glowBlurRadius parameters
2. THE GlassmorphismCard SHALL render a Container with the specified border, background color of cardSurface, and optional box shadow glow
3. THE GlassmorphismCard SHALL use a const constructor where possible

### Requirement 13: Architecture Rules

**User Story:** As a developer, I want enforced architecture conventions, so that the codebase remains maintainable and consistent as it grows.

#### Acceptance Criteria

1. THE App SHALL use GetX Rx observables with Obx() for all reactive state — no setState calls
2. THE App SHALL use Get.toNamed(AppRoutes.*) for all navigation — no Navigator.push calls
3. THE App SHALL use Get.lazyPut in bindings for controller registration — no Get.put
4. WHEN a module contains widgets, THE module SHALL not import widgets from another module's widgets directory
5. WHEN a GetxController creates AnimationControllers, THE controller SHALL dispose them in onClose()
6. THE App SHALL use const constructors on all widgets and constructors where the compiler allows
