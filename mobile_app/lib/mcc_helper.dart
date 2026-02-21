class MccHelper {
  static const Map<String, String> domains = {
    "8011": "Hospital",
    "8021": "Dentist",
    "8031": "Doctor / Clinic",
    "8041": "Chiropractor",
    "8042": "Optometrist",
    "8049": "Medical Services",
    "8050": "Nursing / Care",
    "5912": "Pharmacy",
    "7011": "Hotel",
    "7012": "Timeshare",
    "7032": "Camping / Lodging",
    "4722": "Travel Agency",
    "5812": "Restaurant",
    "5813": "Bar / Pub",
    "5814": "Fast Food",
    "5462": "Bakery",
    "5441": "Candy / Snacks",
    "5411": "Grocery / Retail Shop",
    "5311": "Department Store",
    "5399": "General Retail",
    "5499": "Misc. Food Store",
    "5651": "Clothing Store",
    "5732": "Electronics Store",
    "5941": "Sporting Goods",
    "5942": "Book Store",
    "5977": "Cosmetics",
    "8211": "School",
    "8220": "College / University",
    "8241": "Training / Coaching",
    "8249": "Education Services",
    "4111": "Transport / Taxi",
    "4121": "Cab / Auto",
    "4131": "Bus / Travel",
    "4511": "Airlines",
    "4789": "Transport Services",
    "4900": "Utilities",
    "4814": "Telecom",
    "6012": "Financial Institution",
    "6300": "Insurance",
    "8111": "Legal Services",
    "8931": "Accounting",
    "7392": "Consulting",
    "7372": "Software / IT",
    "7349": "Cleaning Services",
    "7210": "Laundry",
    "7832": "Cinema",
    "7996": "Amusement Park",
    "7999": "Recreation",
    "7922": "Theater",
    "7991": "Tourist Attraction",
    "7399": "Business Services",
    "5661": "Shoe Store",
    "5251": "Hardware Store",
    "5712": "Furniture Store",
    "5944": "Jewelry",
  };

  static String getDomain(String? mcc) {
    if (isPersonal(mcc)) return "Personal";
    return domains[mcc] ?? "Merchant";
  }

  /// Groups a specific domain into a broader UI category
  static String getGroupedCategory(String domain) {
    if (domain == 'Personal') return 'People';

    switch (domain) {
      case 'Restaurant':
      case 'Bar / Pub':
      case 'Fast Food':
      case 'Bakery':
      case 'Candy / Snacks':
      case 'Grocery / Retail Shop':
      case 'Misc. Food Store':
      case 'Hotel':
        return 'Food & Drinks';

      case 'Department Store':
      case 'General Retail':
      case 'Clothing Store':
      case 'Electronics Store':
      case 'Sporting Goods':
      case 'Book Store':
      case 'Cosmetics':
      case 'Shoe Store':
      case 'Hardware Store':
      case 'Furniture Store':
      case 'Jewelry':
        return 'Shopping';

      case 'Travel Agency':
      case 'Transport / Taxi':
      case 'Cab / Auto':
      case 'Bus / Travel':
      case 'Airlines':
      case 'Transport Services':
        return 'Transport';

      case 'Utilities':
      case 'Telecom':
        return 'Bills & Utilities';

      case 'Cinema':
      case 'Amusement Park':
      case 'Recreation':
      case 'Theater':
      case 'Tourist Attraction':
        return 'Entertainment';

      case 'Hospital':
      case 'Dentist':
      case 'Doctor / Clinic':
      case 'Chiropractor':
      case 'Optometrist':
      case 'Medical Services':
      case 'Nursing / Care':
      case 'Pharmacy':
        return 'Health';

      case 'Merchant':
      case 'Uncategorized':
        return 'Others';

      default:
        // Any other specific domains like Education, Financial, Insurance, Legal, etc.
        return 'Others';
    }
  }

  /// Check if the MCC indicates a personal account (not a merchant).
  /// Returns true if MCC is null, empty, or any form of zeros (0, 00, 000, 0000, etc.)
  static bool isPersonal(dynamic mcc) {
    if (mcc == null) return true;

    final String mccStr = mcc.toString().trim();

    // Empty string is personal
    if (mccStr.isEmpty) return true;

    // Check if it's all zeros (0, 00, 000, 0000, etc.)
    final RegExp allZeros = RegExp(r'^0+$');
    if (allZeros.hasMatch(mccStr)) return true;

    return false;
  }

  /// Check if the MCC indicates a merchant account.
  /// Returns true if MCC is a valid non-zero code.
  static bool isMerchant(dynamic mcc) {
    return !isPersonal(mcc);
  }
}
