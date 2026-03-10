import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FontHelper {
  /// Returns the appropriate TextStyle based on the current locale
  /// Uses Noto Sans for ALL languages which has excellent support for all scripts including Indian languages
  static TextStyle getLocalizedTextStyle(
    BuildContext context, {
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
    FontStyle? fontStyle,
  }) {
    // Use Noto Sans for ALL languages to ensure proper rendering
    // Noto Sans supports: English, Hindi, Tamil, Telugu, Kannada, Malayalam, Marathi, Punjabi, Gujarati, Bengali
    return GoogleFonts.notoSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
    );
  }

  /// Convenience method for getting just the font family name
  static TextStyle getBaseStyle(BuildContext context) {
    // Use Noto Sans for all languages
    return GoogleFonts.notoSans();
  }
}
