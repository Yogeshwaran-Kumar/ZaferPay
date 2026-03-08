import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'login_screen.dart';
import 'api_service.dart';
import 'main_navigation_screen.dart';
import 'scan_screen.dart';
import 'pay_screen.dart';
import 'settings_screen.dart';
import 'change_pin_screen.dart';
import 'risk_analysis_screen.dart';
import 'pending_requests_screen.dart';
import 'profile_screen.dart';
import 'amount_screen.dart';
import 'contacts_screen.dart';
import 'transaction_details_screen.dart';
import 'payment_pin_screen.dart';
import 'conversation_screen.dart';
import 'money_screen.dart';
import 'upi_circle_setup_pin_screen.dart';
import 'services/notification_service.dart';
import 'services/app_localizations.dart';
import 'services/app_language_provider.dart';
import 'mcc_helper.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart'
    as mlkit;
import 'video_splash_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
bool _isDeviceCompromised = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('is_dark_theme') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  themeNotifier.addListener(() {
    prefs.setBool('is_dark_theme', themeNotifier.value == ThemeMode.dark);
  });

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  HttpOverrides.global = MyHttpOverrides();

  try {
    _isDeviceCompromised = await FlutterJailbreakDetection.jailbroken;
  } catch (e) {
    _isDeviceCompromised = false;
  }

  ApiService().warmUpIdentity();
  ApiService().warmUpPinCache();

  try {
    final String? homeStr = prefs.getString('home_data_cache');
    if (homeStr != null) {
      final Map<String, dynamic> homeData = jsonDecode(homeStr);
      if (homeData['user'] != null) {
        if (homeData['user']['app_lock_enabled'] != null) {
          MyApp.appLockEnabled = homeData['user']['app_lock_enabled'] == true;
        } else {
          MyApp.appLockEnabled = homeData['user']['has_mpin'] == true;
        }
      }
    }
    MyApp.biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    MyApp.appLockEnabled =
        prefs.getBool('app_lock_enabled') ?? MyApp.appLockEnabled;
  } catch (_) {}

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppLanguageProvider())],
      child: const MyApp(),
    ),
  );
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
  static bool isRequestingPermission = false;
  static bool appLockEnabled = true;
  static bool biometricEnabled = false;
  static DateTime? lastShareTime;
  static DateTime? lastPermissionRequestTime;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isLockScreenShown = false;
  final _routeObserver = _CurrentRouteObserver();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initial initialization without localization
    NotificationService.instance.initialize();
    NotificationService.instance.resetBadgeCount();
    _initSharingIntent();
  }

  late StreamSubscription _intentDataStreamSubscription;

  void _initSharingIntent() {
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedMediaFile> value) {
          if (value.isNotEmpty) _handleSharedImages(value);
        }, onError: (err) => debugPrint("getIntentDataStream error: $err"));

    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      if (value.isNotEmpty) _handleSharedImages(value);
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

    if (result['mcc'] != null && result['mcc']!.isNotEmpty) {
      result['category'] = MccHelper.getDomain(result['mcc']!);
    }

    if (MyApp.appLockEnabled || MyApp.biometricEnabled) {
      if (_routeObserver.currentRouteName != '/login') {
        await _checkAndLockApp();
      }

      int attempts = 0;
      Map<String, dynamic>? userData;
      while (attempts < 60) {
        if (_routeObserver.currentRouteName != '/login' &&
            !_isLockScreenShown) {
          userData = await ApiService().getMe();
          if (userData != null) break;
        }
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
      }
      if (userData == null) return;

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

  bool _wasPaused = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
    } else if (state == AppLifecycleState.resumed) {
      NotificationService.instance.resetBadgeCount();
      if (_wasPaused) {
        _checkAndLockApp();
        _wasPaused = false;
      }
    }
  }

  Future<dynamic> _checkAndLockApp() async {
    if (_isLockScreenShown) return null;
    final currentRoute = _routeObserver.currentRouteName;
    if (currentRoute == '/login' ||
        MyApp.isSharing ||
        MyApp.isRequestingPermission) {
      return null;
    }

    if (!MyApp.appLockEnabled && !MyApp.biometricEnabled) return null;

    _isLockScreenShown = true;
    return navigatorKey.currentState
        ?.push(
          MaterialPageRoute(
            builder: (context) => const LoginScreen(isUnlockMode: true),
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
                  Text(
                    AppLocalizations.of(
                          context,
                        )?.translate('common.security_alert') ??
                        'Security Alert',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(
                          context,
                        )?.translate('common.compromised_desc') ??
                        'This app cannot run on rooted or jailbroken devices for security reasons.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => SystemNavigator.pop(),
                    child: Text(
                      AppLocalizations.of(
                            context,
                          )?.translate('common.exit_app') ??
                          'Exit App',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final language = Provider.of<AppLanguageProvider>(context);

    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (context, currentMode, _) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              navigatorObservers: [_routeObserver, moneyScreenRouteObserver],
              title: 'ZaferPay',
              debugShowCheckedModeBanner: false,
              themeMode: currentMode,
              locale: language.appLocale,
              builder: (context, child) {
                // Notification channels are now initialized only once in initState
                return child!;
              },
              supportedLocales: const [
                Locale('en', ''),
                Locale('hi', ''),
                Locale('ta', ''),
                Locale('bn', ''),
                Locale('gu', ''),
                Locale('kn', ''),
                Locale('ml', ''),
                Locale('mr', ''),
                Locale('te', ''),
                Locale('pa', ''),
                Locale('hi', 'EN'),
              ],
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: ThemeData(
                useMaterial3: true,
                scaffoldBackgroundColor: Colors.white,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF00B9F1),
                ),
                appBarTheme: AppBarTheme(
                  backgroundColor: Colors.white,
                  elevation: 0,
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
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                scaffoldBackgroundColor: const Color(0xFF181818),
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF00B9F1),
                  brightness: Brightness.dark,
                ),
                appBarTheme: AppBarTheme(
                  backgroundColor: const Color(0xFF181818),
                  elevation: 0,
                  titleTextStyle: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                textTheme: GoogleFonts.outfitTextTheme(
                  ThemeData.dark().textTheme,
                ).apply(bodyColor: Colors.white, displayColor: Colors.white),
              ),
              initialRoute: '/splash',
              routes: {
                '/splash': (context) => const VideoSplashScreen(),
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
                '/profile': (context) => const ProfileScreen(),
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
                    receiverName: args['name'],
                    category: args['category'],
                    mcc: args['mcc'],
                    note: args['note'],
                    skipFraudCheck: args['skipFraudCheck'] ?? false,
                    acknowledgedRisk: args['acknowledgedRisk'],
                    requestId: args['paymentRequestId'],
                    paymentSource: args['payment_source'],
                    isCirclePayment: args['isCirclePayment'] ?? false,
                    circleId: args['circleId'],
                  );
                },
                '/conversation': (context) => ConversationScreen(
                  args:
                      ModalRoute.of(context)!.settings.arguments
                          as Map<String, dynamic>,
                ),
                '/upi-circle-setup-pin': (context) {
                  final args =
                      ModalRoute.of(context)!.settings.arguments
                          as Map<String, dynamic>;
                  return UPICircleSetupPinScreen(
                    secondaryUpi: args['secondaryUpi'],
                    secondaryName: args['secondaryName'],
                    limit: args['limit'],
                    delegationType: args['delegationType'],
                  );
                },
              },
            );
          },
        );
      },
    );
  }
}

class _CurrentRouteObserver extends NavigatorObserver {
  String? currentRouteName;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name != null) currentRouteName = route.settings.name;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute?.settings.name != null) {
      currentRouteName = previousRoute?.settings.name;
    }
  }
}
