import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguageProvider extends ChangeNotifier {
  Locale _appLocale = const Locale('en');

  Locale get appLocale => _appLocale;

  AppLanguageProvider() {
    _fetchLocale();
  }

  void changeLanguage(Locale type) async {
    var prefs = await SharedPreferences.getInstance();
    if (_appLocale == type) {
      return;
    }

    _appLocale = type;
    // Save both formats for compatibility
    await prefs.setString('language_code', type.toString());
    await prefs.setString('language', type.languageCode); // For API client
    notifyListeners();
  }

  void _fetchLocale() async {
    var prefs = await SharedPreferences.getInstance();
    String? languageCode = prefs.getString('language_code');
    if (languageCode == null) {
      _appLocale = const Locale('en');
    } else {
      List<String> parts = languageCode.split('_');
      if (parts.length > 1) {
        _appLocale = Locale(parts[0], parts[1]);
      } else {
        _appLocale = Locale(languageCode);
      }
    }
    notifyListeners();
  }
}
