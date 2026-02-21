import 'package:flutter/material.dart';

String formatAmount(dynamic amount) {
  if (amount == null) return "0";
  double val;
  if (amount is int) {
    val = amount.toDouble();
  } else if (amount is double) {
    val = amount;
  } else if (amount is String) {
    val = double.tryParse(amount) ?? 0.0;
  } else {
    return "0";
  }

  // Check if it's effectively an integer (handling float precision)
  // Converting to fixed(2) first handles the rounding
  String formatted = val.toStringAsFixed(2);
  if (formatted.endsWith('.00')) {
    return formatted.substring(0, formatted.length - 3);
  }
  // Optional: If you prefer 5.5 over 5.50, uncomment below:
  // if (formatted.endsWith('0')) return formatted.substring(0, formatted.length - 1);
  return formatted;
}

Color getAvatarColor(String? name) {
  if (name == null || name.isEmpty) {
    return const Color(0xFF90A4AE); // Default Grey
  }

  final List<Color> avatarColors = [
    const Color(0xFFE57373), // Red
    const Color(0xFFBA68C8), // Purple
    const Color(0xFF7986CB), // Indigo
    const Color(0xFF4FC3F7), // Light Blue
    const Color(0xFF4DB6AC), // Teal
    const Color(0xFF81C784), // Green
    const Color(0xFFFFB74D), // Orange
    const Color(0xFFA1887F), // Brown
    const Color(0xFF90A4AE), // Blue Grey
    const Color(0xFFD4E157), // Lime
  ];

  // Deterministic hash
  return avatarColors[name.hashCode.abs() % avatarColors.length];
}
