import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LocalizationHelper {
  static Map<String, dynamic> _localizedStrings = {};

  static Future<void> load(String locale, [AssetBundle? bundle]) async {
    try {
      final String jsonString = await (bundle ?? rootBundle).loadString('resources/locales/$locale.json');
      _localizedStrings = json.decode(jsonString);
    } catch (e) {
      debugPrint("Error loading localization: $e");
      _localizedStrings = {};
    }
  }

  static String get(String key) {
    final keys = key.split('.');
    dynamic current = _localizedStrings;
    for (var k in keys) {
      if (current is Map && current.containsKey(k)) {
        current = current[k];
      } else {
        return key; // Return the key itself as a fallback
      }
    }
    return current.toString();
  }
}
