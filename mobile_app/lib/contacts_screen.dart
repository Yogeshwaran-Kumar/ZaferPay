import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

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
  final ApiService _api = ApiService();

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _searchController.addListener(_filterContacts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);

    // Request permission
    final status = await Permission.contacts.request();

    if (status.isGranted) {
      try {
        final contacts = await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
        );

        // Sort contacts alphabetically
        contacts.sort(
          (a, b) => (a.displayName).toLowerCase().compareTo(
            (b.displayName).toLowerCase(),
          ),
        );

        setState(() {
          _contacts = contacts;
          _filteredContacts = contacts;
          _isLoading = false;
          _permissionDenied = false;
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
          _permissionDenied = true;
        });
      }
    } else {
      setState(() {
        _isLoading = false;
        _permissionDenied = true;
      });
    }
  }

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

  Future<void> _selectContact(Contact contact) async {
    if (contact.phones.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This contact has no phone number')),
      );
      return;
    }

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Looking up contact...'),
              ],
            ),
          ),
        ),
      ),
    );

    // Try to lookup by phone number
    String? foundUpi;
    String? foundName;

    for (var phone in contact.phones) {
      // Clean phone number (remove spaces, dashes, etc.)
      String cleanedPhone = phone.number.replaceAll(RegExp(r'[^0-9+]'), '');

      // Try with the original cleaned number first
      var userInfo = await _api.lookupUserByPhone(cleanedPhone);

      if (userInfo != null) {
        foundUpi = userInfo['upi_id'];
        foundName = userInfo['username'];
        break;
      }

      // If not found and number starts with +91, try without country code
      if (cleanedPhone.startsWith('+91')) {
        String phoneWithoutCountryCode = cleanedPhone.substring(
          3,
        ); // Remove +91

        userInfo = await _api.lookupUserByPhone(phoneWithoutCountryCode);

        if (userInfo != null) {
          foundUpi = userInfo['upi_id'];
          foundName = userInfo['username'];
          break;
        }
      }
      // If not found and number doesn't have +91, try WITH country code
      else if (cleanedPhone.length == 10 && !cleanedPhone.startsWith('+')) {
        String phoneWithCountryCode = '+91$cleanedPhone';

        userInfo = await _api.lookupUserByPhone(phoneWithCountryCode);

        if (userInfo != null) {
          foundUpi = userInfo['upi_id'];
          foundName = userInfo['username'];
          break;
        }
      }
    }

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    if (foundUpi != null) {
      // Found UPI ID, return to home screen
      Navigator.pop(context, {
        'upi': foundUpi,
        'name': foundName ?? contact.displayName,
      });
    } else {
      // Not found in database
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${contact.displayName} is not registered on 2Way'),
          backgroundColor: Colors.orange,
        ),
      );
    }
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
            Text(
              'Contact Permission Required',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                'Please grant contact permission to select contacts for payment',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadContacts,
              icon: const Icon(Icons.refresh),
              label: const Text('Grant Permission'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5F259F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_filteredContacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No contacts found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.grey.shade400 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredContacts.length,
      itemBuilder: (context, index) {
        final contact = _filteredContacts[index];
        final hasPhone = contact.phones.isNotEmpty;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF5F259F).withValues(alpha: 0.1),
            child: Text(
              contact.displayName.isNotEmpty
                  ? contact.displayName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Color(0xFF5F259F),
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
              : const Text(
                  'No phone number',
                  style: TextStyle(color: Colors.grey),
                ),
          trailing: hasPhone
              ? Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: isDark ? Colors.grey.shade600 : Colors.grey,
                )
              : null,
          enabled: hasPhone,
          onTap: hasPhone ? () => _selectContact(contact) : null,
        );
      },
    );
  }
}
