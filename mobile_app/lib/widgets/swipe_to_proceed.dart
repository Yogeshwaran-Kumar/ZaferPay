import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SwipeToProceed extends StatefulWidget {
  final Future<void> Function() onSwipeComplete;
  final String label;
  final Color baseColor;

  const SwipeToProceed({
    super.key,
    required this.onSwipeComplete,
    this.label = "Swipe to Proceed",
    this.baseColor = const Color(0xFF00B9F1),
  });

  @override
  State<SwipeToProceed> createState() => _SwipeToProceedState();
}

class _SwipeToProceedState extends State<SwipeToProceed>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0.0;
  bool _isCompleted = false;
  late AnimationController _resetController;
  late Animation<double> _resetAnimation;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _resetController.addListener(() {
      setState(() {
        _dragPosition = _resetAnimation.value;
      });
    });
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double maxWidth) {
    if (_isCompleted) return;

    setState(() {
      _dragPosition += details.delta.dx;
      if (_dragPosition < 0) _dragPosition = 0;
      if (_dragPosition > maxWidth - 60) {
        _dragPosition = maxWidth - 60; // 60 is approx thumb width
      }
    });
  }

  void _onDragEnd(DragEndDetails details, double maxWidth) async {
    if (_isCompleted) return;

    if (_dragPosition >= maxWidth - 65) {
      // Threshold reached, lock and trigger
      setState(() {
        _isCompleted = true;
        _dragPosition = maxWidth - 60;
      });
      await widget.onSwipeComplete();
      // Reset if the action completes and we stay on screen (e.g. error)
      if (mounted) {
        setState(() {
          _isCompleted = false;
        });
        _resetToZero();
      }
    } else {
      // Snap back
      _resetToZero();
    }
  }

  void _resetToZero() {
    _resetAnimation = Tween<double>(begin: _dragPosition, end: 0.0).animate(
      CurvedAnimation(parent: _resetController, curve: Curves.easeOutCubic),
    );
    _resetController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        return Container(
          height: 60,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[800] : Colors.grey[200],
            borderRadius: BorderRadius.circular(30),
          ),
          child: Stack(
            children: [
              // Background Text
              Center(
                child: Text(
                  widget.label,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),

              // Progress Fill
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _dragPosition + 30, // +30 for thumb center
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.baseColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),

              // Draggable Thumb
              Positioned(
                left: _dragPosition,
                top: 4,
                bottom: 4,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) =>
                      _onDragUpdate(details, maxWidth),
                  onHorizontalDragEnd: (details) =>
                      _onDragEnd(details, maxWidth),
                  child: Container(
                    width: 52,
                    decoration: BoxDecoration(
                      color: widget.baseColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: widget.baseColor.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _isCompleted
                        ? const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
