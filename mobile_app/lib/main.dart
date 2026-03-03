import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io'; // Import dart:io for HttpOverrides
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'login_screen.dart';
import 'api_service.dart';

import 'main_navigation_screen.dart';
import 'scan_screen.dart';
import 'pay_screen.dart';
import 'settings_screen.dart';
import 'change_pin_screen.dart';
import 'risk_analysis_screen.dart'; // Import RiskAnalysisScreen
import 'pending_requests_screen.dart'; // Import PendingRequestsScreen
import 'amount_screen.dart';
import 'contacts_screen.dart';
import 'transaction_details_screen.dart';

// Note: PaymentPinScreen is usually pushed with arguments, so simpler to use named route or onGenerateRoute.
// But we can add it here if we want named route navigation.
import 'payment_pin_screen.dart';
import 'conversation_screen.dart';
import 'money_screen.dart'; // For RouteObserver
import 'services/notification_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart'
    as mlkit;
import 'mcc_helper.dart';

// Global Key to access Navigator without Context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global Theme Notifier
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

// Flag to track if device is compromised
bool _isDeviceCompromised = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load Saved Theme
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('is_dark_theme') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  // Persist Theme Changes
  themeNotifier.addListener(() {
    prefs.setBool('is_dark_theme', themeNotifier.value == ThemeMode.dark);
  });

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  HttpOverrides.global = MyHttpOverrides(); // Bypass SSL verification

  // ═══════════════════════════════════════════════════════════════════════════
  // SECURITY CHECK: Root/Jailbreak Detection
  // ═══════════════════════════════════════════════════════════════════════════
  try {
    _isDeviceCompromised = await FlutterJailbreakDetection.jailbroken;
    // Also check for developer mode (optional, can be commented out if too strict)
    // final isDeveloperMode = await FlutterJailbreakDetection.developerMode;
    // _isDeviceCompromised = _isDeviceCompromised || isDeveloperMode;
  } catch (e) {
    // If detection fails, assume safe (don't block legitimate users)
    _isDeviceCompromised = false;
  }

  // Pre-fetch Identity for Zero-Latency PIN Pad
  ApiService().warmUpIdentity();

  // OPTIMIZATION: Warm up caches
  ApiService().warmUpPinCache();

  try {
    final String? homeStr = prefs.getString('home_data_cache');
    if (homeStr != null) {
      final Map<String, dynamic> homeData = jsonDecode(homeStr);
      if (homeData['user'] != null) {
        // Use the persisted app_lock_enabled setting if available
        if (homeData['user']['app_lock_enabled'] != null) {
          MyApp.appLockEnabled = homeData['user']['app_lock_enabled'] == true;
        } else {
          // Fallback to has_mpin if legacy user
          MyApp.appLockEnabled = homeData['user']['has_mpin'] == true;
        }
      }
    }

    // Also fetch preferences from local store for immediate apply on cold start
    MyApp.biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    MyApp.appLockEnabled =
        prefs.getBool('app_lock_enabled') ?? MyApp.appLockEnabled;
  } catch (_) {}

  runApp(const MyApp());
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static bool isSharing = false;
  static DateTime? lastShareTime;
  static bool isRequestingPermission = false;
  static DateTime? lastPermissionRequestTime;
  static bool appLockEnabled = true; // Synced safely on launch
  static bool biometricEnabled = false; // Synced safely on launch

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // We need to know if we are already showing the lock screen to avoid stacking it
  bool _isLockScreenShown = false;

  // Route Observer to track current route
  final _routeObserver = _CurrentRouteObserver();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize and clear notifications on cold start
    NotificationService.instance.initialize();
    NotificationService.instance.resetBadgeCount();

    _initSharingIntent();
  }

  late StreamSubscription _intentDataStreamSubscription;

  void _initSharingIntent() {
    // For sharing images while app is in memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (List<SharedMediaFile> value) {
            if (value.isNotEmpty) {
              _handleSharedImages(value);
            }
          },
          onError: (err) {
            debugPrint("getIntentDataStream error: $err");
          },
        );

    // For sharing images while app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      if (value.isNotEmpty) {
        _handleSharedImages(value);
      }
    });
  }

  Future<void> _handleSharedImages(List<SharedMediaFile> files) async {
    for (var file in files) {
      if (file.path.endsWith('.png') ||
          file.path.endsWith('.jpg') ||
          file.path.endsWith('.jpeg')) {
        await _processSharedImage(file.path);
      }
    }
  }

  Future<void> _processSharedImage(String path) async {
    final inputImage = mlkit.InputImage.fromFilePath(path);
    final scanner = mlkit.BarcodeScanner(formats: [mlkit.BarcodeFormat.qrCode]);

    try {
      final barcodes = await scanner.processImage(inputImage);
      for (final barcode in barcodes) {
        if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
          _handleQrResult(barcode.rawValue!);
          break;
        }
      }
    } catch (e) {
      debugPrint("ML Kit Error processing shared image: $e");
    } finally {
      await scanner.close();
    }
  }

  void _handleQrResult(String raw) async {
    Map<String, String> result = {'upi': raw, 'payment_source': 'qr_share'};

    if (raw.startsWith('upi://')) {
      try {
        final uri = Uri.parse(raw);
        final params = uri.queryParameters;
        if (params.containsKey('pa')) result['upi'] = params['pa']!;
        if (params.containsKey('mc')) result['mcc'] = params['mc']!;
        if (params.containsKey('pn')) result['name'] = params['pn']!;
        if (params.containsKey('am')) result['amount'] = params['am']!;
      } catch (e) {
        debugPrint("Error parsing URI: $e");
      }
    }

    // Determine category from MCC if present
    String? category;
    if (result['mcc'] != null && result['mcc']!.isNotEmpty) {
      category = MccHelper.getDomain(result['mcc']!);
      result['category'] = category;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECURITY: Ensure app is unlocked before proceeding
    // ═══════════════════════════════════════════════════════════════════════════
    if (MyApp.appLockEnabled || MyApp.biometricEnabled) {
      // If we are on login screen (cold start or explicit logout), WAIT until it's gone
      if (_routeObserver.currentRouteName == '/login') {
        debugPrint("QR Share: App is on login screen, waiting for unlock...");
      } else {
        // App is open, trigger lock
        debugPrint("QR Share: Triggering app lock...");
        await _checkAndLockApp();
      }

      // STRICT WAIT LOOP: Ensure we are NOT on login screen AND we have a valid session
      int attempts = 0;
      Map<String, dynamic>? userData;

      while (attempts < 60) {
        // Wait up to 30 seconds
        if (_routeObserver.currentRouteName != '/login' &&
            !_isLockScreenShown) {
          // Try to get session
          userData = await ApiService().getMe();
          if (userData != null) {
            debugPrint("QR Share: Authentication verified.");
            break;
          }
        }
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
      }

      if (userData == null) {
        debugPrint("QR Share: Authentication failed or timed out. Aborting.");
        return;
      }

      // Navigate to amount screen ONLY if user is authenticated
      navigatorKey.currentState?.pushNamed(
        '/amount',
        arguments: {
          'upi': result['upi'],
          'name': result['name'],
          'category': result['category'],
          'mcc': result['mcc'],
          'senderBalance': userData['balance'],
          'senderUpi': userData['upi_id'],
          'payment_source': 'qr_share',
          if (result['amount'] != null) 'prefillAmount': result['amount'],
          if (result['amount'] != null) 'isLockedAmount': true,
        },
      );
    } else {
      // Security disabled: proceed directly
      final userData = await ApiService().getMe();
      navigatorKey.currentState?.pushNamed(
        '/amount',
        arguments: {
          'upi': result['upi'],
          'name': result['name'],
          'category': result['category'],
          'mcc': result['mcc'],
          'senderBalance': userData?['balance'],
          'senderUpi': userData?['upi_id'],
          'payment_source': 'qr_share',
          if (result['amount'] != null) 'prefillAmount': result['amount'],
          if (result['amount'] != null) 'isLockedAmount': true,
        },
      );
    }
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _wasPaused = false; // Track if the app was previously paused

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
    } else if (state == AppLifecycleState.resumed) {
      // Reset Badge Count on Resume
      NotificationService.instance.resetBadgeCount();

      if (_wasPaused) {
        _checkAndLockApp();
        _wasPaused = false; // Reset after checking
      }
    }
  }

  Future<dynamic> _checkAndLockApp() async {
    // If lock screen is already shown, don't show it again.
    if (_isLockScreenShown) return null;

    // Check current route to decide if we should lock.
    final currentRoute = _routeObserver.currentRouteName;

    // 1. If we are on the Login Screen (App Unlock), do NOT lock.
    // This handles the "Double Lock" prevention.
    // Also handles the case where user is not logged in yet (initial flow).
    if (currentRoute == '/login') {
      return;
    }

    // 2. If currently sharing (awaiting return), skip lock.
    if (MyApp.isSharing) return;

    // 3. If returned from sharing recently (within 2 seconds), skip lock.
    // 3. Removed grace period for sharing return as per user request

    // 4. If requesting permission (awaiting return), skip lock.
    if (MyApp.isRequestingPermission) return;

    // 5. If returned from permission request recently, skip lock.
    // 5. Removed grace period for permission return as per user request

    // Check if App Lock or Biometrics are enabled via global flags
    // These are synced on launch and updated via SettingsScreen
    final bool isLockEnabled = MyApp.appLockEnabled || MyApp.biometricEnabled;

    if (!isLockEnabled) {
      return null; // Skip lock
    }

    // Default: LOCK THE APP
    // We assume if the user is NOT on /login, they are logged in and in a sensitive area.
    _isLockScreenShown = true;
    return navigatorKey.currentState
        ?.push(
          MaterialPageRoute(
            builder: (context) => const LoginScreen(isUnlockMode: true),
            fullscreenDialog: false,
            settings: const RouteSettings(name: '/login'),
          ),
        )
        .then((result) {
          _isLockScreenShown = false;
          return result;
        });
  }

  @override
  Widget build(BuildContext context) {
    // ═══════════════════════════════════════════════════════════════════════════
    // SECURITY: Block compromised devices
    // ═══════════════════════════════════════════════════════════════════════════
    if (_isDeviceCompromised) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.red.shade900,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.security, size: 80, color: Colors.white),
                  const SizedBox(height: 24),
                  const Text(
                    'Security Alert',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'This app cannot run on rooted or jailbroken devices for security reasons.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => SystemNavigator.pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade900,
                    ),
                    child: const Text('Exit App'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [
            _routeObserver,
            moneyScreenRouteObserver,
          ], // Add observer here
          title: 'ZaferPay',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.white,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00B9F1),
              brightness: Brightness.light,
              primary: const Color(0xFF00B9F1),
              secondary: const Color(0xFF00B9F1),
              surface: Colors.white,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.white,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.black87),
              titleTextStyle: GoogleFonts.outfit(
                color: Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            textTheme: GoogleFonts.outfitTextTheme().apply(
              bodyColor: Colors.black87,
              displayColor: Colors.black87,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              color: Colors.white,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            // "Light Black" background as requested (Charcoal/Dark Grey)
            scaffoldBackgroundColor: const Color(0xFF181818),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00B9F1),
              brightness: Brightness.dark,
              primary: const Color(0xFF00B9F1),
              secondary: const Color(0xFF00B9F1),
              surface: const Color(0xFF222222), // Card/Sheet background
              onSurface: Colors.white,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: const Color(0xFF181818),
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              systemOverlayStyle:
                  SystemUiOverlayStyle.light, // Ensure status bar is white text
              titleTextStyle: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            textTheme: GoogleFonts.outfitTextTheme(
              ThemeData.dark().textTheme,
            ).apply(bodyColor: Colors.white, displayColor: Colors.white),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
              color: const Color(0xFF222222),
            ),
            dividerTheme: DividerThemeData(
              color: Colors.white.withValues(alpha: 0.1),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          initialRoute: '/login',
          routes: {
            '/login': (context) => const LoginScreen(),
            '/home': (context) => const MainNavigationScreen(),
            '/scan': (context) => const ScanScreen(),
            '/pay': (context) => const PayScreen(),
            '/amount': (context) => const AmountScreen(),
            '/contacts': (context) => const ContactsScreen(),
            '/transaction-details': (context) {
              final args =
                  ModalRoute.of(context)!.settings.arguments
                      as Map<String, dynamic>;
              return TransactionDetailsScreen(
                transaction: args['transaction'],
                currentUpiId: args['currentUpiId'],
                merchantCategory: args['merchantCategory'],
              );
            },
            '/settings': (context) => const SettingsScreen(),

            '/change-mpin': (context) {
              final args =
                  (ModalRoute.of(context)?.settings.arguments
                      as Map<String, dynamic>?) ??
                  {};
              return ChangePinScreen(
                isMpin: true,
                isSetOnly: args['isSetOnly'] ?? false,
                isDisableOnly: args['isDisableOnly'] ?? false,
              );
            },
            '/change-upi-pin': (context) =>
                const ChangePinScreen(isMpin: false),
            '/risk-analysis': (context) => const RiskAnalysisScreen(),
            '/pending-requests': (context) => const PendingRequestsScreen(),
            '/payment-pin': (context) {
              final args =
                  ModalRoute.of(context)!.settings.arguments
                      as Map<String, dynamic>;
              return PaymentPinScreen(
                receiverUpi: args['receiverUpi'],
                amount: args['amount'],
                receiverName: args['name'], // Pass name
                category: args['category'], // Pass category
                mcc: args['mcc'],
                note: args['note'],
                skipFraudCheck: args['skipFraudCheck'] ?? false,
                acknowledgedRisk: args['acknowledgedRisk'],
                requestId: args['paymentRequestId'], // Pass Request ID
                paymentSource: args['payment_source'], // Pass Telemetry
              );
            },
            '/conversation': (context) {
              final args =
                  ModalRoute.of(context)!.settings.arguments
                      as Map<String, dynamic>;
              return ConversationScreen(args: args);
            },
          },
        );
      },
    );
  }
}

// Simple RouteObserver to track the current route name
class _CurrentRouteObserver extends NavigatorObserver {
  String? currentRouteName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route.settings.name != null) {
      currentRouteName = route.settings.name;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    // When popping, we revert to the previous route's name
    if (previousRoute != null && previousRoute.settings.name != null) {
      currentRouteName = previousRoute.settings.name;
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null && newRoute.settings.name != null) {
      currentRouteName = newRoute.settings.name;
    }
  }
}
