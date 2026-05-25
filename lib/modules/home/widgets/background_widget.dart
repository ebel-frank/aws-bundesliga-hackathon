import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

class BackgroundWidget extends StatefulWidget {
  const BackgroundWidget({super.key});

  @override
  State<BackgroundWidget> createState() => _BackgroundWidgetState();
}

class _BackgroundWidgetState extends State<BackgroundWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat(reverse: true);

    final random = Random();
    _particles = List.generate(10, (_) {
      return _Particle(
        x: random.nextDouble(),
        y: random.nextDouble(),
        size: 2.0 + random.nextDouble() * 2.0,
        speed: 0.3 + random.nextDouble() * 0.5,
        opacity: 0.2 + random.nextDouble() * 0.4,
        color: random.nextBool()
            ? AppColors.arenaAccent
            : AppColors.fantasyAccent,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Dark base
        Container(color: AppColors.background),
        // Animated blobs
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _BackgroundPainter(
                animationValue: _controller.value,
                particles: _particles,
              ),
              size: Size.infinite,
            );
          },
        ),
      ],
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final double animationValue;
  final List<_Particle> particles;

  _BackgroundPainter({
    required this.animationValue,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Purple/magenta glow — top right
    final blob1CenterX = size.width * 0.8 + (animationValue * 2 - 1) * 20;
    final blob1CenterY = size.height * 0.1 + (animationValue * 2 - 1) * 15;
    final blob1Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.fantasyAccent.withValues(alpha: 0.2),
          AppColors.fantasyAccent.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(blob1CenterX, blob1CenterY),
          radius: 200,
        ),
      );
    canvas.drawCircle(Offset(blob1CenterX, blob1CenterY), 200, blob1Paint);

    // Blue glow — bottom left
    final blob2CenterX = size.width * 0.2 + (animationValue * 2 - 1) * 15;
    final blob2CenterY = size.height * 0.85 + (animationValue * 2 - 1) * 15;
    final blob2Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.arenaAccent.withValues(alpha: 0.15),
          AppColors.arenaAccent.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(blob2CenterX, blob2CenterY),
          radius: 180,
        ),
      );
    canvas.drawCircle(Offset(blob2CenterX, blob2CenterY), 180, blob2Paint);

    // Floating particles
    for (final particle in particles) {
      final particleY = (particle.y - animationValue * particle.speed) % 1.0;
      final adjustedY = particleY < 0 ? particleY + 1.0 : particleY;
      final fadeOpacity = adjustedY < 0.1
          ? particle.opacity * (adjustedY / 0.1)
          : particle.opacity;

      final particlePaint = Paint()
        ..color = particle.color.withValues(alpha: fadeOpacity);
      canvas.drawCircle(
        Offset(particle.x * size.width, adjustedY * size.height),
        particle.size,
        particlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) => true;
}

class _Particle {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double opacity;
  final Color color;

  const _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
    required this.color,
  });
}
