import 'package:flutter/material.dart';

class FraudScanningAnimation extends StatefulWidget {
  final bool isDark;
  final double size;
  const FraudScanningAnimation({
    super.key,
    required this.isDark,
    this.size = 280.0,
  });

  @override
  State<FraudScanningAnimation> createState() => _FraudScanningAnimationState();
}

class _FraudScanningAnimationState extends State<FraudScanningAnimation>
    with TickerProviderStateMixin {
  late AnimationController _scanController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isDark ? Colors.blueAccent : const Color(0xFF00B9F1);
    final bgColor = widget.isDark ? Colors.black : Colors.white;

    return Center(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Pulsing Rings (Outer)
            ...List.generate(3, (index) {
              return FadeTransition(
                opacity: Tween(begin: 0.0, end: 1.0).animate(
                  CurvedAnimation(
                    parent: _scanController,
                    curve: Interval(index * 0.2, 1.0, curve: Curves.easeOut),
                  ),
                ),
                child: ScaleTransition(
                  scale: Tween(begin: 0.5, end: 1.2).animate(
                    CurvedAnimation(
                      parent: _scanController,
                      curve: Interval(index * 0.2, 1.0, curve: Curves.easeOut),
                    ),
                  ),
                  child: Container(
                    width: widget.size * (200 / 280),
                    height: widget.size * (200 / 280),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color.withValues(alpha: 0.1 - (index * 0.02)),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              );
            }),

            // 2. Rotating Radar Gradient
            RotationTransition(
              turns: _scanController,
              child: Container(
                width: widget.size * (220 / 280),
                height: widget.size * (220 / 280),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      Colors.transparent,
                      color.withValues(alpha: 0.2),
                      color.withValues(alpha: 0.6),
                    ],
                    stops: const [0.5, 0.8, 1.0],
                  ),
                ),
              ),
            ),

            // 3. Central Shield (Pulsing)
            ScaleTransition(
              scale: Tween(begin: 1.0, end: 1.1).animate(
                CurvedAnimation(
                  parent: _pulseController,
                  curve: Curves.easeInOut,
                ),
              ),
              child: Container(
                width: widget.size * (100 / 280),
                height: widget.size * (100 / 280),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bgColor,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                  border: Border.all(
                    color: color.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.shield_outlined,
                  size: widget.size * (50 / 280),
                  color: color,
                ),
              ),
            ),

            // 4. "AI" Particles/Decorations (Static for now, could be animated)
            Positioned(
              top: widget.size * (40 / 280),
              right: widget.size * (40 / 280),
              child: _buildDataPoint(color),
            ),
            Positioned(
              bottom: widget.size * (40 / 280),
              left: widget.size * (40 / 280),
              child: _buildDataPoint(color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataPoint(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.6),
        shape: BoxShape.circle,
      ),
    );
  }
}
