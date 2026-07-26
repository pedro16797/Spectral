import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/rf/native_sdr_driver.dart';
import 'src/rf/native_sdr_driver_channel.dart' if (dart.library.html) 'src/rf/native_sdr_driver_web.dart';
import 'src/core/signal_controller.dart';
import 'src/core/settings_model.dart';
import 'src/core/spectral_theme.dart';
import 'src/utils/frequency_scale.dart';
import 'src/ui/waveform_painter.dart';
import 'src/ui/fft_bar_chart_painter.dart';
import 'src/ui/waterfall_painter.dart';
import 'src/ui/radio_dial_focus_slider.dart';
import 'src/ui/edge_dial.dart';
import 'src/ui/settings_view.dart';
import 'src/utils/localization_helper.dart';
import 'src/services/settings_service.dart';
import 'src/utils/frequency_formatter.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Support state injection via base64 encoded settings in URL (headless environments)
    AppSettings settings;
    final String? b64 = Uri.base.queryParameters['settings_b64'];
    if (b64 != null) {
      try {
        final decoded = utf8.decode(base64Decode(b64));
        settings = AppSettings.fromMap(json.decode(decoded));
      } catch (e) {
        debugPrint("Error decoding settings_b64: $e");
        settings = await SettingsService.loadSettings();
      }
    } else {
      settings = await SettingsService.loadSettings();
    }

    await LocalizationHelper.load(settings.language);

    // Initialize the SDR driver based on the current platform
    // This is handled via conditional imports above
    NativeSdrDriver().setDelegate(NativeSdrDriverDelegate());

    runApp(SpectralApp(initialSettings: settings));
  } catch (e) {
    debugPrint("Startup error: $e");
    // Minimal fallback app if initialization fails
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text("Failed to start Spectral: $e"),
        ),
      ),
    ));
  }
}

class SpectralApp extends StatefulWidget {
  final AppSettings initialSettings;
  const SpectralApp({super.key, required this.initialSettings});

  @override
  State<SpectralApp> createState() => _SpectralAppState();
}

class _SpectralAppState extends State<SpectralApp> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  void _updateSettings(AppSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    SettingsService.saveSettings(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = SpectralTheme.accent(_settings.theme);
    final backgroundColor = SpectralTheme.background(_settings.theme);

    return MaterialApp(
      title: LocalizationHelper.get('app.name'),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: ColorScheme.dark(
          primary: Colors.white,
          secondary: accentColor,
          surface: const Color(0xFF1C1C1E),
        ),
        useMaterial3: true,
      ),
      home: SpectralHomePage(
        settings: _settings,
        onSettingsChanged: _updateSettings,
        backgroundColor: backgroundColor,
      ),
    );
  }
}

class SpectralHomePage extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final Color backgroundColor;

  const SpectralHomePage({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.backgroundColor,
  });

  @override
  State<SpectralHomePage> createState() => _SpectralHomePageState();
}

/// The four edge dials. Gain/Speed live on the left edge; Sensitivity/Squish on
/// the right.
enum _DialKind { gain, speed, sensitivity, squish }

extension _DialKindX on _DialKind {
  bool get isLeft => this == _DialKind.gain || this == _DialKind.speed;

  /// Stable identifier used for widget keys and semantics, independent of the
  /// localized display label.
  String get keyId {
    switch (this) {
      case _DialKind.gain:
        return 'GAIN';
      case _DialKind.speed:
        return 'SPEED';
      case _DialKind.sensitivity:
        return 'SENS';
      case _DialKind.squish:
        return 'SQUISH';
    }
  }

  String get shortLabel {
    switch (this) {
      case _DialKind.gain:
        return LocalizationHelper.get('dials.gain');
      case _DialKind.speed:
        return LocalizationHelper.get('dials.speed');
      case _DialKind.sensitivity:
        return LocalizationHelper.get('dials.sensitivity');
      case _DialKind.squish:
        return LocalizationHelper.get('dials.squish');
    }
  }

  String get longLabel {
    switch (this) {
      case _DialKind.gain:
        return LocalizationHelper.get('dials.gain_long');
      case _DialKind.speed:
        return LocalizationHelper.get('dials.speed_long');
      case _DialKind.sensitivity:
        return LocalizationHelper.get('dials.sensitivity_long');
      case _DialKind.squish:
        return LocalizationHelper.get('dials.squish_long');
    }
  }
}

class _SpectralHomePageState extends State<SpectralHomePage> with TickerProviderStateMixin {
  late final SignalController _controller;

  final List<double> _markers = [];
  bool _waterfallFocusMode = false;
  RangeValues _freqRange = const RangeValues(0, 22050);

  // The dial currently shown as a large edge dial: the one being dragged, or
  // failing that the one pinned by a tap.
  _DialKind? _pinnedDial;
  _DialKind? _draggingDial;
  _DialKind? get _activeDial => _draggingDial ?? _pinnedDial;

  // Logarithmic frequency distribution ("squish"), live-adjustable via its dial.
  // Initialized from the persisted frequency-skew setting.
  double _squish = 1.0;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _controller = SignalController(
      settings: widget.settings,
      isDemoMode: Uri.base.queryParameters['demo'] == 'true',
      playFile: Uri.base.queryParameters['play_file'],
    );
    _controller.addListener(_onControllerChanged);
    _syncFullRange(widget.settings);
    _squish = widget.settings.frequencySkew;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // Plugging a dongle in should visibly do something even when the app is
    // not already on the integrated source, otherwise the attach goes
    // unnoticed and the hardware looks unsupported.
    _driverStateSubscription =
        NativeSdrDriver().stateChanges.listen(_onSdrDriverStateChanged);
  }

  StreamSubscription<SdrDriverState>? _driverStateSubscription;

  void _onSdrDriverStateChanged(SdrDriverState state) {
    if (!mounted) return;
    final alreadyUsingDongle =
        widget.settings.signalSource == SignalSourceType.rf &&
            widget.settings.rfSource == RfSourceType.integrated;
    if (alreadyUsingDongle) return;
    if (state != SdrDriverState.ready &&
        state != SdrDriverState.needsPermission) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          LocalizationHelper.get('settings.sdr_driver.attached_prompt'),
        ),
        action: SnackBarAction(
          label: LocalizationHelper.get('settings.sdr_driver.use_it'),
          onPressed: _switchToIntegratedSource,
        ),
      ),
    );
  }

  /// Switches the app to the integrated USB source and brings the dongle up.
  void _switchToIntegratedSource() {
    final updated = widget.settings.copyWith(
      signalSource: SignalSourceType.rf,
      rfSource: RfSourceType.integrated,
    );
    widget.onSettingsChanged(updated);
    _controller.updateSettings(updated);
    setState(() => _syncFullRange(updated));
    unawaited(_controller.setupIntegratedDriver());
  }

  /// Keeps the capture pulse animation in sync with the controller's capture
  /// state and rebuilds discrete UI (header text, capture button) when it
  /// changes. Fired only on discrete changes, never per signal frame.
  void _onControllerChanged() {
    if (!mounted) return;
    // The captured span is only known once the source is up, which happens
    // asynchronously after construction.
    _syncFullRange(widget.settings);
    if (_controller.isCapturing) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      if (_pulseController.isAnimating) _pulseController.stop();
    }
    setState(() {});
  }

  /// The full band currently on screen: the whole captured RF span, or the
  /// audio band.
  ///
  /// The RF span comes from the controller rather than the settings, because
  /// the hardware may deliver less than was asked for — the RTL2832U caps at
  /// 3.2 MS/s. Labelling the axis with the requested width would spread the
  /// captured signal across a window several times too wide, which reads as a
  /// featureless smear rather than distinct stations.
  RangeValues _fullRangeForSettings(AppSettings settings) {
    if (settings.signalSource == SignalSourceType.rf) {
      final double center = settings.centerFrequency * 1e6;
      final double halfSpan = _controller.rfSpanHz / 2;
      return RangeValues(center - halfSpan, center + halfSpan);
    }
    return const RangeValues(0, 22050);
  }

  /// Span the visible axis was last built for, so the user's zoom selection is
  /// only reset when the underlying band actually changes.
  RangeValues? _lastFullRange;

  /// Rebuilds the axis if the captured band changed, preserving the user's
  /// selection otherwise. Also keeps the controller's tuned channel in step.
  void _syncFullRange(AppSettings settings) {
    final full = _fullRangeForSettings(settings);
    if (_lastFullRange == null ||
        (full.start - _lastFullRange!.start).abs() > 1 ||
        (full.end - _lastFullRange!.end).abs() > 1) {
      _lastFullRange = full;
      _freqRange = full;
      _controller.setTunedBand(full.start, full.end);
    }
  }

  Future<void> _toggleCapture() async {
    HapticFeedback.mediumImpact();
    await _controller.toggleCapture();
  }

  void _showSettings() {
    try {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: "Settings",
        pageBuilder: (context, _, __) => SettingsView(
          settings: widget.settings,
          onSetupSdrDriver: _controller.setupIntegratedDriver,
          onSettingsChanged: (newSettings) {
            final oldSource = widget.settings.signalSource;
            final oldFreq = widget.settings.centerFrequency;
            final oldBw = widget.settings.rfBandwidth;
            final oldPpm = widget.settings.ppmCorrection;
            final oldSkew = widget.settings.frequencySkew;

            widget.onSettingsChanged(newSettings);
            _controller.updateSettings(newSettings);

            // Keep the live "squish" dial in sync if the skew setting changed.
            if (oldSkew != newSettings.frequencySkew) {
              setState(() => _squish = newSettings.frequencySkew);
            }

            if (oldSource != newSettings.signalSource ||
                oldFreq != newSettings.centerFrequency ||
                oldBw != newSettings.rfBandwidth ||
                oldPpm != newSettings.ppmCorrection ||
                widget.settings.rfSource != newSettings.rfSource ||
                widget.settings.rtlTcpHost != newSettings.rtlTcpHost ||
                widget.settings.rtlTcpPort != newSettings.rtlTcpPort) {
              _controller.reconfigure(newSettings: newSettings);
              setState(() => _syncFullRange(newSettings));
            }

            if (!newSettings.peakHoldEnabled) {
              _controller.clearPeakHold();
            }
          },
        ),
      );
    } catch (e) {
      debugPrint("Error showing settings: $e");
    }
  }

  void _handleFftTap(Offset localOffset, Size size) {
    final freq = _screenOffsetToFreq(localOffset.dx, size.width);
    setState(() {
      // Find and remove if close (within a small frequency epsilon or visual range)
      final double epsilon = (_freqRange.end - _freqRange.start) * 0.02;
      int existingIndex = -1;
      for (int i = 0; i < _markers.length; i++) {
        if ((_markers[i] - freq).abs() < epsilon) {
          existingIndex = i;
          break;
        }
      }

      if (existingIndex != -1) {
        _markers.removeAt(existingIndex);
      } else {
        if (_markers.length >= 3) _markers.removeAt(0);
        _markers.add(freq);
        HapticFeedback.selectionClick();
      }
    });
  }

  double _screenOffsetToFreq(double x, double width) {
    final double t = FrequencyScale.toData(x / width, _squish);
    return _freqRange.start + (_freqRange.end - _freqRange.start) * t;
  }

  @override
  void dispose() {
    _driverStateSubscription?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.secondary;
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final useTabletLayout = isTablet && isLandscape;

    return Scaffold(
      body: Stack(
        children: [
          // Background Liquid Gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.8, -0.6),
                  radius: 1.5,
                  colors: [widget.backgroundColor, Colors.black],
                ),
              ),
            ),
          ),

          // Waterfall Background
          Positioned.fill(
            child: Opacity(
              opacity: _waterfallFocusMode ? 1.0 : 0.4,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller.frame,
                  builder: (context, _) => CustomPaint(
                    size: Size.infinite,
                    painter: WaterfallPainter(
                      fftHistory: _controller.fftHistory,
                      minFreq: _freqRange.start,
                      maxFreq: _freqRange.end,
                      sampleRate: _controller.sampleRate,
                      theme: widget.settings.theme,
                      frequencySkew: _squish,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Scanline Overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.05),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                ),
              ),
            ),
          ),

          // Main Content Layout
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Builder(
                      builder: (context) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Top Minimalist Header
                            _buildMinimalHeader(isLandscape),
                            SizedBox(height: isLandscape ? 12 : 20),

                            if (_waterfallFocusMode) const Spacer(),

                            // Visualizations
                            if (!_waterfallFocusMode)
                              Expanded(
                                flex: 5,
                                child: isLandscape
                                    ? Row(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: _buildGlassCard(
                                              child: SizedBox.expand(
                                                child: RepaintBoundary(
                                                  child: AnimatedBuilder(
                                                    animation: _controller.frame,
                                                    builder: (context, _) => CustomPaint(
                                                      size: Size.infinite,
                                                      painter: WaveformPainter(
                                                        audioData: _controller.currentAudioData,
                                                        history: _controller.audioHistory,
                                                        color: Colors.white.withOpacity(0.8),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: _buildFftCard(accentColor),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: _buildGlassCard(
                                              child: SizedBox.expand(
                                                child: RepaintBoundary(
                                                  child: AnimatedBuilder(
                                                    animation: _controller.frame,
                                                    builder: (context, _) => CustomPaint(
                                                      size: Size.infinite,
                                                      painter: WaveformPainter(
                                                        audioData: _controller.currentAudioData,
                                                        history: _controller.audioHistory,
                                                        color: Colors.white.withOpacity(0.8),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Expanded(
                                            flex: 3,
                                            child: _buildFftCard(accentColor),
                                          ),
                                        ],
                                      ),
                              ),
                            if (!_waterfallFocusMode) SizedBox(height: isLandscape ? 12 : 16),

                            // Frequency Focus Card & Interaction Bar
                            if (isLandscape && !_waterfallFocusMode)
                              Row(
                                children: [
                                  // Gain/Speed stacked (left edge style).
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildDialTriggerFor(_DialKind.gain),
                                      const SizedBox(height: 10),
                                      _buildDialTriggerFor(_DialKind.speed),
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildGlassCard(child: _buildFrequencyFocusSlider())),
                                  const SizedBox(width: 16),
                                  // Squish/Sensitivity stacked (right edge style).
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildDialTriggerFor(_DialKind.squish),
                                      const SizedBox(height: 10),
                                      _buildDialTriggerFor(_DialKind.sensitivity),
                                    ],
                                  ),
                                ],
                              )
                            else ...[
                              _buildGlassCard(child: _buildFrequencyFocusSlider()),
                              if (!_waterfallFocusMode) ...[
                                const SizedBox(height: 16),
                                _buildInteractionBar(),
                              ],
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
                if (useTabletLayout)
                  Container(
                    width: 350,
                    margin: const EdgeInsets.only(right: 20, top: 10, bottom: 10),
                    child: _buildGlassCard(
                      child: SettingsContent(
                        settings: widget.settings,
                        onSettingsChanged: widget.onSettingsChanged,
                        onSetupSdrDriver: _controller.setupIntegratedDriver,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Large Edge Dial (one at a time): the active dial slides in from its
          // edge — Gain/Speed on the left, Sensitivity/Squish on the right.
          if (_activeDial != null)
            EdgeDial(
              isLeft: _activeDial!.isLeft,
              value: _dialValue(_activeDial!),
              label: _activeDial!.longLabel,
              color: accentColor,
              onChanged: (v) => _setDialValue(_activeDial!, v),
            ),
        ],
      ),
    );
  }

  Widget _buildFftCard(Color accentColor) {
    return LayoutBuilder(builder: (context, constraints) {
      return GestureDetector(
        onTapDown: (details) => _handleFftTap(details.localPosition, constraints.biggest),
        child: _buildGlassCard(
          child: SizedBox.expand(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller.frame,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: FftBarChartPainter(
                    fftData: _controller.currentFftData,
                    peakHoldData: widget.settings.peakHoldEnabled ? _controller.peakHoldBuffer : null,
                    markers: _markers,
                    showHarmonics: widget.settings.showHarmonics,
                    fundamentalFreq: _controller.detectedTone?.frequency,
                    snrValue: widget.settings.showSnr ? _controller.snr : null,
                    color: accentColor,
                    minFreq: _freqRange.start,
                    maxFreq: _freqRange.end,
                    sampleRate: _controller.sampleRate,
                    frequencySkew: _squish,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildMinimalHeader(bool isLandscape) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "SPECTRAL ANALYSIS",
              style: TextStyle(fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.w900, color: Colors.white24),
            ),
            Text(
              _controller.isCapturing ? "LIVE SIGNAL" : "SIGNAL IDLE",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.8)),
            ),
          ],
        ),
        const Spacer(),
        if (isLandscape) ...[
          Semantics(
            label: "Capture Toggle",
            button: true,
            child: _buildHeaderAction(
              icon: _controller.isCapturing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              onPressed: _toggleCapture,
              iconColor: _controller.isCapturing ? Colors.redAccent : Colors.white70,
              iconSize: 24,
            ),
          ),
          const SizedBox(width: 12),
        ],
        if (!isLandscape || MediaQuery.of(context).size.shortestSide < 600)
          Semantics(
            label: "Settings",
            button: true,
            child: _buildHeaderAction(icon: Icons.tune_rounded, onPressed: _showSettings),
          ),
        const SizedBox(width: 12),
        Semantics(
          label: "Toggle Focus",
          button: true,
          child: _buildHeaderAction(
            icon: _waterfallFocusMode ? Icons.layers : Icons.layers_outlined,
            onPressed: () => setState(() => _waterfallFocusMode = !_waterfallFocusMode),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderAction({
    required IconData icon,
    required VoidCallback onPressed,
    Color? iconColor,
    double? iconSize,
  }) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: IconButton(
            icon: Icon(icon, size: iconSize ?? 20, color: iconColor ?? Colors.white70),
            onPressed: () {
              HapticFeedback.lightImpact();
              onPressed();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }

  /// Builds the detected-tone label widgets shown above the focus slider.
  /// Recomputed per frame (via the ticker) so it tracks the live signal.
  List<Widget> _buildToneLabelWidgets() {
    if (_controller.detectedTone == null) {
      return [
        Text(
          LocalizationHelper.get('dials.focus'),
          style: const TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              color: Colors.white24,
              fontWeight: FontWeight.bold),
        ),
      ];
    }

    final t = _controller.detectedTone!;
    final freqStr = FrequencyFormatter.format(t.frequency, shortUnit: true);
    return [
      SizedBox(
        width: 52,
        child: Text(
          freqStr,
          textAlign: TextAlign.right,
          style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              color: Colors.white24,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
      const Text(" • ", style: TextStyle(fontSize: 10, color: Colors.white10)),
      SizedBox(
        width: 28,
        child: Text(
          t.note,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              color: Colors.white24,
              fontWeight: FontWeight.bold),
        ),
      ),
      if (t.harmonics.isNotEmpty) ...[
        const Text(" • ", style: TextStyle(fontSize: 10, color: Colors.white10)),
        Text(
          "H: ${t.harmonics.join(', ')}",
          style: const TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              color: Colors.white24,
              fontWeight: FontWeight.bold),
        ),
      ],
    ];
  }

  Widget _buildFrequencyFocusSlider() {
    final accentColor = Theme.of(context).colorScheme.secondary;
    final fullRange = _fullRangeForSettings(widget.settings);

    // Report the *selected* window rather than the whole band: on RF that is
    // the slice being demodulated, so it is the number the user is tuning.
    final bool isRf = widget.settings.signalSource == SignalSourceType.rf;
    final rangeText = isRf
        ? "${FrequencyFormatter.format(_freqRange.start, precision: 3)} - "
            "${FrequencyFormatter.format(_freqRange.end, precision: 3)}"
        : "${FrequencyFormatter.format(_freqRange.start)} - "
            "${FrequencyFormatter.format(_freqRange.end)}";

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: AnimatedBuilder(
                  animation: _controller.frame,
                  builder: (context, _) => Row(
                    children: _buildToneLabelWidgets(),
                  ),
                ),
              ),
            ),
            Flexible(
              child: Text(
                rangeText,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        RadioDialFocusSlider(
          values: _freqRange,
          min: fullRange.start,
          max: fullRange.end,
          onChanged: (values) {
            setState(() => _freqRange = values);
            // Tuning the visible window also tunes what is demodulated.
            _controller.setTunedBand(values.start, values.end);
          },
          accentColor: accentColor,
        ),
      ],
    );
  }

  Widget _buildInteractionBar() {
    // Speed sits next to Gain (left), Squish next to Sensitivity (right).
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildDialTriggerFor(_DialKind.gain),
        _buildDialTriggerFor(_DialKind.speed),
        _buildCaptureButton(),
        _buildDialTriggerFor(_DialKind.squish),
        _buildDialTriggerFor(_DialKind.sensitivity),
      ],
    );
  }

  double _dialValue(_DialKind d) {
    switch (d) {
      case _DialKind.gain:
        return _controller.gain;
      case _DialKind.speed:
        return _controller.waterfallSpeed;
      case _DialKind.sensitivity:
        return _controller.sensitivity;
      case _DialKind.squish:
        return _squish;
    }
  }

  void _setDialValue(_DialKind d, double v) {
    setState(() {
      switch (d) {
        case _DialKind.gain:
          _controller.gain = v;
          break;
        case _DialKind.speed:
          _controller.waterfallSpeed = v;
          break;
        case _DialKind.sensitivity:
          _controller.sensitivity = v;
          break;
        case _DialKind.squish:
          _squish = v;
          break;
      }
    });
  }

  Widget _buildDialTriggerFor(_DialKind d) {
    return Semantics(
      label: d.shortLabel,
      button: true,
      child: DialTrigger(
        id: d.keyId,
        label: d.shortLabel,
        value: _dialValue(d),
        onChanged: (v) => _setDialValue(d, v),
        onActive: (active) => setState(() => _draggingDial = active ? d : null),
        onTap: () => setState(() => _pinnedDial = _pinnedDial == d ? null : d),
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _toggleCapture,
      child: Semantics(
        label: "Capture Toggle",
        button: true,
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _controller.isCapturing ? Colors.red.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                border: Border.all(color: _controller.isCapturing ? Colors.red.withOpacity(0.5) : Colors.white24, width: 2),
                boxShadow: [
                  if (_controller.isCapturing)
                    BoxShadow(color: Colors.red.withOpacity(0.2), blurRadius: 10 + 10 * _pulseController.value)
                ],
              ),
              child: Icon(
                _controller.isCapturing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: _controller.isCapturing ? Colors.redAccent : Colors.white,
                size: 32,
              ),
            );
          },
        ),
      ),
    );
  }

}
