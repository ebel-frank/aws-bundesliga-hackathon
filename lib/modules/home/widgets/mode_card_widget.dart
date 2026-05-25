import 'package:flutter/material.dart';

import '../../../models/game_mode_model.dart';

class ModeCardWidget extends StatefulWidget {
  final GameModeModel mode;
  final Duration animationDelay;
  final bool isSelected;
  final VoidCallback onTap;

  const ModeCardWidget({
    super.key,
    required this.mode,
    required this.animationDelay,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<ModeCardWidget> createState() => _ModeCardWidgetState();
}

class _ModeCardWidgetState extends State<ModeCardWidget>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  late final AnimationController _tapController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 40),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    ));

    Future.delayed(widget.animationDelay, () {
      if (mounted) _entranceController.forward();
    });

    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _tapController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, child) {
        return Transform.translate(
          offset: _slideAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTapDown: (_) => _tapController.forward(),
        onTapUp: (_) => _tapController.reverse(),
        onTapCancel: () => _tapController.reverse(),
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: widget.mode.accentColor.withValues(alpha: 0.3),
                  blurRadius: widget.isSelected ? 20 : 10,
                  spreadRadius: widget.isSelected ? 1 : 0,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Background image
                  Image.asset(
                    widget.mode.iconAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              widget.mode.accentColor.withValues(alpha: 0.8),
                              widget.mode.accentColor.withValues(alpha: 0.4),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  // Gradient overlay for text readability
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                        stops: const [0.3, 1.0],
                      ),
                    ),
                  ),
                  // Arrow button — top right
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            widget.mode.accentColor.withValues(alpha: 0.7),
                            widget.mode.accentColor.withValues(alpha: 0.3),
                          ],
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_outward_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  // Title and subtitle — bottom
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.mode.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.mode.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
