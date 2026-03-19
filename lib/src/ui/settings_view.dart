import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/settings_model.dart';
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 32),

                        _buildSectionTitle(LocalizationHelper.get('settings.theme')),
                        const SizedBox(height: 12),
                        _buildThemeSelector(),

                        const SizedBox(height: 32),
                        _buildSectionTitle(LocalizationHelper.get('settings.technical')),
                        const SizedBox(height: 16),
                        _buildDropdown<int>(
                          label: LocalizationHelper.get('settings.fft_window_size'),
                          value: _currentSettings.fftWindowSize,
                          items: [512, 1024, 2048, 4096],
                          onChanged: (val) {
                            if (val != null) _updateSettings(_currentSettings.copyWith(fftWindowSize: val));
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildDropdown<FftWindowType>(
                          label: LocalizationHelper.get('settings.fft_window_type'),
                          value: _currentSettings.fftWindowType,
                          items: FftWindowType.values,
                          itemLabel: (type) => LocalizationHelper.get('settings.window_types.${type.name}'),
                          onChanged: (val) {
                            if (val != null) _updateSettings(_currentSettings.copyWith(fftWindowType: val));
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildSlider(
                          label: LocalizationHelper.get('settings.frequency_skew'),
                          value: _currentSettings.frequencySkew,
                          min: 0.2,
                          max: 3.0,
                          onChanged: (val) => _updateSettings(_currentSettings.copyWith(frequencySkew: val)),
                        ),
                        const SizedBox(height: 16),
                        _buildSlider(
                          label: LocalizationHelper.get('settings.fft_smoothing'),
                          value: _currentSettings.fftSmoothing,
                          min: 0.0,
                          max: 0.95,
                          onChanged: (val) => _updateSettings(_currentSettings.copyWith(fftSmoothing: val)),
                        ),

                        const SizedBox(height: 32),
                        _buildSectionTitle(LocalizationHelper.get('settings.language')),
                        const SizedBox(height: 12),
                        _buildDropdown<String>(
                          label: LocalizationHelper.get('settings.language'),
                          value: _currentSettings.language,
                          items: ['en'],
                          itemLabel: (lang) => lang == 'en' ? 'English' : lang,
                          onChanged: (val) {
                             if (val != null) _updateSettings(_currentSettings.copyWith(language: val));
                          },
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.tune_rounded, color: Colors.white70, size: 24),
        const SizedBox(width: 12),
        Text(
          LocalizationHelper.get('settings.title').toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
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
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white24,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildThemeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AppTheme.values.map((t) {
        final isSelected = _currentSettings.theme == t;
        final themeLabel = LocalizationHelper.get('settings.themes.${t.name}');
        return Semantics(
          label: themeLabel,
          button: true,
          selected: isSelected,
          child: GestureDetector(
            onTap: () => _updateSettings(_currentSettings.copyWith(theme: t)),
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

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    String Function(T)? itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
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

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
}
