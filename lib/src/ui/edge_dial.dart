import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared dial value bounds.
const double kDialMin = 0.1;
const double kDialMax = 5.0;

/// Pixels-to-value sensitivity for vertical-drag dial adjustment.
const double _kDragSensitivity = 0.01;

/// Computes a new dial value from a vertical drag delta (dragging up increases
/// the value), clamped to [kDialMin, kDialMax]. Emits a selection haptic each
/// time the value crosses a 0.1 step.
///
/// Centralized so the small [DialTrigger] and the large [EdgeDial] share
/// identical adjustment behavior.
double dialValueFromDrag(double current, double dyDelta) {
  final double newValue = (current - dyDelta * _kDragSensitivity).clamp(kDialMin, kDialMax);
  if ((current * 10).floor() != (newValue * 10).floor()) {
    HapticFeedback.selectionClick();
  }
  return newValue;
}

/// A small tappable chip showing a dial value, with vertical-drag adjustment.
///
/// [onTap] toggles persistence, [onActive] reports drag start/end, and
/// [onChanged] reports value changes.
class DialTrigger extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<bool> onActive;
  final VoidCallback onTap;

  const DialTrigger({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('trigger_$label'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      onVerticalDragStart: (_) => onActive(true),
      onVerticalDragEnd: (_) => onActive(false),
      onVerticalDragCancel: () => onActive(false),
      onVerticalDragUpdate: (details) => onChanged(dialValueFromDrag(value, details.delta.dy)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Text(
              value.toStringAsFixed(2),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white24)),
        ],
      ),
    );
  }
}

/// The large semicircular dial that slides in from a screen edge while a
/// gain/sensitivity control is active. Positions itself against the [isLeft]
/// edge and supports vertical-drag adjustment via [onChanged].
///
/// Returns a [Positioned] and is therefore intended to be placed directly
/// inside a [Stack].
class EdgeDial extends StatelessWidget {
  static const double _sizeScale = 0.7;
  static const double _offsetScale = 0.8;

  final bool isLeft;
  final double value;
  final String label;
  final Color color;
  final ValueChanged<double> onChanged;

  const EdgeDial({
    super.key,
    required this.isLeft,
    required this.value,
    required this.label,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final dialSize = size.height * _sizeScale;
    final availableHeight = size.height - padding.top - padding.bottom;

    return Positioned(
      top: padding.top + (availableHeight - dialSize) / 2,
      left: isLeft ? -dialSize * _offsetScale + padding.left : null,
      right: isLeft ? null : -dialSize * _offsetScale + padding.right,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => onChanged(dialValueFromDrag(value, details.delta.dy)),
        child: Container(
          key: Key('large_dial_${isLeft ? "left" : "right"}'),
          width: dialSize,
          height: dialSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.8),
            border: Border.all(color: color.withOpacity(0.3), width: 4),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.2),
                blurRadius: 30,
                spreadRadius: 10,
              )
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: isLeft
                    ? const Alignment(0.85, 0.0)
                    : const Alignment(-0.88, 0.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value.toStringAsFixed(2),
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w100,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: const TextStyle(
                          fontSize: 10,
                          letterSpacing: 2,
                          color: Colors.white24,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              CustomPaint(
                size: Size(dialSize, dialSize),
                painter: DialArcPainter(value: value, isLeft: isLeft, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the progress arc on the visible edge of an [EdgeDial].
class DialArcPainter extends CustomPainter {
  final double value;
  final bool isLeft;
  final Color color;
  DialArcPainter({required this.value, required this.isLeft, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 12; // Avoid clipping at widget bounds

    const totalVisibleSweep = 1.2;
    final progressSweep = (value / 5.0) * totalVisibleSweep;

    final basePaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10;

    if (isLeft) {
      // Left dial: Visible is the right side of the circle.
      // Fill bottom to top (counter-clockwise)
      const startAngle = totalVisibleSweep / 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        -totalVisibleSweep,
        false,
        basePaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        -progressSweep,
        false,
        progressPaint,
      );
    } else {
      // Right dial: Visible is the left side of the circle.
      // Fill bottom to top (clockwise)
      const startAngle = math.pi - (totalVisibleSweep / 2);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        totalVisibleSweep,
        false,
        basePaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        progressSweep,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DialArcPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}
