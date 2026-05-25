import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

/// A circular countdown timer with an animated arc and color transitions.
///
/// Displays the remaining [seconds] as a shrinking arc out of [totalSeconds].
/// Color transitions: >10s electricBlue, 5–10s amber, <5s error red.
class CountdownTimerWidget extends StatelessWidget {
  const CountdownTimerWidget({
    super.key,
    required this.seconds,
    this.totalSeconds = 15,
  });

  final int seconds;
  final int totalSeconds;

  Color _arcColor() {
    if (seconds > 10) return AppColors.electricBlue;
    if (seconds >= 5) return const Color(0xFFFFB300);
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CustomPaint(
              painter: _CountdownArcPainter(
                progress: totalSeconds > 0 ? seconds / totalSeconds : 0,
                arcColor: _arcColor(),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                seconds.toString(),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'SEC',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMuted,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountdownArcPainter extends CustomPainter {
  _CountdownArcPainter({
    required this.progress,
    required this.arcColor,
  });

  final double progress;
  final Color arcColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background circle
    final bgPaint = Paint()
      ..color = AppColors.cardBorder
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Foreground arc
    final fgPaint = Paint()
      ..color = arcColor
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * pi * progress;
    canvas.drawArc(rect, -pi / 2, sweepAngle, false, fgPaint);
  }

  @override
  bool shouldRepaint(_CountdownArcPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.arcColor != arcColor;
  }
}
