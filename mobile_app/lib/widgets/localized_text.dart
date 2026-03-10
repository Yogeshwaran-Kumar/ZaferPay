import 'package:flutter/material.dart';
import '../services/app_localizations.dart';

/// A widget that displays localized text with automatic overflow handling
/// and responsive sizing. Use this for consistent text display across the app.
class LocalizedText extends StatelessWidget {
  final String translationKey;
  final String fallbackText;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final Map<String, dynamic>? arguments;
  final bool softWrap;

  const LocalizedText(
    this.translationKey, {
    required this.fallbackText,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.arguments,
    this.softWrap = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final translatedText = AppLocalizations.of(context)?.translate(
          translationKey,
          arguments: arguments,
        ) ??
        fallbackText;

    return Text(
      translatedText,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.ellipsis,
      softWrap: softWrap,
    );
  }
}

/// A flexible container for localized text that prevents overflow
class FlexibleLocalizedText extends StatelessWidget {
  final String translationKey;
  final String fallbackText;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final Map<String, dynamic>? arguments;
  final int flex;

  const FlexibleLocalizedText(
    this.translationKey, {
    required this.fallbackText,
    this.style,
    this.textAlign,
    this.maxLines,
    this.arguments,
    this.flex = 1,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Flexible(
      flex: flex,
      child: LocalizedText(
        translationKey,
        fallbackText: fallbackText,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        arguments: arguments,
      ),
    );
  }
}

/// A button with localized text that automatically adjusts to content
class LocalizedButton extends StatelessWidget {
  final String translationKey;
  final String fallbackText;
  final VoidCallback? onPressed;
  final ButtonStyle? style;
  final Map<String, dynamic>? arguments;
  final Widget? icon;
  final bool isLoading;

  const LocalizedButton({
    required this.translationKey,
    required this.fallbackText,
    required this.onPressed,
    this.style,
    this.arguments,
    this.icon,
    this.isLoading = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final translatedText = AppLocalizations.of(context)?.translate(
          translationKey,
          arguments: arguments,
        ) ??
        fallbackText;

    if (isLoading) {
      return ElevatedButton(
        onPressed: null,
        style: style,
        child: const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (icon != null) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        style: style,
        icon: icon!,
        label: Text(translatedText),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: Text(translatedText),
    );
  }
}

/// A localized AppBar title with proper overflow handling
class LocalizedAppBarTitle extends StatelessWidget {
  final String translationKey;
  final String fallbackText;
  final Map<String, dynamic>? arguments;

  const LocalizedAppBarTitle(
    this.translationKey, {
    required this.fallbackText,
    this.arguments,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final translatedText = AppLocalizations.of(context)?.translate(
          translationKey,
          arguments: arguments,
        ) ??
        fallbackText;

    return Text(
      translatedText,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }
}

/// A localized dialog with proper text handling
class LocalizedAlertDialog extends StatelessWidget {
  final String titleKey;
  final String titleFallback;
  final String contentKey;
  final String contentFallback;
  final Map<String, dynamic>? titleArguments;
  final Map<String, dynamic>? contentArguments;
  final List<Widget>? actions;

  const LocalizedAlertDialog({
    required this.titleKey,
    required this.titleFallback,
    required this.contentKey,
    required this.contentFallback,
    this.titleArguments,
    this.contentArguments,
    this.actions,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: LocalizedText(
        titleKey,
        fallbackText: titleFallback,
        arguments: titleArguments,
        maxLines: 2,
      ),
      content: LocalizedText(
        contentKey,
        fallbackText: contentFallback,
        arguments: contentArguments,
        maxLines: null,
        softWrap: true,
      ),
      actions: actions,
    );
  }
}

/// Helper extension for easy localization access
extension LocalizationHelper on BuildContext {
  String? translate(String key, {Map<String, dynamic>? arguments}) {
    return AppLocalizations.of(this)?.translate(key, arguments: arguments);
  }

  String translateWithFallback(
    String key,
    String fallback, {
    Map<String, dynamic>? arguments,
  }) {
    return AppLocalizations.of(this)?.translate(key, arguments: arguments) ??
        fallback;
  }
}
