import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  // Hardcoded selected language per requirement (English default)
  String _selectedLanguage = 'English';

  final List<Map<String, String>> _languages = [
    {'native': 'English', 'english': ''},
    {'native': 'हिन्दी', 'english': '(Hindi)'},
    {'native': 'हिंग्लिश', 'english': '(Hinglish)'},
    {'native': 'বাংলা', 'english': '(Bengali)'},
    {'native': 'ગુજરાતી', 'english': '(Gujarati)'},
    {'native': 'ಕನ್ನಡ', 'english': '(Kannada)'},
    {'native': 'മലയാളം', 'english': '(Malayalam)'},
    {'native': 'मराठी', 'english': '(Marathi)'},
    {'native': 'தமிழ்', 'english': '(Tamil)'},
    {'native': 'తెలుగు', 'english': '(Telugu)'},
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF111318) : const Color(0xFFF7F9FC);
    final textColor = isDark ? Colors.white : const Color(0xFF1F1F1F);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Select language',
          style: GoogleFonts.outfit(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.w400,
          ),
        ),
        centerTitle: false,
        actions: const [], // explicitly ensuring no 3-dot menu
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _languages.length,
                itemBuilder: (context, index) {
                  final lang = _languages[index];
                  final isSelected = _selectedLanguage == lang['native'];

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedLanguage = lang['native']!;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: lang['native'],
                                  style: GoogleFonts.outfit(
                                    color: textColor,
                                    fontSize: 16,
                                    fontWeight: isSelected
                                        ? FontWeight.w500
                                        : FontWeight.w400,
                                  ),
                                ),
                                if (lang['english']!.isNotEmpty)
                                  TextSpan(
                                    text: ' ${lang['english']}',
                                    style: GoogleFonts.outfit(
                                      color: textColor,
                                      fontSize: 16,
                                      fontWeight: isSelected
                                          ? FontWeight.w500
                                          : FontWeight.w400,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(
                                  0xFFA8C7FA,
                                ), // Light blue from reference
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Color(
                                    0xFF041E49,
                                  ), // Dark blue check icon
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Done Button pinned to bottom
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    // Navigate back with selected language if needed
                    Navigator.pop(context, _selectedLanguage);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFFA8C7FA)
                        : const Color(0xFF0b57d0),
                    foregroundColor: isDark
                        ? const Color(0xFF041E49)
                        : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
