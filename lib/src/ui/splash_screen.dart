import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Animated welcome overlay shown over the home page while the app settles.
///
/// A Dart port of the web splash (`web/splash.svg`): the scanning ring sweeps
/// in, the signal trace draws across it, the tuner blip pops in, and the
/// SPECTRAL wordmark rises — then a bright pulse travels the trace and a ping
/// radiates from the blip while the overlay fades out. The whole animation is
/// finite (one controller pass), so it never keeps the frame scheduler alive
/// after it dismisses itself.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, this.onFinished});

  /// Invoked once, after the overlay has fully faded out and collapsed.
  final VoidCallback? onFinished;

  /// Visible time before the fade starts.
  static const Duration holdDuration = Duration(milliseconds: 2400);

  /// Duration of the final fade to transparent.
  static const Duration fadeDuration = Duration(milliseconds: 400);

  /// Shortened schedule used when the platform requests reduced motion.
  static const Duration reducedHoldDuration = Duration(milliseconds: 900);

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _done = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final hold = _reduceMotion
        ? SplashOverlay.reducedHoldDuration
        : SplashOverlay.holdDuration;
    _controller = AnimationController(
      vsync: this,
      duration: hold + SplashOverlay.fadeDuration,
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() => _done = true);
          widget.onFinished?.call();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_done || controller == null) return const SizedBox.shrink();

    final totalSeconds = controller.duration!.inMilliseconds / 1000.0;
    final fadeSeconds = SplashOverlay.fadeDuration.inMilliseconds / 1000.0;
    final holdSeconds = totalSeconds - fadeSeconds;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value * totalSeconds;
        final fade = t <= holdSeconds
            ? 1.0
            : 1.0 - ((t - holdSeconds) / fadeSeconds).clamp(0.0, 1.0);
        return Opacity(
          opacity: fade,
          // Purely visual: taps land on the app underneath from the start.
          child: IgnorePointer(
            child: CustomPaint(
              painter: _SplashPainter(t: t, reduceMotion: _reduceMotion),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }
}

/// Paints the splash frame for elapsed time [t] (seconds) in the 1024x1024
/// coordinate space of the master logo, scaled to fit the canvas.
class _SplashPainter extends CustomPainter {
  _SplashPainter({required this.t, required this.reduceMotion});

  final double t;
  final bool reduceMotion;

  // Geometry from resources/icon.svg / web/splash.svg.
  static const Offset _center = Offset(512, 512);
  static const Offset _blip = Offset(724.1, 299.9);
  static const double _blipRadius = 27;

  static final Path _ringPath = Path()
    ..addArc(
      Rect.fromCircle(center: _center, radius: 300),
      -25 * 3.1415926535 / 180,
      320 * 3.1415926535 / 180,
    );

  static final Path _wavePath = Path()
    ..moveTo(250, 512)
    ..cubicTo(285, 512, 305, 462, 340, 462)
    ..cubicTo(375, 462, 395, 562, 430, 562)
    ..cubicTo(468, 562, 478, 345, 512, 345)
    ..cubicTo(546, 345, 556, 562, 594, 562)
    ..cubicTo(629, 562, 649, 462, 684, 462)
    ..cubicTo(719, 462, 739, 512, 774, 512);

  static double _phase(double t, double start, double duration, Curve curve) =>
      curve.transform(((t - start) / duration).clamp(0.0, 1.0));

  static Path _trim(Path path, double fraction) {
    if (fraction >= 1.0) return path;
    final out = Path();
    for (final metric in path.computeMetrics()) {
      out.addPath(metric.extractPath(0, metric.length * fraction), Offset.zero);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Background: the app's dark navy diagonal gradient plus a soft blue bloom,
    // matching both the icon background and the web splash page.
    final bgRect = Offset.zero & size;
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = ui.Gradient.linear(
          bgRect.topLeft,
          bgRect.bottomRight,
          [const Color(0xFF13233C), const Color(0xFF05080F)],
        ),
    );
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width / 2, size.height * 0.46),
          0.6 * size.longestSide,
          [
            const Color(0xFF007AFF).withValues(alpha: 0.14),
            const Color(0xFF007AFF).withValues(alpha: 0.0),
          ],
        ),
    );

    // Fit the 1024-space mark to the canvas, centered.
    final scale = size.shortestSide / 1024.0;
    canvas.save();
    canvas.translate(
      (size.width - 1024 * scale) / 2,
      (size.height - 1024 * scale) / 2,
    );
    canvas.scale(scale);

    // Intro phases (all complete instantly under reduced motion).
    final ringT =
        reduceMotion ? 1.0 : _phase(t, 0.05, 0.55, Curves.easeOutCubic);
    final waveT =
        reduceMotion ? 1.0 : _phase(t, 0.35, 0.55, Curves.fastOutSlowIn);
    final blipT = reduceMotion ? 1.0 : ((t - 0.78) / 0.35).clamp(0.0, 1.0);
    final wordT = reduceMotion ? 1.0 : _phase(t, 0.9, 0.5, Curves.easeOut);

    final ring = _trim(_ringPath, ringT);
    final wave = _trim(_wavePath, waveT);
    final blipScale =
        0.2 + 0.8 * (reduceMotion ? 1.0 : Curves.easeOutBack.transform(blipT));

    // Soft halo behind the crisp strokes, drawn with the same trim progress.
    // MaskFilter sigma is in local (pre-transform) space, so 17 matches the SVG.
    const glowSigma = MaskFilter.blur(BlurStyle.normal, 17);
    if (ringT > 0) {
      canvas.drawPath(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 34
          ..strokeCap = StrokeCap.round
          ..maskFilter = glowSigma
          ..color = const Color(0xFF2E86E0).withValues(alpha: 0.55),
      );
    }
    if (waveT > 0) {
      canvas.drawPath(
        wave,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 40
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = glowSigma
          ..color = const Color(0xFF5AC8FA).withValues(alpha: 0.55),
      );
    }
    if (blipT > 0) {
      canvas.drawCircle(
        _blip,
        _blipRadius * blipScale,
        Paint()
          ..maskFilter = glowSigma
          ..color = const Color(0xFF5AC8FA).withValues(alpha: 0.55 * blipT),
      );
    }

    // Scanning ring with tuner gap.
    if (ringT > 0) {
      canvas.drawPath(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 34
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(
            const Offset(212, 812),
            const Offset(812, 212),
            [const Color(0xFF1C5FAE), const Color(0xFF4AA8F0)],
          ),
      );
    }

    // Ping ripple radiating from the blip ("scan found something").
    if (!reduceMotion && t >= 1.9) {
      final cycle = ((t - 1.9) % 1.6) / 1.6;
      final expand = Curves.easeOutCubic.transform(cycle);
      final fadeOut = Curves.easeOut.transform((cycle / 0.7).clamp(0.0, 1.0));
      final factor = ui.lerpDouble(0.5, 2.4, expand)!;
      canvas.drawCircle(
        _blip,
        _blipRadius * factor,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7 * factor
          ..color = const Color(0xFF8FD5FF).withValues(alpha: 0.75 * (1 - fadeOut)),
      );
    }

    // Tuner blip.
    if (blipT > 0) {
      canvas.drawCircle(
        _blip,
        _blipRadius * blipScale,
        Paint()..color = const Color(0xFFAEE2FF).withValues(alpha: blipT),
      );
    }

    // Signal trace.
    if (waveT > 0) {
      canvas.drawPath(
        wave,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 40
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = ui.Gradient.linear(
            const Offset(250, 512),
            const Offset(774, 512),
            [
              const Color(0xFF1E7BEA),
              const Color(0xFF4AA8F0),
              const Color(0xFFD8F1FF),
              const Color(0xFF4AA8F0),
              const Color(0xFF1E7BEA),
            ],
            [0.0, 0.32, 0.5, 0.68, 1.0],
          ),
      );
    }

    // Bright pulse traveling along the trace ("signal coming in").
    if (!reduceMotion && t >= 1.15) {
      final fadeIn = ((t - 1.15) / 0.3).clamp(0.0, 1.0) * 0.9;
      final cycle = ((t - 1.15) % 1.6) / 1.6;
      const window = 0.16;
      final start = cycle * (1 + window) - window;
      final end = start + window;
      final metric = _wavePath.computeMetrics().first;
      final a = (start.clamp(0.0, 1.0)) * metric.length;
      final b = (end.clamp(0.0, 1.0)) * metric.length;
      if (b - a > 1e-3) {
        canvas.drawPath(
          metric.extractPath(a, b),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 30
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFFEAF7FF).withValues(alpha: fadeIn),
        );
      }
    }

    // Wordmark.
    if (wordT > 0) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'SPECTRAL',
          style: TextStyle(
            fontSize: 58,
            fontWeight: FontWeight.w500,
            letterSpacing: 26,
            color: const Color(0xFFA9C7E8).withValues(alpha: 0.85 * wordT),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Optically center: TextPainter width includes the trailing letter space.
      final dx = 512 - (textPainter.width - 26) / 2;
      final dy = 948 - textPainter.height * 0.78 + 14 * (1 - wordT);
      textPainter.paint(canvas, Offset(dx, dy));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SplashPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.reduceMotion != reduceMotion;
}
