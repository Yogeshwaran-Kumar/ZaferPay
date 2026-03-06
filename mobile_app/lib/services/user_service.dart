import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class UserService {
  final ApiClient _apiClient;

  // Caching
  static const String _homeCacheKey = 'home_data_cache';
  static Map<String, dynamic>? _homeRamCache;
  static final Map<String, Map<String, dynamic>> _phoneRamCache = {};
  static const String _phoneCachePrefix = 'user_phone_cache_';
  static const String _userCachePrefix = 'user_cache_';

  UserService(this._apiClient);

  // --- Home Data (Aggregate) ---
  Future<Map<String, dynamic>> getHomeScreenData() async {
    try {
      final response = await _apiClient.get('/home-aggregate');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _cacheHomeData(data);
        return data;
      }
    } catch (e) {
      if (kDebugMode) print("Home Data Error: $e");
    }
    return {'user': null, 'history': [], 'people': [], 'merchants': []};
  }

  Map<String, dynamic>? getCachedHomeDataSync() => _homeRamCache;

  Future<Map<String, dynamic>?> getCachedHomeData() async {
    if (_homeRamCache != null) return _homeRamCache;
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_homeCacheKey);
      if (jsonString != null) {
        _homeRamCache = json.decode(jsonString);
        return _homeRamCache;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _cacheHomeData(Map<String, dynamic> data) async {
    try {
      _homeRamCache = data;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_homeCacheKey, json.encode(data));

      // Cache individuals
      if (data['people'] != null) {
        for (var p in data['people']) {
          _cacheUser(p);
        }
      }
      if (data['merchants'] != null) {
        for (var m in data['merchants']) {
          _cacheUser(m);
        }
      }
    } catch (_) {}
  }

  /// Zeroes out all unread_count values in the RAM cache (and persists to disk).
  /// Called by NotificationService.resetBadgeCount() BEFORE HomeScreen is created,
  /// so that stale badge counts never appear from cached data.
  Future<void> clearCachedUnreadCounts() async {
    if (_homeRamCache == null) return;

    // Zero out in RAM
    if (_homeRamCache!['people'] != null) {
      for (var p in _homeRamCache!['people']) {
        p['unread_count'] = 0;
      }
    }
    if (_homeRamCache!['merchants'] != null) {
      for (var m in _homeRamCache!['merchants']) {
        m['unread_count'] = 0;
      }
    }
    if (_homeRamCache!['total_unread'] != null) {
      _homeRamCache!['total_unread'] = 0;
    }

    // Persist zeroed-out data to disk so it survives app restarts
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_homeCacheKey, json.encode(_homeRamCache));
    } catch (_) {}
  }

  // --- Get Me ---
  Future<Map<String, dynamic>?> getMe() async {
    try {
      final response = await _apiClient.get('/users/me');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Update Home Cache User
        if (_homeRamCache == null) await getCachedHomeData();
        _homeRamCache ??= {};
        _homeRamCache!['user'] = data;
        _cacheHomeData(_homeRamCache!);
        return data;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getCachedMe() async {
    // 1. Try RAM
    if (_homeRamCache != null && _homeRamCache!['user'] != null) {
      return _homeRamCache!['user'];
    }
    // 2. Try Disk via Home Data
    final homeData = await getCachedHomeData();
    if (homeData != null && homeData['user'] != null) {
      return homeData['user'];
    }
    return null;
  }

  Future<Map<String, dynamic>?> getCachedUser(String upiId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString('$_userCachePrefix$upiId');
      if (jsonString != null) {
        return json.decode(jsonString);
      }
    } catch (_) {}
    return null;
  }

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
        _phoneRamCache[phone] = data;
        return data;
      }
    } catch (_) {}
    return null;
  }

  // --- User Lookups ---
  Future<Map<String, dynamic>?> lookupUser(String upiId) async {
    try {
      final response = await _apiClient.get(
        '/users/lookup/${Uri.encodeComponent(upiId)}',
      );
      if (response.statusCode == 200) return json.decode(response.body);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> lookupUserByPhone(String phone) async {
    try {
      final response = await _apiClient.get(
        '/users/lookup-phone/${Uri.encodeComponent(phone)}',
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _phoneRamCache[phone] = data;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('$_phoneCachePrefix$phone', json.encode(data));
        return data;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, String>> checkRegisteredUsers(List<String> phones) async {
    try {
      final response = await _apiClient.post(
        '/users/lookup-contacts',
        body: {'phone_numbers': phones},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final Map<String, String> results = {};
        for (var match in data['matches']) {
          results[match['phone_number']] = match['upi_id'];
        }
        return results;
      }
    } catch (_) {}
    return {};
  }

  Future<Map<String, dynamic>> syncContacts(List<String> phones) async {
    try {
      final response = await _apiClient.post(
        '/users/contacts/sync',
        body: {'contacts': phones},
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      if (kDebugMode) print("Sync Contacts Error: $e");
    }
    return {'synced_count': 0, 'new_trust_links': 0};
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final response = await _apiClient.get(
        '/users/search?query=${Uri.encodeComponent(query)}',
      );
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
    } catch (e) {
      if (kDebugMode) print("User Search Error: $e");
    }
    return [];
  }

  // --- Caching Helpers ---
  Future<void> _cacheUser(Map<String, dynamic> user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (user['upi_id'] != null) {
        await prefs.setString(
          '$_userCachePrefix${user['upi_id']}',
          json.encode(user),
        );
      }
      String? mobile =
          user['mobile_number'] ?? user['mobile'] ?? user['phone_number'];
      if (mobile != null) {
        mobile = mobile.replaceAll(RegExp(r'[^\d]'), '');
        _phoneRamCache[mobile] = user;
        await prefs.setString('$_phoneCachePrefix$mobile', json.encode(user));
      }
    } catch (_) {}
  }

  Map<String, dynamic>? getCachedUserByPhoneSync(String phone) {
    return _phoneRamCache[phone];
  }

  // --- UPI Circle ---
  Future<Map<String, dynamic>> getCircleStatus() async {
    try {
      final response = await _apiClient.get('/circle/status');
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      if (kDebugMode) print("Circle Status Error: $e");
    }
    return {'my_circles': [], 'joined_circles': []};
  }

  Future<Map<String, dynamic>> inviteToCircle(
    String upiId,
    double limit,
    String type,
  ) async {
    try {
      final response = await _apiClient.post(
        '/circle/invite',
        body: {
          'secondary_upi_id': upiId,
          'monthly_limit': limit,
          'delegation_type': type,
        },
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['msg'] ?? 'Invitation sent'};
      } else {
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to send invitation',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error. Please try again.'};
    }
  }

  Future<bool> respondToCircleInvite(int inviteId, String action) async {
    try {
      final response = await _apiClient.post(
        '/circle/respond',
        body: {'invitation_id': inviteId, 'action': action},
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateCircleLimit(int circleId, double newLimit) async {
    try {
      final response = await _apiClient.put(
        '/circle/update-limit',
        body: {'circle_id': circleId, 'new_limit': newLimit},
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeCircleMember(int circleId) async {
    try {
      final response = await _apiClient.delete('/circle/remove/$circleId');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearCaches() async {
    _homeRamCache = null;
    _phoneRamCache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_homeCacheKey);
      // We don't necessarily clear all individual user lookups,
      // but clearing Home Data ensures the Home Screen starts fresh.
    } catch (_) {}
  }
}
