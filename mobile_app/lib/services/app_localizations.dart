import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  late Map<String, String> _localizedStrings;

  Future<bool> load() async {
    String fileName = locale.languageCode;
    if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
      fileName = '${locale.languageCode}_${locale.countryCode}';
    }

    String jsonString = await rootBundle.loadString(
      'assets/translations/$fileName.json',
    );
    Map<String, dynamic> jsonMap = json.decode(jsonString);

    _localizedStrings = _flattenMap(jsonMap);
    return true;
  }

  Map<String, String> _flattenMap(
    Map<String, dynamic> map, [
    String prefix = '',
  ]) {
    Map<String, String> flattened = {};
    map.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        flattened.addAll(_flattenMap(value, '$prefix$key.'));
      } else {
        flattened['$prefix$key'] = value.toString();
      }
    });
    return flattened;
  }

  String? translate(String key, {Map<String, dynamic>? arguments}) {
    String? translation = _localizedStrings[key];
    if (translation == null) return null;

    if (arguments != null) {
      arguments.forEach((argKey, argValue) {
        translation = translation!.replaceAll('{$argKey}', argValue.toString());
      });
    }
    return translation;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return [
      'en',
      'hi',
    ].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    AppLocalizations localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
