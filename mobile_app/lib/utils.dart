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

  // Check if it's effectively an integer
  if (val % 1 == 0) {
    return val.toInt().toString();
  } else {
    return val.toString();
  }
}
