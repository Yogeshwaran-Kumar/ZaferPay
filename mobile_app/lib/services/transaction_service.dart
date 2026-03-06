import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'user_service.dart';

class TransactionService {
  final ApiClient _apiClient;
  final AuthService _authService;
  final UserService _userService;

  static const String _historyCacheKey = 'history_cache';
  // static const String _balanceCacheKey = 'balance_cache'; // Unused
  static final List<Map<String, dynamic>> _pendingTransactions = [];

  // Conversation Cache
  static final Map<String, List<dynamic>> _ramCache = {};
  static const String _conversationCachePrefix = 'conversation_cache_';

  // HMAC Secret - Must match backend HMAC_SECRET in .env
  // SECURITY: In production, inject via dart-define or secure config
  static const String _hmacSecret = "hK7pL4xN9mQ2wT5yR8vB1cF6gA3jD0sE";
  static int _serverTimeOffsetMs = 0;
  static bool _isTimeSynced = false;

  TransactionService(this._apiClient, this._authService, this._userService);

  // --- Pre-PIN Risk Analysis ---
  Future<Map<String, dynamic>> analyzeRisk(
    String receiverUpi,
    double amount, {
    String? mcc,
    String? note,
    bool isContact = false,
    String?
    paymentSource, // 'qr_scan', 'deep_link', 'manual_entry', 'contact_list'
    bool isScreenSharing = false, // true if AnyDesk/TeamViewer detected
  }) async {
    final body = {
      'receiver_upi_id': receiverUpi,
      'amount': amount,
      'receiver_mcc': mcc,
      'note': note,
      'is_contact': isContact,
      if (paymentSource != null) 'payment_source': paymentSource,
      'is_screen_sharing': isScreenSharing,
    };

    try {
      final response = await _apiClient.post(
        '/transactions/analyze',
        body: body,
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {
        'risk_score': 'SAFE',
        'detail': {'risk': 'SAFE', 'message': 'Analysis Unavailable'},
      };
    } catch (e) {
      if (kDebugMode) print("Risk Analysis Error: $e");
      return {
        'risk_score': 'SAFE',
        'detail': {'risk': 'SAFE', 'message': 'Analysis Offline'},
      };
    }
  }

  // --- Core Transaction Logic ---
  Future<Map<String, dynamic>> createTransactionOptimistic(
    String receiverUpi,
    double amount,
    String pin, {
    String? mcc,
    String? note,
    String receiverName = 'Unknown',
    int? requestId,
    bool isContact = false,
    bool skipFraudCheck = false,
    String? acknowledgedRisk,
    String? paymentSource, // v5.0 scam telemetry
    bool isScreenSharing = false, // v5.0 scam telemetry
    bool isCirclePayment = false,
    int? circleId,
  }) async {
    final txnId = 'TXN${DateTime.now().millisecondsSinceEpoch}';

    // 1. PIN Check
    final pinStatus = await _authService.verifyUpiPin(pin);
    if (pinStatus == PinVerificationStatus.incorrect) {
      return {'status': 'FAILED', 'detail': 'Incorrect PIN'};
    }
    if (pinStatus == PinVerificationStatus.lockedOut) {
      return {'status': 'LOCKED', 'detail': 'Account Locked'};
    }

    // 2. Check Balance & Optimistic Update
    final homeData = _userService.getCachedHomeDataSync();
    if (homeData != null && homeData['user'] != null) {
      final double currentBalance = homeData['user']['balance'] ?? 0.0;
      if (!isCirclePayment && currentBalance < amount) {
        return {'status': 'FAILED', 'detail': 'Insufficient funds'};
      }

      homeData['user']['balance'] = currentBalance - amount;

      final newTx = {
        'id': txnId,
        'amount': amount,
        'receiver_upi_id': receiverUpi,
        'sender_upi_id': homeData['user']['upi_id'],
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'status': 'SUCCESS',
        'receiver_mcc': mcc ?? '0000',
        'receiver_name': receiverName,
        'sender_name': homeData['user']['username'] ?? 'Me',
        'note': note ?? '',
      };

      _pendingTransactions.add(newTx);
      _updateLocalHistory(newTx);

      if (_ramCache.containsKey(receiverUpi)) {
        _ramCache[receiverUpi]!.insert(0, newTx);
        _updateConversationCache(receiverUpi, _ramCache[receiverUpi]!);
      } else {
        _ramCache[receiverUpi] = [newTx];
        _updateConversationCache(receiverUpi, [newTx]);
      }
    }

    // 3. Call Backend and AWAIT Real Response
    final result = await _createRealTransaction(
      receiverUpi,
      amount,
      pin,
      mcc: mcc,
      note: note,
      requestId: requestId,
      isContact: isContact,
      skipFraudCheck: skipFraudCheck,
      acknowledgedRisk: acknowledgedRisk,
      paymentSource: paymentSource,
      isScreenSharing: isScreenSharing,
      isCirclePayment: isCirclePayment,
      circleId: circleId,
    );

    // 4. Handle result
    _pendingTransactions.removeWhere((tx) => tx['id'] == txnId);

    // If the server didn't reject the PIN, it means the PIN was correct.
    if (result['detail'] != 'Incorrect PIN' &&
        result['detail'] != 'Connection Error' &&
        result['detail'] != 'Server Error') {
      await _authService.resetFailedAttempts();
    }

    if (result['status'] == 'SUCCESS' || result['transaction_id'] != null) {
      _userService.getHomeScreenData();
      getConversation(receiverUpi);
      return result;
    } else {
      _userService.getHomeScreenData();
      return result;
    }
  }

  Future<Map<String, dynamic>> _createRealTransaction(
    String receiverUpi,
    double amount,
    String pin, {
    String? mcc,
    String? note,
    int? requestId,
    bool isContact = false,
    bool skipFraudCheck = false,
    String? acknowledgedRisk,
    String? paymentSource, // v5.0 scam telemetry
    bool isScreenSharing = false, // v5.0 scam telemetry
    bool isCirclePayment = false,
    int? circleId,
  }) async {
    try {
      if (!_isTimeSynced) await _syncTime();

      final correctedTime =
          DateTime.now().millisecondsSinceEpoch + _serverTimeOffsetMs;
      final timestampStr = (correctedTime ~/ 1000).toString();
      final idempotencyKey =
          '$correctedTime-${receiverUpi.hashCode}-${amount.hashCode}';

      final body = {
        'receiver_upi_id': receiverUpi,
        'amount': amount,
        'pin': pin,
        'idempotency_key': idempotencyKey,
        if (note != null) 'note': note,
        if (mcc != null && mcc != '0000') 'receiver_mcc': mcc,
        if (requestId != null) 'request_id': requestId,
        'is_contact': isContact,
        'skip_fraud_check': skipFraudCheck,
        if (acknowledgedRisk != null) 'acknowledged_risk': acknowledgedRisk,
        if (paymentSource != null) 'payment_source': paymentSource,
        'is_screen_sharing': isScreenSharing,
        'is_circle_payment': isCirclePayment,
        'circle_id': circleId,
      };

      final signature = _generateHmac(json.encode(body), timestampStr);

      final response = await _apiClient.post(
        '/transactions/',
        body: body,
        headers: {'X-Timestamp': timestampStr, 'X-Signature': signature},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      }

      if (response.statusCode == 401) {
        await _authService.recordFailedAttempt();
        if (_authService.failedAttempts >= 3) {
          return {'status': 'LOCKED', 'detail': 'Account Locked'};
        }
        return {'status': 'FAILED', 'detail': 'Incorrect PIN'};
      }

      if (response.statusCode >= 500) {
        return {'status': 'FAILED', 'detail': 'Server Error'};
      }

      try {
        final error = json.decode(response.body);
        return {
          'status': 'FAILED',
          'detail': error['detail'] ?? 'Transaction Failed',
        };
      } catch (_) {
        return {'status': 'FAILED', 'detail': 'Transaction Failed'};
      }
    } catch (e) {
      if (kDebugMode) print("Tx Error: $e");
      return {'status': 'FAILED', 'detail': 'Connection Error'};
    }
  }

  // --- HMAC & Time ---
  Future<void> _syncTime() async {
    try {
      final start = DateTime.now().millisecondsSinceEpoch;
      final response = await _apiClient.get('/time');
      final end = DateTime.now().millisecondsSinceEpoch;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final serverTs = data['timestamp'] * 1000;
        final latency = (end - start) ~/ 2;
        _serverTimeOffsetMs = (serverTs + latency) - end;
        _isTimeSynced = true;
      }
    } catch (_) {}
  }

  String _generateHmac(String body, String timestamp) {
    final payload = '$timestamp:$body';
    final key = utf8.encode(_hmacSecret);
    final bytes = utf8.encode(payload);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }

  // --- History & Conversation ---
  Future<List<dynamic>?> getHistory() async {
    try {
      final response = await _apiClient.get('/transactions/history');
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (_pendingTransactions.isNotEmpty) {
          data.insertAll(0, _pendingTransactions.cast<dynamic>());
        }
        await _cacheHistory(data);
        return data;
      }
    } catch (_) {}
    return null;
  }

  Future<List<dynamic>?> getCachedHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_historyCacheKey);
      if (jsonString != null) return json.decode(jsonString);
    } catch (_) {}
    return null;
  }

  Future<void> _cacheHistory(List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyCacheKey, json.encode(data));
  }

  Future<List<dynamic>?> getConversation(String upiId) async {
    try {
      final response = await _apiClient.get(
        '/transactions/conversation/${Uri.encodeComponent(upiId)}',
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final pendingForUser = _pendingTransactions
            .where(
              (tx) =>
                  tx['receiver_upi_id'] == upiId ||
                  tx['sender_upi_id'] == upiId,
            )
            .toList();
        if (pendingForUser.isNotEmpty) data.insertAll(0, pendingForUser);

        _updateConversationCache(upiId, data);
        return data;
      }
    } catch (_) {}
    return null;
  }

  // --- Caching Helpers ---
  void _updateLocalHistory(Map<String, dynamic> newTx) {
    // Only RAM update useful here if we expose getHistorySync?
    // Not critical for now as UI usually refetches or observes streams.
  }

  void _updateConversationCache(String upiId, List<dynamic> data) {
    _ramCache[upiId] = data;
    // Async save
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('$_conversationCachePrefix$upiId', json.encode(data));
    });
  }

  List<dynamic>? getCachedConversationSync(String upiId) => _ramCache[upiId];

  Future<List<dynamic>?> getCachedConversation(String upiId) async {
    if (_ramCache.containsKey(upiId)) return _ramCache[upiId];
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(
        '$_conversationCachePrefix$upiId',
      );
      if (jsonString != null) {
        final data = json.decode(jsonString) as List<dynamic>;
        _ramCache[upiId] = data;
        return data;
      }
    } catch (_) {}
    return null;
  }

  // Recents
  Future<List<dynamic>?> getRecentPeople() async {
    final response = await _apiClient.get(
      '/transactions/recent-people?limit=16',
    );
    if (response.statusCode == 200) return json.decode(response.body);
    return null;
  }

  Future<List<dynamic>?> getRecentMerchants() async {
    final response = await _apiClient.get(
      '/transactions/recent-merchants?limit=16',
    );
    if (response.statusCode == 200) return json.decode(response.body);
    return null;
  }

  Future<bool> sendMessage(String targetUpi, String content) async {
    try {
      final response = await _apiClient.post(
        '/messages',
        body: {'receiver_upi_id': targetUpi, 'content': content},
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> reportFraud({
    required String transactionId,
    required String reason,
    String? description,
  }) async {
    try {
      final body = {
        'transaction_id': transactionId,
        'reason': reason,
        if (description != null && description.isNotEmpty)
          'description': description,
      };

      final response = await _apiClient.post('/api/report-fraud', body: body);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        try {
          return json.decode(response.body);
        } catch (_) {
          return {'success': false, 'message': 'Failed to submit report'};
        }
      }
    } catch (e) {
      if (kDebugMode) print("Report Fraud Error: $e");
      return {'success': false, 'message': 'Connection error'};
    }
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
  }) async {
    try {
      final body = {
        'transaction_id': transactionId,
        'reported_user_upi': reportedUserUpi,
        'reason': reason,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (senderName != null) 'sender_name': senderName,
        if (senderUpiId != null) 'sender_upi_id': senderUpiId,
        if (senderBank != null) 'sender_bank': senderBank,
        if (receiverName != null) 'receiver_name': receiverName,
        if (receiverUpiId != null) 'receiver_upi_id': receiverUpiId,
        if (receiverBank != null) 'receiver_bank': receiverBank,
        if (transactionDate != null) 'transaction_date': transactionDate,
        if (transactionTime != null) 'transaction_time': transactionTime,
        if (transactionAmount != null) 'transaction_amount': transactionAmount,
      };

      final response = await _apiClient.post('/complaints', body: body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': json.decode(response.body)};
      } else {
        try {
          final err = json.decode(response.body);
          return {
            'success': false,
            'message': err['detail'] ?? 'Submission failed',
          };
        } catch (_) {
          return {
            'success': false,
            'message': 'Server error: ${response.statusCode}',
          };
        }
      }
    } catch (e) {
      if (kDebugMode) print("Submit Complaint Error: $e");
      return {'success': false, 'message': 'Connection error'};
    }
  }

  Future<Map<String, dynamic>> checkComplaintExists(
    String transactionId,
  ) async {
    try {
      final response = await _apiClient.get('/complaints/check/$transactionId');
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'exists': false};
    } catch (e) {
      if (kDebugMode) print("Check Complaint Error: $e");
      return {'exists': false};
    }
  }

  // --- Payment Requests ---

  /// Request money from another user
  Future<Map<String, dynamic>> requestMoney({
    required String payerUpiId,
    required double amount,
    required String reason,
    String? description,
    String? originalTransactionId,
  }) async {
    try {
      final body = {
        'payer_upi_id': payerUpiId,
        'amount': amount,
        'reason': reason,
        if (description != null) 'description': description,
        if (originalTransactionId != null)
          'original_transaction_id': originalTransactionId,
      };

      final response = await _apiClient.post('/requests', body: body);

      if (response.statusCode == 200) {
        return {'success': true, 'data': json.decode(response.body)};
      } else {
        try {
          final error = json.decode(response.body);
          return {
            'success': false,
            'message': error['detail'] ?? 'Request failed',
          };
        } catch (_) {
          return {'success': false, 'message': 'Request failed'};
        }
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error'};
    }
  }

  /// Cancel or Decline a payment request
  Future<bool> cancelPaymentRequest(int requestId) async {
    try {
      final response = await _apiClient.post('/requests/$requestId/cancel');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Get pending requests for me (Payer)
  Future<List<dynamic>> getPendingRequests() async {
    try {
      final response = await _apiClient.get('/requests/pending');
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (_) {}
    return [];
  }

  /// Get requests I have sent
  Future<List<dynamic>> getSentRequests() async {
    try {
      final response = await _apiClient.get('/requests/sent');
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (_) {}
    return [];
  }

  /// Check if a request exists for a specific transaction
  Future<Map<String, dynamic>?> getRequestForTransaction(
    String transactionId,
  ) async {
    try {
      final response = await _apiClient.get(
        '/requests/for-transaction/$transactionId',
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (_) {}
    return null;
  }

  /// Mark a payment request as paid
  Future<bool> markRequestPaid(int requestId) async {
    try {
      final response = await _apiClient.post('/requests/$requestId/mark-paid');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearCaches() async {
    _ramCache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyCacheKey);
      // Logic to remove conversation caches can be added if needed,
      // but history is the primary 'leaking' UI element.
    } catch (_) {}
  }
}
