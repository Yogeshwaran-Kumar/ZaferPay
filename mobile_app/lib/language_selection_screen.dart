import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'services/app_language_provider.dart';
import 'services/app_localizations.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  final List<Map<String, String>> _languages = [
    {'name': 'English', 'localName': 'English', 'code': 'en'},
    {'name': 'Hindi', 'localName': 'हिन्दी', 'code': 'hi'},
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final languageProvider = Provider.of<AppLanguageProvider>(context);
    final locale = languageProvider.appLocale;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF111318) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)?.translate('select_language') ??
              'Select language',
          style: GoogleFonts.notoSans(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              itemCount: _languages.length,
              separatorBuilder: (context, index) => Divider(
                color: isDark
                    ? Colors.white10
                    : Colors.grey.withValues(alpha: 0.1),
                height: 1,
              ),
              itemBuilder: (context, index) {
                final lang = _languages[index];
                final isSelected =
                    locale.languageCode == lang['code'] &&
                    (lang['country'] == null ||
                        locale.countryCode == lang['country']);

                final displayText = lang['name'] == lang['localName']
                    ? lang['name']!
                    : "${lang['localName']} (${lang['name']})";

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  title: Text(
                    displayText,
                    style: GoogleFonts.notoSans(
                      fontSize: 17,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  trailing: isSelected
                      ? Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFF0553CF),
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          ),
                        )
                      : null,
                  onTap: () {
                    languageProvider.changeLanguage(
                      Locale(lang['code']!, lang['country'] ?? ''),
                    );
                    // Show a snackbar to indicate the change
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(context)?.translate('language_changed') ??
                              'Language changed',
                        ),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0553CF),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  AppLocalizations.of(context)?.translate('done') ?? 'Done',
                  style: GoogleFonts.notoSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
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
