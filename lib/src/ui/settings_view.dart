import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/settings_model.dart';
import '../utils/localization_helper.dart';

class SettingsView extends StatelessWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  const SettingsView({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background Blur
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(color: Colors.black.withOpacity(0.4)),
            ),
          ),

          // Settings Card
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
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
                          value: settings.fftWindowSize,
                          items: [512, 1024, 2048, 4096],
                          onChanged: (val) {
                            if (val != null) onSettingsChanged(settings.copyWith(fftWindowSize: val));
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildDropdown<FftWindowType>(
                          label: LocalizationHelper.get('settings.fft_window_type'),
                          value: settings.fftWindowType,
                          items: FftWindowType.values,
                          itemLabel: (type) => LocalizationHelper.get('settings.window_types.${type.name}'),
                          onChanged: (val) {
                            if (val != null) onSettingsChanged(settings.copyWith(fftWindowType: val));
                          },
                        ),

                        const SizedBox(height: 32),
                        _buildSectionTitle(LocalizationHelper.get('settings.language')),
                        const SizedBox(height: 12),
                        _buildDropdown<String>(
                          label: LocalizationHelper.get('settings.language'),
                          value: settings.language,
                          items: ['en'],
                          itemLabel: (lang) => lang == 'en' ? 'English' : lang,
                          onChanged: (val) {
                             if (val != null) onSettingsChanged(settings.copyWith(language: val));
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
        IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white54),
          onPressed: () => Navigator.of(context).pop(),
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
      spacing: 12,
      runSpacing: 12,
      children: AppTheme.values.map((t) {
        final isSelected = settings.theme == t;
        return GestureDetector(
          onTap: () => onSettingsChanged(settings.copyWith(theme: t)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.white.withOpacity(0.3) : Colors.white.withOpacity(0.05),
              ),
            ),
            child: Text(
              LocalizationHelper.get('settings.themes.${t.name}'),
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
}
