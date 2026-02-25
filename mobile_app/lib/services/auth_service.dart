import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'api_client.dart';
import '../main.dart';

enum PinVerificationStatus { success, incorrect, lockedOut, expired, unknown }

class AuthService {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final StreamController<void> _authStateController =
      StreamController<void>.broadcast();

  // PIN Security - Attempt tracking
  static int _failedPinAttempts = 0;

  AuthService(this._apiClient) {
    _initFailedAttempts();
  }

  Future<void> _initFailedAttempts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _failedPinAttempts = prefs.getInt('failed_pin_attempts') ?? 0;
    } catch (_) {}
  }

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
        await resetFailedAttempts(); // Reset on successful login

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
        await recordFailedAttempt();
        if (failedAttempts >= 3) {
          return 'LOCKED_OUT';
        }
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
      // Explicit manual logout clears the "Identity" (saved mobile)
      // so the next user has to start from the mobile number entry page.
      await removeSavedMobile();
      await resetFailedAttempts();
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
  Future<void> recordFailedAttempt() async {
    _failedPinAttempts++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('failed_pin_attempts', _failedPinAttempts);
    } catch (_) {}
  }

  Future<void> resetFailedAttempts() async {
    _failedPinAttempts = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('failed_pin_attempts');
    } catch (_) {}
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

  // Identity Persistence (Memory Cache for Zero-Latency Access)
  static String? _cachedMobile;

  Future<String?> getSavedMobile() async {
    if (_cachedMobile != null) return _cachedMobile;
    final prefs = await SharedPreferences.getInstance();
    _cachedMobile = prefs.getString('saved_mobile');
    return _cachedMobile;
  }

  String? getSavedMobileSync() {
    return _cachedMobile;
  }

  Future<void> saveMobile(String mobile) async {
    _cachedMobile = mobile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_mobile', mobile);
  }

  Future<void> removeSavedMobile() async {
    _cachedMobile = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_mobile');
  }

  void clearCachedMobile() {
    _cachedMobile = null;
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

  Future<bool> changeMpin(String currentPin, String newPin) async {
    try {
      final response = await _apiClient.put(
        '/users/me/change-mpin',
        body: {'current_pin': currentPin, 'new_pin': newPin},
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> changeUpiPin(String currentPin, String newPin) async {
    try {
      final response = await _apiClient.put(
        '/users/me/change-upi-pin',
        body: {'current_pin': currentPin, 'new_pin': newPin},
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> disableMpin(String currentPin) async {
    try {
      final response = await _apiClient.put(
        '/users/me/disable-mpin',
        body: {'pin': currentPin},
      );
      if (response.statusCode == 401) {
        await recordFailedAttempt();
      }
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> enableMpin(String newPin) async {
    try {
      final response = await _apiClient.put(
        '/users/me/enable-mpin',
        body: {'pin': newPin},
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<PinVerificationStatus> verifyUpiPin(String pin) async {
    try {
      final response = await _apiClient.post(
        '/auth/verify-upi-pin',
        body: {'pin': pin},
      );
      if (response.statusCode == 200) {
        return PinVerificationStatus.success;
      } else if (response.statusCode == 401) {
        await recordFailedAttempt();
        if (failedAttempts >= 3) {
          return PinVerificationStatus.lockedOut;
        }
        return PinVerificationStatus.incorrect;
      } else if (response.statusCode == 403) {
        return PinVerificationStatus.expired;
      }
      return PinVerificationStatus.unknown;
    } catch (_) {
      return PinVerificationStatus.unknown;
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

  Future<bool> updateSettings({
    bool? biometricEnabled,
    bool? appLockEnabled,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (biometricEnabled != null) {
        body['biometric_enabled'] = biometricEnabled;
      }
      if (appLockEnabled != null) {
        body['app_lock_enabled'] = appLockEnabled;
      }

      final response = await _apiClient.patch('/users/me/settings', body: body);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> syncUserSettings() async {
    try {
      final response = await _apiClient.get('/users/me');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final bool serverBio = data['biometric_enabled'] ?? false;
        final bool serverLock = data['app_lock_enabled'] ?? true;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('biometric_enabled', serverBio);
        await prefs.setBool('app_lock_enabled', serverLock);

        // Update global MyApp state
        MyApp.biometricEnabled = serverBio;
        MyApp.appLockEnabled = serverLock;
      }
    } catch (_) {}
  }
}
