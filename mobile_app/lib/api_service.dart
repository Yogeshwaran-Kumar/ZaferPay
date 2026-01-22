import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class ApiService {
  // Default URLs for different environments
  static String get _defaultBaseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    // Default for Android Emulator
    return 'http://10.0.2.2:8000';
  }

  static const Duration _timeout = Duration(seconds: 5);
  final _storage = const FlutterSecureStorage();

  Future<String> get baseUrl async {
    final stored = await _storage.read(key: 'backend_url');
    return stored ?? _defaultBaseUrl;
  }

  final _authStateController = StreamController<void>.broadcast();
  Stream<void> get authStateChanges => _authStateController.stream;

  void _handleUnauthorized() {
    _storage.delete(key: 'token');
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
      final response = await http
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
      } else {
        if (kDebugMode) {
          print('Login Failed Code: ${response.statusCode}');
          print('Login Failed Body: ${response.body}');
        }
        final msg = response.body.isEmpty
            ? 'Status ${response.statusCode}'
            : response.body;
        return 'Login failed: $msg';
      }
    } catch (e) {
      if (kDebugMode) print("Login Error: $e");
      return 'Connection Error: $e';
    }
  }

  Future<Map<String, dynamic>?> getMe() async {
    try {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      if (token == null) return null;

      final response = await http
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

  Future<Map<String, dynamic>> createTransaction(
    String receiverUpi,
    double amount,
  ) async {
    try {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      final response = await http
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
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 401) {
        _handleUnauthorized();
        return {'detail': 'Session expired'};
      }
      return json.decode(response.body);
    } catch (e) {
      if (kDebugMode) print("Transaction Error: $e");
      return {'detail': 'Transaction Failed: $e'};
    }
  }

  Future<List<dynamic>> getHistory() async {
    try {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      final response = await http
          .get(
            Uri.parse('$url/transactions/history'),
            headers: {
              'Authorization': 'Bearer $token',
              'ngrok-skip-browser-warning': 'true',
            },
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
      }
    } catch (e) {
      if (kDebugMode) print("History Error: $e");
    }
    return [];
  }

  Future<void> logout() async {
    try {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      if (token != null) {
        await http.post(
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
    // Note: We don't trigger _authStateController here because this is a deliberate logout,
    // usually handled by the UI immediately anyway.
    // But we COULD trigger it if we wanted "logout anywhere" to update generic listeners.
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

  Future<String> getDeviceId() async {
    var deviceId = await _storage.read(key: 'device_id');
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await _storage.write(key: 'device_id', value: deviceId);
    }
    return deviceId;
  }
}
