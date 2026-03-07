import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'api_client.dart';

// Background handler must be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (kDebugMode) {
    print("Background Notification: ${message.messageId}");
  }

  // Use the static helper to ensure consistent increment logic
  await NotificationService.incrementBadgeCount();
}

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  static NotificationService get instance => _instance;

  final ApiClient _apiClient = ApiClient();
  late final FirebaseMessaging _fcm;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  bool _isInitialized = false;

  // Stream for UI to listen for reset events
  final _resetController = StreamController<void>.broadcast();
  Stream<void> get onReset => _resetController.stream;

  // Android Notification Channel
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel_v2', // id - Changed to force update
    'Important Notifications', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.max, // Changed from high to max
    playSound: true,
  );

  Future<void> initialize({bool askPermission = false}) async {
    if (_isInitialized) {
      if (askPermission) {
        // Only request if asked, after already initialized
        await _fcm.requestPermission(alert: true, badge: true, sound: true);
      }
      return;
    }
    _isInitialized = true;

    // 0. Initialize Firebase Core
    await Firebase.initializeApp();
    _fcm = FirebaseMessaging.instance;

    // 1. Request Permission
    if (askPermission) {
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        if (kDebugMode) {
          print('✅ User granted permission');
        }
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        if (kDebugMode) {
          print('⚠️ User granted provisional permission');
        }
      } else {
        if (kDebugMode) {
          print('❌ User declined permission');
        }
        // We still continue initialization in case they change their mind or for foreground handling
      }
    }

    // 2. Initialize Local Notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _localNotifications.initialize(initializationSettings);

    // Create Channel (Android)
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    // 3. Set Background Handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 4. Get Token
    try {
      _fcmToken = await _fcm.getToken();
      if (_fcmToken != null) {
        if (kDebugMode) {
          print("🔥 FCM Token: $_fcmToken");
        }
        await _sendTokenToBackend(_fcmToken!);
      }
    } catch (e) {
      if (kDebugMode) {
        print("❌ Failed to get FCM token: $e");
      }
    }

    // 5. Listen for Token Refresh
    _fcm.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) {
        print("🔄 FCM Token Refreshed: $newToken");
      }
      _fcmToken = newToken;
      await _sendTokenToBackend(newToken);
    });

    // 6. Handle Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (kDebugMode) {
        print('🔔 Foreground Message: ${message.notification?.title}');
      }

      RemoteNotification? notification = message.notification;

      // Increment Badge Count (Foreground)
      await NotificationService.incrementBadgeCount();

      // Check for custom data to update UI if needed
      if (message.data['type'] == 'transaction_received') {
        // Here we could trigger a provider refresh via a global event bus or similar
        if (kDebugMode) {
          print("💰 Transaction Received: Refreshing Data...");
        }
      }

      // Show Local Notification
      if (notification != null) {
        _localNotifications.show(
          DateTime.now().millisecondsSinceEpoch.remainder(100000),
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              icon: 'ic_launcher',
              importance: Importance.max,
              priority: Priority.max,
              playSound: true,
              enableVibration: true,
              fullScreenIntent: true, // Forces heads-up on some devices
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
        );
      }
    });
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      // Ensure we are logged in before sending?
      // ApiClient handles headers, so if we have a token it sends it.
      // If we are not logged in, this might fail, which is fine.
      final response = await _apiClient.post(
        '/users/me/fcm-token',
        body: {'fcm_token': token},
      );

      if (response.statusCode == 200) {
        if (kDebugMode) {
          print("✅ FCM Token synced with server");
        }
      } else {
        if (kDebugMode) {
          print("❌ Failed to sync FCM token: ${response.statusCode}");
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("❌ Error syncing FCM token: $e");
      }
    }
  }

  Future<void> resetBadgeCount() async {
    try {
      if (kDebugMode) {
        print(
          "🔔 NotificationService: Resetting badge count and notifications",
        );
      }

      // --- TRUE ZERO LATENCY UI UPDATE ---
      // Notify active UI to hide dots IMMEDIATELY, before ANY async disk/network work.
      // This prevents a 1-frame flash on app resume.
      _resetController.add(null);

      // --- ZERO LATENCY: Clear cached badge counts FIRST ---
      // This ensures HomeScreen's initState never sees stale unread counts
      // even if it loads sync cached data on cold start.
      await ApiService().clearCachedUnreadCounts();

      // Clear badge completely (Nothing should show on icon)
      FlutterAppBadger.removeBadge();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('badge_count', 0);

      // Clear all shown notifications from status bar
      // We can call cancelAll even if initialize wasn't fully finished for other things,
      // as the plugin instance is already created.
      await _localNotifications.cancelAll();

      // Clear Backend Unread Counts (In-app badges)
      try {
        await ApiService().markAllRead();
      } catch (_) {}

      if (kDebugMode) {
        print("✅ NotificationService: Reset process initiated");
      }
    } catch (e) {
      if (kDebugMode) {
        print("❌ NotificationService: Failed to reset badge count: $e");
      }
    }
  }

  String? get fcmToken => _fcmToken;

  /// Global static helper to increment the launcher badge count.
  /// Used by both background handler and foreground listener.
  static Future<void> incrementBadgeCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int currentCount = prefs.getInt('badge_count') ?? 0;
      int newCount = currentCount + 1;

      // Update local storage
      await prefs.setInt('badge_count', newCount);

      // Update Launcher Icon (System Badge)
      bool isSupported = await FlutterAppBadger.isAppBadgeSupported();
      if (isSupported) {
        FlutterAppBadger.updateBadgeCount(newCount);
      }

      if (kDebugMode) {
        print("🔔 Badge Incremented: $currentCount -> $newCount");
      }
    } catch (e) {
      if (kDebugMode) {
        print("❌ Failed to increment badge: $e");
      }
    }
  }
}
