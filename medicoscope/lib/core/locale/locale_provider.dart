import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const String _localeKey = 'app_language';
  String _languageCode = 'en';

  static const Map<String, String> supportedLanguages = {
    'en': 'English',
    'hi': 'हिन्दी',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
    'mr': 'मराठी',
    'bn': 'বাংলা',
    'kn': 'ಕನ್ನಡ',
  };

  LocaleProvider() {
    _loadLocale();
  }

  String get languageCode => _languageCode;
  Locale get locale => Locale(_languageCode);

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    _languageCode = prefs.getString(_localeKey) ?? 'en';
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    if (!supportedLanguages.containsKey(code)) return;
    _languageCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, code);
  }
}
