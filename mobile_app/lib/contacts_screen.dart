import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:share_plus/share_plus.dart';
import 'contact_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  bool _isLoading = true;
  bool _permissionDenied = false;
  final TextEditingController _searchController = TextEditingController();

  // Contact Verification State
  final Set<String> _checkedContactIds = {}; // IDs that have been checked
  final Map<String, String> _contactUpiMap = {}; // ID -> UPI Map (Found users)

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterContacts);

    // Subscribe to updates for LIVE UI
    ContactService.instance.addListener(_applyServiceData);

    // Initial Load Check
    _initService();
  }

  void _initService() async {
    setState(() => _isLoading = true);
    // If loaded, apply now
    if (ContactService.instance.isLoaded) {
      _applyServiceData();
    }

    // Trigger load if needed (and capable)
    final success = await ContactService.instance.ensureContactsLoaded();
    if (!success && mounted && _contacts.isEmpty) {
      setState(() {
        _isLoading = false;
        _permissionDenied = true;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    ContactService.instance.removeListener(_applyServiceData);
    super.dispose();
  }

  // Called automatically whenever Service calls notifyListeners()
  void _applyServiceData() {
    if (!mounted) return;

    final service = ContactService.instance;
    setState(() {
      _contacts = service.contacts;
      _filteredContacts =
          _contacts; // Note: this resets search filter on update.
      // Ideally we should re-apply filter, but this is simple for now.

      _checkedContactIds.addAll(service.checkedContactIds);
      _contactUpiMap.addAll(service.contactUpiMap);

      _isLoading = false;
      _permissionDenied = false;
    });

    // Re-apply filter if searching
    if (_searchController.text.isNotEmpty) {
      _filterContacts();
    }
  }

  // Legacy method removed/replaced by service call
  // _startBackgroundVerification and _verifyContact are handled by Service now.

  void _filterContacts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredContacts = _contacts;
      } else {
        _filteredContacts = _contacts.where((contact) {
          return contact.displayName.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  void _onPay(Contact contact, String upiId) {
    Navigator.pop(context, {'upi': upiId, 'name': contact.displayName});
  }

  void _onInvite() {
    SharePlus.instance.share(
      ShareParams(text: 'Hey! Join me on 2Way app for secure payments.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Select Contact',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color,
          ),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        iconTheme: Theme.of(context).iconTheme,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: 'Search contacts',
                hintStyle: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark ? Colors.grey.shade400 : Colors.grey,
                ),
                filled: true,
                fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_permissionDenied) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.contacts_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'Contact Permission Required',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Please grant permission to view contacts'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _initService,
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      );
    }

    if (_filteredContacts.isEmpty) {
      return const Center(child: Text("No contacts found"));
    }

    return ListView.builder(
      itemCount: _filteredContacts.length,
      itemBuilder: (context, index) {
        final contact = _filteredContacts[index];
        final hasPhone = contact.phones.isNotEmpty;

        final isChecked = _checkedContactIds.contains(contact.id);
        final upiId = _contactUpiMap[contact.id];
        final isRegistered = upiId != null;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF00B9F1).withValues(alpha: 0.1),
            child: Text(
              contact.displayName.isNotEmpty
                  ? contact.displayName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Color(0xFF00B9F1),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            contact.displayName,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          subtitle: hasPhone
              ? Text(
                  contact.phones.first.number,
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.black54,
                  ),
                )
              : const Text("No phone"),

          trailing: hasPhone
              ? (isChecked
                    ? (isRegistered
                          ? ElevatedButton(
                              onPressed: () => _onPay(contact, upiId),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(
                                  0xFF00B9F1,
                                ), // Blue
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 0,
                              ),
                              child: const Text("Pay"),
                            )
                          : OutlinedButton(
                              onPressed: _onInvite,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade700,
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.grey.shade700
                                      : Colors.grey.shade300,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: const Text("Invite"),
                            ))
                    : const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ))
              : null,
        );
      },
    );
  }
}
