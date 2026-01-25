import 'package:flutter/material.dart';
import 'dart:io'; // Import dart:io for HttpOverrides
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login_screen.dart';

import 'main_navigation_screen.dart';
import 'scan_screen.dart';
import 'pay_screen.dart';
import 'settings_screen.dart';
import 'change_pin_screen.dart';

// Note: PaymentPinScreen is usually pushed with arguments, so simpler to use named route or onGenerateRoute.
// But we can add it here if we want named route navigation.
import 'payment_pin_screen.dart';
import 'amount_screen.dart';
import 'conversation_screen.dart';

// Global Key to access Navigator without Context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global Theme Notifier
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  HttpOverrides.global = MyHttpOverrides(); // Bypass SSL verification
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

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // We need to know if we are already showing the lock screen to avoid stacking it
  bool _isLockScreenShown = false;
  final _storage = const FlutterSecureStorage();

  // Route Observer to track current route
  final _routeObserver = _CurrentRouteObserver();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _wasPaused = false; // Track if the app was previously paused

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
    } else if (state == AppLifecycleState.resumed) {
      if (_wasPaused) {
        _checkAndLockApp();
        _wasPaused = false; // Reset after checking
      }
    }
  }

  Future<void> _checkAndLockApp() async {
    // Check if user is "logged in" (has a token or saved mobile)
    // We only want to lock if the user has actually set up the app.
    final savedMobile = await _storage.read(key: 'saved_mobile');

    if (savedMobile != null && !_isLockScreenShown) {
      // Check if we are currently on the Login Screen or Payment PIN Screen
      final currentRoute = _routeObserver.currentRouteName;
      // ONLY skip locking if we are already on the Login screen (App Unlock)
      // If we are on Payment PIN, we MUST lock for security.
      if (currentRoute == '/login') {
        return;
      }

      // Check if we are currently on the Login Screen (to avoid double locking on startup/logout)
      // This is a bit tricky with Navigator, but usually if we have savedMobile, we might be in Home.
      // A simple heuristic: If we are resumed, and have a user, show lock.

      // However, we don't want to show it if the user just opened the app and is AT the login screen.
      // But typically, if they have savedMobile, we might auto-login or show login.
      // To be safe and simple: Always show unlock screen if savedMobile exists.

      // 1. If currently sharing (awaiting return), skip lock
      if (MyApp.isSharing) return;

      // 2. If returned from sharing recently (within 2 seconds), skip lock
      if (MyApp.lastShareTime != null) {
        final diff = DateTime.now().difference(MyApp.lastShareTime!);
        if (diff.inSeconds < 2) {
          return;
        }
      }

      _isLockScreenShown = true;
      navigatorKey.currentState
          ?.push(
            MaterialPageRoute(
              builder: (context) => const LoginScreen(isUnlockMode: true),
              fullscreenDialog: false,
            ),
          )
          .then((_) {
            _isLockScreenShown = false;
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [_routeObserver], // Add observer here
          title: 'MockBank',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.white,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF5F259F),
              brightness: Brightness.light,
              primary: const Color(0xFF5F259F),
              secondary: const Color(0xFF00B9F1),
              surface: Colors.white,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.white,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.black87),
              titleTextStyle: GoogleFonts.inter(
                color: Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            textTheme: GoogleFonts.interTextTheme().apply(
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
              seedColor: const Color(0xFF5F259F),
              brightness: Brightness.dark,
              primary: const Color(0xFF9E65E6),
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
              titleTextStyle: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            textTheme: GoogleFonts.interTextTheme(
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
            '/settings': (context) => const SettingsScreen(),

            '/change-pin': (context) => const ChangePinScreen(),
            '/payment-pin': (context) {
              final args =
                  ModalRoute.of(context)!.settings.arguments
                      as Map<String, dynamic>;
              return PaymentPinScreen(
                receiverUpi: args['receiverUpi'],
                amount: args['amount'],
                receiverName: args['name'], // Pass name
                category: args['category'], // Pass category
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
