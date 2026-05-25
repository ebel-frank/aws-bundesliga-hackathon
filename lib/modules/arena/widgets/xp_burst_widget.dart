import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

/// Animated XP burst indicator showing correct (green check with scale)
/// or wrong (red X, static) result.
class XpBurstWidget extends StatefulWidget {
  const XpBurstWidget({super.key, required this.isCorrect});

  final bool isCorrect;

  @override
  State<XpBurstWidget> createState() => _XpBurstWidgetState();
}

class _XpBurstWidgetState extends State<XpBurstWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40,
      ),
    ]).animate(_controller);

    if (widget.isCorrect) {
      _controller.forward();
    } else {
      // For wrong answers, just show static (no scale animation)
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isCorrect ? AppColors.neonGreen : AppColors.error;
    final icon = widget.isCorrect ? Icons.check : Icons.close;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isCorrect ? _scaleAnimation.value : 1.0,
          child: child,
        );
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0.3),
            ],
            stops: const [0.0, 1.0],
          ),
        ),
        child: Icon(
          icon,
          size: 32,
          color: Colors.white,
        ),
      ),
    );
  }
}
