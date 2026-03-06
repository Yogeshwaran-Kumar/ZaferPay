import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../api_service.dart';
import '../contact_service.dart';

class SelectMemberScreen extends StatefulWidget {
  const SelectMemberScreen({super.key});

  @override
  State<SelectMemberScreen> createState() => _SelectMemberScreenState();
}

class _SelectMemberScreenState extends State<SelectMemberScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Timer? _debounceTimer;

  // DB Lookup State
  Map<String, dynamic>? _foundUser;
  List<dynamic> _globalUsers = []; // New list for global name search
  bool _isLookingUp = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _initContacts();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _initContacts() async {
    setState(() => _isLoading = true);
    await ContactService.instance.ensureContactsLoaded();
    if (mounted) {
      setState(() {
        _contacts = ContactService.instance.contacts;
        _filteredContacts = _contacts;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    setState(() {
      _searchQuery = query;
    });

    _debounceTimer?.cancel();
    if (query.isEmpty) {
      setState(() {
        _filteredContacts = _contacts;
        _foundUser = null;
        _globalUsers = [];
        _isLookingUp = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  void _performSearch(String query) async {
    // 1. Filter local contacts
    setState(() {
      _filteredContacts = _contacts.where((c) {
        return c.displayName.toLowerCase().contains(query.toLowerCase()) ||
            c.phones.any((p) => p.number.contains(query));
      }).toList();
    });

    // 2. Database Lookup if it looks like a UPI or Phone
    if (query.contains('@') || _isPhoneNumber(query)) {
      setState(() => _isLookingUp = true);
      Map<String, dynamic>? user;
      if (query.contains('@')) {
        user = await _api.lookupUser(query);
      } else {
        String cleaned = query.replaceAll(RegExp(r'[^\d]'), '');
        if (cleaned.length >= 10) {
          user = await _api.lookupUserByPhone(
            cleaned.substring(cleaned.length - 10),
          );
        }
      }
      if (mounted) {
        setState(() {
          _foundUser = user;
          _globalUsers = []; // Clear global list if specific user found
          _isLookingUp = false;
        });
      }
    } else if (query.length >= 3) {
      // 3. Global Name Search
      setState(() => _isLookingUp = true);
      try {
        final results = await _api.searchUsers(query);
        if (mounted) {
          setState(() {
            _globalUsers = results;
            _foundUser = null;
            _isLookingUp = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isLookingUp = false);
      }
    } else {
      setState(() {
        _foundUser = null;
        _globalUsers = [];
        _isLookingUp = false;
      });
    }
  }

  bool _isPhoneNumber(String q) {
    final cleaned = q.replaceAll(RegExp(r'[^\d]'), '');
    return cleaned.length >= 10;
  }

  void _selectUser(String upi, String name) {
    Navigator.pop(context, {'upi': upi, 'name': name});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Member"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: "Search name, phone or UPI ID",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isLookingUp
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (_foundUser != null || _globalUsers.isNotEmpty) ...[
                  _buildSectionHeader("Global Reach"),
                  if (_foundUser != null)
                    _buildUserTile(
                      _foundUser!['username'] ?? "User",
                      _foundUser!['upi_id'],
                      null, // No icon, use letter
                      isVerified: true,
                      onTap: () => _selectUser(
                        _foundUser!['upi_id'],
                        _foundUser!['username'] ?? "User",
                      ),
                    ),
                  ..._globalUsers.map(
                    (u) => _buildUserTile(
                      u['username'] ?? "User",
                      u['upi_id'] ?? "",
                      null, // No icon, use letter
                      isVerified: true,
                      onTap: () =>
                          _selectUser(u['upi_id'], u['username'] ?? "User"),
                    ),
                  ),
                  const Divider(),
                ],

                if (_searchQuery.isNotEmpty &&
                    _foundUser == null &&
                    _globalUsers.isEmpty &&
                    !_isLookingUp &&
                    (_searchQuery.contains('@') ||
                        _isPhoneNumber(_searchQuery)))
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "User not found in ZaferPay database.",
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                  ),

                _buildSectionHeader(
                  _searchQuery.isEmpty ? "All Contacts" : "Matching Contacts",
                ),
                ..._filteredContacts.map((contact) {
                  final upi = ContactService.instance.contactUpiMap[contact.id];
                  final isRegistered = upi != null;

                  return _buildUserTile(
                    contact.displayName,
                    contact.phones.isNotEmpty
                        ? contact.phones.first.number
                        : "No phone",
                    null, // Use name letter as icon
                    isVerified: isRegistered,
                    customSubtitle: isRegistered ? upi : "Not on ZaferPay",
                    onTap: isRegistered
                        ? () => _selectUser(upi, contact.displayName)
                        : null,
                  );
                }),

                if (_filteredContacts.isEmpty &&
                    _foundUser == null &&
                    _globalUsers.isEmpty &&
                    !_isLookingUp)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text("No matching contacts found")),
                  ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildUserTile(
    String title,
    String subtitle,
    IconData? icon, {
    bool isVerified = false,
    String? customSubtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isVerified
            ? Colors.blue.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.1),
        child: icon != null
            ? Icon(icon, color: isVerified ? Colors.blue : Colors.grey)
            : Text(
                title.isNotEmpty ? title[0].toUpperCase() : 'U',
                style: TextStyle(
                  color: isVerified ? Colors.blue : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
      title: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (isVerified) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified, size: 16, color: Colors.blue),
          ],
        ],
      ),
      subtitle: Text(
        customSubtitle ?? subtitle,
        style: TextStyle(
          color: isVerified ? Colors.blue.shade700 : Colors.grey,
        ),
      ),
      trailing: isVerified
          ? const Icon(Icons.chevron_right, color: Colors.blue)
          : TextButton(
              onPressed: null,
              child: Text(
                "Invite",
                style: TextStyle(color: Colors.grey.shade400),
              ),
            ),
      onTap: onTap,
      enabled: isVerified,
    );
  }
}
