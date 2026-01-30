import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

class ContactService extends ChangeNotifier {
  // Singleton
  static final ContactService _instance = ContactService._internal();
  static ContactService get instance => _instance;
  ContactService._internal();

  final ApiService _api = ApiService();

  // Cache
  List<Contact> _contacts = [];
  final Map<String, String> _contactUpiMap = {}; // ID -> UPI Map
  final Set<String> _checkedContactIds = {};

  bool _isLoaded = false;
  bool _isFetching = false;

  // Getters
  List<Contact> get contacts => _contacts;
  Map<String, String> get contactUpiMap => _contactUpiMap;
  Set<String> get checkedContactIds => _checkedContactIds;
  bool get isLoaded => _isLoaded;

  // 1. Silent Pre-fetch (Called from Home)
  Future<void> prefetchContactsIfGranted() async {
    if (_isLoaded || _isFetching) return;

    final status = await Permission.contacts.status;
    if (status.isGranted) {
      // Don't await this, let it run in background
      _fetchAndVerify();
    }
  }

  // 2. Active Fetch (Called from Contacts Screen if needed)
  Future<bool> ensureContactsLoaded() async {
    if (_isLoaded) return true;
    // If already fetching, just wait for it?
    // For simplicity, we just trigger fetch if not running.
    if (_isFetching) {
      // Ideally wait for completion, but for now we rely on the listener to update UI
      return true;
    }

    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (granted) {
      await _fetchAndVerify();
      return true;
    }
    return false;
  }

  Future<void> _fetchAndVerify() async {
    if (_isFetching) return;
    _isFetching = true;
    notifyListeners(); // Notify loading start

    try {
      // A. Load Contacts from Phone
      // Check if we already have contacts loaded to avoid re-reading phone book (slow)
      if (_contacts.isEmpty) {
        final contacts = await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
        );

        contacts.sort(
          (a, b) => (a.displayName).toLowerCase().compareTo(
            (b.displayName).toLowerCase(),
          ),
        );
        _contacts = contacts;
        notifyListeners(); // Contacts loaded, but verification pending
      }

      // B. Batch Identity Check
      // Only verify contacts we haven't checked yet
      await _batchVerifyContacts(_contacts);

      _isLoaded = true;
    } catch (e) {
      print("Contact Pre-fetch Error: $e");
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }

  Future<void> _batchVerifyContacts(List<Contact> contacts) async {
    final List<String> numbersToCheck = [];
    final Map<String, String> phoneToContactId = {};

    // 1. Prepare Numbers (Only unchecked ones)
    for (final contact in contacts) {
      if (_checkedContactIds.contains(contact.id)) continue;

      if (contact.phones.isEmpty) {
        _checkedContactIds.add(contact.id);
        continue;
      }

      for (var phone in contact.phones) {
        String cleaned = phone.number.replaceAll(RegExp(r'[^0-9+]'), '');
        String numberToCheck = cleaned;
        if (cleaned.startsWith('+91')) {
          numberToCheck = cleaned.substring(3);
        }

        if (numberToCheck.length >= 10) {
          numbersToCheck.add(numberToCheck);
          phoneToContactId[numberToCheck] = contact.id;
          break;
        }
      }
    }

    if (numbersToCheck.isEmpty) return;

    // 2. API Call (Batch with Chunking + Live Updates)
    try {
      const int batchSize = 50; // Smaller chunks for faster visual updates
      for (var i = 0; i < numbersToCheck.length; i += batchSize) {
        final end = (i + batchSize < numbersToCheck.length)
            ? i + batchSize
            : numbersToCheck.length;
        final chunk = numbersToCheck.sublist(i, end);

        final results = await _api.checkRegisteredUsers(chunk);

        // 3. Update Cache & Notify Immediately
        for (var entry in results.entries) {
          final phone = entry.key;
          final upi = entry.value;

          final contactId = phoneToContactId[phone];
          if (contactId != null) {
            _contactUpiMap[contactId] = upi;
          }
        }

        // Mark checked IDs for this chunk
        for (var phone in chunk) {
          final id = phoneToContactId[phone];
          if (id != null) _checkedContactIds.add(id);
        }

        notifyListeners(); // <--- LIVE UPDATE UI HERE
      }
    } catch (e) {
      print("Batch Verify Failed: $e");
    }
  }
}
