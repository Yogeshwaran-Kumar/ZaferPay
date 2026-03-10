import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  // Default URLs 
  static String get _defaultBaseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    
    // FOR DEMO: Update this URL when you start Cloudflare tunnel
    // Then rebuild APK and distribute to all phones
    // No need to configure each phone individually!
    return 'https://phones-longitude-list-powers.trycloudflare.com';
    
    // INSTRUCTIONS:
    // 1. Start backend: uvicorn main:app --reload --host 0.0.0.0 --port 8000
    // 2. Start tunnel: cloudflared tunnel --url http://localhost:8000
    // 3. Copy tunnel URL from terminal
    // 4. Paste URL above (replace the existing URL)
    // 5. Build APK: flutter build apk --release
    // 6. Distribute APK to all phones
    // 7. Done! All phones will use the same URL
  }

  static const Duration _timeout = Duration(seconds: 30);
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  http.Client? _client;

  ApiClient() {
    _client = _createHttpClient();
  }

  // Allow runtime URL override for demos
  static String? _customBaseUrl;
  
  static void setCustomBaseUrl(String url) {
    _customBaseUrl = url;
  }
  
  static void clearCustomBaseUrl() {
    _customBaseUrl = null;
  }

  Future<String> get baseUrl async {
    // Check for saved custom URL first
    if (_customBaseUrl != null) return _customBaseUrl!;
    
    // Check SharedPreferences for saved URL
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('custom_backend_url');
      if (savedUrl != null && savedUrl.isNotEmpty) {
        return savedUrl;
      }
    } catch (_) {}
    
    return _defaultBaseUrl;
  }
  
  static Future<void> saveCustomBaseUrl(String url) async {
    _customBaseUrl = url;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_backend_url', url);
    } catch (_) {}
  }
  
  static Future<void> clearSavedBaseUrl() async {
    _customBaseUrl = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('custom_backend_url');
    } catch (_) {}
  }

  // SECURITY: Certificate Pinning
  // For production deployment with your own domain, uncomment and configure:
  // 1. Use `package:http_certificate_pinning` for proper SHA256 pinning
  // 2. Pin your server's certificate chain
  // 3. Update pins when certificates rotate
  //
  // Cloudflare tunnels provide valid, trusted certificates from their CA
  // which are automatically validated by the standard SSL handshake.

  // Robust Client Creation with SSL Validation
  static http.Client _createHttpClient() {
    final ioClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 15);

    // SECURITY: Certificate Validation Callback
    // This callback is ONLY invoked for certificates that FAIL normal validation
    // Cloudflare tunnels use valid certificates, so this won't be called for them
    ioClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
          // Log any certificate issues (should not happen with Cloudflare)
          // print('⚠️ SECURITY: Certificate validation failed for $host');

          // Always reject bad certificates - never bypass SSL
          return false;
        };

    return io.IOClient(ioClient);
  }

  void resetClient() {
    try {
      _client?.close();
    } catch (_) {}
    _client = _createHttpClient();
  }

  Future<http.Response> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    return _retryRequest(() async {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('language') ?? 'en';
      final combinedHeaders = {
        'Content-Type': 'application/json',
        'Accept-Language': lang,
        if (token != null) 'Authorization': 'Bearer $token',
        ...?headers,
      };

      return _client!
          .post(
            Uri.parse('$url$endpoint'),
            headers: combinedHeaders,
            body: body != null ? json.encode(body) : null,
          )
          .timeout(_timeout);
    });
  }

  // Form-encoded POST (for OAuth2 token endpoint)
  Future<http.Response> postForm(
    String endpoint, {
    Map<String, String>? body,
    Map<String, String>? headers,
  }) async {
    return _retryRequest(() async {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('language') ?? 'en';
      final combinedHeaders = {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept-Language': lang,
        if (token != null) 'Authorization': 'Bearer $token',
        ...?headers,
      };

      return _client!
          .post(
            Uri.parse('$url$endpoint'),
            headers: combinedHeaders,
            body: body, // Form data is already encoded by http package
          )
          .timeout(_timeout);
    });
  }

  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
  }) async {
    return _retryRequest(() async {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('language') ?? 'en';
      final combinedHeaders = {
        'Accept-Language': lang,
        if (token != null) 'Authorization': 'Bearer $token',
        ...?headers,
      };

      return _client!
          .get(Uri.parse('$url$endpoint'), headers: combinedHeaders)
          .timeout(_timeout);
    });
  }

  Future<http.Response> put(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    return _retryRequest(() async {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('language') ?? 'en';
      final combinedHeaders = {
        'Content-Type': 'application/json',
        'Accept-Language': lang,
        if (token != null) 'Authorization': 'Bearer $token',
        ...?headers,
      };

      return _client!
          .put(
            Uri.parse('$url$endpoint'),
            headers: combinedHeaders,
            body: body != null ? json.encode(body) : null,
          )
          .timeout(_timeout);
    });
  }

  Future<http.Response> patch(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    return _retryRequest(() async {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('language') ?? 'en';
      final combinedHeaders = {
        'Content-Type': 'application/json',
        'Accept-Language': lang,
        if (token != null) 'Authorization': 'Bearer $token',
        ...?headers,
      };

      return _client!
          .patch(
            Uri.parse('$url$endpoint'),
            headers: combinedHeaders,
            body: body != null ? json.encode(body) : null,
          )
          .timeout(_timeout);
    });
  }

  Future<http.Response> delete(
    String endpoint, {
    Map<String, String>? headers,
  }) async {
    return _retryRequest(() async {
      final url = await baseUrl;
      final token = await _storage.read(key: 'token');
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('language') ?? 'en';
      final combinedHeaders = {
        'Accept-Language': lang,
        if (token != null) 'Authorization': 'Bearer $token',
        ...?headers,
      };

      return _client!
          .delete(Uri.parse('$url$endpoint'), headers: combinedHeaders)
          .timeout(_timeout);
    });
  }

  // Internal Retry Logic with Auto-Refresh
  Future<http.Response> _retryRequest(
    Future<http.Response> Function() requestFunc, {
    int retries = 3,
  }) async {
    bool authRetryAttempted = false;

    for (int i = 0; i < retries; i++) {
      try {
        final response = await requestFunc();

        // Auto-Refresh Token on 401
        if (response.statusCode == 401 && !authRetryAttempted) {
          authRetryAttempted = true; // Prevent infinite loops
          if (kDebugMode) {
            print("⚠️ 401 Unauthorized. Attempting token refresh...");
          }

          final refreshed = await _refreshToken();
          if (refreshed) {
            if (kDebugMode) print("✅ Token refreshed. Retrying request...");
            // Decrement counter to ensure we still have network retries if needed,
            // but effectively just retry immediately.
            i--;
            continue;
          } else {
            if (kDebugMode) print("❌ Token refresh failed. Login required.");
          }
        }

        return response;
      } catch (e) {
        final isNetworkError =
            e.toString().contains('HandshakeException') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Connection closed');

        if (isNetworkError && i < retries - 1) {
          resetClient();
          if (kDebugMode) print("Network error, retrying...");
          await Future.delayed(Duration(milliseconds: 1000 * (i + 1)));
          continue;
        }
        rethrow;
      }
    }
    throw Exception('Request failed after retries');
  }

  // Auto-Refresh Logic
  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) return false;

      final url = await baseUrl;
      // Use clean call to avoid recursion
      final response = await _client!
          .post(
            Uri.parse('$url/auth/refresh'),
            headers: {
              'X-Refresh-Token': refreshToken,
              'Content-Type': 'application/json',
            },
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _storage.write(key: 'token', value: data['access_token']);
        // Store new refresh token if provided (optional, backend currently doesn't rotate it but might)
        if (data['refresh_token'] != null) {
          await _storage.write(
            key: 'refresh_token',
            value: data['refresh_token'],
          );
        }
        return true;
      } else {
        // Refresh failed (expired/revoked) - Clear session
        await _storage.delete(key: 'token');
        await _storage.delete(key: 'refresh_token');
        return false;
      }
    } catch (e) {
      if (kDebugMode) print("Refresh error: $e");
      return false;
    }
  }
}
