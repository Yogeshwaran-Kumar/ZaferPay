import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'api_client.dart';

enum PinVerificationStatus { success, incorrect, lockedOut, unknown }

class AuthService {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final StreamController<void> _authStateController =
      StreamController<void>.broadcast();

  // PIN Security - Attempt tracking only (no local storage)
  static int _failedPinAttempts = 0;

  AuthService(this._apiClient);

  Stream<void> get authStateChanges => _authStateController.stream;

  // --- Login ---
  Future<String?> login(
    String username,
    String password, {
    bool forceLogin = false,
  }) async {
    try {
      final deviceId = await _getDeviceId();
      // OAuth2 /token endpoint requires form-encoded data, not JSON
      final response = await _apiClient.postForm(
        '/token${forceLogin ? "?force_logout=true" : ""}',
        body: {'username': username, 'password': password},
        headers: {'X-Device-ID': deviceId},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _storage.write(key: 'token', value: data['access_token']);
        // SECURITY: No PIN storage - server verifies via /token call
        _failedPinAttempts = 0; // Reset on successful login

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
        return 'INCORRECT_PIN';
      }

      if (kDebugMode) {
        print('Login Failed: ${response.statusCode} - ${response.body}');
      }
      try {
        final err = json.decode(response.body);
        return err['detail']?.toString() ??
            'SERVER_ERROR: ${response.statusCode}';
      } catch (_) {
        return 'SERVER_ERROR: ${response.statusCode}';
      }
    } catch (e) {
      if (kDebugMode) print("Login Error: $e");
      return 'CONNECTION_ERROR';
    }
  }

  Future<void> logout() async {
    try {
      await _storage.delete(key: 'token');
      await _storage.delete(key: 'refresh_token');
      // Keep mobile number? Logic says explicit logout might want to clear.
      // api_service.dart said: "Only explicit logout() should clear the user binding."
      // But _handleUnauthorized didn't.
      // For now, let's just clear tokens.
      _authStateController.add(null);
    } catch (_) {}
  }

  // --- PIN Logic (SERVER-SIDE ONLY) ---
  // SECURITY: No local PIN storage. All verification happens via /token API call.
  // The verifyPinSmart method returns 'unknown' to force server verification.
  // This prevents PIN extraction from rooted/jailbroken devices.

  Future<PinVerificationStatus> verifyPinSmart(String inputPin) async {
    // SECURITY: Always return unknown to force server-side verification
    // The ProcessingShieldScreen will make the actual /token call
    // which is the ONLY place where PIN is validated (server-side, Argon2id)
    return PinVerificationStatus.unknown;
  }

  // Track failed attempts for lockout (client-side UX only, server also enforces)
  void recordFailedAttempt() {
    _failedPinAttempts++;
  }

  void resetFailedAttempts() {
    _failedPinAttempts = 0;
  }

  int get failedAttempts => _failedPinAttempts;

  // Warm up is now a no-op (no local cache to warm)
  Future<void> warmUpPinCache() async {
    // SECURITY: No-op. PIN is never stored locally.
  }

  // --- Helpers ---
  Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (kIsWeb) return 'web-client';
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'ios-unknown';
    }
    return 'unknown';
  }

  // --- Mobile Persistence ---
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

  // --- Extended Auth Flows ---
  Future<Map<String, dynamic>> checkMobile(String mobile) async {
    try {
      final deviceId = await _getDeviceId();
      final response = await _apiClient.post(
        '/auth/check-mobile',
        headers: {'X-Device-ID': deviceId},
        body: {'mobile_number': mobile},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {
        'exists': false,
        'status': 'error',
        'detail': 'Server error: ${response.statusCode}',
      };
    } catch (e) {
      if (kDebugMode) print("Check Mobile Error: $e");
      return {
        'exists': false,
        'status': 'error',
        'detail': 'Connection failed',
      };
    }
  }

  Future<bool> setPin(String mobile, String pin) async {
    try {
      final response = await _apiClient.post(
        '/auth/set-pin',
        body: {'mobile_number': mobile, 'pin': pin},
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> changePin(String newPin) async {
    try {
      final response = await _apiClient.put(
        '/users/me/change-pin',
        body: {'new_pin': newPin}, // Client handles Auth header
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<dynamic>?> getLoginHistory() async {
    try {
      final response = await _apiClient.get('/users/login-history');
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (_) {}
    return null;
  }
}
