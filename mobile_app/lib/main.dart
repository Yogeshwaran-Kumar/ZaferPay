import 'package:flutter/material.dart';
import 'dart:io'; // Import dart:io for HttpOverrides
import 'package:google_fonts/google_fonts.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'scan_screen.dart';
import 'pay_screen.dart';
import 'settings_screen.dart';
import 'change_pin_screen.dart';
import 'payment_pin_screen.dart';
import 'lock_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final _storage = const FlutterSecureStorage();
  bool _isBackground = false;

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
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      _isBackground = true;
    } else if (state == AppLifecycleState.resumed) {
      if (_isBackground) {
        _isBackground = false;
        await _checkAndLock();
      }
    }
  }

  Future<void> _checkAndLock() async {
    // Check if user is logged in
    final token = await _storage.read(key: 'token');
    if (token != null) {
      // User is logged in, show lock screen
      // Use navigator key to push lock screen
      if (_navigatorKey.currentState != null) {
        // Avoid stacking multiple lock screens
        // A simple way is to push it.
        // Note: We might be on any screen. Just push LockScreen on top.
        // It prevents back navigation inside itself.

        // Optional: Check if top route is already LockScreen
        // but Navigator doesn't easily expose "top route".
        // We will just push it.
        _navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (context) => const LockScreen(),
            fullscreenDialog:
                true, // Makes it slide up like a model usually, looks distinct
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
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
          );
        },
      },
    );
  }
}
