import 'dart:async';
import 'package:flutter/foundation.dart'; // Add this for kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'api_service.dart';
import 'mcc_helper.dart';
import 'main.dart';

class PayScreen extends StatefulWidget {
  const PayScreen({super.key});

  @override
  State<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<PayScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _recentPeople = [];

  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  bool _isLoading = true;
  bool _areContactsLoaded = false;
  bool _isSearching = false;
  String _searchQuery = '';

  // For database lookup result
  Map<String, dynamic>? _databaseUser;
  List<dynamic> _globalUsers = []; // New list for global name search
  bool _isLookingUp = false;

  // Contact Verification State
  final Set<String> _checkedContactIds = {}; // IDs that have been checked
  final Map<String, String> _contactUpiMap = {}; // ID -> UPI Map (Found users)
  bool _isCheckerRunning = false;

  // Debounce timer for search
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);

    // 0. Sync Load (True Zero Latency)
    final homeData = _api.getCachedHomeDataSync();
    if (homeData != null) {
      if (homeData['people'] != null) {
        _recentPeople = (homeData['people'] as List).take(6).toList();
      }
      if (_recentPeople.isNotEmpty) {
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

    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _filteredContacts = [];
        _databaseUser = null;
        _globalUsers = [];
        _isLookingUp = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _filterContactsAndLookup(query);
    });
  }

  void _filterContactsAndLookup(String query) {
    // Normalize query - remove all non-digit characters for phone comparison
    final normalizedQuery = query.replaceAll(RegExp(r'[^\d]'), '');
    final bool hasDigits = normalizedQuery.isNotEmpty;

    final queryLast10 = hasDigits && normalizedQuery.length >= 10
        ? normalizedQuery.substring(normalizedQuery.length - 10)
        : normalizedQuery;

    // Filter contacts that match the query (by name or phone number)
    final filtered = _contacts.where((contact) {
      // Check if name matches
      final nameMatch = contact.displayName.toLowerCase().contains(
        query.toLowerCase(),
      );

      // Check if any phone number matches (only if user provided digits)
      bool phoneMatch = false;
      if (hasDigits) {
        phoneMatch = contact.phones.any((phone) {
          final normalizedPhone = phone.number.replaceAll(RegExp(r'[^\d]'), '');
          final phoneLast10 = normalizedPhone.length >= 10
              ? normalizedPhone.substring(normalizedPhone.length - 10)
              : normalizedPhone;

          final isMatch =
              phoneLast10.contains(queryLast10) ||
              queryLast10.contains(phoneLast10) ||
              phoneLast10 == queryLast10;

          return isMatch;
        });
      }

      return nameMatch || phoneMatch;
    }).toList();

    setState(() {
      _filteredContacts = filtered;
    });

    if (_isPhoneNumber(query)) {
      _lookupUserFromDatabase(query);
    } else if (query.contains('@')) {
      _lookupUserByUpi(query);
    } else if (query.length >= 3) {
      // Global Search for Names
      _lookupUsersGlobal(query);
    }
  }

  Future<void> _lookupUsersGlobal(String query) async {
    setState(() => _isLookingUp = true);

    try {
      final results = await _api.searchUsers(query);
      if (mounted) {
        setState(() {
          _globalUsers = results;
          _isLookingUp = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  Future<void> _lookupUserByUpi(String upiId) async {
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
    final digitsOnly = query.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    return digitsOnly.length >= 6 && RegExp(r'^\d+$').hasMatch(digitsOnly);
  }

  Future<void> _lookupUserFromDatabase(String phoneNumber) async {
    final normalizedPhone = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');

    final cached = await _api.getCachedUserByPhone(normalizedPhone);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _databaseUser = cached;
          _isLookingUp = false;
        });
      }
      return;
    }

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
    final cachedPeople = await _api.getCachedRecents('people_cache');

    if (mounted) {
      if (cachedPeople != null) {
        setState(() {
          _recentPeople = cachedPeople.take(6).toList();
          _isLoading = false;
        });
      }
    }

    final people = await _api.getRecentPeople();
    await _loadContacts();

    if (mounted) {
      setState(() {
        _recentPeople = people?.take(6).toList() ?? _recentPeople;
        _isLoading = false;
      });
      // Start verification after loading
      _startBackgroundVerification();
    }
  }

  Future<void> _loadContacts() async {
    try {
      MyApp.isSharing = true;
      final permissionStatus = await Permission.contacts.request();

      if (permissionStatus.isGranted) {
        final contacts = await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
          withAccounts: true,
        );

        final contactsWithPhones = contacts
            .where((c) => c.phones.isNotEmpty)
            .toList();

        // Sort
        contactsWithPhones.sort(
          (a, b) => a.displayName.compareTo(b.displayName),
        );

        if (mounted) {
          setState(() {
            _contacts = contactsWithPhones;
          });
        }
      }
    } catch (e) {
      // Ignore
    } finally {
      if (mounted) {
        setState(() {
          _areContactsLoaded = true;
        });
      }
    }
  }

  Future<void> _startBackgroundVerification() async {
    if (_isCheckerRunning) return;
    _isCheckerRunning = true;

    for (final contact in _contacts) {
      if (!mounted) break;
      if (_contactUpiMap.containsKey(contact.id)) continue;
      if (_checkedContactIds.contains(contact.id)) continue;

      await _verifyContact(contact);
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _isCheckerRunning = false;
  }

  Future<void> _verifyContact(Contact contact) async {
    if (contact.phones.isEmpty) {
      if (mounted) setState(() => _checkedContactIds.add(contact.id));
      return;
    }
    String? foundUpi;
    for (var phone in contact.phones) {
      String cleaned = phone.number.replaceAll(RegExp(r'[^0-9+]'), '');
      String numberToCheck = cleaned;
      if (cleaned.startsWith('+91')) {
        numberToCheck = cleaned.substring(3);
      }
      if (numberToCheck.length < 10) continue;

      final user = await _api.lookupUserByPhone(numberToCheck);
      if (user != null && user['upi_id'] != null) {
        foundUpi = user['upi_id'];
        break;
      }
    }
    if (mounted) {
      setState(() {
        _checkedContactIds.add(contact.id);
        if (foundUpi != null) _contactUpiMap[contact.id] = foundUpi;
      });
    }
  }

  void _onInvite() {
    SharePlus.instance.share(
      ShareParams(text: 'Hey! Join me on 2Way app for secure payments.'),
    );
  }

  Future<void> _onPay(String upi, String? name, {String? category}) async {
    await Navigator.pushNamed(
      context,
      '/amount',
      arguments: {'upi': upi, 'name': name, 'category': category},
    );
    if (mounted) {
      _loadData();
    }
  }

  void _openConversation(dynamic person) {
    Navigator.pushNamed(
      context,
      '/conversation',
      arguments: {
        'upi': person['upi_id'] ?? person['upi'] ?? '',
        'name': person['username'] ?? person['name'] ?? 'User',
        'mobile': person['mobile_encrypted'] ?? person['mobile'] ?? '',
        'isMerchant': person['isMerchant'] ?? false,
        'isValid':
            person['isValid'] ??
            true, // Default to true for backend data (e.g. Recent People)
      },
    );
  }

  Future<void> _onContactTap(Contact contact) async {
    // If verified, go to conversation
    if (_contactUpiMap.containsKey(contact.id)) {
      _openConversation({
        'upi_id': _contactUpiMap[contact.id],
        'username': contact.displayName,
        'mobile_encrypted': contact.phones.isNotEmpty
            ? contact.phones.first.number
            : '',
        'isMerchant': false,
        'isValid': true,
      });
      return;
    }

    // Fallback: Perform lookup logic if tap happens before background check finishes
    if (contact.phones.isEmpty) return;
    setState(() => _isLookingUp = true);

    String originalPhone = contact.phones.first.number;
    String normalizedPhone = originalPhone.replaceAll(
      RegExp(r'[\s\-\(\)]'),
      '',
    );
    if (normalizedPhone.startsWith('+91')) {
      normalizedPhone = normalizedPhone.substring(3);
    }

    String? displayName = contact.displayName;
    String upiIdOrPhone = normalizedPhone;
    bool isMerchant = false;
    bool isValid = false;

    try {
      final user = await _api.lookupUserByPhone(normalizedPhone);
      if (user != null) {
        // displayName = _getDisplayName(user); // Keep contact name
        upiIdOrPhone = user['upi_id'] ?? normalizedPhone;
        isMerchant = MccHelper.isMerchant(user['mcc']);
        isValid = true;
      }
    } catch (e) {
      if (kDebugMode) print("Contact Lookup Error: $e");
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }

    if (mounted) {
      _openConversation({
        'upi_id': upiIdOrPhone,
        'username': displayName,
        'mobile_encrypted': originalPhone,
        'isMerchant': isMerchant,
        'isValid': isValid,
      });
    }
  }

  Future<void> _onSearchSubmit(String value) async {
    if (value.isEmpty) return;
    String? upiOrPhone = value;
    String? displayName;
    bool isMerchant = false;

    if (value.contains('@')) {
      setState(() => _isLookingUp = true);
      final user = await _api.lookupUser(value);
      setState(() => _isLookingUp = false);

      if (user != null) {
        displayName = _getDisplayName(user);
        upiOrPhone = user['upi_id'] ?? value;
        isMerchant = MccHelper.isMerchant(user['mcc']);
      }
      _openConversation({
        'upi_id': upiOrPhone ?? value,
        'username': displayName,
        'mobile_encrypted': '',
        'isMerchant': isMerchant,
        'isValid': true,
      });
      return;
    }

    final normalizedValue = value.replaceAll(RegExp(r'[^\d]'), '');
    if (_isPhoneNumber(value)) {
      final valueLast10 = normalizedValue.length >= 10
          ? normalizedValue.substring(normalizedValue.length - 10)
          : normalizedValue;

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

      bool isValid = false;

      if (displayName == null) {
        setState(() => _isLookingUp = true);
        final user = await _api.lookupUserByPhone(normalizedValue);
        setState(() => _isLookingUp = false);
        if (user != null) {
          displayName = _getDisplayName(user);
          isMerchant = MccHelper.isMerchant(user['mcc']);
          isValid = true;
        }
      } else {
        // If found in contacts, we need to verify if it's a valid ZaferPay user
        // But for search by number, we can assume valid for now or do a quick check
        // Ideally we should check if they are on ZaferPay.
        // For now, let's mark true if they were found via explicit number search and we assume user knows.
        // Or better, do a background check if not already done.
        isValid =
            true; // defaulting to true for explicit number entry, but let's check.
        // Actually, if it's a contact, we might not know if they are on ZaferPay yet unless we checked.
        // Let's do a quick check if not checked.
        try {
          final user = await _api.lookupUserByPhone(normalizedValue);
          if (user != null) isValid = true;
        } catch (e) {
          // Ignore: Contact might not be on ZaferPay or network issue
        }
      }

      _openConversation({
        'upi_id': normalizedValue,
        'username': displayName,
        'mobile_encrypted': normalizedValue,
        'isMerchant': isMerchant,
        'isValid': isValid,
      });
      return;
    }

    if (_filteredContacts.isNotEmpty) {
      final contact = _filteredContacts.first;
      if (contact.phones.isNotEmpty) {
        final phone = contact.phones.first.number.replaceAll(
          RegExp(r'\s+'),
          '',
        );
        final upiId = _contactUpiMap[contact.id];

        _openConversation({
          'upi_id': upiId ?? phone,
          'username': contact.displayName,
          'mobile_encrypted': phone,
          'isMerchant': false,
          'isValid':
              upiId !=
              null, // Valid only if we found a UPI ID (meaning they are on ZaferPay)
        });
        return;
      }
    }
    _openConversation({
      'upi_id': value,
      'username': null,
      'mobile_encrypted': '',
      'isMerchant': false,
      'isValid': false,
    });
  }

  String _getDisplayName(Map<String, dynamic> user) {
    String name = user['username'] ?? 'Unknown';
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

                // Search Results
                if (_isSearching) ...[
                  // Global Results (Database search)
                  if (_databaseUser != null || _globalUsers.isNotEmpty) ...[
                    const Text(
                      "Global Search Results",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_databaseUser != null)
                      _buildUserSearchResult(_databaseUser!),
                    ..._globalUsers.map((user) => _buildUserSearchResult(user)),
                    const SizedBox(height: 16),
                  ],

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

                  if (_filteredContacts.isEmpty &&
                      _databaseUser == null &&
                      _globalUsers.isEmpty &&
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
                            "No matching users found",
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                ] else ...[
                  // Recents
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

                  // All Contacts
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
                              "No contacts found",
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          )
                        : const Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Center(child: CircularProgressIndicator()),
                          )
                  else
                    ..._contacts.map((contact) {
                      final isChecked = _checkedContactIds.contains(contact.id);
                      final upiId = _contactUpiMap[contact.id];
                      final isRegistered = upiId != null;

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
                        trailing: isChecked
                            ? (isRegistered
                                  ? GestureDetector(
                                      onTap: () =>
                                          _onPay(upiId, contact.displayName),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00B9F1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Text(
                                          "Pay",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    )
                                  : GestureDetector(
                                      onTap: _onInvite,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Text(
                                          "Invite",
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ))
                            : const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
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
    final isMerchant = MccHelper.isMerchant(item['mcc']);

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

  Widget _buildUserSearchResult(Map<String, dynamic> user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = _getDisplayName(user);
    final upiId = user['upi_id'] ?? '';
    final mcc = user['mcc'];
    final isMerchant = MccHelper.isMerchant(mcc);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Colors.blue,
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Text(
        displayName,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            upiId,
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          if (isMerchant) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '🏪 ${MccHelper.getDomain(mcc)}',
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          "Pay",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      onTap: () => _openConversation({
        'upi_id': upiId,
        'username': displayName,
        'isMerchant': isMerchant,
        'isValid': true,
      }),
    );
  }
}
