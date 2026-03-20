import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/frequency_formatter.dart';

class RadioDialFocusSlider extends StatefulWidget {
  final RangeValues values;
  final double min;
  final double max;
  final ValueChanged<RangeValues> onChanged;
  final Color accentColor;

  const RadioDialFocusSlider({
    super.key,
    required this.values,
    required this.min,
    required this.max,
    required this.onChanged,
    this.accentColor = const Color(0xFF007AFF),
  });

  @override
  State<RadioDialFocusSlider> createState() => _RadioDialFocusSliderState();
}

enum _InteractionType { none, move, resizeStart, resizeEnd }

class _RadioDialFocusSliderState extends State<RadioDialFocusSlider>
    with SingleTickerProviderStateMixin {
  late AnimationController _activeController;
  _InteractionType _interactionType = _InteractionType.none;

  @override
  void initState() {
    super.initState();
    _activeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _activeController.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final double width = constraints.maxWidth;
    if (width <= 0) return;

    final double delta = (details.delta.dx) / width * (widget.max - widget.min);

    double start = widget.values.start;
    double end = widget.values.end;
    const double minSpan = 500.0;
    const int tickCount = 80;
    final double tickThreshold = (widget.max - widget.min) / tickCount;

    switch (_interactionType) {
      case _InteractionType.move:
        double span = end - start;
        double newStart = (start + delta).clamp(widget.min, widget.max - span);
        double newEnd = newStart + span;
        if ((start / tickThreshold).floor() != (newStart / tickThreshold).floor()) {
          HapticFeedback.selectionClick();
        }
        widget.onChanged(RangeValues(newStart, newEnd));
        break;
      case _InteractionType.resizeStart:
        double newStart = (start + delta).clamp(widget.min, end - minSpan);
        if ((start / tickThreshold).floor() != (newStart / tickThreshold).floor()) {
          HapticFeedback.selectionClick();
        }
        widget.onChanged(RangeValues(newStart, end));
        break;
      case _InteractionType.resizeEnd:
        double newEnd = (end + delta).clamp(start + minSpan, widget.max);
        if ((end / tickThreshold).floor() != (newEnd / tickThreshold).floor()) {
          HapticFeedback.selectionClick();
        }
        widget.onChanged(RangeValues(start, newEnd));
        break;
      case _InteractionType.none:
        break;
    }
  }

  void _handleDragStart(DragStartDetails details, BoxConstraints constraints) {
    final double width = constraints.maxWidth;
    if (width <= 0) return;

    final double x = details.localPosition.dx / width;
    final double val = widget.min + x * (widget.max - widget.min);

    final double start = widget.values.start;
    final double end = widget.values.end;

    // Normalized threshold (approx 24 pixels on a standard screen)
    final double threshold = 24.0 / width * (widget.max - widget.min);

    if ((val - start).abs() < threshold) {
      _interactionType = _InteractionType.resizeStart;
    } else if ((val - end).abs() < threshold) {
      _interactionType = _InteractionType.resizeEnd;
    } else if (val >= start && val <= end) {
      _interactionType = _InteractionType.move;
    } else {
      _interactionType = _InteractionType.none;
      return;
    }
    HapticFeedback.selectionClick();
    _activeController.forward();
  }

  void _handleDragEnd(DragEndDetails details) {
    _interactionType = _InteractionType.none;
    _activeController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) => _handleDragStart(details, constraints),
          onHorizontalDragUpdate: (details) => _handleDragUpdate(details, constraints),
          onHorizontalDragEnd: _handleDragEnd,
          onHorizontalDragCancel: () {
            _interactionType = _InteractionType.none;
            _activeController.reverse();
          },
          child: AnimatedBuilder(
            animation: _activeController,
            builder: (context, child) {
              final double heightScale = 1.0 + (0.5 * _activeController.value);
              return SizedBox(
                height: 60 * heightScale,
                width: double.infinity,
                child: CustomPaint(
                  painter: RadioDialPainter(
                    values: widget.values,
                    min: widget.min,
                    max: widget.max,
                    activeFactor: _activeController.value,
                    accentColor: widget.accentColor,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class RadioDialPainter extends CustomPainter {
  final RangeValues values;
  final double min;
  final double max;
  final double activeFactor;
  final Color accentColor;

  RadioDialPainter({
    required this.values,
    required this.min,
    required this.max,
    required this.activeFactor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;
    final double baseline = height * 0.8;

    final Paint linePaint = Paint()
      ..color = Colors.white.withOpacity(0.1 + 0.1 * activeFactor)
      ..strokeWidth = 1.0;

    // 1. Draw Background Track
    canvas.drawLine(Offset(0, baseline), Offset(width, baseline), linePaint);

    // 2. Draw Ticks
    const int tickCount = 80;
    for (int i = 0; i <= tickCount; i++) {
      final double x = (i / tickCount) * width;
      final bool isMajor = i % 10 == 0;
      final bool isMid = i % 5 == 0 && !isMajor;

      double tickHeight = isMajor ? 16.0 : (isMid ? 10.0 : 6.0);
      tickHeight += tickHeight * 0.3 * activeFactor;

      final double opacity = (isMajor ? 0.4 : (isMid ? 0.2 : 0.1)) + (0.2 * activeFactor);

      canvas.drawLine(
        Offset(x, baseline),
        Offset(x, baseline - tickHeight),
        Paint()
          ..color = Colors.white.withOpacity(opacity)
          ..strokeWidth = isMajor ? 1.5 : 1.0,
      );

      if (isMajor && activeFactor > 0.5) {
        final double freq = min + (i / tickCount) * (max - min);
        final String label = FrequencyFormatter.format(freq, precision: 0, shortUnit: true);
        final textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.3 * activeFactor),
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(x - textPainter.width / 2, baseline + 4));
      }
    }

    // 3. Draw Selected Window
    final double startX = ((values.start - min) / (max - min)) * width;
    final double endX = ((values.end - min) / (max - min)) * width;

    final Rect windowRect = Rect.fromLTRB(startX, height * 0.1, endX, baseline);

    final Paint windowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accentColor.withOpacity(0.05 + 0.1 * activeFactor),
          accentColor.withOpacity(0.2 + 0.2 * activeFactor),
        ],
      ).createShader(windowRect);

    canvas.drawRect(windowRect, windowPaint);

    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 * activeFactor)
      ..color = accentColor.withOpacity(0.5 + 0.5 * activeFactor);

    canvas.drawLine(Offset(startX, height * 0.1), Offset(startX, baseline), glowPaint);
    canvas.drawLine(Offset(endX, height * 0.1), Offset(endX, baseline), glowPaint);

    // 4. Handles
    final Paint handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(startX, baseline), width: 4, height: 12),
        const Radius.circular(2),
      ),
      handlePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(endX, baseline), width: 4, height: 12),
        const Radius.circular(2),
      ),
      handlePaint,
    );

    if (activeFactor > 0.2) {
      final double centerX = (startX + endX) / 2;
      final Paint needlePaint = Paint()
        ..color = accentColor.withOpacity(activeFactor)
        ..strokeWidth = 2.0;

      canvas.drawLine(
        Offset(centerX, height * 0.05),
        Offset(centerX, baseline + 10),
        needlePaint,
      );

      canvas.drawCircle(Offset(centerX, height * 0.05), 3, needlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant RadioDialPainter oldDelegate) {
    return oldDelegate.values != values ||
           oldDelegate.activeFactor != activeFactor ||
           oldDelegate.accentColor != accentColor;
  }
}
