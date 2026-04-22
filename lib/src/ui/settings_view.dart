import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/settings_model.dart';
import '../rf/native_sdr_driver.dart';
import '../utils/localization_helper.dart';

class SettingsView extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  const SettingsView({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late AppSettings _currentSettings;

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.settings;
  }

  void _updateSettings(AppSettings newSettings) {
    HapticFeedback.lightImpact();
    setState(() {
      _currentSettings = newSettings;
    });
    widget.onSettingsChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background Blur
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(color: Colors.black.withOpacity(0.4)),
            ),
          ),

          // Settings Card
          Center(
            child: Container(
              width: isLandscape
                  ? MediaQuery.of(context).size.width * 0.6
                  : MediaQuery.of(context).size.width * 0.85,
              constraints: BoxConstraints(
                maxHeight: isLandscape
                    ? MediaQuery.of(context).size.height * 0.9
                    : MediaQuery.of(context).size.height * 0.75,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 40,
                    spreadRadius: 10,
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: SettingsContent(
                    settings: _currentSettings,
                    onSettingsChanged: _updateSettings,
                    showCloseButton: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsContent extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final bool showCloseButton;

  const SettingsContent({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    this.showCloseButton = false,
  });

  @override
  State<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<SettingsContent> {
  late final TextEditingController _freqController;
  late final TextEditingController _bwController;
  late final TextEditingController _rtlHostController;
  late final TextEditingController _rtlPortController;
  late final TextEditingController _ppmController;

  @override
  void initState() {
    super.initState();
    _freqController = TextEditingController(text: widget.settings.centerFrequency.toString());
    _bwController = TextEditingController(text: widget.settings.rfBandwidth.toString());
    _rtlHostController = TextEditingController(text: widget.settings.rtlTcpHost);
    _rtlPortController = TextEditingController(text: widget.settings.rtlTcpPort.toString());
    _ppmController = TextEditingController(text: widget.settings.ppmCorrection.toString());
  }

  @override
  void didUpdateWidget(SettingsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.settings.centerFrequency != double.tryParse(_freqController.text)) {
      _freqController.text = widget.settings.centerFrequency.toString();
    }
    if (widget.settings.rfBandwidth != double.tryParse(_bwController.text)) {
      _bwController.text = widget.settings.rfBandwidth.toString();
    }
    if (widget.settings.rtlTcpHost != _rtlHostController.text) {
      _rtlHostController.text = widget.settings.rtlTcpHost;
    }
    if (widget.settings.rtlTcpPort != int.tryParse(_rtlPortController.text)) {
      _rtlPortController.text = widget.settings.rtlTcpPort.toString();
    }
    if (widget.settings.ppmCorrection != double.tryParse(_ppmController.text)) {
      _ppmController.text = widget.settings.ppmCorrection.toString();
    }
  }

  @override
  void dispose() {
    _freqController.dispose();
    _bwController.dispose();
    _rtlHostController.dispose();
    _rtlPortController.dispose();
    _ppmController.dispose();
    super.dispose();
  }

  void _updateSettings(AppSettings newSettings) {
    widget.onSettingsChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 32),

          // Section 1: Mode
          _buildSectionTitle(LocalizationHelper.get('settings.mode')),
          const SizedBox(height: 12),
          _buildDropdown<SignalSourceType>(
            label: LocalizationHelper.get('settings.signal_source'),
            tooltip: LocalizationHelper.get('settings.tooltips.signal_source'),
            value: widget.settings.signalSource,
            items: SignalSourceType.values,
            itemLabel: (type) => LocalizationHelper.get('settings.signal_sources.${type.name}'),
            onChanged: (val) {
              if (val != null) _updateSettings(widget.settings.copyWith(signalSource: val));
            },
          ),

          const SizedBox(height: 32),
          // Section 2: Language
          _buildSectionTitle(LocalizationHelper.get('settings.language')),
          const SizedBox(height: 12),
          _buildDropdown<String>(
            label: LocalizationHelper.get('settings.language'),
            tooltip: LocalizationHelper.get('settings.tooltips.language'),
            value: widget.settings.language,
            items: ['en', 'zh', 'ja', 'fr', 'de', 'it', 'es', 'gl', 'pt', 'ca', 'eu'],
            itemLabel: (lang) {
              switch (lang) {
                case 'en': return 'English';
                case 'zh': return '中文 (Chinese)';
                case 'ja': return '日本語 (Japanese)';
                case 'fr': return 'Français (French)';
                case 'de': return 'Deutsch (German)';
                case 'it': return 'Italiano (Italian)';
                case 'es': return 'Español (Spanish)';
                case 'gl': return 'Galego (Galician)';
                case 'pt': return 'Português (Portuguese)';
                case 'ca': return 'Català (Catalan)';
                case 'eu': return 'Euskara (Basque)';
                default: return lang;
              }
            },
            onChanged: (val) async {
              if (val != null) {
                await LocalizationHelper.load(val);
                _updateSettings(widget.settings.copyWith(language: val));
              }
            },
          ),

          const SizedBox(height: 32),
          // Section 3: Theme
          _buildSectionTitle(LocalizationHelper.get('settings.theme')),
          const SizedBox(height: 12),
          _buildThemeSelector(),
          // Add a tooltip helper for themes if needed, but theme selector is a wrap of buttons.
          // The prompt says "various settings", so we'll skip theme selector for now unless it's easy.

          // SDR Specific Settings (Only visible in RF mode)
          if (widget.settings.signalSource == SignalSourceType.rf) ...[
            const SizedBox(height: 32),
            _buildSectionTitle("SDR CONFIGURATION"),
            const SizedBox(height: 16),
            _buildDropdown<RfSourceType>(
              label: LocalizationHelper.get('settings.rf_source'),
              tooltip: LocalizationHelper.get('settings.tooltips.rf_source'),
              value: widget.settings.rfSource,
              items: RfSourceType.values,
              itemLabel: (type) => LocalizationHelper.get('settings.rf_sources.${type.name}'),
              onChanged: (val) {
                if (val != null) _updateSettings(widget.settings.copyWith(rfSource: val));
              },
            ),
            const SizedBox(height: 16),
            _buildDropdown<DemodulationMode>(
              label: LocalizationHelper.get('settings.demodulation_mode'),
              tooltip: LocalizationHelper.get('settings.tooltips.demodulation_mode'),
              value: widget.settings.demodulationMode,
              items: DemodulationMode.values,
              itemLabel: (mode) => LocalizationHelper.get('settings.demodulation_modes.${mode.name}'),
              onChanged: (val) {
                if (val != null) _updateSettings(widget.settings.copyWith(demodulationMode: val));
              },
            ),
            const SizedBox(height: 16),
            _buildSwitch(
              label: LocalizationHelper.get('settings.audio_output'),
              tooltip: LocalizationHelper.get('settings.tooltips.audio_output'),
              value: widget.settings.audioOutputEnabled,
              onChanged: (val) => _updateSettings(widget.settings.copyWith(audioOutputEnabled: val)),
            ),
            if (widget.settings.rfSource == RfSourceType.integrated) ...[
              const SizedBox(height: 12),
              _buildDriverStatus(),
            ],
            if (widget.settings.rfSource == RfSourceType.rtlTcp) ...[
              const SizedBox(height: 16),
              _buildTextField(
                label: LocalizationHelper.get('settings.rtl_tcp_host'),
                tooltip: LocalizationHelper.get('settings.tooltips.rtl_tcp_host'),
                controller: _rtlHostController,
                onChanged: (val) {
                  _updateSettings(widget.settings.copyWith(rtlTcpHost: val));
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                label: LocalizationHelper.get('settings.rtl_tcp_port'),
                tooltip: LocalizationHelper.get('settings.tooltips.rtl_tcp_port'),
                controller: _rtlPortController,
                onChanged: (val) {
                  final int? port = int.tryParse(val);
                  if (port != null) _updateSettings(widget.settings.copyWith(rtlTcpPort: port));
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      _rtlPortController.text = "14423";
                      _updateSettings(widget.settings.copyWith(rtlTcpPort: 14423));
                    },
                    icon: const Icon(Icons.flash_on_rounded, size: 14),
                    label: const Text("Use 14423 (SDR Driver App)", style: TextStyle(fontSize: 10)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _buildTextField(
              label: LocalizationHelper.get('settings.center_frequency'),
              tooltip: LocalizationHelper.get('settings.tooltips.center_frequency'),
              controller: _freqController,
              onChanged: (val) {
                final double? freq = double.tryParse(val);
                if (freq != null) _updateSettings(widget.settings.copyWith(centerFrequency: freq));
              },
            ),
            const SizedBox(height: 16),
            _buildTextField(
              label: LocalizationHelper.get('settings.rf_bandwidth'),
              tooltip: LocalizationHelper.get('settings.tooltips.rf_bandwidth'),
              controller: _bwController,
              onChanged: (val) {
                final double? bw = double.tryParse(val);
                if (bw != null) _updateSettings(widget.settings.copyWith(rfBandwidth: bw));
              },
            ),
            const SizedBox(height: 16),
            _buildTextField(
              label: LocalizationHelper.get('settings.ppm_correction'),
              tooltip: LocalizationHelper.get('settings.tooltips.ppm_correction'),
              controller: _ppmController,
              onChanged: (val) {
                final double? ppm = double.tryParse(val);
                if (ppm != null) _updateSettings(widget.settings.copyWith(ppmCorrection: ppm));
              },
            ),
          ],

          const SizedBox(height: 32),
          _buildSectionTitle(LocalizationHelper.get('settings.analysis')),
          const SizedBox(height: 16),
          _buildSwitch(
            label: LocalizationHelper.get('settings.peak_hold'),
            tooltip: LocalizationHelper.get('settings.tooltips.peak_hold'),
            value: widget.settings.peakHoldEnabled,
            onChanged: (val) => _updateSettings(widget.settings.copyWith(peakHoldEnabled: val)),
          ),
          const SizedBox(height: 16),
          _buildDropdown<FftAveragingMode>(
            label: LocalizationHelper.get('settings.averaging_mode'),
            tooltip: LocalizationHelper.get('settings.tooltips.averaging_mode'),
            value: widget.settings.fftAveragingMode,
            items: FftAveragingMode.values,
            itemLabel: (type) => LocalizationHelper.get('settings.averaging_modes.${type.name}'),
            onChanged: (val) {
              if (val != null) _updateSettings(widget.settings.copyWith(fftAveragingMode: val));
            },
          ),
          const SizedBox(height: 16),
          _buildSlider(
            label: LocalizationHelper.get('settings.averaging_count'),
            tooltip: LocalizationHelper.get('settings.tooltips.averaging_count'),
            value: widget.settings.fftAveragingCount.toDouble(),
            min: 2,
            max: 50,
            onChanged: (val) => _updateSettings(widget.settings.copyWith(fftAveragingCount: val.toInt())),
          ),
          const SizedBox(height: 16),
          _buildSwitch(
            label: LocalizationHelper.get('settings.show_harmonics'),
            tooltip: LocalizationHelper.get('settings.tooltips.show_harmonics'),
            value: widget.settings.showHarmonics,
            onChanged: (val) => _updateSettings(widget.settings.copyWith(showHarmonics: val)),
          ),
          const SizedBox(height: 16),
          _buildSwitch(
            label: LocalizationHelper.get('settings.show_snr'),
            tooltip: LocalizationHelper.get('settings.tooltips.show_snr'),
            value: widget.settings.showSnr,
            onChanged: (val) => _updateSettings(widget.settings.copyWith(showSnr: val)),
          ),

          const SizedBox(height: 32),
          _buildSectionTitle(LocalizationHelper.get('settings.technical')),
          const SizedBox(height: 16),
          _buildDropdown<int>(
            label: LocalizationHelper.get('settings.fft_window_size'),
            tooltip: LocalizationHelper.get('settings.tooltips.fft_window_size'),
            value: widget.settings.fftWindowSize,
            items: [512, 1024, 2048, 4096],
            onChanged: (val) {
              if (val != null) _updateSettings(widget.settings.copyWith(fftWindowSize: val));
            },
          ),
          const SizedBox(height: 16),
          _buildDropdown<FftWindowType>(
            label: LocalizationHelper.get('settings.fft_window_type'),
            tooltip: LocalizationHelper.get('settings.tooltips.fft_window_type'),
            value: widget.settings.fftWindowType,
            items: FftWindowType.values,
            itemLabel: (type) => LocalizationHelper.get('settings.window_types.${type.name}'),
            onChanged: (val) {
              if (val != null) _updateSettings(widget.settings.copyWith(fftWindowType: val));
            },
          ),
          const SizedBox(height: 16),
          _buildSlider(
            label: LocalizationHelper.get('settings.frequency_skew'),
            tooltip: LocalizationHelper.get('settings.tooltips.frequency_skew'),
            value: widget.settings.frequencySkew,
            min: 0.2,
            max: 3.0,
            onChanged: (val) => _updateSettings(widget.settings.copyWith(frequencySkew: val)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.tune_rounded, color: Colors.white70, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            LocalizationHelper.get('settings.title').toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.showCloseButton) ...[
          const Spacer(),
          Semantics(
            label: "Close Settings",
            button: true,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white54),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionTitle(String title, {String? tooltip}) {
    return _buildLabelWithTooltip(title.toUpperCase(), tooltip, isTitle: true);
  }

  Widget _buildThemeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AppTheme.values.map((t) {
        final isSelected = widget.settings.theme == t;
        final themeLabel = LocalizationHelper.get('settings.themes.${t.name}');
        return Semantics(
          label: themeLabel,
          button: true,
          selected: isSelected,
          child: GestureDetector(
            onTap: () => _updateSettings(widget.settings.copyWith(theme: t)),
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.white.withOpacity(0.3) : Colors.white.withOpacity(0.05),
              ),
            ),
              child: Text(
                themeLabel,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDriverStatus() {
    final bool isReady = NativeSdrDriver().isInitialized;
    return GestureDetector(
      onTap: isReady
          ? null
          : () async {
              HapticFeedback.mediumImpact();
              final success = await NativeSdrDriver().initialize();
              if (success) {
                if (mounted) setState(() {});
                // Trigger a refresh in the parent to re-init source
                widget.onSettingsChanged(widget.settings);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Failed to initialize SDR driver. Ensure no other app is using the module."),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isReady ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isReady ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(
              isReady ? Icons.check_circle_outline : Icons.info_outline,
              size: 16,
              color: isReady ? Colors.greenAccent : Colors.orangeAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isReady ? "Driver Ready" : "Driver Setup Required",
                style: TextStyle(
                  color: isReady ? Colors.greenAccent : Colors.orangeAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (!isReady)
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: Colors.orangeAccent,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabelWithTooltip(String label, String? tooltip, {bool isTitle = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            style: isTitle
                ? const TextStyle(
                    color: Colors.white24,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  )
                : const TextStyle(color: Colors.white54, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (tooltip != null) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: tooltip,
            triggerMode: TooltipTriggerMode.tap,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            showDuration: const Duration(seconds: 3),
            preferBelow: false,
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E).withOpacity(0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ],
            ),
            textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.4,
            ),
            child: Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    String Function(T)? itemLabel,
    required ValueChanged<T?> onChanged,
    String? tooltip,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelWithTooltip(label, tooltip),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items.map((item) {
                return DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    itemLabel?.call(item) ?? item.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
              dropdownColor: const Color(0xFF1C1C1E),
              icon: const Icon(Icons.expand_more_rounded, color: Colors.white54),
              isExpanded: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? tooltip,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelWithTooltip(label, tooltip),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(border: InputBorder.none),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String? tooltip,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: _buildLabelWithTooltip(label, tooltip)),
            Text(value.toStringAsFixed(2), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: (val) {
            if ((val * 10).floor() != (value * 10).floor()) {
              HapticFeedback.selectionClick();
            }
            onChanged(val);
          },
          activeColor: Theme.of(context).colorScheme.secondary,
          inactiveColor: Colors.white.withOpacity(0.05),
        ),
      ],
    );
  }

  Widget _buildSwitch({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? tooltip,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: _buildLabelWithTooltip(label, tooltip)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Theme.of(context).colorScheme.secondary,
        ),
      ],
    );
  }
}
