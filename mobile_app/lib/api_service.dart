import 'dart:async';
// import 'package:http/http.dart' as http; // Unused
// import 'package:flutter/foundation.dart'; // Unused

// Import New Services
import 'services/api_client.dart';
import 'services/auth_service.dart';
export 'services/auth_service.dart' show PinVerificationStatus;
import 'services/user_service.dart';
import 'services/transaction_service.dart';

/// FACADE: This class now delegates to the specialized services.
/// It maintains the old API surface to prevent UI breakage.
class ApiService {
  // Instances
  static final ApiClient _client = ApiClient();
  static final AuthService _auth = AuthService(_client);
  static final UserService _user = UserService(_client);
  static final TransactionService _tx = TransactionService(
    _client,
    _auth,
    _user,
  );

  // --- Auth Delegates ---
  Stream<void> get authStateChanges => _auth.authStateChanges;

  Future<String?> login(String u, String p, {bool forceLogin = false}) =>
      _auth.login(u, p, forceLogin: forceLogin);

  Future<void> logout() => _auth.logout();

  // PIN
  Future<PinVerificationStatus> verifyPinSmart(String pin) =>
      _auth.verifyPinSmart(pin);
  Future<bool> verifyPinFast(String pin) async {
    return (await _auth.verifyPinSmart(pin)) == PinVerificationStatus.success;
  }

  Future<void> warmUpPinCache() => _auth.warmUpPinCache();

  // Mobile Persistence
  Future<String?> getSavedMobile() => _auth.getSavedMobile();
  Future<void> saveMobile(String m) => _auth.saveMobile(m);
  Future<void> removeSavedMobile() => _auth.removeSavedMobile();
  Future<Map<String, dynamic>> checkMobile(String m) => _auth.checkMobile(m);
  Future<bool> setPin(String m, String p) => _auth.setPin(m, p);
  Future<bool> changePin(String p) => _auth.changePin(p);
  Future<List<dynamic>?> getLoginHistory() => _auth.getLoginHistory();

  // --- User Delegates ---
  Future<Map<String, dynamic>> getHomeScreenData() => _user.getHomeScreenData();
  Future<Map<String, dynamic>?> getMe() => _user.getMe();

  // Caching
  Map<String, dynamic>? getCachedHomeDataSync() =>
      _user.getCachedHomeDataSync();
  Future<Map<String, dynamic>?> getCachedHomeData() =>
      _user.getCachedHomeData();

  Future<Map<String, dynamic>?> getCachedUser(String id) =>
      _user.getCachedUser(id);
  Future<Map<String, dynamic>?> getCachedMe() => _user.getCachedMe();

  Future<Map<String, dynamic>?> lookupUser(String upi) => _user.lookupUser(upi);
  Future<Map<String, dynamic>?> lookupUserByPhone(String p) =>
      _user.lookupUserByPhone(p);
  Future<Map<String, String>> checkRegisteredUsers(List<String> p) =>
      _user.checkRegisteredUsers(p);
  Future<Map<String, dynamic>?> getCachedUserByPhone(String p) =>
      _user.getCachedUserByPhone(p);
  Map<String, dynamic>? getCachedUserByPhoneSync(String p) =>
      _user.getCachedUserByPhoneSync(p);
  Map<String, dynamic>? getUserSync() {
    final home = _user.getCachedHomeDataSync();
    return home?['user'];
  }

  // --- Transaction Delegates ---
  Future<Map<String, dynamic>> createTransactionOptimistic(
    String r,
    double a,
    String p, {
    String? mcc,
    String? note,
    String receiverName = 'Unknown',
  }) => _tx.createTransactionOptimistic(
    r,
    a,
    p,
    mcc: mcc,
    note: note,
    receiverName: receiverName,
  );

  Future<Map<String, dynamic>> createTransaction(
    String r,
    double a,
    String p, {
    String? mcc,
    String? note,
  }) => _tx.createTransactionOptimistic(r, a, p, mcc: mcc, note: note);

  Future<List<dynamic>?> getHistory() => _tx.getHistory();
  Future<List<dynamic>?> getCachedHistory() => _tx.getCachedHistory();
  List<dynamic>? getHistorySync() => null;

  Future<List<dynamic>?> getConversation(String upi) =>
      _tx.getConversation(upi);
  Future<List<dynamic>?> getCachedConversation(String upi) =>
      _tx.getCachedConversation(upi);
  List<dynamic>? getCachedConversationSync(String upi) =>
      _tx.getCachedConversationSync(upi);

  Future<List<dynamic>?> getRecentPeople() => _tx.getRecentPeople();
  Future<List<dynamic>?> getRecentMerchants() => _tx.getRecentMerchants();
  Future<List<dynamic>?> getCachedRecents(String k) async => null; // Internal

  Future<bool> sendMessage(String t, String c) => _tx.sendMessage(t, c);
  Future<bool> sendMessageOptimistic(
    String t,
    String c,
    Map<String, dynamic> m,
  ) => _tx.sendMessage(t, c);

  // --- Misc / Legacy Stubs ---
  Future<String> get baseUrl => _client.baseUrl;
  Future<bool> checkTamperDetection() async => true;
  Future<String> getDeviceId() async => "device-id-placeholder";
  Future<bool> verifySimBinding() async => true;
  Future<double?> getCachedBalance() async {
    final home = _user.getCachedHomeDataSync();
    return home?['user']?['balance'];
  }

  // --- Fraud Reporting ---
  Future<Map<String, dynamic>> reportFraud({
    required String transactionId,
    required String reason,
    String? description,
  }) => _tx.reportFraud(
    transactionId: transactionId,
    reason: reason,
    description: description,
  );
}
