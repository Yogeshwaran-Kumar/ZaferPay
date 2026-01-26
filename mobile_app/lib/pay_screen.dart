import 'dart:async';
import 'package:flutter/foundation.dart'; // Add this for kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';
import 'mcc_helper.dart';
import 'main.dart';
import 'conversation_screen.dart';

class PayScreen extends StatefulWidget {
  const PayScreen({super.key});

  @override
  State<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<PayScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _recentPeople = [];
  List<dynamic> _recentMerchants = [];
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  bool _isLoading = true;
  bool _areContactsLoaded = false; // Add this flag
  bool _isSearching = false;
  String _searchQuery = '';

  // For database lookup result
  Map<String, dynamic>? _databaseUser;
  bool _isLookingUp = false;

  // Debounce timer for search
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);

    // 0. Sync Load (True Zero Latency)
    // We leverage the data already loaded in HomeScreen (RAM)
    final homeData = _api.getCachedHomeDataSync();
    if (homeData != null) {
      if (homeData['people'] != null) {
        _recentPeople = (homeData['people'] as List).take(6).toList();
      }
      if (homeData['merchants'] != null) {
        _recentMerchants = (homeData['merchants'] as List).take(6).toList();
      }
      // If we have ANY data, show UI immediately (No spinner)
      if (_recentPeople.isNotEmpty || _recentMerchants.isNotEmpty) {
        _isLoading = false;
      }
    }

    _loadData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    setState(() {
      _searchQuery = query;
      _isSearching = query.isNotEmpty;
    });

    // Cancel previous debounce timer
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _filteredContacts = [];
        _databaseUser = null;
        _isLookingUp = false;
      });
      return;
    }

    // Debounce search for 300ms to prevent excessive API calls
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _filterContactsAndLookup(query);
    });
  }

  void _filterContactsAndLookup(String query) {
    // Normalize query - remove all non-digit characters for phone comparison
    final normalizedQuery = query.replaceAll(RegExp(r'[^\d]'), '');
    final queryLast10 = normalizedQuery.length >= 10
        ? normalizedQuery.substring(normalizedQuery.length - 10)
        : normalizedQuery;

    // Filter contacts that match the query (by name or phone number)
    final filtered = _contacts.where((contact) {
      // Check if name matches
      final nameMatch = contact.displayName.toLowerCase().contains(
        query.toLowerCase(),
      );

      // Check if any phone number matches (comparing last 10 digits)
      final phoneMatch = contact.phones.any((phone) {
        final normalizedPhone = phone.number.replaceAll(RegExp(r'[^\d]'), '');
        final phoneLast10 = normalizedPhone.length >= 10
            ? normalizedPhone.substring(normalizedPhone.length - 10)
            : normalizedPhone;

        final isMatch =
            phoneLast10.contains(queryLast10) ||
            queryLast10.contains(phoneLast10) ||
            phoneLast10 == queryLast10;

        // Debug EVERY comparison when query is exactly 10 digits

        return isMatch;
      });

      return nameMatch || phoneMatch;
    }).toList();

    setState(() {
      _filteredContacts = filtered;
    });

    // Check what type of query this is and lookup accordingly
    if (_isPhoneNumber(query)) {
      // Phone number - lookup by phone
      _lookupUserFromDatabase(query);
    } else if (query.contains('@')) {
      // UPI ID - lookup by UPI ID
      _lookupUserByUpi(query);
    } else {
      // Name search - no database lookup, just show contacts
      setState(() {
        _databaseUser = null;
        _isLookingUp = false;
      });
    }
  }

  Future<void> _lookupUserByUpi(String upiId) async {
    // 1. Check Cache
    final cached = await _api.getCachedUser(upiId);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _databaseUser = cached;
          _isLookingUp = false;
        });
      }
      return;
    }

    // 2. Network Lookup
    setState(() {
      _isLookingUp = true;
    });

    final user = await _api.lookupUser(upiId);

    if (mounted) {
      setState(() {
        _databaseUser = user;
        _isLookingUp = false;
      });
    }
  }

  bool _isPhoneNumber(String query) {
    // Check if query is mostly digits (allowing some formatting characters)
    final digitsOnly = query.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    return digitsOnly.length >= 6 && RegExp(r'^\d+$').hasMatch(digitsOnly);
  }

  Future<void> _lookupUserFromDatabase(String phoneNumber) async {
    // Normalize phone number
    final normalizedPhone = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');

    // 1. Check Cache (Try to find by phone if we had a mapping, else skip for now)
    // Since we only cache by UPI ID currently, we might miss this optimization for pure phone entry
    // UNLESS we update _api to cache by phone too.
    // Ideally, we should skip cache for phone unless we're sure.
    // However, if the user enters a number that resolves to a cached UPI, we wouldn't know the UPI yet.

    setState(() {
      _isLookingUp = true;
    });

    final user = await _api.lookupUserByPhone(normalizedPhone);

    if (mounted) {
      setState(() {
        _databaseUser = user;
        _isLookingUp = false;
      });
    }
  }

  Future<void> _loadData() async {
    // 1. Instant Cache Load
    final cachedPeople = await _api.getCachedRecents('people_cache');
    final cachedMerchants = await _api.getCachedRecents('merchants_cache');

    if (mounted) {
      if (cachedPeople != null || cachedMerchants != null) {
        setState(() {
          if (cachedPeople != null) {
            _recentPeople = cachedPeople.take(6).toList();
          }
          if (cachedMerchants != null) {
            _recentMerchants = cachedMerchants.take(6).toList();
          }
          // Hide loading if we have initial data to show
          if (cachedPeople != null) _isLoading = false;
        });
      }
    }

    // 2. Fetch Fresh Recents (People + Merchants)
    // Run in parallel
    final results = await Future.wait([
      _api.getRecentPeople(),
      _api.getRecentMerchants(),
    ]);

    final people = results[0];
    final merchants = results[1];

    // 3. Fetch Contacts with proper permission handling
    await _loadContacts();

    if (mounted) {
      setState(() {
        _recentPeople = people?.take(6).toList() ?? _recentPeople;
        _recentMerchants = merchants?.take(6).toList() ?? _recentMerchants;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadContacts() async {
    try {
      // Skip app lock while requesting permission to prevent PIN prompt
      MyApp.isSharing = true;

      // Request permission
      final permissionStatus = await Permission.contacts.request();

      if (permissionStatus.isGranted) {
        // Get ALL contacts with account info
        final contacts = await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
          withAccounts: true, // Include account info to see sources
        );

        // Filter to only contacts with phone numbers
        final contactsWithPhones = contacts
            .where((c) => c.phones.isNotEmpty)
            .toList();

        if (mounted) {
          setState(() {
            _contacts = contactsWithPhones;
          });
        }
      } else if (permissionStatus.isPermanentlyDenied) {
        // Open app settings if permanently denied
        // openAppSettings();
      } else {}
    } catch (e) {
      // Ignore errors (permission denied or platform error)
    } finally {
      if (mounted) {
        setState(() {
          _areContactsLoaded = true;
        });
      }
      // Delay before re-enabling app lock to allow lifecycle callback to complete
      Future.delayed(const Duration(seconds: 1), () {
        MyApp.isSharing = false;
        MyApp.lastShareTime = DateTime.now();
      });
    }
  }

  Future<void> _onPay(String upi, String? name, {String? category}) async {
    // Navigate with all known data for INSTANT render
    await Navigator.pushNamed(
      context,
      '/amount',
      // Pass 'name' properly so AmountScreen doesn't need to look it up if known
      arguments: {'upi': upi, 'name': name, 'category': category},
    );
    // Refresh recents on return in case payment was made
    if (mounted) {
      _loadData();
    }
  }

  void _openConversation(dynamic person) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConversationScreen(
          args: {
            'upi': person['upi_id'] ?? '',
            'name': person['username'] ?? 'User',
            'mobile':
                person['mobile_encrypted'] ??
                '', // or decoded if available locally
            'isMerchant': false, // or logic from person
          },
        ),
      ),
    );
  }

  Future<void> _onContactTap(Contact contact) async {
    if (contact.phones.isEmpty) return;

    // Show loading while looking up
    setState(() => _isLookingUp = true);

    String originalPhone = contact.phones.first.number;
    // 1. Normalize the phone number
    String normalizedPhone = originalPhone.replaceAll(
      RegExp(r'[\s\-\(\)]'),
      '',
    ); // Remove spaces, dashes, parens

    // Remove country code if present (assuming +91 or 91 for India)
    if (normalizedPhone.startsWith('+91')) {
      normalizedPhone = normalizedPhone.substring(3);
    } else if (normalizedPhone.startsWith('91') &&
        normalizedPhone.length > 10) {
      // Basic check to avoid removing '91' from real numbers like 9198... if trying to guess
      // But safest is to only remove +91.
      // However, user said "if i save that number with +91 also"
      // If it starts with 91 and is 12 digits, it's likely country code.
      if (normalizedPhone.length == 12) {
        normalizedPhone = normalizedPhone.substring(2);
      }
    }

    String? displayName = contact.displayName;
    String upiIdOrPhone = normalizedPhone;

    // 2. Lookup this normalized phone in our backend
    try {
      final user = await _api.lookupUserByPhone(normalizedPhone);
      if (user != null) {
        // User exists! Use their data
        displayName = _getDisplayName(user); // Will get "Dhanush" etc
        upiIdOrPhone = user['upi_id'];
      }
    } catch (e) {
      if (kDebugMode) print("Contact Lookup Error: $e");
    } finally {
      if (mounted) {
        setState(() => _isLookingUp = false);
      }
    }

    if (mounted) {
      _onPay(upiIdOrPhone, displayName);
    }
  }

  Future<void> _onSearchSubmit(String value) async {
    if (value.isEmpty) return;

    String? upiOrPhone = value;
    String? displayName;

    // Check if it's a UPI ID (contains @)
    if (value.contains('@')) {
      // It's a UPI ID - look it up
      setState(() => _isLookingUp = true);
      final user = await _api.lookupUser(value);
      setState(() => _isLookingUp = false);

      if (user != null) {
        displayName = _getDisplayName(user);
        upiOrPhone = user['upi_id'] ?? value;
      }
      _onPay(upiOrPhone ?? value, displayName);
      return;
    }

    // Check if it's a phone number
    final normalizedValue = value.replaceAll(RegExp(r'[^\d]'), '');
    if (_isPhoneNumber(value)) {
      final valueLast10 = normalizedValue.length >= 10
          ? normalizedValue.substring(normalizedValue.length - 10)
          : normalizedValue;

      // First, check if there's a matching contact in phone
      for (final contact in _contacts) {
        for (final phone in contact.phones) {
          final normalizedPhone = phone.number.replaceAll(RegExp(r'[^\d]'), '');
          final phoneLast10 = normalizedPhone.length >= 10
              ? normalizedPhone.substring(normalizedPhone.length - 10)
              : normalizedPhone;

          if (phoneLast10 == valueLast10) {
            displayName = contact.displayName;
            break;
          }
        }
        if (displayName != null) break;
      }

      // If no contact match, check database
      if (displayName == null) {
        setState(() => _isLookingUp = true);
        final user = await _api.lookupUserByPhone(normalizedValue);
        setState(() => _isLookingUp = false);

        if (user != null) {
          displayName = _getDisplayName(user);
        }
      }

      // Navigate with phone number
      _onPay(normalizedValue, displayName);
      return;
    }

    // It's a name search - if there's a matching contact, use it
    if (_filteredContacts.isNotEmpty) {
      final contact = _filteredContacts.first;
      if (contact.phones.isNotEmpty) {
        final phone = contact.phones.first.number.replaceAll(
          RegExp(r'\s+'),
          '',
        );
        _onPay(phone, contact.displayName);
        return;
      }
    }

    // No match - just try with the value as-is
    _onPay(value, null);
  }

  String _getDisplayName(Map<String, dynamic> user) {
    String name = user['username'] ?? 'Unknown';
    // Clean up default "UserXXX" format
    if (name.startsWith('User') && name.length > 4) {
      if (RegExp(r'^User\d+$').hasMatch(name)) {
        name = name.substring(4);
      }
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).iconTheme.color,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Pay anyone",
              style: TextStyle(
                color: Theme.of(context).textTheme.titleLarge?.color,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              "Pay any UPI app using name, number or UPI ID",
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Search Bar
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.search,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    decoration: InputDecoration(
                      hintText: "Enter name, mobile number or UPI ID",
                      hintStyle: TextStyle(
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade400,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      suffixIcon: _isLookingUp
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.arrow_forward,
                                color: Colors.blue,
                              ),
                              onPressed: () => _onSearchSubmit(_searchQuery),
                            )
                          : const Chip(
                              label: Text(
                                "123",
                                style: TextStyle(fontSize: 12),
                              ),
                              backgroundColor: Colors.transparent,
                            ),
                    ),
                    onSubmitted: _onSearchSubmit,
                  ),
                ),

                const SizedBox(height: 24),

                // Show search results when searching
                if (_isSearching) ...[
                  // Database user result (if found and no contact match)
                  if (_databaseUser != null) ...[
                    const Text(
                      "Found on UPI",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Text(
                          _getDisplayName(_databaseUser!).isNotEmpty
                              ? _getDisplayName(_databaseUser!)[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(
                        _getDisplayName(_databaseUser!),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _databaseUser!['upi_id'] ?? _searchQuery,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                          // Show MCC category if merchant account
                          if (_databaseUser!['mcc'] != null &&
                              _databaseUser!['mcc'] != '0000') ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '🏪 ${MccHelper.getDomain(_databaseUser!['mcc'])}',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          "Pay",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onTap: () => _onPay(
                        _databaseUser!['upi_id'] ?? _searchQuery,
                        _getDisplayName(_databaseUser!),
                        category:
                            (_databaseUser!['mcc'] != null &&
                                _databaseUser!['mcc'] != '0000')
                            ? MccHelper.getDomain(_databaseUser!['mcc'])
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Filtered contacts
                  if (_filteredContacts.isNotEmpty) ...[
                    Text(
                      "Contacts",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._filteredContacts.take(5).map((contact) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                          child: Text(
                            contact.displayName.isNotEmpty
                                ? contact.displayName[0].toUpperCase()
                                : 'C',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        title: Text(
                          contact.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        subtitle: Text(
                          contact.phones.isNotEmpty
                              ? contact.phones.first.number
                              : '',
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                        onTap: () => _onContactTap(contact),
                      );
                    }),
                    const SizedBox(height: 16),
                  ],

                  // If no results found
                  if (_filteredContacts.isEmpty &&
                      _databaseUser == null &&
                      !_isLookingUp)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "No matching contacts found",
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Press Enter or tap → to pay this number",
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ] else ...[
                  // Show recents and all contacts when not searching
                  // Recents
                  // Recent People
                  if (_recentPeople.isNotEmpty) ...[
                    Text(
                      "Recent People",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._recentPeople.map((person) => _buildRecentItem(person)),
                    const SizedBox(height: 24),
                  ],

                  // Recent Businesses
                  if (_recentMerchants.isNotEmpty) ...[
                    Text(
                      "Recent Businesses",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._recentMerchants.map(
                      (merchant) => _buildRecentItem(merchant),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // All people on UPI
                  Text(
                    "All people on UPI",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_contacts.isEmpty)
                    _areContactsLoaded
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              "No contacts found or permission denied",
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          )
                        : const Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Center(child: CircularProgressIndicator()),
                          )
                  else
                    ..._contacts.map((contact) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                          child: Text(
                            contact.displayName.isNotEmpty
                                ? contact.displayName[0].toUpperCase()
                                : 'C',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        title: Text(
                          contact.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        subtitle: Text(
                          contact.phones.isNotEmpty
                              ? contact.phones.first.number
                              : '',
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            "New",
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                        onTap: () => _onContactTap(contact),
                      );
                    }),
                ],
              ],
            ),
    );
  }

  Widget _buildRecentItem(dynamic item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String name = item['username'] ?? 'Unknown';
    final upi = item['upi_id'] ?? '';
    final isMerchant = item['mcc'] != null && item['mcc'] != '0000';

    // Clean up default "UserXXX" format
    if (name.startsWith('User') && name.length > 4) {
      if (RegExp(r'^User\d+$').hasMatch(name)) {
        name = name.substring(4);
      }
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: Colors.blue.shade100,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'U',
          style: TextStyle(
            color: Colors.blue.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      subtitle: Text(
        isMerchant ? 'Merchant' : upi,
        style: TextStyle(
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        ),
      ),
      onTap: () {
        _openConversation(item);
      },
    );
  }
}
