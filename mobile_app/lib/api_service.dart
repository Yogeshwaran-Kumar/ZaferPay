import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';

class ApiService {
  // Default URLs for different environments
  static String get _defaultBaseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    // Default for Android Emulator
    return 'https://collen-horrent-allison.ngrok-free.dev';
  }

  static const Duration _timeout = Duration(seconds: 15);
  static final http.Client _client = http.Client();
  final _storage = const FlutterSecureStorage();
  final _authStateController = StreamController<void>.broadcast();

  Future<String> get baseUrl async {
    // For debugging: Force use of default URL and clear any stale cache
    // final stored = await _storage.read(key: 'backend_url');
    // return stored ?? _defaultBaseUrl;
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
            headers: {
              'ngrok-skip-browser-warning': 'true',
              'X-Device-ID': deviceId,
            },
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _storage.write(key: 'token', value: data['access_token']);
        return null; // Success
      } else if (response.statusCode == 409) {
        return 'LOGGED_IN_ELSEWHERE';
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
          }
        } catch (_) {
          // If JSON parsing fails, log but don't show HTML to user
          if (kDebugMode) {
            print('Login Failed Code: ${response.statusCode}');
            print('Login Failed Body: ${response.body}');
          }
        }
        // Return clean error code instead of raw message
        return 'INCORRECT_PIN';
      }
    } catch (e) {
      if (kDebugMode) print("Login Error: $e");
      return 'CONNECTION_ERROR';
    }
  }

  Future<Map<String, dynamic>?> getMe() async {
    try {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      if (token == null) return null;

      final response = await _client
          .get(
            Uri.parse('$url/users/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'ngrok-skip-browser-warning': 'true',
            },
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        _handleUnauthorized(); // Trigger logout logic
      }
    } catch (e) {
      if (kDebugMode) print("GetMe Error: $e");
    }
    return null;
  }

  Future<dynamic> _retryRequest(
    Future<http.Response> Function() requestFunc, {
    int retries = 3,
  }) async {
    for (int i = 0; i < retries; i++) {
      try {
        return await requestFunc();
      } catch (e) {
        final isNetworkError =
            e.toString().contains('HandshakeException') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Connection closed');

        if (isNetworkError && i < retries - 1) {
          await Future.delayed(
            Duration(milliseconds: 500 * (i + 1)),
          ); // Exponential backoff
          continue;
        }
        rethrow;
      }
    }
  }

  Future<Map<String, dynamic>> createTransaction(
    String receiverUpi,
    double amount,
    String pin,
  ) async {
    try {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');

      final response = await _retryRequest(
        () => _client
            .post(
              Uri.parse('$url/transactions/'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
                'ngrok-skip-browser-warning': 'true',
              },
              body: json.encode({
                'receiver_upi_id': receiverUpi,
                'amount': amount,
                'pin': pin,
              }),
            )
            .timeout(_timeout),
      );

      if (response.statusCode == 401) {
        _handleUnauthorized();
        return {'detail': 'Session expired'};
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

  Future<List<dynamic>?> getHistory() async {
    try {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');

      final response = await _retryRequest(
        () => _client
            .get(
              Uri.parse('$url/transactions/history'),
              headers: {
                'Authorization': 'Bearer $token',
                'ngrok-skip-browser-warning': 'true',
              },
            )
            .timeout(_timeout),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
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
      final token = await _storage.read(key: 'token');

      final response = await _retryRequest(
        () => _client
            .get(
              Uri.parse('$url/transactions/recent-people?limit=16'),
              headers: {
                'Authorization': 'Bearer $token',
                'ngrok-skip-browser-warning': 'true',
              },
            )
            .timeout(_timeout),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
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
      final token = await _storage.read(key: 'token');

      final response = await _retryRequest(
        () => _client
            .get(
              Uri.parse('$url/transactions/recent-merchants?limit=16'),
              headers: {
                'Authorization': 'Bearer $token',
                'ngrok-skip-browser-warning': 'true',
              },
            )
            .timeout(_timeout),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
      }
    } catch (e) {
      if (kDebugMode) print("Recent Merchants Error: $e");
    }
    return null;
  }

  /// Fetches all home screen data in parallel for faster loading
  Future<Map<String, dynamic>> getHomeScreenData() async {
    // Run all API calls in parallel instead of sequential
    final results = await Future.wait([
      getMe(),
      getHistory(),
      getRecentPeople(),
      getRecentMerchants(),
    ]);
    return {
      'user': results[0],
      'history': results[1],
      'people': results[2],
      'merchants': results[3],
    };
  }

  Future<List<dynamic>?> getConversation(String upiId) async {
    try {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');

      final response = await _retryRequest(
        () => _client
            .get(
              Uri.parse(
                '$url/transactions/conversation/${Uri.encodeComponent(upiId)}',
              ),
              headers: {
                'Authorization': 'Bearer $token',
                'ngrok-skip-browser-warning': 'true',
              },
            )
            .timeout(_timeout),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
      }
    } catch (e) {
      if (kDebugMode) print("Conversation Error: $e");
    }
    return null;
  }

  Future<bool> sendMessage(String targetUpi, String content) async {
    try {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');

      final response = await _client
          .post(
            Uri.parse('$url/messages'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
            body: json.encode({
              'receiver_upi_id': targetUpi,
              'content': content,
            }),
          )
          .timeout(_timeout);

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print("Send Message Error: $e");
      return false;
    }
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
      final token = await _storage.read(key: 'token');
      // Token usually required for secured endpoints
      final response = await _client
          .get(
            Uri.parse('$url/users/lookup/${Uri.encodeComponent(upiId)}'),
            headers: {
              'Authorization': 'Bearer $token',
              'ngrok-skip-browser-warning': 'true',
            },
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      if (kDebugMode) print("Lookup Error: $e");
    }
    return null;
  }

  Future<Map<String, dynamic>?> lookupUserByPhone(String phoneNumber) async {
    try {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      final response = await _client
          .get(
            Uri.parse(
              '$url/users/lookup-phone/${Uri.encodeComponent(phoneNumber)}',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'ngrok-skip-browser-warning': 'true',
            },
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
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
              'ngrok-skip-browser-warning': 'true',
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
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
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
      final token = await _storage.read(key: 'token');
      if (token == null) return false;

      final response = await _client
          .put(
            Uri.parse('$url/users/me/change-pin'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
            body: json.encode({'new_pin': newPin}),
          )
          .timeout(_timeout);

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print("Change PIN Error: $e");
      return false;
    }
  }

  Future<List<dynamic>?> getLoginHistory() async {
    try {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');

      final response = await _retryRequest(
        () => _client
            .get(
              Uri.parse('$url/users/login-history'),
              headers: {
                'Authorization': 'Bearer $token',
                'ngrok-skip-browser-warning': 'true',
              },
            )
            .timeout(_timeout),
      );

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
