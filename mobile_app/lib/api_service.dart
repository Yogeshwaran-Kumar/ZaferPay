import 'dart:async';
import 'dart:convert';
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
  Future<void> warmUpIdentity() =>
      _auth.getSavedMobile(); // Triggers cache populate

  // Global PIN Security Tracking
  Future<void> recordFailedAttempt() => _auth.recordFailedAttempt();
  Future<void> resetFailedAttempts() => _auth.resetFailedAttempts();
  int get failedAttempts => _auth.failedAttempts;

  // Mobile Persistence
  Future<String?> getSavedMobile() => _auth.getSavedMobile();
  String? getSavedMobileSync() => _auth.getSavedMobileSync();
  Future<void> saveMobile(String m) => _auth.saveMobile(m);
  Future<void> removeSavedMobile() => _auth.removeSavedMobile();
  void clearCachedMobile() => _auth.clearCachedMobile();
  Future<Map<String, dynamic>> checkMobile(String m) => _auth.checkMobile(m);
  Future<bool> setPin(String m, String p) => _auth.setPin(m, p);
  Future<bool> changeMpin(String currentPin, String newPin) =>
      _auth.changeMpin(currentPin, newPin);
  Future<bool> disableMpin(String currentPin) => _auth.disableMpin(currentPin);
  Future<bool> enableMpin(String newPin) => _auth.enableMpin(newPin);
  Future<bool> changeUpiPin(String currentPin, String newPin) =>
      _auth.changeUpiPin(currentPin, newPin);
  Future<PinVerificationStatus> verifyUpiPin(
    String pin, {
    bool isCirclePayment = false,
  }) => _auth.verifyUpiPin(pin, isCirclePayment: isCirclePayment);
  Future<List<dynamic>?> getLoginHistory() => _auth.getLoginHistory();
  Future<bool> updateSettings({
    bool? biometricEnabled,
    bool? appLockEnabled,
    int? summaryFrequency,
    double? spendingLimit,
    int? spendingLimitPeriod,
    bool clearSpendingLimit = false,
  }) => _auth.updateSettings(
    biometricEnabled: biometricEnabled,
    appLockEnabled: appLockEnabled,
    summaryFrequency: summaryFrequency,
    spendingLimit: spendingLimit,
    spendingLimitPeriod: spendingLimitPeriod,
    clearSpendingLimit: clearSpendingLimit,
  );
  Future<void> syncUserSettings() => _auth.syncUserSettings();

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
  Future<List<Map<String, dynamic>>> searchUsers(String q) =>
      _user.searchUsers(q);
  Future<Map<String, dynamic>> syncContacts(List<String> p) =>
      _user.syncContacts(p);
  Future<Map<String, dynamic>?> getCachedUserByPhone(String p) =>
      _user.getCachedUserByPhone(p);
  Map<String, dynamic>? getCachedUserByPhoneSync(String p) =>
      _user.getCachedUserByPhoneSync(p);
  Map<String, dynamic>? getUserSync() {
    final home = _user.getCachedHomeDataSync();
    return home?['user'];
  }

  // --- UPI Circle Delegates ---
  Future<Map<String, dynamic>> getCircleStatus() => _user.getCircleStatus();
  Future<Map<String, dynamic>> inviteToCircle(
    String upiId,
    double limit,
    String type,
  ) => _user.inviteToCircle(upiId, limit, type);
  Future<bool> respondToCircleInvite(int inviteId, String action) =>
      _user.respondToCircleInvite(inviteId, action);
  Future<bool> updateCircleLimit(int circleId, double newLimit) =>
      _user.updateCircleLimit(circleId, newLimit);
  Future<bool> removeCircleMember(int circleId) =>
      _user.removeCircleMember(circleId);

  // --- Transaction Delegates ---
  Future<Map<String, dynamic>> createTransactionOptimistic(
    String r,
    double a,
    String p, {
    String? mcc,
    String? note,
    String receiverName = 'Unknown',
    bool skipFraudCheck = false,
    String? acknowledgedRisk,
    int? requestId,
    String? paymentSource,
    bool isScreenSharing = false,
    bool isCirclePayment = false,
    int? circleId,
  }) => _tx.createTransactionOptimistic(
    r,
    a,
    p,
    mcc: mcc,
    note: note,
    receiverName: receiverName,
    skipFraudCheck: skipFraudCheck,
    acknowledgedRisk: acknowledgedRisk,
    requestId: requestId,
    paymentSource: paymentSource,
    isScreenSharing: isScreenSharing,
    isCirclePayment: isCirclePayment,
    circleId: circleId,
  );

  // Pre-PIN Risk Analysis
  Future<Map<String, dynamic>> analyzeTransactionRisk(
    String receiverUpi,
    double amount, {
    String? mcc,
    String? note,
    bool isContact = false,
    String? paymentSource,
    bool isScreenSharing = false,
  }) => _tx.analyzeRisk(
    receiverUpi,
    amount,
    mcc: mcc,
    note: note,
    isContact: isContact,
    paymentSource: paymentSource,
    isScreenSharing: isScreenSharing,
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

  Future<Map<String, dynamic>> submitComplaint({
    required String transactionId,
    required String reportedUserUpi,
    required String reason,
    String? description,
    String? senderName,
    String? senderUpiId,
    String? senderBank,
    String? receiverName,
    String? receiverUpiId,
    String? receiverBank,
    String? transactionDate,
    String? transactionTime,
    String? transactionAmount,
  }) => _tx.submitComplaint(
    transactionId: transactionId,
    reportedUserUpi: reportedUserUpi,
    reason: reason,
    description: description,
    senderName: senderName,
    senderUpiId: senderUpiId,
    senderBank: senderBank,
    receiverName: receiverName,
    receiverUpiId: receiverUpiId,
    receiverBank: receiverBank,
    transactionDate: transactionDate,
    transactionTime: transactionTime,
    transactionAmount: transactionAmount,
  );

  Future<Map<String, dynamic>> checkComplaintExists(String transactionId) =>
      _tx.checkComplaintExists(transactionId);

  // --- Notifications ---
  Future<void> markRead(int senderId) async {
    try {
      await _client.post('/notifications/mark-read/$senderId');
    } catch (_) {
      // Best effort, don't crash
    }
  }

  Future<void> markAllRead() async {
    try {
      await _client.post('/notifications/mark-all-read');
    } catch (_) {
      // Best effort
    }
  }

  // --- Admin Methods ---
  Future<Map<String, dynamic>> getAiStats() async {
    final response = await _client.get('/admin/ai-stats');
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    return {};
  }

  Future<Map<String, dynamic>> retrainAi() async {
    final response = await _client.post('/admin/retrain-ai');
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    return {'success': false, 'message': 'Failed to retrain'};
  }

  Future<List<dynamic>> getFraudReports({String status = 'pending'}) async {
    final response = await _client.get('/admin/fraud-reports?status=$status');
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    return [];
  }

  Future<Map<String, dynamic>> confirmFraud(int reportId) async {
    final response = await _client.post('/admin/confirm-fraud/$reportId');
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    return {'success': false, 'message': 'Failed to confirm'};
  }

  Future<Map<String, dynamic>> rejectFraud(int reportId) async {
    final response = await _client.post('/admin/reject-fraud/$reportId');
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    return {'success': false, 'message': 'Failed to reject'};
  }

  Future<void> clearCachedUnreadCounts() => _user.clearCachedUnreadCounts();

  Future<void> clearUserDataCaches() => _user.clearCaches();

  Future<void> clearTransactionDataCaches() => _tx.clearCaches();

  Future<void> wipeAllCaches() async {
    _auth.clearCachedMobile();
    await _user.clearCaches();
    await _tx.clearCaches();
  }
}
