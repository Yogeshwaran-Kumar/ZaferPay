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
