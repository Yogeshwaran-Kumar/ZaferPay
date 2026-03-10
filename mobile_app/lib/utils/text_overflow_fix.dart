import 'package:flutter/material.dart';

/// Utility class to prevent text overflow in multilingual contexts
/// Use these helpers to ensure text displays properly in all 10 supported languages
class TextOverflowFix {
  /// Wraps text in a Row with Expanded to prevent overflow
  static Widget safeRowText({
    required String text,
    TextStyle? style,
    int? maxLines,
    TextOverflow overflow = TextOverflow.ellipsis,
    TextAlign? textAlign,
    List<Widget> leading = const [],
    List<Widget> trailing = const [],
  }) {
    return Row(
      children: [
        ...leading,
        Expanded(
          child: Text(
            text,
            style: style,
            maxLines: maxLines,
            overflow: overflow,
            textAlign: textAlign,
          ),
        ),
        ...trailing,
      ],
    );
  }

  /// Creates a flexible Row that handles long text gracefully
  static Widget flexibleRow({
    required List<Widget> children,
    MainAxisAlignment mainAxisAlignment = MainAxisAlignment.start,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
  }) {
    return Row(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: children.map((child) {
        // Automatically wrap Text widgets in Expanded if not already wrapped
        if (child is Text && child.overflow == null) {
          return Expanded(
            child: Text(
              child.data ?? '',
              style: child.style,
              maxLines: child.maxLines,
              overflow: TextOverflow.ellipsis,
              textAlign: child.textAlign,
            ),
          );
        }
        return child;
      }).toList(),
    );
  }

  /// Ensures text fits within constraints with ellipsis
  static Widget constrainedText({
    required String text,
    required double maxWidth,
    TextStyle? style,
    int? maxLines = 1,
    TextOverflow overflow = TextOverflow.ellipsis,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }

  /// Creates a responsive text widget that scales down if needed
  static Widget responsiveText({
    required String text,
    required TextStyle style,
    double minFontSize = 12,
    int? maxLines,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        if (textPainter.didExceedMaxLines) {
          // Scale down font size
          final scaledStyle = style.copyWith(
            fontSize: (style.fontSize ?? 14) * 0.9,
          );
          return Text(
            text,
            style: scaledStyle,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          );
        }

        return Text(
          text,
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
