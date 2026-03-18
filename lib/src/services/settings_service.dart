import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/settings_model.dart';

class SettingsService {
  static const String _kSettingsKey = 'app_settings';

  static Future<AppSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_kSettingsKey);
      if (settingsJson != null) {
        final Map<String, dynamic> settingsMap = json.decode(settingsJson);
        return AppSettings.fromMap(settingsMap);
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
    }
    return const AppSettings();
  }

  static Future<void> saveSettings(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = json.encode(settings.toMap());
      await prefs.setString(_kSettingsKey, settingsJson);
    } catch (e) {
      debugPrint("Error saving settings: $e");
    }
  }
}
