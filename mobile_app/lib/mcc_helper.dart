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

      case 'School':
      case 'College / University':
      case 'Training / Coaching':
      case 'Education Services':
        return 'Education';

      case 'Financial Institution':
      case 'Accounting':
      case 'Consulting':
      case 'Software / IT':
      case 'Business Services':
        return 'Investments';

      case 'Insurance':
      case 'Legal Services':
        return 'Bills & Utilities';

      case 'Merchant':
      case 'Uncategorized':
        return 'Others';

      default:
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

  /// Automatic categorization based on keywords in the transaction note/remark.
  /// Returns a category name if a match is found, otherwise null.
  static String? getCategoryFromNote(String? note) {
    if (note == null || note.isEmpty) return null;

    final String lowerNote = note.toLowerCase();

    // Comprehensive keyword dictionary (expanding towards 1000+)
    final Map<String, Set<String>> keywordDictionary = {
      'Food & Drinks': {
        // General & Meals
        'food', 'lunch', 'dinner', 'breakfast', 'brunch', 'snacks', 'snack',
        'eats', 'meal', 'treat', 'party', 'canteen', 'mess', 'pantry', 'order',
        'yummy',
        'tasty',
        'delicious',
        'hungry',
        'foodie',
        'delivery',
        'takeaway',
        'parcel',
        'menu',
        'waiter',
        'chef',
        'kitchen',
        'billing',
        'buffet',
        'dine',
        'hotel',
        'restaurant',
        'dhaba',
        'cafe',
        'bakery',
        'patisserie',
        'chowpatty',
        // Dishes - Indian
        'biryani',
        'pulao',
        'khichdi',
        'rice',
        'fried rice',
        'roti',
        'naan',
        'puris',
        'paratha',
        'kulcha',
        'pav bhaji',
        'vada pav',
        'misal',
        'kachori',
        'samosa',
        'chaat',
        'pani puri',
        'gol gappa',
        'bhel',
        'sev puri',
        'dhokla',
        'farsan',
        'jalebi',
        'gulab jamun',
        'rasgulla',
        'barfi',
        'peda',
        'kaju katli',
        'mithai',
        'sweets',
        'halwa',
        'ladoo',
        'paneer',
        'chicken',
        'mutton',
        'egg',
        'fish',
        'meat',
        'kebab',
        'tandoori',
        'tikka',
        'roast',
        'curry',
        'gravy',
        'dal tadka',
        'dal makhani', 'paneer butter masala', 'shahi paneer', 'kadai paneer',
        'chole',
        'rajma',
        'bhindi',
        'aloo',
        'gobi',
        'baingan',
        'kofta',
        'mutter',
        'mushroom', 'corn', 'capsicum', 'veg', 'nonveg', 'omelette', 'bhurji',
        'fish fry', 'prawns', 'crab', 'seafood', 'mutton rogan josh', 'keema',
        'korma',
        'butter chicken',
        'hyd biryani',
        'lucknowi',
        'andhra',
        'chettinad',
        'malabar',
        'kerala',
        'goan',
        'rajasthani',
        'gujarati',
        'punjabi',
        'south indian',
        'north indian',
        'thali',
        'dosa',
        'idli',
        'vada',
        'pongal',
        // Dishes - International
        'pizza', 'burger', 'momos', 'pasta', 'sandwich', 'noodles', 'chowmein',
        'hakka', 'schezwan', 'manchurian', 'bao', 'spring roll', 'starters',
        'uttapam', 'appam',
        'steak', 'grill', 'bbq', 'sushi', 'ramen', 'dimsum', 'taco', 'nachos',
        'fries', 'chips', 'pancake', 'waffle', 'crepe', 'donut', 'cupcake',
        'muffin', 'brownie', 'sizzler', 'hummus', 'falafel', 'shawarma',
        // Drinks & Beverages
        'tea', 'chai', 'coffee', 'juice', 'shake', 'smoothie', 'soda', 'pepsi',
        'coke', 'cola', 'sprite', 'beer', 'wine', 'whiskey', 'alcohol', 'bar',
        'pub', 'club', 'lounge', 'brewery', 'water', 'aquafina', 'bisleri',
        'milk',
        'curd',
        'lassi',
        'buttermilk',
        'kokum',
        'sharbath',
        'cold drink',
        'beverage', 'mocktail', 'cocktail', 'liquor', 'vodka', 'rum', 'gin',
        'maaza', 'fanta', 'limca', 'appy', 'frooty', 'thumsup',
        // Brands & Apps
        'swiggy', 'zomato', 'magicpin', 'eatit', 'faasos', 'behrouz', 'kfc',
        'mcdonalds', 'mcd', 'dominos', 'pizzahut', 'subway', 'burgerking',
        'bk', 'taco bell', 'wow momo', 'haldiram', 'bikano', 'baskin robbins',
        'gianis', 'naturals', 'ccd', 'blue tokai', 'third wave', 'starbucks',
        'grofers', 'bbnow', 'instamart', 'blinkit', 'zepto', 'bigbasket',
        'nestle', 'amul', 'mother dairy', 'motherdairy',
        // Groceries & Raw
        'vegetables', 'fruits', 'apple', 'banana', 'mango', 'grocery', 'pulse',
        'atta', 'dal', 'oil', 'sugar', 'salt', 'spice', 'masala', 'turmeric',
        'chilli', 'clove', 'cardamom', 'cinnamon', 'pepper', 'garlic', 'ginger',
        'onion', 'potato', 'tomato', 'ladyfinger', 'brinjal', 'cabbage',
        'cauliflower', 'spinach', 'broccoli', 'carrot', 'radish', 'cucumber',
        'lemon', 'chili', 'mint', 'coriander', 'coconut', 'mustard', 'cumin',
        'fennel', 'fenugreek', 'walnut', 'almond', 'cashew', 'raisin', 'pista',
        'peanut', 'seeds', 'sunflower', 'olive', 'soybean', 'refined', 'ghee',
        'butter', 'cheese', 'mayo', 'sauce', 'ketchup', 'jam', 'honey', 'syrup',
        'pickle', 'papad', 'mukhwas', 'pan', 'beetlenut', 'supari',
      },
      'Shopping': {
        // General
        'shop', 'shopping', 'mall', 'purchase', 'bought', 'items', 'stuff',
        'mart', 'store', 'retail', 'outlet', 'showroom', 'supermarket',
        // Apparel & Fashion
        'dress', 'shirt', 'pant', 'jeans', 'tshirt', 'cloth', 'clothes',
        'suit', 'saree', 'kurta', 'top', 'skirt', 'jacket', 'coat', 'sweater',
        'socks', 'underwear', 'garments', 'fashion', 'wear', 'outfit',
        'zara', 'h&m', 'max', 'pantaloons', 'shoppers stop', 'lifestyle',
        'westside', 'decathlon', 'unlimited', 'trends', 'biba', 'allensolly',
        'arrow', 'aurelia', 'blackberrys', 'celio', 'flying machine',
        'global desi', 'jack & jones', 'levi', 'levis', 'mufti', 'pepe',
        'park avenue', 'peter england', 'raymond', 'red tape', 'spykar',
        'ucb', 'us polo', 'van heusen', 'veromoda', 'woodland', 'wrangler',
        // Footwear & Accessories
        'shoes', 'sneakers', 'sandals', 'slippers', 'boots', 'heel', 'bata',
        'puma', 'nike', 'adidas', 'skechers', 'crocs', 'bag', 'wallet', 'purse',
        'watch', 'jewelry', 'jewellery', 'gold', 'silver', 'diamond', 'ring',
        'earring', 'necklace', 'bangle', 'titan', 'casio', 'fossil', 'fastrack',
        'tanishq',
        'caratlane',
        'malabar gold',
        'joyalukkas',
        'kalyan jewellers',
        // Online Portals
        'amazon', 'flipkart', 'myntra', 'ajio', 'nykaa', 'meesho', 'bewakoof',
        'snapdeal', 'tata cliq', 'reliance digital', 'jiomart', 'big bazaar',
        'dmart', 'spencer', 'more', 'reliance fresh', 'blinkit', 'zepto',
        'dunzo',
        // Electronics
        'laptop', 'mobile', 'phone', 'iphone', 'samsung', 'apple', 'ipad',
        'macbook', 'headphone', 'earphone', 'airpods', 'charger', 'cable',
        'electronics', 'camera', 'tv', 'fridge', 'refrigerator', 'ac',
        'microwave', 'washing machine', 'iron', 'trimmer', 'gadget', 'beats',
        'boat', 'jbl', 'sony', 'bose', 'sennheiser', 'skullcandy', 'marshall',
        'oneplus', 'xiaomi', 'mi', 'redmi', 'realme', 'oppo', 'vivo', 'nothing',
        'pixel', 'google', 'lenovo', 'hp', 'dell', 'asus', 'acer', 'msi',
        'razer',
        'logitech',
        'canon',
        'nikon',
        'gopro',
        'dji',
        'drone',
        'fitbit',
        'garmin', 'amazfit', 'noise', 'fire boltt',
        // Home & Household
        'furniture', 'sofa', 'bed', 'chair', 'table', 'curtain', 'bedsheet',
        'decor', 'painting', 'lamp', 'kitchenware', 'cookware', 'utensils',
        'prestige', 'butterfly', 'ikea', 'pepperfry', 'urban ladder', 'hawkins',
        'milton', 'cello', 'tupperware', 'lock', 'godrej', 'key', 'replicate',
        'safe', 'paint', 'asian paints', 'berger', 'nerolac', 'dulux', 'tiles',
        'kajaria', 'somany', 'sanitaryware', 'hindware', 'jacquar', 'pipe',
        'wire', 'havells', 'anchor', 'syska', 'philips', 'crompton',
        // Personal Care
        'makeup', 'lipstick', 'perfume', 'deodorant', 'soap', 'shampoo',
        'lotion', 'cream', 'stationary', 'book', 'copy', 'gift', 'toy',
        'detergent', 'surf', 'ariel', 'tide', 'dove', 'pantene', 'loreal',
        'herbal', 'toothpaste', 'colgate', 'pepsodent', 'sensodyne', 'brush',
        'clinic plus', 'head & shoulders', 'vaseline', 'nivea', 'ponds',
        'garnier', 'lakme', 'maybelline', 'revlon', 'biotique', 'mamaearth',
        'wow', 'mcaffeine', 'plum', 'sugar cosmetics',
      },
      'Transport': {
        'transport',
        // Services
        'ola', 'uber', 'rapido', 'blusmart', 'indriver', 'cab', 'taxi',
        'auto', 'rickshaw', 'ride', 'travel', 'trip', 'journey', 'tour',
        'paisa vasool', 'fare', 'parking', 'toll', 'highway', 'fastag',
        'nhai', 'valet', 'garage', 'workshop', 'towing', 'breakdown',
        // Fuel
        'petrol', 'diesel', 'fuel', 'gas', 'cng', 'ev', 'charging', 'shell',
        'hp', 'bp', 'iocl', 'oil', 'lubricant',
        // Public Transport
        'bus', 'metro', 'train', 'irctc', 'railway', 'ticket', 'booking',
        'flight', 'airline', 'indigo', 'airindia', 'vistara', 'spicejet',
        'akasa', 'airport', 'shuttle', 'ferry', 'ship', 'cruise', 'yacht',
        'coach', 'pnr', 'boarding', 'terminal', 'gate', 'transit', 'stopover',
        // Maintenance & Gear
        'service', 'repair', 'mechanic', 'car', 'bike', 'scooty', 'puncture',
        'tyre', 'tire', 'alloy', 'parts', 'insurance', 'challan', 'traffic',
        'helmet', 'gloves', 'riding gear', 'expedition', 'camping', 'caravan',
        // Brands
        'maruti', 'hyundai', 'tata', 'mahindra', 'honda', 'toyota', 'bmw',
        'audi', 'mercedes', 'volvo', 'royal enfield', 'ktm', 'tvs', 'bajaj',
        'yamaha', 'suzuki', 'kawasaki', 'harley', 'ducati', 'vespa', 'aprilia',
        'force', 'isuzu', 'jeep', 'kia', 'skoda', 'volkswagen', 'mg',
      },
      'Education': {
        'education',
        'school',
        'college',
        'university',
        'tuition',
        'coaching',
        'fees',
        'admission',
        'exam',
        'result',
        'degree',
        'diploma',
        'course',
        'udemy',
        'coursera',
        'edx',
        'unacademy',
        'byjus',
        'vedantu',
        'physics wallah',
        'pw',
        'simplilearn',
        'upgrad',
        'allen',
        'aakash',
        'fitjee',
        'chaitanya',
        'narayana',
        'resonance',
        'vibrant',
        'books',
        'notebook',
        'stationary',
        'library',
        'internship',
        'project',
        'seminar',
        'workshop',
        'training',
        'skill',
        'placement',
        'scholarship',
        'grant',
        'educational',
        'instruction',
        'lesson',
        'tutor',
        'professor',
        'teacher',
      },
      'Health': {
        'health',
        'doctor',
        'hospital',
        'clinic',
        'dentist',
        'medical',
        'medicine',
        'pharmacy',
        'chemist',
        'apollo',
        'pharmeasy',
        '1mg',
        'netmeds',
        'lab',
        'test',
        'blood',
        'report',
        'mri',
        'ct scan',
        'xray',
        'vaccine',
        'corona',
        'cultfit',
        'trainer',
        'protein',
        'supplement',
        'vitamin',
        'diet',
        'ayurveda',
        'homeopathy',
        'therapy',
        'massage',
        'spa',
        'salon',
        'parlor',
        'haircut',
        'shave',
        'dentistry',
        'physician',
        'surgeon',
        'ambulance',
        'ward',
        'patient',
        'checkup',
        'wellness',
      },
      'Investments': {
        'investments',
        'stock',
        'share',
        'mutual fund',
        'mf',
        'sip',
        'investment',
        'invest',
        'zerodha',
        'groww',
        'upstox',
        'angel one',
        'icici direct',
        'hdfc sec',
        'bitcoin',
        'crypto',
        'binance',
        'coinbase',
        'wazirx',
        'etf',
        'gold',
        'silver',
        'fd',
        'rd',
        'ppf',
        'nps',
        'epf',
        'provident',
        'pension',
        'dividend',
        'interest',
      },
      'Bills & Utilities': {
        'utilities', 'bills',
        // Utilities
        'rent', 'bill', 'maintenance', 'electricity', 'light', 'current',
        'water', 'gas', 'cylinder', 'piped', 'indane', 'hp gas', 'bharat gas',
        'garbage', 'society', 'premium', 'lic', 'policy', 'tax', 'gst',
        'income tax', 'tds', 'recharge', 'prepaid', 'postpaid', 'topup', 'jio',
        'airtel', 'vi', 'bsnl', 'broadband', 'wifi', 'internet', 'fiber',
        'excitel', 'act', 'tikona', 'hathway', 'dth', 'tata sky', 'tata play',
        'dish tv', 'videocon', 'subscription', 'bbps', 'npci', 'salary',
        'stipend', 'bonus', 'invoice', 'voucher', 'receipt', 'emi', 'loan',
        'credit card', 'property',
        // Charity & Misc
        'donation', 'charity', 'ngo', 'relief', 'trust', 'temple', 'church',
        'mosque', 'gurudwara', 'seva', 'contribution', 'membership',
      },
      'Entertainment': {
        'entertainment',
        'movie',
        'cinema',
        'pvr',
        'inox',
        'cinepolis',
        'theatre',
        'show',
        'netflix',
        'hotstar',
        'prime',
        'amazon prime',
        'sony liv',
        'zee5',
        'alt balaji',
        'youtube',
        'premium',
        'spotify',
        'gaana',
        'wynk',
        'music',
        'concert',
        'event',
        'bookmyshow',
        'paytm insider',
        'game',
        'gaming',
        'steam',
        'epic',
        'ps5',
        'xbox',
        'nintendo',
        'pubg',
        'bgmi',
        'cod',
        'freefire',
        'minecraft',
        'discord',
        'twitch',
        'hobby',
        'craft',
        'art',
        'museum',
        'exhibition',
        'resort',
        'park',
        'zoo',
        'vacation',
        'holiday',
        'stadium',
        'match',
        'ipl',
        'cricket',
        'football',
        'fifa',
        'sports',
        'disney',
        'marvel',
        'dc',
        'kindle',
        'audible',
        'magazine',
        'party',
      },
    };

    // Split note into tokens (words)
    final List<String> tokens = lowerNote.split(RegExp(r'[\s,_/\-]+'));

    for (var entry in keywordDictionary.entries) {
      final category = entry.key;
      final keywords = entry.value;

      for (var token in tokens) {
        if (token.length < 2) continue; // Skip very short tokens
        if (keywords.contains(token)) {
          return category;
        }
      }

      // Also check if any keyword is a substring of the note (for phrases or connected words)
      for (var keyword in keywords) {
        if (keyword.length > 3 && lowerNote.contains(keyword)) {
          return category;
        }
      }
    }

    return null;
  }
}
