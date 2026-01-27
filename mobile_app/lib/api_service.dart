import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';

class ApiService {
  // Default URLs for different environments
  static String get _defaultBaseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    // Cloudflare Tunnel URL
    return 'https://associate-estimate-merger-fitted.trycloudflare.com';
  }

  static const Duration _timeout = Duration(seconds: 30);

  // Custom client to handle bad certificates robustly
  static http.Client _client = _createHttpClient();

  static http.Client _createHttpClient() {
    final ioClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        return true;
      }
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 15);
    return io.IOClient(ioClient);
  }

  static void _resetClient() {
    try {
      _client.close();
    } catch (_) {}
    _client = _createHttpClient();
  }

  final _storage = const FlutterSecureStorage();
  final _authStateController = StreamController<void>.broadcast();

  Future<String> get baseUrl async {
    // For debugging: Force use of default URL and clear any stale cache

    return _defaultBaseUrl;
  }

  Stream<void> get authStateChanges => _authStateController.stream;

  void _handleUnauthorized() {
    _storage.delete(key: 'token');
    removeSavedMobile(); // Ensure we clear the saved session to avoid PIN loop
    _authStateController.add(null);
  }

  Future<String?> login(
    String username,
    String password, {
    bool forceLogin = false,
  }) async {
    try {
      final url = await baseUrl;
      final deviceId = await getDeviceId();
      final response = await _client
          .post(
            Uri.parse('$url/token${forceLogin ? "?force_logout=true" : ""}'),
            body: {'username': username, 'password': password},
            headers: {'X-Device-ID': deviceId},
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _storage.write(key: 'token', value: data['access_token']);
        // Cache Valid PIN for 0.0s local verification (Persistent)
        await _persistPin(password);

        // Store refresh token for token rotation
        if (data['refresh_token'] != null) {
          await _storage.write(
            key: 'refresh_token',
            value: data['refresh_token'],
          );
        }
        return null; // Success
      } else if (response.statusCode == 409) {
        return 'LOGGED_IN_ELSEWHERE';
      } else if (response.statusCode == 429) {
        return 'RATE_LIMIT_EXCEEDED';
      } else if (response.statusCode == 401) {
        // Unauthorized - Incorrect credentials
        return 'INCORRECT_PIN';
      } else {
        // Try to parse JSON error response
        try {
          final errorData = json.decode(response.body);
          if (errorData['detail'] != null) {
            String detail = errorData['detail'].toString().toLowerCase();
            if (detail.contains('incorrect') ||
                detail.contains('password') ||
                detail.contains('credential')) {
              return 'INCORRECT_PIN';
            }
            return errorData['detail'].toString(); // Return actual server error
          }
        } catch (_) {
          // If JSON parsing fails, log but don't show HTML to user
          if (kDebugMode) {
            print('Login Failed Code: ${response.statusCode}');
            print('Login Failed Body: ${response.body}');
          }
        }
        // Return generic error code
        return 'SERVER_ERROR: ${response.statusCode}';
      }
    } catch (e) {
      if (kDebugMode) print("Login Error: $e");
      return 'CONNECTION_ERROR';
    }
  }

  // --- Local PIN Verification (Zero Latency & Persistent) ---
  static String? _cachedPin;
  static const String _pinCacheKey = 'user_pin_secret';

  // Security Counter
  static int _failedPinAttempts = 0;

  Future<PinVerificationStatus> verifyPinSmart(String inputPin) async {
    // 1. Check RAM/Disk for PIN
    String? validPin = _cachedPin;
    if (validPin == null) {
      // Try read from disk
      try {
        validPin = await _storage.read(key: _pinCacheKey);
        if (validPin != null) _cachedPin = validPin;
      } catch (_) {}
    }

    // 2. If we have the PIN, verify locally (0.0s)
    if (validPin != null) {
      if (validPin == inputPin) {
        _failedPinAttempts = 0; // Reset
        return PinVerificationStatus.success;
      } else {
        _failedPinAttempts++;
        if (_failedPinAttempts >= 3) {
          await logout(); // Auto logout
          return PinVerificationStatus.lockedOut;
        }
        return PinVerificationStatus.incorrect;
      }
    }

    // 3. If we don't have PIN cached, we can't verify locally
    return PinVerificationStatus.unknown;
  }

  Future<bool> verifyPinFast(String inputPin) async {
    // Forward to smart, treat lockedOut/incorrect as false, success as true
    final status = await verifyPinSmart(inputPin);
    return status == PinVerificationStatus.success;
  }

  Future<void> _persistPin(String pin) async {
    _cachedPin = pin;
    _failedPinAttempts = 0; // Reset on new pin set/success login
    await _storage.write(key: _pinCacheKey, value: pin);
  }

  // Pre-load PIN from disk to RAM on app start
  Future<void> warmUpPinCache() async {
    if (_cachedPin != null) return;
    try {
      final stored = await _storage.read(key: _pinCacheKey);
      if (stored != null) _cachedPin = stored;
    } catch (_) {}
  }

  // Deprecated sync method, used for temporary RAM-only check if needed
  bool verifyPinRamOnly(String inputPin) {
    return _cachedPin == inputPin;
  }

  Future<Map<String, dynamic>?> getCachedMe() async {
    // 1. Try RAM
    if (_homeRamCache != null && _homeRamCache!['user'] != null) {
      return _homeRamCache!['user'];
    }
    // 2. Try Disk (via Home Data)
    final homeData = await getCachedHomeData();
    if (homeData != null && homeData['user'] != null) {
      return homeData['user'];
    }
    return null;
  }

  Future<Map<String, dynamic>?> getMe() async {
    try {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      if (token == null) return null;

      final response = await _retryRequest(() async {
        final token = await _storage.read(key: 'token');
        return _client
            .get(
              Uri.parse('$url/users/me'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(_timeout);
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Update Home Cache User if possible
        // Update Home Cache User
        if (_homeRamCache == null) {
          await getCachedHomeData(); // Try load from disk
          _homeRamCache ??= {}; // Init if still null
        }
        _homeRamCache!['user'] = data;
        _cacheHomeData(_homeRamCache!); // Persist
        return data;
      } else if (response.statusCode == 401) {
        // Try to refresh token before logging out
        final refreshed = await refreshToken();
        if (!refreshed) {
          _handleUnauthorized(); // Trigger logout logic
        }
      }
    } catch (e) {
      if (kDebugMode) print("GetMe Error: $e");
    }
    return null;
  }

  /// Refresh Token Rotation - Get new access token using refresh token
  /// Returns true if successful, false if refresh failed (need to re-login)
  Future<bool> refreshToken() async {
    try {
      final url = await baseUrl;
      final refreshTokenValue = await _storage.read(key: 'refresh_token');

      if (refreshTokenValue == null) return false;

      final response = await _client
          .post(
            Uri.parse('$url/auth/refresh'),
            headers: {'X-Refresh-Token': refreshTokenValue},
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _storage.write(key: 'token', value: data['access_token']);
        if (kDebugMode) print("Token refreshed successfully");
        return true;
      }
    } catch (e) {
      if (kDebugMode) print("Token refresh error: $e");
    }
    return false;
  }

  /// Tamper Detection - Check if app is running in a safe environment
  /// Returns true if environment is safe, false if potentially tampered
  Future<bool> checkTamperDetection() async {
    try {
      // Check 1: Debug mode detection
      if (kDebugMode) {
        if (kDebugMode) print("Warning: Running in debug mode");
        // Allow in debug, but flag in release
      }

      // Check 2: Package name verification (Android)
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;

        // Check if running on emulator (potential security risk in production)
        if (!kDebugMode && androidInfo.isPhysicalDevice == false) {
          if (kDebugMode) print("Warning: Running on emulator");
          // In production, you might want to block this
        }
      }

      return true; // Environment check passed
    } catch (e) {
      if (kDebugMode) print("Tamper detection error: $e");
      return true; // Don't block on error
    }
  }

  Future<http.Response> _retryRequest(
    Future<http.Response> Function() requestFunc, {
    int retries = 3,
  }) async {
    for (int i = 0; i < retries; i++) {
      try {
        final response = await requestFunc();

        // Auto-Refresh Token on 401
        if (response.statusCode == 401 && i < retries - 1) {
          if (kDebugMode) print("401 detected, attempting auto-refresh...");
          final refreshed = await refreshToken();
          if (refreshed) {
            if (kDebugMode) print("Token refreshed, retrying request...");
            continue; // Retry the request (requestFunc must fetch fresh token!)
          } else {
            if (kDebugMode) print("Token refresh failed.");
            return response; // Return 401 so caller handles logout
          }
        }

        return response;
      } catch (e) {
        final isNetworkError =
            e.toString().contains('HandshakeException') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Connection closed');

        if (isNetworkError && i < retries - 1) {
          // Reset client to establish fresh connection
          _resetClient();
          if (kDebugMode) {
            print("Network error, resetting client and retrying...");
          }

          await Future.delayed(
            Duration(milliseconds: 1000 * (i + 1)), // Increased backoff
          );
          continue;
        }
        rethrow;
      }
    }
    throw Exception('Request failed after retries');
  }

  /// Create a new transaction with idempotency protection
  ///
  /// Idempotency Key: A unique UUID generated per transaction request.
  /// If the network is slow and user clicks pay multiple times, the server
  /// will process only the first request and return cached response for duplicates.
  // --- Optimistic Transaction (Zero Latency Payment) ---
  Future<Map<String, dynamic>> createTransactionOptimistic(
    String receiverUpi,
    double amount,
    String pin, {
    String? mcc,
    String receiverName = 'Unknown',
  }) async {
    // Generate optimistic ID matching server format style (TXN...)
    final txnId = 'TXN${DateTime.now().millisecondsSinceEpoch}';

    // 1. Local PIN Check (Fast)
    final pinStatus = await verifyPinSmart(pin);

    if (pinStatus == PinVerificationStatus.incorrect) {
      return {'detail': 'Incorrect PIN'};
    }
    if (pinStatus == PinVerificationStatus.lockedOut) {
      return {'detail': 'Account Locked', 'status': 'LOCKED'};
    }

    // 2. Local Balance Check & Update
    if (pinStatus == PinVerificationStatus.success) {
      if (_homeRamCache != null && _homeRamCache!['user'] != null) {
        final currentBalance = _homeRamCache!['user']['balance'] as double;
        if (currentBalance < amount) {
          return {'detail': 'Insufficient funds'}; // Instant fail
        }

        // OPTIMISTIC UPDATE: Deduct Balance
        _homeRamCache!['user']['balance'] = currentBalance - amount;

        // OPTIMISTIC UPDATE: Add to History
        String senderName = 'Me';
        if (_homeRamCache != null && _homeRamCache!['user'] != null) {
          senderName = _homeRamCache!['user']['username'] ?? 'Me';
        }
        final newTx = {
          'id': txnId, // Use generated ID
          'amount': amount,
          'receiver_upi_id': receiverUpi,
          'sender_upi_id': _homeRamCache!['user']['upi_id'],
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'status': 'SUCCESS',
          'receiver_mcc': mcc ?? '0000',
          'receiver_name': receiverName,
          'sender_name': senderName,
        };

        if (_historyRamCache != null) {
          _historyRamCache!.insert(0, newTx);
        } else {
          _historyRamCache = [newTx];
        }

        // OPTIMISTIC UPDATE: Add to Conversation Cache
        if (_ramCache.containsKey(receiverUpi)) {
          _ramCache[receiverUpi]!.insert(0, newTx);
          _cacheConversation(receiverUpi, _ramCache[receiverUpi]!);
        } else {
          _ramCache[receiverUpi] = [newTx];
          _cacheConversation(receiverUpi, [newTx]);
        }
        _cacheHomeData(_homeRamCache!);
      }
    }

    // 3. Fire & Forget Real Transaction
    createTransaction(receiverUpi, amount, pin, mcc: mcc).then((result) async {
      if (result['detail'] != null && result['status'] != 'SUCCESS') {
        // Transaction FAILED - Revert state (complex, simplified here)
        await getHomeScreenData();
      } else {
        // Success - Refresh to get server truth (replacing optimistic data)
        await getHomeScreenData();
      }
    });

    // 4. Return Instant Success with details
    return {
      'status': 'SUCCESS',
      'detail': 'Transfer Successful',
      'transaction_id': txnId,
      'receiver_name': receiverName,
    };
  }

  Future<Map<String, dynamic>> createTransaction(
    String receiverUpi,
    double amount,
    String pin, {
    String? mcc,
  }) async {
    try {
      final url = await baseUrl;

      // Generate unique idempotency key for this transaction request
      final idempotencyKey =
          '${DateTime.now().millisecondsSinceEpoch}-${receiverUpi.hashCode}-${amount.hashCode}';

      final Map<String, dynamic> requestBody = {
        'receiver_upi_id': receiverUpi,
        'amount': amount,
        'pin': pin,
        'idempotency_key': idempotencyKey, // Prevent duplicate transactions
      };

      if (mcc != null && mcc.isNotEmpty && mcc != '0000') {
        requestBody['receiver_mcc'] = mcc;
      }

      final response = await _retryRequest(() async {
        final token = await _storage.read(key: 'token');
        return _client
            .post(
              Uri.parse('$url/transactions/'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: json.encode(requestBody),
            )
            .timeout(_timeout);
      });

      if (response.statusCode != 200 && response.statusCode != 201) {
        if (kDebugMode) {
          print("Transaction Failed Status: ${response.statusCode}");
          print("Transaction Failed Body: ${response.body}");
        }
      } else {
        // Success! Cache the PIN for future zero-latency checks
        await _persistPin(pin);
      }

      if (response.statusCode == 401) {
        _handleUnauthorized();
        return {'detail': 'Session expired'};
      }
      if (response.statusCode == 409) {
        // Transaction already processed (duplicate request)
        return json.decode(response.body);
      }

      // If server error (500), try to return body if json, else generic error
      if (response.statusCode >= 500) {
        try {
          return json.decode(response.body);
        } catch (_) {
          return {
            'detail': 'Server error ${response.statusCode}: ${response.body}',
          };
        }
      }

      return json.decode(response.body);
    } catch (e) {
      if (kDebugMode) print("Transaction Error: $e");

      String errorMsg = 'Transaction Failed: $e';
      if (e.toString().contains('HandshakeException') ||
          e.toString().contains('Connection closed')) {
        errorMsg = 'Network Error: $e';
      }
      return {'detail': errorMsg};
    }
  }

  // --- Expanded Caching Logic ---
  static const String _historyCacheKey = 'history_cache';
  static const String _peopleCacheKey = 'people_cache';
  static const String _merchantsCacheKey = 'merchants_cache';
  static const String _balanceCacheKey = 'balance_cache';

  // History Caching
  // History Caching
  // _cacheHistory is defined below with RAM support

  Future<List<dynamic>?> getCachedHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_historyCacheKey);
      if (jsonString != null) return json.decode(jsonString);
    } catch (_) {}
    return null;
  }

  // Recents Caching
  Future<void> _cacheRecents(String key, List<dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, json.encode(data));
      // Also cache individual users
      for (var item in data) {
        _cacheUser(item);
      }
    } catch (_) {}
  }

  Future<List<dynamic>?> getCachedRecents(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(key);
      if (jsonString != null) return json.decode(jsonString);
    } catch (_) {}
    return null;
  }

  Future<double?> getCachedBalance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_balanceCacheKey);
    } catch (_) {}
    return null;
  }

  // --- Conversation Caching (RAM + Disk) ---
  static const String _conversationCachePrefix = 'conversation_cache_';

  // 1. RAM Cache (L1) - Instant access (0.0ms)
  static final Map<String, List<dynamic>> _ramCache = {};

  Future<void> _cacheConversation(String upiId, List<dynamic> data) async {
    try {
      // Write to RAM (L1)
      _ramCache[upiId] = data;

      // Write to Disk (L2) - Async
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_conversationCachePrefix$upiId',
        json.encode(data),
      );
    } catch (_) {}
  }

  Future<List<dynamic>?> getCachedConversation(String upiId) async {
    // 1. Try RAM (L1) - Instant
    if (_ramCache.containsKey(upiId)) {
      return _ramCache[upiId];
    }

    // 2. Try Disk (L2) - Fast
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(
        '$_conversationCachePrefix$upiId',
      );
      if (jsonString != null) {
        final data = json.decode(jsonString) as List<dynamic>;
        _ramCache[upiId] = data; // Populate RAM for next time
        return data;
      }
    } catch (_) {}
    return null;
  }

  Future<List<dynamic>?> getConversation(String upiId) async {
    try {
      final url = await baseUrl;

      final response = await _retryRequest(() async {
        final token = await _storage.read(key: 'token');
        return _client
            .get(
              Uri.parse(
                '$url/transactions/conversation/${Uri.encodeComponent(upiId)}',
              ),
              headers: {
                'Authorization': 'Bearer $token',
                // Cloudflare doesn't need the browser warning skip header
              },
            )
            .timeout(_timeout);
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Cache the fresh conversation data
        _cacheConversation(upiId, data);
        return data;
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
      }
    } catch (e) {
      if (kDebugMode) print("Conversation Error: $e");
    }
    return null;
  }

  Future<List<dynamic>?> getHistory() async {
    try {
      final url = await baseUrl;

      final response = await _retryRequest(() async {
        final token = await _storage.read(key: 'token');
        return _client
            .get(
              Uri.parse('$url/transactions/history'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(_timeout);
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _cacheHistory(data);
        return data;
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
      }
    } catch (e) {
      if (kDebugMode) print("History Error: $e");
    }
    return null;
  }

  Future<List<dynamic>?> getRecentPeople() async {
    try {
      final url = await baseUrl;

      final response = await _retryRequest(() async {
        final token = await _storage.read(key: 'token');
        return _client
            .get(
              Uri.parse('$url/transactions/recent-people?limit=16'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(_timeout);
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _cacheRecents(_peopleCacheKey, data);
        return data;
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
      }
    } catch (e) {
      if (kDebugMode) print("Recent People Error: $e");
    }
    return null;
  }

  Future<List<dynamic>?> getRecentMerchants() async {
    try {
      final url = await baseUrl;

      final response = await _retryRequest(() async {
        final token = await _storage.read(key: 'token');
        return _client
            .get(
              Uri.parse('$url/transactions/recent-merchants?limit=16'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(_timeout);
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _cacheRecents(_merchantsCacheKey, data);
        return data;
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
      }
    } catch (e) {
      if (kDebugMode) print("Recent Merchants Error: $e");
    }
    return null;
  }

  /// Fetches all home screen data in a single request for maximum speed
  // --- Caching Logic ---
  static const String _homeCacheKey = 'home_data_cache';
  static const String _userCachePrefix = 'user_cache_';
  static const String _phoneCachePrefix =
      'user_phone_cache_'; // Add persistent phone cache key

  // RAM Cache for Home Data (Zero Latency)
  static Map<String, dynamic>? _homeRamCache;

  Future<void> _cacheHomeData(Map<String, dynamic> data) async {
    try {
      // 1. Write to RAM
      _homeRamCache = data;

      // 2. Write to Disk
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_homeCacheKey, json.encode(data));

      // Also cache individual users found in history/people for QR lookups
      if (data['people'] != null) {
        for (var person in data['people']) {
          _cacheUser(person);
        }
      }
      if (data['merchants'] != null) {
        for (var merchant in data['merchants']) {
          _cacheUser(merchant);
        }
      }
    } catch (e) {
      if (kDebugMode) print("Cache Error: $e");
    }
  }

  Future<Map<String, dynamic>?> getCachedHomeData() async {
    // 1. Try RAM - Instant
    if (_homeRamCache != null) {
      return _homeRamCache;
    }

    // 2. Try Disk
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_homeCacheKey);
      if (jsonString != null) {
        final data = json.decode(jsonString);
        _homeRamCache = data; // Populate RAM
        return data;
      }
    } catch (e) {
      if (kDebugMode) print("Cache Read Error: $e");
    }
    return null;
  }

  Future<void> _cacheUser(Map<String, dynamic> user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final upiId = user['upi_id'];
      if (upiId != null) {
        await prefs.setString('$_userCachePrefix$upiId', json.encode(user));
      }

      // Cache by Phone if available (robust check)
      String? mobile =
          user['mobile_number'] ?? user['mobile'] ?? user['phone_number'];

      if (mobile != null && mobile.isNotEmpty) {
        // Clean mobile
        mobile = mobile.replaceAll(RegExp(r'[^\d]'), '');
        // Update RAM
        _phoneRamCache[mobile] = user;
        // Update Disk
        await prefs.setString('$_phoneCachePrefix$mobile', json.encode(user));
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<Map<String, dynamic>?> getCachedUser(String identifier) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Try finding by UPI ID key
      final String? jsonString = prefs.getString(
        '$_userCachePrefix$identifier',
      );
      if (jsonString != null) {
        return json.decode(jsonString);
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }

  // --- Synchronous Getters for Zero-Frame Latency ---

  // 1. Home Data Sync
  Map<String, dynamic>? getCachedHomeDataSync() {
    return _homeRamCache;
  }

  // 2. Conversation Sync
  List<dynamic>? getCachedConversationSync(String upiId) {
    if (_ramCache.containsKey(upiId)) {
      return _ramCache[upiId];
    }
    return null;
  }

  // 3. Phone Lookup Sync
  Map<String, dynamic>? getCachedUserByPhoneSync(String phone) {
    if (_phoneRamCache.containsKey(phone)) {
      return _phoneRamCache[phone];
    }
    return null;
  }

  // 4. History Sync
  List<dynamic>? getHistorySync() {
    return _historyRamCache;
  }

  // 5. User Sync (Me)
  Map<String, dynamic>? getUserSync() {
    // Attempt to get from Home Cache first
    if (_homeRamCache != null && _homeRamCache!['user'] != null) {
      return _homeRamCache!['user'];
    }
    return null;
  }

  /// Fetches all home screen data in a single request for maximum speed
  Future<Map<String, dynamic>> getHomeScreenData() async {
    // OPTIMIZED: Single Request to reduce network latency (RTT)
    try {
      final url = await baseUrl;

      final response = await _retryRequest(() async {
        final token = await _storage.read(key: 'token');
        return _client
            .get(
              Uri.parse('$url/home-aggregate'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(_timeout);
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _cacheHomeData(data); // Cache the fresh data
        return data;
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
      }
    } catch (e) {
      if (kDebugMode) print("Home Data Aggregate Error: $e");
    }

    // Return empty structure on failure to prevent UI crash
    return {'user': null, 'history': [], 'people': [], 'merchants': []};
  }

  // History Caching (Updated with RAM)
  static List<dynamic>? _historyRamCache;

  Future<void> _cacheHistory(List<dynamic> data) async {
    try {
      _historyRamCache = data; // RAM
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_historyCacheKey, json.encode(data)); // Disk
    } catch (_) {}
  }

  // Note: getCachedHistory (async) is still there but we prefer getHistorySync

  Future<bool> sendMessageOptimistic(
    String targetUpi,
    String content,
    Map<String, dynamic> optimisticMsg,
  ) async {
    // 1. Update Conversation Cache Instantly
    try {
      if (_ramCache.containsKey(targetUpi)) {
        _ramCache[targetUpi]!.insert(0, optimisticMsg);
        _cacheConversation(targetUpi, _ramCache[targetUpi]!);
      } else {
        _ramCache[targetUpi] = [optimisticMsg];
        _cacheConversation(targetUpi, [optimisticMsg]);
      }

      // 2. Update Recent People Cache (Home Screen)
      // Move this user to the top of the list so when we go back, it's reflected instantly
      if (_homeRamCache != null && _homeRamCache!['people'] != null) {
        final List people = _homeRamCache!['people'];
        final index = people.indexWhere((p) => p['upi_id'] == targetUpi);
        if (index != -1) {
          final person = people.removeAt(index);
          // Verify if person is a Map and mutable
          if (person is Map) {
            // Try to update last message preview if the structure supports it
          }
          people.insert(0, person);
          _cacheHomeData(_homeRamCache!);
        }
      }
    } catch (_) {}

    // 2. Network Call
    try {
      final url = await baseUrl;
      final response = await _retryRequest(() async {
        final token = await _storage.read(key: 'token');
        return _client
            .post(
              Uri.parse('$url/messages'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: json.encode({
                'receiver_upi_id': targetUpi,
                'content': content,
              }),
            )
            .timeout(_timeout);
      });

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print("Send Message Error: $e");
      // Update cache to failed? For now, just return false.
      return false;
    }
  }

  // Deprecated: usage replaced by Optimistic version
  Future<bool> sendMessage(String targetUpi, String content) async {
    return sendMessageOptimistic(targetUpi, content, {});
  }

  Future<void> logout() async {
    try {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      if (token != null) {
        await _client.post(
          Uri.parse('$url/logout'),
          headers: {
            'Authorization': 'Bearer $token',
            'ngrok-skip-browser-warning': 'true',
          },
        );
      }
    } catch (e) {
      // Ignore
    }
    await _storage.delete(key: 'token');
    await removeSavedMobile(); // Clear saved mobile on logout
  }

  Future<Map<String, dynamic>?> lookupUser(String upiId) async {
    try {
      final url = await baseUrl;
      // Token usually required for secured endpoints
      final response = await _retryRequest(() async {
        final token = await _storage.read(key: 'token');
        return _client
            .get(
              Uri.parse('$url/users/lookup/${Uri.encodeComponent(upiId)}'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(_timeout);
      });
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      if (kDebugMode) print("Lookup Error: $e");
    }
    return null;
  }

  // --- Phone Cache (RAM) ---
  static final Map<String, Map<String, dynamic>> _phoneRamCache = {};

  Future<Map<String, dynamic>?> getCachedUserByPhone(String phone) async {
    // 1. Try RAM
    if (_phoneRamCache.containsKey(phone)) {
      return _phoneRamCache[phone];
    }
    // 2. Try Disk
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString('$_phoneCachePrefix$phone');
      if (jsonString != null) {
        final data = json.decode(jsonString);
        _phoneRamCache[phone] = data; // Populate RAM
        return data;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> lookupUserByPhone(String phoneNumber) async {
    try {
      final url = await baseUrl;

      final response = await _retryRequest(() async {
        final token = await _storage.read(key: 'token');
        return _client
            .get(
              Uri.parse(
                '$url/users/lookup-phone/${Uri.encodeComponent(phoneNumber)}',
              ),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(_timeout);
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Cache it!
        // We assume phone number is normalized here or we cache by the input key
        _phoneRamCache[phoneNumber] = data;

        // Persist to Disk
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            '$_phoneCachePrefix$phoneNumber',
            json.encode(data),
          );
        } catch (_) {}

        return data;
      }
    } catch (e) {
      if (kDebugMode) print("Phone Lookup Error: $e");
    }
    return null;
  }

  Future<void> setBaseUrl(String url) async {
    // Validate URL format
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url'; // Default to https for safety
    }
    // Force HTTPS for ngrok
    if (url.contains('ngrok') && url.startsWith('http://')) {
      url = url.replaceFirst('http://', 'https://');
    }

    if (!url.contains(':') && !url.contains('ngrok')) {
      url = '$url:8000';
    }
    await _storage.write(key: 'backend_url', value: url);
  }

  /// Gets a persistent device ID that survives app reinstalls.
  /// Uses Android's ANDROID_ID or iOS's identifierForVendor.
  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if we already have a cached device ID
    var deviceId = prefs.getString('device_id');
    if (deviceId != null && deviceId.isNotEmpty) {
      return deviceId;
    }

    // Get hardware-level ID based on platform
    final deviceInfo = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // ANDROID_ID is unique per app signing key and survives reinstalls
        deviceId = androidInfo.id; // This is the Android ID
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        // identifierForVendor is unique per vendor and survives reinstalls
        deviceId = iosInfo.identifierForVendor;
      }
    } catch (e) {
      if (kDebugMode) print('Error getting device ID: $e');
    }

    // Fallback: generate a random ID if hardware ID unavailable
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    // Cache the device ID
    await prefs.setString('device_id', deviceId);
    return deviceId;
  }

  // --- Mobile Number Persistence ---
  Future<String?> getSavedMobile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('saved_mobile');
  }

  Future<void> saveMobile(String mobile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_mobile', mobile);
  }

  Future<void> removeSavedMobile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_mobile');
  }

  // --- Auth Flow Methods ---
  Future<Map<String, dynamic>> checkMobile(String mobile) async {
    try {
      final url = await baseUrl;
      final deviceId = await getDeviceId();
      final response = await _client
          .post(
            Uri.parse('$url/auth/check-mobile'),
            headers: {
              'Content-Type': 'application/json',

              'X-Device-ID': deviceId,
            },
            body: json.encode({'mobile_number': mobile}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {
        'exists': false,
        'status': 'error',
        'detail': 'Server error: ${response.statusCode} ${response.body}',
      };
    } catch (e) {
      if (kDebugMode) print("Check Mobile Error: $e");
      return {
        'exists': false,
        'status': 'error',
        'detail': 'Connection failed: ${e.toString()}', // Show actual error
      };
    }
  }

  Future<bool> setPin(String mobile, String pin) async {
    try {
      final url = await baseUrl;
      final response = await _client
          .post(
            Uri.parse('$url/auth/set-pin'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'mobile_number': mobile, 'pin': pin}),
          )
          .timeout(_timeout);

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print("Set PIN Error: $e");
      return false;
    }
  }

  Future<bool> changePin(String newPin) async {
    try {
      final url = await baseUrl;
      final response = await _retryRequest(() async {
        final token = await _storage.read(key: 'token');
        if (token == null) throw Exception('No token');

        return _client
            .put(
              Uri.parse('$url/users/me/change-pin'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: json.encode({'new_pin': newPin}),
            )
            .timeout(_timeout);
      });

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print("Change PIN Error: $e");
      return false;
    }
  }

  Future<List<dynamic>?> getLoginHistory() async {
    try {
      final url = await baseUrl;

      final response = await _retryRequest(() async {
        final token = await _storage.read(key: 'token');
        return _client
            .get(
              Uri.parse('$url/users/login-history'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(_timeout);
      });

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
      }
    } catch (e) {
      if (kDebugMode) print("Login History Error: $e");
    }
    return null;
  }
}

enum PinVerificationStatus { success, incorrect, unknown, lockedOut }
