import 'package:flutter/material.dart';
import 'dart:io'; // Import dart:io for HttpOverrides
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'scan_screen.dart';
import 'pay_screen.dart';
import 'settings_screen.dart';
import 'change_pin_screen.dart';
// Note: PaymentPinScreen is usually pushed with arguments, so simpler to use named route or onGenerateRoute.
// But we can add it here if we want named route navigation.
// Actually, it takes arguments in constructor, so passing arguments via settings.arguments is key.
import 'payment_pin_screen.dart';

// Global Key to access Navigator without Context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
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

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // We need to know if we are already showing the lock screen to avoid stacking it
  bool _isLockScreenShown = false;
  final _storage = const FlutterSecureStorage();

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndLockApp();
    }
  }

  Future<void> _checkAndLockApp() async {
    // Check if user is "logged in" (has a token or saved mobile)
    // We only want to lock if the user has actually set up the app.
    final savedMobile = await _storage.read(key: 'saved_mobile');

    if (savedMobile != null && !_isLockScreenShown) {
      // Check if we are currently on the Login Screen (to avoid double locking on startup/logout)
      // This is a bit tricky with Navigator, but usually if we have savedMobile, we might be in Home.
      // A simple heuristic: If we are resumed, and have a user, show lock.

      // However, we don't want to show it if the user just opened the app and is AT the login screen.
      // But typically, if they have savedMobile, we might auto-login or show login.
      // To be safe and simple: Always show unlock screen if savedMobile exists.

      _isLockScreenShown = true;
      navigatorKey.currentState
          ?.push(
            MaterialPageRoute(
              builder: (context) => const LoginScreen(isUnlockMode: true),
              fullscreenDialog: true,
            ),
          )
          .then((_) {
            _isLockScreenShown = false;
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'MockBank',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6200EE),
          brightness: Brightness.light,
          primary: const Color(0xFF6200EE),
          secondary: const Color(0xFF03DAC6),
        ),
        textTheme: GoogleFonts.interTextTheme(),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          color: Colors.white,
        ),
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/scan': (context) => const ScanScreen(),
        '/pay': (context) => const PayScreen(),
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
          );
        },
      },
    );
  }
}
