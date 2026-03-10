import 'dart:async';
import 'utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'mcc_helper.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/call_state_service.dart';
import 'services/transaction_service.dart';
import 'services/user_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'fraud_scanning_animation.dart';
import 'services/app_localizations.dart';

class AmountScreen extends StatefulWidget {
  const AmountScreen({super.key});

  @override
  State<AmountScreen> createState() => _AmountScreenState();
}

class _AmountScreenState extends State<AmountScreen> {
  late String _receiverUpi;
  String? _contactName;
  String? _bankingName;
  String? _category;
  double? _balance;
  String? _currentUserUpi;
  String? _currentUserMobile;
  bool _isSelfTransfer = false;
  String? _rawMcc;
  String? _paymentSource;

  // UPI Circle State
  List<dynamic> _joinedCircles = [];
  dynamic
  _selectedCircle; // Selected circle object, null means Personal Balance

  final ApiService _api = ApiService();
  final _apiClient = ApiClient();
  late final _authService = AuthService(_apiClient);
  late final _userService = UserService(_apiClient);
  late final _transactionService = TransactionService(
    _apiClient,
    _authService,
    _userService,
  );
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isLoadingName = true;
  bool _userNotFound = false;
  bool _isAmountTooHigh = false;
  bool _isQrLimitExceeded = false;

  // Spending limit state
  double? _spendingLimit;
  int _spendingLimitPeriod = 1;
  double _spentInPeriod = 0.0;
  bool _isSpendingLimitExceeded = false;

  // Request payment state
  bool _isRequestPayment = false;
  int? _paymentRequestId;
  String? _requestReason;
  bool _isCirclePaymentApproval = false;

  // Fixed QR Amount state
  bool _isLockedAmount = false;

  // Phone call detection
  bool _isOnCall = false;
  bool _hasPhonePermission = true;
  StreamSubscription<bool>? _callStateSub;

  // --- Inline Risk Analysis State ---
  bool _isAnalyzingRisk = false;
  bool _hasAnalyzedRisk = false;
  bool _isRisk = false;
  bool _isWarn = false;
  bool _isHighRisk = false;
  bool _isBypassable = true;
  String _riskScore = "SAFE";
  String _riskExplanation = "";
  String? _specificRiskCode;
  Map<String, dynamic>? _fraudFeatures;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_validateAmount);
    _initCallDetection();
  }

  Future<void> _initCallDetection() async {
    final hasPerm = await CallStateService.instance.init();
    if (!mounted) return;
    setState(() {
      _hasPhonePermission = hasPerm;
      _isOnCall = CallStateService.instance.isOnCall;
    });
    _callStateSub = CallStateService.instance.stream.listen((onCall) {
      if (mounted) setState(() => _isOnCall = onCall);
    });
  }

  @override
  void dispose() {
    _callStateSub?.cancel();
    _amountController.removeListener(_validateAmount);
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _validateAmount() {
    final amountText = _amountController.text;
    if (amountText.isEmpty) {
      if (_isAmountTooHigh || _isSpendingLimitExceeded) {
        setState(() {
          _isAmountTooHigh = false;
          _isSpendingLimitExceeded = false;
        });
      }
      return;
    }

    final amount = double.tryParse(amountText);
    bool qrLimitExceeded = false;

    if (amount != null &&
        (_paymentSource == 'qr_upload' || _paymentSource == 'qr_share') &&
        amount > 2000) {
      qrLimitExceeded = true;
    }

    // Check custom spending limit (skip for circle payments)
    bool spendingLimitExceeded = false;
    if (amount != null &&
        _spendingLimit != null &&
        _spendingLimit! > 0 &&
        _selectedCircle == null &&
        !_isCirclePaymentApproval) {
      if (_spentInPeriod + amount > _spendingLimit!) {
        spendingLimitExceeded = true;
      }
    }

    if (amount != null && amount > 500000) {
      setState(() {
        _isAmountTooHigh = true;
        _isQrLimitExceeded = qrLimitExceeded;
        _isSpendingLimitExceeded = spendingLimitExceeded;
      });
    } else {
      setState(() {
        _isAmountTooHigh = false;
        _isQrLimitExceeded = qrLimitExceeded;
        _isSpendingLimitExceeded = spendingLimitExceeded;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _receiverUpi = args?['upi'] ?? '';
    _contactName = args?['name'];
    _category = args?['category'];
    _paymentSource = args?['payment_source'];
    _rawMcc = args?['mcc'];

    // Request payment prefill
    if (args != null && args['isRequestPayment'] == true) {
      _isRequestPayment = true;
      _paymentRequestId = args['paymentRequestId'];
      _requestReason = args['requestReason'];
      if (args['prefillAmount'] != null) {
        final prefill = args['prefillAmount'];
        _amountController.text = prefill is int
            ? prefill.toString()
            : (prefill is num)
            ? prefill.toStringAsFixed(
                prefill == prefill.roundToDouble() ? 0 : 2,
              )
            : prefill.toString();
      }
      _isCirclePaymentApproval = args['isCirclePayment'] == true;
      if (args['note'] != null) {
        _noteController.text = args['note'];
      }
    }

    // Locked QR Amount prefill
    if (args != null && args['isLockedAmount'] == true) {
      _isLockedAmount = true;
      if (args['prefillAmount'] != null) {
        final prefill = args['prefillAmount'];
        _amountController.text = prefill
            .toString(); // Usually a string from URI
      }
    }

    if (args != null) {
      if (args['senderBalance'] != null) {
        _balance = (args['senderBalance'] as num).toDouble();
      }
      if (args['senderUpi'] != null) {
        _currentUserUpi = args['senderUpi'];
      }
    }

    if (_isLoadingName) {
      _resolveReceiverAndName();
    }
  }

  Future<void> _resolveReceiverAndName() async {
    // 1. Fetch current user info (Optimized: Check preloaded args first)
    if (_balance == null ||
        _currentUserUpi == null ||
        _currentUserMobile == null) {
      final userData = await _api.getMe();
      if (mounted && userData != null) {
        setState(() {
          _balance = (userData['balance'] as num?)?.toDouble();
          _currentUserUpi = userData['upi_id'];
          _currentUserMobile = userData['mobile_number'] ?? userData['mobile'];

          // Load spending limit settings
          if (userData['spending_limit'] != null) {
            _spendingLimit = (userData['spending_limit'] as num).toDouble();
          }
          _spendingLimitPeriod = userData['spending_limit_period'] ?? 1;
        });

        // Calculate amount spent in this period using cached history
        _recalcSpentInPeriod(userData);

        // Load UPI Circles (New)
        _loadCircles();
      }
    }

    // Check if _receiverUpi looks like a phone number (mostly digits)
    final digitsOnly = _receiverUpi.replaceAll(RegExp(r'[^\d]'), '');
    final isPhoneNumber =
        !_receiverUpi.contains('@') &&
        digitsOnly.length >= 10 &&
        RegExp(r'^\d+$').hasMatch(digitsOnly);

    Map<String, dynamic>? info;

    // Check local cache first for instant resolution
    Map<String, dynamic>? cachedUser;
    if (!isPhoneNumber) {
      cachedUser = await _api.getCachedUser(_receiverUpi);
    }

    if (cachedUser != null) {
      info = cachedUser;
      _userNotFound = false;
    } else {
      // Network Lookup (Fallback)
      if (isPhoneNumber) {
        final phoneLast10 = digitsOnly.length >= 10
            ? digitsOnly.substring(digitsOnly.length - 10)
            : digitsOnly;

        // 1. Try RAM Cache for Phone Lookup
        info = _api.getCachedUserByPhoneSync(phoneLast10);
        info ??= await _api.lookupUserByPhone(phoneLast10);

        if (info != null && info['upi_id'] != null) {
          // Update _receiverUpi to actual UPI ID (critical for payment to work!)
          setState(() {
            _receiverUpi = info!['upi_id'];
            // Store banking name
            _bankingName = info['username'];
            _userNotFound = false; // User confirmed found
          });
          // cache this user for future UPI lookups
          _api.getCachedUser(_receiverUpi);
        } else {
          setState(() {
            _userNotFound = true;
          });
        }
      } else {
        // Not a phone number - regular UPI lookup
        info = await _api.lookupUser(_receiverUpi);
        if (info == null) {
          setState(() {
            _userNotFound = true;
          });
        } else {
          setState(() {
            _userNotFound = false;
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        if (info != null) {
          // Set banking name
          _bankingName = info['username'];

          if (MccHelper.isMerchant(info['mcc'])) {
            _rawMcc = info['mcc'];
            _category = MccHelper.getDomain(info['mcc']);
          }
        }
        _isLoadingName = false;

        // Check for self-transfer
        final myMobile = _currentUserMobile?.replaceAll(RegExp(r'[^\d]'), '');
        final receiverMobile = _receiverUpi.replaceAll(RegExp(r'[^\d]'), '');

        if (!_userNotFound &&
            ((_currentUserUpi != null && _receiverUpi == _currentUserUpi) ||
                (myMobile != null &&
                    receiverMobile.isNotEmpty &&
                    receiverMobile == myMobile))) {
          _isSelfTransfer = true;
        } else {
          _isSelfTransfer = false;
        }
      });
    }
  }

  Future<void> _loadCircles() async {
    final data = await _api.getCircleStatus();
    if (mounted) {
      setState(() {
        _joinedCircles = (data['joined_circles'] ?? [])
            .where((c) => c['status'] == 'ACTIVE')
            .toList();
      });
    }
  }

  void _recalcSpentInPeriod(Map<String, dynamic> userData) {
    if (_spendingLimit == null || _spendingLimit! <= 0) return;

    final int periodDays = _spendingLimitPeriod;
    final limitStart = DateTime.now().subtract(Duration(days: periodDays));
    final myUpi = userData['upi_id'] as String?;

    // Use cached history from home aggregate
    final homeData = _api.getCachedHomeDataSync();
    final history = homeData?['history'] as List<dynamic>? ?? [];

    double spent = 0.0;
    for (final tx in history) {
      if (tx['status'] != 'SUCCESS') continue;
      if (myUpi != null && tx['sender_upi_id'] != myUpi) continue;
      try {
        final txDate = DateTime.parse(tx['timestamp']).toLocal();
        if (txDate.isAfter(limitStart)) {
          spent += (tx['amount'] ?? 0).toDouble();
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _spentInPeriod = spent;
      });
      // Re-validate after recalc
      _validateAmount();
    }
  }

  String _spendingLimitMessage() {
    final periodLabel = _spendingLimitPeriod == 1
        ? (AppLocalizations.of(context)?.translate('common.daily') ?? 'daily')
        : _spendingLimitPeriod == 7
        ? (AppLocalizations.of(context)?.translate('common.weekly') ?? 'weekly')
        : _spendingLimitPeriod == 14
        ? (AppLocalizations.of(context)?.translate('common.bi_weekly') ??
              'bi-weekly')
        : _spendingLimitPeriod == 30
        ? (AppLocalizations.of(context)?.translate('common.monthly') ??
              'monthly')
        : '$_spendingLimitPeriod-day';
    final limit = _spendingLimit ?? 0;
    final remaining = (limit - _spentInPeriod).clamp(0.0, double.infinity);
    return AppLocalizations.of(context)?.translate(
          'amount.limit_summary_msg',
          arguments: {
            'period': periodLabel,
            'limit': limit.toStringAsFixed(0),
            'spent': _spentInPeriod.toStringAsFixed(0),
            'remaining': remaining.toStringAsFixed(0),
          },
        ) ??
        'Your $periodLabel limit is ₹${limit.toStringAsFixed(0)}. '
            'You have already spent ₹${_spentInPeriod.toStringAsFixed(0)}, '
            'with ₹${remaining.toStringAsFixed(0)} remaining.';
  }

  Future<void> _onPayPressed() async {
    if (_isSelfTransfer ||
        _isAmountTooHigh ||
        _isQrLimitExceeded ||
        _isSpendingLimitExceeded) {
      return;
    }

    // Guard: block payment during active phone call (directly queries Android OS)
    final bool onCallNow = await CallStateService.isCurrentlyOnCall();
    if (!mounted) return;

    if (onCallNow || _isOnCall) {
      _showOnCallDialog();
      return;
    }

    // Guard: block payment if phone state permission is missing for security
    if (!_hasPhonePermission) {
      final stillNoPerm = !await CallStateService.instance.init();
      if (!mounted) return;
      setState(() => _hasPhonePermission = !stillNoPerm);
      if (stillNoPerm) {
        _showPermissionRequiredDialog();
        return;
      }
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.translate('amount.min_amount') ??
                "Minimum amount is ₹1",
          ),
        ),
      );
      return;
    }

    // Balance Validation (skip for UPI Circle payments — parent's balance is used)
    if (_selectedCircle == null && _balance != null && amount > _balance!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
                  context,
                )?.translate('amount.insufficient_balance') ??
                "Insufficient balance",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Unfocus keyboard
    FocusScope.of(context).unfocus();

    // Trigger Inline Risk Analysis
    setState(() {
      _isAnalyzingRisk = true;
      _hasAnalyzedRisk = false;
      // Clear previous results
      _riskScore = "SAFE";
      _riskExplanation = "";
      _specificRiskCode = null;
      _fraudFeatures = null;
      _isRisk = false;
      _isWarn = false;
      _isHighRisk = false;
      _isBypassable = true;
    });

    try {
      final result = await _api.analyzeTransactionRisk(
        _receiverUpi,
        amount,
        mcc: _rawMcc,
        note: _noteController.text.trim(),
        paymentSource: _paymentSource,
        isOnCall: _isOnCall,
      );

      if (result['risk_score'] == 'FRAUD_BLOCKED') {
        if (mounted) {
          setState(() {
            _isAnalyzingRisk = false;
            _hasAnalyzedRisk = false;
          });
          _showResultDialog({
            'status': 'FRAUD_BLOCKED',
            'custom_message':
                result['detail'] != null && result['detail']['message'] != null
                ? result['detail']['message']
                : AppLocalizations.of(
                        context,
                      )?.translate('transaction.fraud_blocked_desc') ??
                      'Transaction blocked. This account has been flagged for fraudulent activity.',
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _riskScore = result['risk_score'] ?? 'SAFE';
          _specificRiskCode = result['risk_reason'];
          _isRisk = _riskScore != 'SAFE';
          _isWarn = _riskScore == 'WARN';
          _isHighRisk = _riskScore == 'HIGH';
          _isBypassable = result['is_bypassable'] ?? true;

          // Update receiver name from backend if available
          if (result['receiver_name'] != null &&
              result['receiver_name'] != 'Unknown') {
            _bankingName = result['receiver_name'];
          }

          _riskExplanation =
              _getHumanReadableExplanation(_specificRiskCode) ??
              (result['detail'] is Map
                  ? result['detail']['message']
                  : _getDefaultExplanation());

          if (result['detail'] is Map) {
            _fraudFeatures = result['detail']['features'];
          }

          _isAnalyzingRisk = false;
          _hasAnalyzedRisk = true;

          // AUTO-PROCEED: If safe, go to PIN entry after 1 second
          if (_riskScore == 'SAFE') {
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted && _hasAnalyzedRisk && !_isAnalyzingRisk) {
                _proceedToPin();
              }
            });
          }
        });
      }
    } catch (e) {
      // CRITICAL ERROR: Risk analysis failed
      if (kDebugMode) {
        print('❌❌❌ CRITICAL: Risk Analysis Failed ❌❌❌');
        print('Error: $e');
        print('Stack trace:');
        print(StackTrace.current);
      }
      
      if (mounted) {
        // SHOW ERROR TO USER - DO NOT AUTO-PROCEED OR SHOW SAFE
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Cannot connect to server. Please check your internet connection.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        
        // CRITICAL: Reset state to prevent payment
        setState(() {
          _isAnalyzingRisk = false;
          _hasAnalyzedRisk = false; // Prevent auto-proceed
          _isRisk = false;
          _isWarn = false;
          _isHighRisk = false;
          _riskScore = 'ERROR'; // Mark as error, not SAFE
          _riskExplanation = 'Connection failed';
        });
      }
    }
  }

  String _getDefaultExplanation() {
    switch (_riskScore) {
      case 'HIGH':
        return AppLocalizations.of(context)?.translate('risk.high_title') ??
            'High risk transaction detected. Please review carefully.';
      case 'WARN':
        return AppLocalizations.of(context)?.translate('risk.warn_title') ??
            'Unusual pattern detected. Proceed with caution.';
      default:
        return AppLocalizations.of(context)?.translate('risk.safe_title') ??
            'Transaction appears safe.';
    }
  }

  String? _getHumanReadableExplanation(String? code) {
    if (code == null) return null;

    if (code.contains("F18_DAILY")) {
      return AppLocalizations.of(context)?.translate('risk.f18_daily') ??
          "You've exceeded the daily transfer limit for this receiver.";
    }
    if (code.contains("F1_VELOCITY")) {
      return AppLocalizations.of(context)?.translate('risk.f1_velocity') ??
          "Too many transactions in a short time. Please wait a moment.";
    }
    if (code.contains("AI_DETECTED")) {
      return AppLocalizations.of(context)?.translate('risk.ai_detected') ??
          "Our AI detected a highly unusual pattern compared to your history.";
    }
    if (code.contains("F29_GEO")) {
      return AppLocalizations.of(context)?.translate('risk.f29_geo') ??
          "Impossible travel detected. Your location changed too fast.";
    }
    if (code.contains("F15_RAPID_DRAIN")) {
      return AppLocalizations.of(context)?.translate('risk.f15_rapid_drain') ??
          "Unusual rapid spending detected from your account.";
    }
    if (code.contains("NEW_RECEIVER")) {
      return AppLocalizations.of(context)?.translate('risk.new_receiver') ??
          "You are sending money to a new person for the first time.";
    }
    if (code.contains("SELF_TRANSFER")) {
      return AppLocalizations.of(context)?.translate('risk.self_transfer') ??
          "You cannot send money to your own UPI ID.";
    }
    if (code.contains("F52_LAYERING")) {
      return AppLocalizations.of(context)?.translate('risk.f52_layering') ??
          "Complex money flow pattern detected (Layering Risk).";
    }
    if (code.contains("F30_WEEKLY")) {
      return AppLocalizations.of(context)?.translate('risk.f30_weekly') ??
          "Weekly spending limit exceeded for this receiver.";
    }

    return null;
  }

  Future<void> _proceedToPin() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null) return;

    final result = await Navigator.pushNamed(
      context,
      '/payment-pin',
      arguments: {
        'receiverUpi': _receiverUpi,
        'amount': amount,
        'name': _bankingName ?? _contactName ?? _receiverUpi,
        'category': _category,
        'mcc': _rawMcc,
        'note': _noteController.text.trim(),
        'skipFraudCheck': _hasAnalyzedRisk, // Always true if pre-check finished
        'acknowledgedRisk': _riskScore, // Pass the score (SAFE/WARN/HIGH)
        'paymentRequestId': _paymentRequestId,
        'paymentSource': _paymentSource,
        'isCirclePayment': _selectedCircle != null,
        'circleId': _selectedCircle != null ? _selectedCircle['id'] : null,
      },
    );

    if (result != null && result is Map<String, dynamic>) {
      if (_isRequestPayment &&
          _paymentRequestId != null &&
          (result['status'] == 'SUCCESS' || result['status'] == 'success')) {
        await _transactionService.markRequestPaid(_paymentRequestId!);
      }
      if (mounted) {
        _showResultDialog(result);
      }
    }
  }

  void _showOnCallDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.phone_disabled_rounded,
                  color: Colors.red,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                AppLocalizations.of(
                      context,
                    )?.translate('amount.security_block') ??
                    'Security Block',
                style: GoogleFonts.notoSans(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context)?.translate('amount.on_call_msg') ??
                    'For your safety, payments are disabled while you are on an active phone call to prevent potential scams.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSans(
                  fontSize: 15,
                  color: isDark ? Colors.white70 : Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    AppLocalizations.of(context)?.translate('common.got_it') ??
                        'Got it',
                    style: GoogleFonts.notoSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPermissionRequiredDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.security_rounded,
                  color: Colors.blue,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                AppLocalizations.of(
                      context,
                    )?.translate('amount.security_permission_title') ??
                    'Security Permission Required',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSans(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(
                      context,
                    )?.translate('amount.security_permission_desc') ??
                    'To protect you from fraudulent calls, Safe Pay needs permission to detect if you are on a call during payments.\n\nPlease grant the Phone permission to proceed.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSans(
                  fontSize: 13,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B9F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    openAppSettings();
                  },
                  child: Text(
                    AppLocalizations.of(
                          context,
                        )?.translate('common.open_settings') ??
                        'Open Settings',
                    style: GoogleFonts.notoSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionWarning(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppLocalizations.of(
                      context,
                    )?.translate('alerts.permission_title') ??
                    'Call security is disabled. Grant Phone permission for safe payments.',
                style: GoogleFonts.notoSans(
                  fontSize: 12,
                  color: isDark ? Colors.orange[200] : Colors.orange[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                final hasPerm = await CallStateService.instance.init();
                if (mounted) setState(() => _hasPhonePermission = hasPerm);
              },
              child: Text(
                AppLocalizations.of(context)?.translate('common.enable') ??
                    'Enable',
                style: GoogleFonts.notoSans(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF00B9F1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showResultDialog(Map<String, dynamic> result) {
    if (result.containsKey('detail') && !result.containsKey('status')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result['detail'])));
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = result['status'];
    final risk = result['risk_score'];

    // Determine color and icon based on status
    Color color = const Color(0xFF4CAF50); // Material Green 500
    IconData icon = Icons.check_circle_rounded;
    String title =
        AppLocalizations.of(context)?.translate('transaction.success') ??
        "Payment Successful";
    Color bgColor = isDark ? const Color(0xFF1E2630) : Colors.white;

    if (status == "BLOCKED") {
      color = const Color(0xFFE53935); // Red 600
      icon = Icons.block_rounded;
      title =
          AppLocalizations.of(context)?.translate('transaction.blocked') ??
          "Transaction Blocked";
    } else if (status == "FAILED" || status == "CANCELLED") {
      color = const Color(0xFFE53935);
      icon = Icons.error_rounded;
      title = status == "CANCELLED"
          ? AppLocalizations.of(context)?.translate('transaction.cancelled') ??
                "Transaction Cancelled"
          : AppLocalizations.of(context)?.translate('transaction.failed') ??
                "Payment Failed";
    } else if (risk == "WARN") {
      color = const Color(0xFFFB8C00); // Orange 600
      icon = Icons.warning_rounded;
      title =
          AppLocalizations.of(context)?.translate('risk.warn_title_short') ??
          "Warning Detected";
    } else if (status == "SECURITY_RISK") {
      // PHASE 2 ALERT: Integrity/HMAC Failure
      color = const Color(0xFFD32F2F); // Darker Red
      icon = Icons.security_rounded;
      title =
          AppLocalizations.of(context)?.translate('alerts.security_block') ??
          "Security Alert";
    } else if (status == "FRAUD_BLOCKED") {
      // PHASE 1 ALERT: AI Block
      color = const Color(0xFFC62828); // Sharp Red
      icon = Icons.gpp_bad_rounded;
      title =
          AppLocalizations.of(context)?.translate('transaction.blocked') ??
          "Fraud Detected";
    } else if (status == "PENDING_APPROVAL") {
      color = const Color(0xFFFB8C00); // Orange 600
      icon = Icons.hourglass_empty_rounded;
      title =
          AppLocalizations.of(context)?.translate('transaction.pending') ??
          "Approval Required";
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon Circle with Pulse Effect (simulated vs static)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.1),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.2),
                  ),
                  child: Icon(icon, size: 48, color: color),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSans(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              if (status == "SUCCESS") ...[
                Text(
                  "₹${formatAmount(result['amount'])}",
                  style: GoogleFonts.notoSans(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 24),
                // Transaction Details Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF303030)
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AppLocalizations.of(
                                  context,
                                )?.translate('amount.to_label') ??
                                "To",
                            style: GoogleFonts.notoSans(
                              color: isDark ? Colors.grey[400] : Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _contactName ?? _bankingName ?? _receiverUpi,
                            style: GoogleFonts.notoSans(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AppLocalizations.of(
                                  context,
                                )?.translate('amount.tx_id_label') ??
                                "Transaction ID",
                            style: GoogleFonts.notoSans(
                              color: isDark ? Colors.grey[400] : Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            result['transaction_id']?.toString().substring(
                                  0,
                                  12,
                                ) ??
                                "N/A",
                            style: GoogleFonts.notoSans(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Error Case
                Text(
                  AppLocalizations.of(
                        context,
                      )?.translate('transaction.error_generic') ??
                      "Your transaction could not be completed.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSans(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.grey[800]
                        : Colors.black, // Sleek black/dark button
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        24,
                      ), // Pill shape for Done
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.pop(context); // Close Dialog
                    Navigator.pop(
                      context,
                      result,
                    ); // Go back to Home / Conversation
                  },
                  child: Text(
                    AppLocalizations.of(
                          context,
                        )?.translate('amount.done_btn') ??
                        "Done",
                    style: GoogleFonts.notoSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12), // Added a SizedBox for spacing
              Text(
                AppLocalizations.of(context)?.translate('common.powered_by') ??
                    'Powered by ZaferPay',
                style: GoogleFonts.notoSans(
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine Theme Colors to match "Safe Pay" aesthetic
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Background: Clean White or Deep Dark (no grey tint)
    final bgColor = isDark ? const Color(0xFF0F1115) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey[600];

    // Logic for Name Display
    final displayContactName = _contactName ?? _bankingName ?? _receiverUpi;
    final displayBankingName =
        _bankingName ??
        (!_userNotFound && _bankingName != null ? _bankingName : null);

    // Initial for Avatar
    final initial = displayContactName.isNotEmpty
        ? displayContactName[0].toUpperCase()
        : "?";

    return Scaffold(
      backgroundColor: bgColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0, // Prevent color change on scroll
        leading: IconButton(
          icon: Icon(Icons.close, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      // Hide floating action button if risk is being analyzed or already analyzed
      floatingActionButton: (_isAnalyzingRisk || _hasAnalyzedRisk)
          ? null
          : SizedBox(
              width: MediaQuery.of(context).size.width - 32,
              child: FloatingActionButton.extended(
                onPressed:
                    (_isSelfTransfer ||
                        _isAmountTooHigh ||
                        _isQrLimitExceeded ||
                        (_isSpendingLimitExceeded &&
                            _selectedCircle == null &&
                            !_isCirclePaymentApproval))
                    ? null
                    : _onPayPressed,
                backgroundColor:
                    (_isSelfTransfer ||
                        _isAmountTooHigh ||
                        _isQrLimitExceeded ||
                        (_isSpendingLimitExceeded &&
                            _selectedCircle == null &&
                            !_isCirclePaymentApproval))
                    ? (isDark ? Colors.grey[800] : Colors.grey[300])
                    : const Color(0xFF00B9F1), // Brand Cyan/Blue
                elevation:
                    (_isSelfTransfer ||
                        _isAmountTooHigh ||
                        _isQrLimitExceeded ||
                        (_isSpendingLimitExceeded &&
                            _selectedCircle == null &&
                            !_isCirclePaymentApproval))
                    ? 0
                    : 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                label: Text(
                  _isSelfTransfer
                      ? (AppLocalizations.of(
                              context,
                            )?.translate('amount.cannot_transfer_self') ??
                            "Cannot transfer to self")
                      : _isQrLimitExceeded
                      ? (AppLocalizations.of(context)!
                                .translate('amount.exceeds_limit')
                                ?.replaceAll('{amount}', '2,000') ??
                            "Exceeds limit: ₹2,000")
                      : (_isSpendingLimitExceeded &&
                            _selectedCircle == null &&
                            !_isCirclePaymentApproval)
                      ? (AppLocalizations.of(
                              context,
                            )?.translate('amount.spending_limit_exceeded') ??
                            "Spending Limit Exceeded")
                      : (_isCirclePaymentApproval
                            ? (AppLocalizations.of(
                                    context,
                                  )?.translate('amount.approve') ??
                                  "Approve")
                            : (_selectedCircle != null
                                  ? (AppLocalizations.of(
                                          context,
                                        )?.translate('amount.send_approval') ??
                                        "Send for Approval")
                                  : (AppLocalizations.of(
                                          context,
                                        )?.translate('amount.proceed') ??
                                        "Proceed"))),
                  style: GoogleFonts.notoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color:
                        (_isSelfTransfer ||
                            _isAmountTooHigh ||
                            _isQrLimitExceeded ||
                            (_isSpendingLimitExceeded &&
                                _selectedCircle == null &&
                                !_isCirclePaymentApproval))
                        ? Colors.grey[500]
                        : Colors.white,
                  ),
                ),
                icon: Icon(
                  (_isSelfTransfer ||
                          _isQrLimitExceeded ||
                          _isSpendingLimitExceeded)
                      ? Icons.block_rounded
                      : Icons.arrow_forward_rounded,
                  color:
                      (_isSelfTransfer ||
                          _isAmountTooHigh ||
                          _isQrLimitExceeded ||
                          (_isSpendingLimitExceeded &&
                              _selectedCircle == null &&
                              !_isCirclePaymentApproval))
                      ? Colors.grey[500]
                      : Colors.white,
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: Column(
          children: [
            // TOP HALF: Amount and Receiver Info (Wrapped in Expanded)
            Expanded(
              flex: (_isAnalyzingRisk || _hasAnalyzedRisk) ? 3 : 1,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // 1. Receiver Info Section (Top)
                    Center(
                      child: Column(
                        children: [
                          // Avatar with Orange Gradient
                          Container(
                            width: (_isAnalyzingRisk || _hasAnalyzedRisk)
                                ? 56
                                : 72,
                            height: (_isAnalyzingRisk || _hasAnalyzedRisk)
                                ? 56
                                : 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: getAvatarColor(displayContactName),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              initial,
                              style: GoogleFonts.notoSans(
                                fontSize: (_isAnalyzingRisk || _hasAnalyzedRisk)
                                    ? 24
                                    : 32,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // "Paying [Name]" header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isRequestPayment
                                    ? (AppLocalizations.of(context)?.translate(
                                            'amount.paying_request_label',
                                          ) ??
                                          "Paying request to ")
                                    : (AppLocalizations.of(context)?.translate(
                                            'amount.paying_to_label',
                                          ) ??
                                          "Paying "),
                                style: GoogleFonts.notoSans(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  displayContactName,
                                  style: GoogleFonts.notoSans(
                                    color: textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // "Banking name: [Name]" + Verified Tick
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!_userNotFound) ...[
                                Flexible(
                                  child: Text(
                                    "${AppLocalizations.of(context)?.translate('amount.banking_name_label') ?? "Banking name"}: ${displayBankingName ?? (_rawMcc != null ? (AppLocalizations.of(context)?.translate('amount.verified_merchant_label') ?? 'Verified Merchant') : (AppLocalizations.of(context)?.translate('amount.verified_user_label') ?? 'Verified User'))}",
                                    style: GoogleFonts.notoSans(
                                      color: secondaryTextColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.verified,
                                  color: _rawMcc != null
                                      ? Colors.blueAccent
                                      : Colors.greenAccent, // Verified tick
                                  size: 14,
                                ),
                              ] else ...[
                                Text(
                                  AppLocalizations.of(
                                        context,
                                      )?.translate('amount.banking_unknown') ??
                                      "Banking name: Unknown",
                                  style: GoogleFonts.notoSans(
                                    color: secondaryTextColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),

                          // Mobile / UPI ID
                          Text(
                            _receiverUpi,
                            style: GoogleFonts.notoSans(
                              color: secondaryTextColor,
                              fontSize: 13,
                            ),
                          ),

                          // Self-transfer warning
                          if (_isSelfTransfer &&
                              !_isAnalyzingRisk &&
                              !_hasAnalyzedRisk)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                AppLocalizations.of(context)?.translate(
                                      'amount.cannot_transfer_self_msg',
                                    ) ??
                                    "Cannot transfer to self",
                                style: GoogleFonts.notoSans(
                                  color: const Color.fromARGB(255, 248, 5, 5),
                                  fontSize: 15,
                                ),
                              ),
                            ),

                          // Request payment info banner
                          if (_isRequestPayment &&
                              !_isAnalyzingRisk &&
                              !_hasAnalyzedRisk)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF00B9F1,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.info_outline,
                                      color: Color(0xFF00B9F1),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${AppLocalizations.of(context)?.translate('amount.payment_request_title') ?? "Payment Request"}: ${_requestReason != null ? (_requestReason == 'wrongly_sent'
                                                ? (AppLocalizations.of(context)?.translate('amount.wrongly_sent_label') ?? 'Wrongly Sent')
                                                : _requestReason == 'wrong_amount'
                                                ? (AppLocalizations.of(context)?.translate('amount.wrong_amount_label') ?? 'Wrong Amount')
                                                : (AppLocalizations.of(context)?.translate('amount.other_label') ?? 'Other')) : ''}',
                                      style: GoogleFonts.notoSans(
                                        color: const Color(0xFF00B9F1),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (!_hasPhonePermission &&
                        !_isAnalyzingRisk &&
                        !_hasAnalyzedRisk)
                      _buildPermissionWarning(isDark),

                    SizedBox(
                      height: (_isAnalyzingRisk || _hasAnalyzedRisk) ? 16 : 32,
                    ),

                    // 2. Amount Input Section (Middle - Expanded)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Merchant Badge (if applicable) - Moved above amount
                          if (!_isAnalyzingRisk &&
                              !_hasAnalyzedRisk &&
                              _rawMcc != null &&
                              MccHelper.isMerchant(_rawMcc))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildMerchantBadge(isDark),
                            ),

                          // Amount TextField
                          IntrinsicWidth(
                            child: TextField(
                              controller: _amountController,
                              keyboardType: TextInputType.number,
                              autofocus: !_isRequestPayment && !_isLockedAmount,
                              readOnly:
                                  _isRequestPayment ||
                                  _isLockedAmount ||
                                  _isAnalyzingRisk ||
                                  _hasAnalyzedRisk,
                              enabled:
                                  !_isRequestPayment &&
                                  !_isLockedAmount &&
                                  !_isAnalyzingRisk &&
                                  !_hasAnalyzedRisk,
                              inputFormatters:
                                  (_isRequestPayment || _isLockedAmount)
                                  ? []
                                  : [
                                      MaxValueTextInputFormatter(
                                        500000,
                                        onMaxValueExceeded: () {
                                          if (!_isAmountTooHigh) {
                                            setState(
                                              () => _isAmountTooHigh = true,
                                            );
                                          }
                                        },
                                      ),
                                    ],
                              style: GoogleFonts.notoSans(
                                color: textColor,
                                fontSize: (_isAnalyzingRisk || _hasAnalyzedRisk)
                                    ? 48
                                    : 64, // Shrink text
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                filled: false,
                                prefixText: "₹ ",
                                prefixStyle: GoogleFonts.notoSans(
                                  color: textColor,
                                  fontSize:
                                      (_isAnalyzingRisk || _hasAnalyzedRisk)
                                      ? 48
                                      : 64,
                                  fontWeight: FontWeight.w500,
                                ),
                                hintText: "0",
                                hintStyle: GoogleFonts.notoSans(
                                  color: isDark
                                      ? Colors.grey[700]
                                      : Colors.grey[300],
                                  fontSize:
                                      (_isAnalyzingRisk || _hasAnalyzedRisk)
                                      ? 48
                                      : 64,
                                  fontWeight: FontWeight.w500,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),

                          // Amount Too High Warning
                          if (_isAmountTooHigh &&
                              !_isAnalyzingRisk &&
                              !_hasAnalyzedRisk)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                AppLocalizations.of(
                                      context,
                                    )?.translate('amount.max_limit_msg') ??
                                    "Max limit: ₹5,00,000",
                                style: GoogleFonts.notoSans(
                                  color: Colors.red[300],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                          // Unified Alerts Box
                          if (!_isAnalyzingRisk &&
                              !_hasAnalyzedRisk &&
                              ((_paymentSource != null &&
                                      _paymentSource!.startsWith('qr_')) ||
                                  _isQrLimitExceeded ||
                                  _isSpendingLimitExceeded))
                            Builder(
                              builder: (context) {
                                final alerts = <Widget>[];

                                if (_paymentSource != null &&
                                    _paymentSource!.startsWith('qr_')) {
                                  alerts.add(
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.warning_amber_rounded,
                                              color: Colors.red,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              AppLocalizations.of(
                                                    context,
                                                  )?.translate(
                                                    'amount.attention_label',
                                                  ) ??
                                                  'Attention!',
                                              style: GoogleFonts.notoSans(
                                                color: Colors.red,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          AppLocalizations.of(
                                                context,
                                              )?.translate(
                                                'amount.qr_warning_msg',
                                              ) ??
                                              "QR codes are ONLY for sending money. Never scan a QR code to receive money.",
                                          style: GoogleFonts.notoSans(
                                            color: isDark
                                                ? Colors.red[300]
                                                : Colors.red[700],
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                if (_isQrLimitExceeded) {
                                  alerts.add(
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.warning_amber_rounded,
                                              color: Colors.red,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              AppLocalizations.of(
                                                    context,
                                                  )?.translate(
                                                    'amount.qr_limit_title',
                                                  ) ??
                                                  'QR Limit Exceeded',
                                              style: GoogleFonts.notoSans(
                                                color: Colors.red,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          AppLocalizations.of(
                                                context,
                                              )?.translate(
                                                'amount.qr_limit_msg',
                                              ) ??
                                              "You cannot send more than 2,000 rupees by scanning a QR code.",
                                          style: GoogleFonts.notoSans(
                                            color: isDark
                                                ? Colors.red[300]
                                                : Colors.red[700],
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                if (_isSpendingLimitExceeded) {
                                  alerts.add(
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.block_rounded,
                                              color: Colors.red,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              AppLocalizations.of(
                                                    context,
                                                  )?.translate(
                                                    'amount.spending_limit_title',
                                                  ) ??
                                                  'Spending Limit Exceeded',
                                              style: GoogleFonts.notoSans(
                                                color: Colors.red,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _spendingLimitMessage(),
                                          style: GoogleFonts.notoSans(
                                            color: isDark
                                                ? Colors.red[300]
                                                : Colors.red[700],
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    12,
                                    24,
                                    0,
                                  ),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.red.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (
                                          int i = 0;
                                          i < alerts.length;
                                          i++
                                        ) ...[
                                          alerts[i],
                                          if (i < alerts.length - 1)
                                            const SizedBox(height: 12),
                                          if (i < alerts.length - 1)
                                            Divider(
                                              color: Colors.red.withValues(
                                                alpha: 0.2,
                                              ),
                                              height: 1,
                                            ),
                                          if (i < alerts.length - 1)
                                            const SizedBox(height: 12),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                          SizedBox(
                            height: (_isAnalyzingRisk || _hasAnalyzedRisk)
                                ? 12
                                : 8,
                          ),

                          if (!_isAnalyzingRisk && !_hasAnalyzedRisk)
                            SizedBox(height: 16),

                          // "Add note" Pill Button
                          if (!_isAnalyzingRisk && !_hasAnalyzedRisk)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E2630)
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: IntrinsicWidth(
                                child: TextField(
                                  controller: _noteController,
                                  textAlign: TextAlign.center,
                                  readOnly:
                                      _isCirclePaymentApproval ||
                                      _isAnalyzingRisk ||
                                      _hasAnalyzedRisk,
                                  enabled:
                                      !_isCirclePaymentApproval &&
                                      !_isAnalyzingRisk &&
                                      !_hasAnalyzedRisk,
                                  style: GoogleFonts.notoSans(
                                    color: textColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: InputDecoration(
                                    filled: false,
                                    isDense: true,
                                    hintText:
                                        AppLocalizations.of(
                                          context,
                                        )?.translate('amount.add_note') ??
                                        "Add note",
                                    hintStyle: GoogleFonts.notoSans(
                                      color: secondaryTextColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),

                          if ((_isAnalyzingRisk || _hasAnalyzedRisk) &&
                              _noteController.text.isNotEmpty)
                            Text(
                              '"${_noteController.text}"',
                              style: GoogleFonts.notoSans(
                                color: secondaryTextColor,
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),

                    SizedBox(
                      height: (_isAnalyzingRisk || _hasAnalyzedRisk) ? 16 : 40,
                    ),

                    // 4. Payment Source Selector (New for UPI Circle)
                    if (_joinedCircles.isNotEmpty &&
                        !_isAnalyzingRisk &&
                        !_hasAnalyzedRisk)
                      _buildPaymentSourceSelector(isDark),

                    if (!_isAnalyzingRisk && !_hasAnalyzedRisk)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: Colors.blue[300],
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              AppLocalizations.of(
                                    context,
                                  )?.translate('details.powered_by') ??
                                  AppLocalizations.of(
                                    context,
                                  )?.translate('details.powered_by') ??
                                  "Powered by ZaferPay",
                              style: GoogleFonts.notoSans(
                                color: Colors.blue[300],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // BOTTOM HALF: Risk Analysis / Scanning
            if (_isAnalyzingRisk || _hasAnalyzedRisk)
              Expanded(
                flex: 4,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E1E1E)
                        : Colors.grey.shade50,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade300,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                    child: _isAnalyzingRisk
                        ? _buildScanningState(textColor)
                        : _buildRiskResultState(textColor, isDark, context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantBadge(bool isDark) {
    if (_rawMcc == null || !MccHelper.isMerchant(_rawMcc)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF00B9F1).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF00B9F1).withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.store_rounded, size: 14, color: Color(0xFF00B9F1)),
          const SizedBox(width: 8),
          Text(
            "Merchant",
            style: GoogleFonts.notoSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF00B9F1),
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningState(Color textColor) {
    final screenHeight = MediaQuery.of(context).size.height;
    final animSize = (screenHeight * 0.3).clamp(180.0, 280.0);

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          FraudScanningAnimation(
            isDark: Theme.of(context).brightness == Brightness.dark,
            size: animSize,
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              AppLocalizations.of(context)?.translate('risk.analyzing') ??
                  "Analyzing Transaction...",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              AppLocalizations.of(
                    context,
                  )?.translate('risk.checking_pattern') ??
                  "Checking recipient pattern...",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildRiskResultState(
    Color textColor,
    bool isDark,
    BuildContext context,
  ) {
    Color getStatusColor() {
      if (_isHighRisk) return const Color(0xFFD32F2F); // Red 700
      if (_isWarn) return const Color(0xFFFFA000); // Amber 700
      return const Color(0xFF4CAF50); // Green
    }

    final statusColor = getStatusColor();
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final secondaryTextColor = isDark
        ? Colors.grey.shade400
        : Colors.grey.shade600;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Status Icon
            if (_isRisk)
              Icon(
                _isHighRisk
                    ? Icons.gpp_bad_rounded
                    : Icons.warning_amber_rounded,
                size: 64,
                color: statusColor,
              )
            else
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 40, color: Colors.white),
              ),

            const SizedBox(height: 16),

            // Title
            Text(
              _isHighRisk
                  ? (AppLocalizations.of(
                          context,
                        )?.translate('risk.critical_fraud_risk') ??
                        "Critical Fraud Risk!")
                  : (_isWarn
                        ? (AppLocalizations.of(
                                context,
                              )?.translate('risk.security_warning') ??
                              "Security Warning")
                        : (AppLocalizations.of(
                                context,
                              )?.translate('risk.verified_safe') ??
                              "Transaction Verified Safe")),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),

            const SizedBox(height: 16),

            // Description & Factors
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildRiskFactors(isDark, textColor),
              ),
            ),

            const SizedBox(height: 24),

            // Proceed Button
            if (!_isRisk || _isBypassable)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _proceedToPin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRisk
                        ? statusColor
                        : const Color(0xFF00B9F1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _isRisk
                        ? (AppLocalizations.of(
                                context,
                              )?.translate('risk.proceed_caution') ??
                              "Proceed with Caution")
                        : (_isCirclePaymentApproval
                              ? (AppLocalizations.of(
                                      context,
                                    )?.translate('risk.approve') ??
                                    "Approve")
                              : (_selectedCircle != null
                                    ? (AppLocalizations.of(
                                            context,
                                          )?.translate('risk.send_approval') ??
                                          "Send for Approval")
                                    : (AppLocalizations.of(
                                            context,
                                          )?.translate('risk.proceed') ??
                                          "Proceed"))),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    AppLocalizations.of(context)?.translate('risk.go_back') ??
                        "Go Back",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Cancel button
            TextButton(
              onPressed: () {
                setState(() {
                  _isAnalyzingRisk = false;
                  _hasAnalyzedRisk = false;
                });
              },
              child: Text(
                AppLocalizations.of(context)?.translate('details.cancel') ??
                    'Cancel',
                style: TextStyle(color: secondaryTextColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSourceSelector(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E2630)
            : Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.grey[800]!
              : Colors.blue.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(
                  context,
                )?.translate('amount.choose_payment_source') ??
                "CHOOSE PAYMENT SOURCE",
            style: GoogleFonts.notoSans(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<dynamic>(
              value: _selectedCircle,
              isExpanded: true,
              dropdownColor: isDark ? const Color(0xFF1E2630) : Colors.white,
              onChanged: (val) {
                setState(() {
                  _selectedCircle = val;
                });
              },
              items: [
                DropdownMenuItem<dynamic>(
                  value: null,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_balance_wallet,
                        size: 20,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "${AppLocalizations.of(context)?.translate('common.personal_account') ?? "Personal Balance"} (₹${_balance?.toStringAsFixed(2) ?? '0.00'})",
                          style: GoogleFonts.notoSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                ..._joinedCircles.map((circle) {
                  final limit = circle['monthly_limit'];
                  final spend = circle['current_monthly_spend'];
                  final remaining = limit - spend;
                  return DropdownMenuItem<dynamic>(
                    value: circle,
                    child: Row(
                      children: [
                        const Icon(Icons.group, size: 20, color: Colors.orange),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Expanded(
                              child: Text(
                                AppLocalizations.of(context)?.translate(
                                      'amount.primary_circle_label',
                                      arguments: {
                                        'name': circle['primary_user_name'],
                                      },
                                    ) ??
                                    "${circle['primary_user_name']}'s Circle",
                                style: GoogleFonts.notoSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              "${AppLocalizations.of(context)?.translate('amount.limit_left_label', arguments: {'amount': remaining.toStringAsFixed(0)}) ?? "Limit Left"}: ₹${remaining.toStringAsFixed(0)}",
                              style: GoogleFonts.notoSans(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Exact Logic from risk_analysis_screen.dart duplicated for Split UI ---
  List<Widget> _buildRiskFactors(bool useDarkTheme, Color textColor) {
    if (_isRisk) {
      if (_specificRiskCode != null) {
        return _buildDynamicRiskList(_specificRiskCode!, textColor);
      } else {
        return [
          _buildRiskItem(
            AppLocalizations.of(context)?.translate('risk.unusual_activity') ??
                "Unusual activity detected.",
            Icons.warning_amber_rounded,
            false,
            textColor,
          ),
          const SizedBox(height: 16),
          _buildRiskItem(
            _riskExplanation.isNotEmpty
                ? _riskExplanation
                : (AppLocalizations.of(
                        context,
                      )?.translate('risk.review_before') ??
                      "Please review before proceeding."),
            Icons.shield_outlined,
            false,
            textColor,
          ),
        ];
      }
    } else {
      return [
        _buildRiskItem(
          AppLocalizations.of(context)?.translate('risk.identity_verified') ??
              "Receiver identity has been successfully verified by ZaferPay.",
          Icons.verified_rounded,
          true,
          textColor,
        ),
        const SizedBox(height: 16),
        _buildRiskItem(
          AppLocalizations.of(context)?.translate('risk.within_patterns') ??
              "Transaction amount is within your normal spending patterns.",
          Icons.check_circle_outline_rounded,
          true,
          textColor,
        ),
      ];
    }
  }

  String _getRiskMessage(String code) {
    // Map fraud codes to translation keys
    final Map<String, String> codeToKey = {
      'F1_VELOCITY': 'risk.f1_velocity_msg',
      'F19_SESSION': 'risk.f19_session_msg',
      'F25_CONSECUTIVE': 'risk.f25_consecutive_msg',
      'F39_NIGHT': 'risk.f39_night_msg',
      'F41_FREQUENCY': 'risk.f41_frequency_msg',
      'F48_CONCURRENT': 'risk.f48_concurrent_msg',
      'F49_FAILED': 'risk.f49_failed_msg',
      'F2_CIRCULAR': 'risk.f2_circular_msg',
      'F54_ROUND_TRIP': 'risk.f54_round_trip_msg',
      'F4_FIRST_TX': 'risk.f4_first_tx_msg',
      'F22_DORMANT': 'risk.f22_dormant_msg',
      'F40_NEW_RECEIVER': 'risk.f40_new_receiver_msg',
      'F5_EXTREME': 'risk.f5_extreme_msg',
      'F5_VERY_HIGH': 'risk.f5_very_high_msg',
      'F5_HIGH': 'risk.f5_high_msg',
      'F5_MEDIUM': 'risk.f5_high_msg',
      'F5_SPIKE': 'risk.f5_high_msg',
      'F8_STRANGER': 'risk.f8_stranger_msg',
      'F21_DRIFT': 'risk.f21_drift_msg',
      'F6': 'risk.f6_merchant_msg',
      'F7': 'risk.f7_unverified_msg',
      'F30_MERCHANT_LOCATION': 'risk.f30_merchant_location_msg',
      'F47_MCC_SWITCHING': 'risk.f47_mcc_switching_msg',
      'F56_FAKE_MERCHANT': 'risk.f56_fake_merchant_msg',
      'F57_MCC_MISMATCH': 'risk.f57_mcc_mismatch_msg',
      'F9_UNUSUAL_TIME': 'risk.f9_unusual_time_msg',
      'F20_TIME_PATTERN': 'risk.f20_time_pattern_msg',
      'F33_HOLIDAY': 'risk.f33_holiday_msg',
      'F10_SPLIT': 'risk.f10_split_msg',
      'F31_MICRO_BURST': 'risk.f31_micro_burst_msg',
      'F35_SAME_AMOUNT': 'risk.f35_same_amount_msg',
      'F53_SMURFING': 'risk.f53_smurfing_msg',
      'F11_EXTREME_DAILY': 'risk.f11_extreme_daily_msg',
      'F11_HIGH_DAILY': 'risk.f11_high_daily_msg',
      'F11_DAILY': 'risk.f11_daily_msg',
      'F18_DAILY_LIMIT': 'risk.f18_daily_limit_msg',
      'F30_EXTREME_WEEKLY': 'risk.f30_extreme_weekly_msg',
      'F30_HIGH_WEEKLY': 'risk.f30_high_weekly_msg',
      'F30_WEEKLY': 'risk.f30_weekly_msg',
      'F12_STRANGER': 'risk.f12_stranger_msg',
      'F13_NEW_RECEIVER_BURST': 'risk.f13_new_receiver_burst_msg',
      'F23_BURST_TO_NEW': 'risk.f23_burst_to_new_msg',
      'F14_ROUND_AMOUNT': 'risk.f14_round_amount_msg',
      'F28_FIRST_TIME_AMOUNT': 'risk.f28_first_time_amount_msg',
      'F36_PROGRESSIVE': 'risk.f36_progressive_msg',
      'F37_COUNTDOWN': 'risk.f37_countdown_msg',
      'F38_EVEN_AMOUNT': 'risk.f38_even_amount_msg',
      'F46_WHOLE_NUMBER': 'risk.f46_whole_number_msg',
      'F15_EXTREME': 'risk.f15_extreme_drain_msg',
      'F15_RAPID': 'risk.f15_drain_msg',
      'F15_MODERATE': 'risk.f15_drain_msg',
      'F15_DRAIN': 'risk.f15_drain_msg',
      'F26_BALANCE_DRAIN': 'risk.f26_balance_drain_msg',
      'F42_SPENDING_EXCEEDS': 'risk.f42_spending_exceeds_msg',
      'F16_DEVICE_CHANGE': 'risk.f16_device_change_msg',
      'F43_NEW_DEVICE': 'risk.f43_new_device_msg',
      'F44_MULTIPLE_IPS': 'risk.f44_multiple_ips_msg',
      'F45_INSTANT': 'risk.f45_instant_msg',
      'F17_RECEIVER_HIGH_INFLOW': 'risk.f17_receiver_inflow_msg',
      'F27_RECIPIENT_CLUSTER': 'risk.f27_recipient_cluster_msg',
      'F34_TOO_MANY_UNIQUE': 'risk.f34_too_many_unique_msg',
      'F24_CHAIN': 'risk.f24_chain_msg',
      'F50_STAR_PATTERN': 'risk.f50_star_pattern_msg',
      'F51_FUNNEL_PATTERN': 'risk.f51_funnel_pattern_msg',
      'F52_LAYERING': 'risk.f52_layering_msg',
      'F29_GEO_VELOCITY': 'risk.f29_geo_velocity_msg',
      'F29_LOCATION_CHANGE': 'risk.f29_location_change_msg',
      'F32_WEEKEND': 'risk.f32_weekend_msg',
      'F55_SCREEN_SHARING': 'risk.f55_screen_sharing_msg',
      'F58_QR_PERSONAL': 'risk.f58_qr_personal_msg',
      'F59_DEEP_LINK': 'risk.f59_deep_link_msg',
      'F60_PANIC': 'risk.f60_panic_msg',
      'F61_INVESTMENT_SCAM': 'risk.f61_investment_scam_msg',
      'AI_DETECTED': 'risk.ai_detected_msg',
      'SELF_TRANSFER': 'risk.self_transfer_msg',
    };

    // Find matching key
    for (var entry in codeToKey.entries) {
      if (code.contains(entry.key)) {
        return AppLocalizations.of(context)?.translate(entry.value) ?? "";
      }
    }

    // Default fallback
    return AppLocalizations.of(context)?.translate('risk.spike_risk') ?? 
           "This payment is significantly higher than your usual spending.";
  }

  List<Widget> _buildDynamicRiskList(String code, Color textColor) {
    List<Widget> items = [];
    List<Map<String, dynamic>> allReasons = [];

    // Extract behavioral metrics from fraud features
    final trustDepth = _fraudFeatures?['trust_depth'] ?? 0;

    // ═══════════════════════════════════════════════════════════════════════
    // GET PRIMARY REASON WITH TRANSLATION
    // ═══════════════════════════════════════════════════════════════════════
    
    String primaryReason = _getRiskMessage(code);
    IconData primaryIcon = Icons.warning_amber_rounded;
    int primaryPriority = 2; // Default priority
    
    // Determine icon and priority based on code patterns
    if (code.contains("F1") || code.contains("F48") || code.contains("F49") || 
        code.contains("F2") || code.contains("F54") || code.contains("F4") ||
        code.contains("F40") || code.contains("F5") || code.contains("F8") ||
        code.contains("F21") || code.contains("F7") || code.contains("F30_MERCHANT") ||
        code.contains("F56") || code.contains("F57") || code.contains("F10") ||
        code.contains("F31") || code.contains("F53") || code.contains("F11_EXTREME") ||
        code.contains("F11_HIGH") || code.contains("F18") || code.contains("F30_EXTREME") ||
        code.contains("F30_HIGH") || code.contains("F13") || code.contains("F23") ||
        code.contains("F36") || code.contains("F15") || code.contains("F26") ||
        code.contains("F42") || code.contains("F16") || code.contains("F44") ||
        code.contains("F24") || code.contains("F50") || code.contains("F51") ||
        code.contains("F52") || code.contains("F29_GEO") || code.contains("F55") ||
        code.contains("F60") || code.contains("F61") || code.contains("AI_DETECTED") ||
        code.contains("SELF_TRANSFER")) {
      primaryPriority = 1; // Critical
    } else if (code.contains("F19") || code.contains("F25") || code.contains("F39") ||
               code.contains("F41") || code.contains("F22") || code.contains("F6") ||
               code.contains("F47") || code.contains("F9") || code.contains("F35") ||
               code.contains("F11_DAILY") || code.contains("F30_WEEKLY") || code.contains("F12") ||
               code.contains("F37") || code.contains("F43") || code.contains("F45") ||
               code.contains("F17") || code.contains("F27") || code.contains("F34") ||
               code.contains("F29_LOCATION") || code.contains("F58") || code.contains("F59")) {
      primaryPriority = 2; // High
    } else {
      primaryPriority = 3; // Medium
    }

    // Set icon based on code type
    if (code.contains("VELOCITY") || code.contains("F1")) primaryIcon = Icons.speed_rounded;
    else if (code.contains("SESSION") || code.contains("F19")) primaryIcon = Icons.access_time_rounded;
    else if (code.contains("CONSECUTIVE") || code.contains("F25")) primaryIcon = Icons.repeat_rounded;
    else if (code.contains("NIGHT") || code.contains("F39")) primaryIcon = Icons.nightlight_round;
    else if (code.contains("FREQUENCY") || code.contains("F41")) primaryIcon = Icons.repeat_rounded;
    else if (code.contains("CONCURRENT") || code.contains("F48")) primaryIcon = Icons.warning_rounded;
    else if (code.contains("FAILED") || code.contains("F49")) primaryIcon = Icons.error_outline_rounded;
    else if (code.contains("CIRCULAR") || code.contains("F2")) primaryIcon = Icons.loop_rounded;
    else if (code.contains("ROUND_TRIP") || code.contains("F54")) primaryIcon = Icons.swap_horiz_rounded;
    else if (code.contains("FIRST_TX") || code.contains("F4")) primaryIcon = Icons.new_releases_rounded;
    else if (code.contains("DORMANT") || code.contains("F22")) primaryIcon = Icons.person_off_rounded;
    else if (code.contains("NEW_RECEIVER") || code.contains("F40")) primaryIcon = Icons.person_add_rounded;
    else if (code.contains("SPIKE") || code.contains("F5") || code.contains("F8") || code.contains("F21")) primaryIcon = Icons.trending_up_rounded;
    else if (code.contains("MERCHANT") && code.contains("F6")) primaryIcon = Icons.store_rounded;
    else if (code.contains("F7")) primaryIcon = Icons.store_mall_directory_rounded;
    else if (code.contains("MERCHANT_LOCATION") || code.contains("F30_MERCHANT")) primaryIcon = Icons.location_off_rounded;
    else if (code.contains("MCC_SWITCHING") || code.contains("F47")) primaryIcon = Icons.category_rounded;
    else if (code.contains("FAKE_MERCHANT") || code.contains("F56")) primaryIcon = Icons.report_problem_rounded;
    else if (code.contains("MCC_MISMATCH") || code.contains("F57")) primaryIcon = Icons.qr_code_scanner_rounded;
    else if (code.contains("UNUSUAL_TIME") || code.contains("F9")) primaryIcon = Icons.access_time_rounded;
    else if (code.contains("TIME_PATTERN") || code.contains("F20")) primaryIcon = Icons.schedule_rounded;
    else if (code.contains("HOLIDAY") || code.contains("F33")) primaryIcon = Icons.celebration_rounded;
    else if (code.contains("SPLIT") || code.contains("F10")) primaryIcon = Icons.call_split_rounded;
    else if (code.contains("MICRO_BURST") || code.contains("F31")) primaryIcon = Icons.grain_rounded;
    else if (code.contains("SAME_AMOUNT") || code.contains("F35")) primaryIcon = Icons.content_copy_rounded;
    else if (code.contains("SMURFING") || code.contains("F53")) primaryIcon = Icons.scatter_plot_rounded;
    else if (code.contains("DAILY") && (code.contains("F11") || code.contains("F18"))) primaryIcon = code.contains("F18") ? Icons.block_rounded : Icons.calendar_today_rounded;
    else if (code.contains("WEEKLY") || code.contains("F30")) primaryIcon = Icons.date_range_rounded;
    else if (code.contains("STRANGER") || code.contains("F12")) primaryIcon = Icons.handshake_outlined;
    else if (code.contains("BURST") && (code.contains("F13") || code.contains("F23"))) primaryIcon = code.contains("F13") ? Icons.people_outline_rounded : Icons.person_add_alt_rounded;
    else if (code.contains("ROUND_AMOUNT") || code.contains("F14")) primaryIcon = Icons.looks_rounded;
    else if (code.contains("FIRST_TIME_AMOUNT") || code.contains("F28")) primaryIcon = Icons.fiber_new_rounded;
    else if (code.contains("PROGRESSIVE") || code.contains("F36")) primaryIcon = Icons.trending_up_rounded;
    else if (code.contains("COUNTDOWN") || code.contains("F37")) primaryIcon = Icons.trending_down_rounded;
    else if (code.contains("EVEN_AMOUNT") || code.contains("F38")) primaryIcon = Icons.filter_9_plus_rounded;
    else if (code.contains("WHOLE_NUMBER") || code.contains("F46")) primaryIcon = Icons.calculate_rounded;
    else if (code.contains("DRAIN") || code.contains("F15") || code.contains("F26")) primaryIcon = code.contains("F26") ? Icons.account_balance_wallet_rounded : Icons.trending_down_rounded;
    else if (code.contains("SPENDING_EXCEEDS") || code.contains("F42")) primaryIcon = Icons.speed_rounded;
    else if (code.contains("DEVICE_CHANGE") || code.contains("F16")) primaryIcon = Icons.phonelink_off_rounded;
    else if (code.contains("NEW_DEVICE") || code.contains("F43")) primaryIcon = Icons.phone_android_rounded;
    else if (code.contains("MULTIPLE_IPS") || code.contains("F44")) primaryIcon = Icons.location_searching_rounded;
    else if (code.contains("INSTANT") || code.contains("F45")) primaryIcon = Icons.flash_on_rounded;
    else if (code.contains("RECEIVER_HIGH_INFLOW") || code.contains("F17")) primaryIcon = Icons.call_received_rounded;
    else if (code.contains("RECIPIENT_CLUSTER") || code.contains("F27")) primaryIcon = Icons.hub_rounded;
    else if (code.contains("TOO_MANY_UNIQUE") || code.contains("F34")) primaryIcon = Icons.groups_rounded;
    else if (code.contains("CHAIN") || code.contains("F24")) primaryIcon = Icons.link_rounded;
    else if (code.contains("STAR_PATTERN") || code.contains("F50")) primaryIcon = Icons.star_border_rounded;
    else if (code.contains("FUNNEL_PATTERN") || code.contains("F51")) primaryIcon = Icons.filter_alt_rounded;
    else if (code.contains("LAYERING") || code.contains("F52")) primaryIcon = Icons.account_tree_rounded;
    else if (code.contains("GEO") || code.contains("F29")) primaryIcon = code.contains("GEO_VELOCITY") ? Icons.location_off_rounded : Icons.my_location_rounded;
    else if (code.contains("WEEKEND") || code.contains("F32")) primaryIcon = Icons.weekend_rounded;
    else if (code.contains("SCREEN_SHARING") || code.contains("F55")) primaryIcon = Icons.screen_share_rounded;
    else if (code.contains("QR_PERSONAL") || code.contains("F58")) primaryIcon = Icons.qr_code_2_rounded;
    else if (code.contains("DEEP_LINK") || code.contains("F59")) primaryIcon = Icons.link_rounded;
    else if (code.contains("PANIC") || code.contains("F60")) primaryIcon = Icons.timer_rounded;
    else if (code.contains("INVESTMENT_SCAM") || code.contains("F61")) primaryIcon = Icons.report_rounded;
    else if (code.contains("AI_DETECTED")) primaryIcon = Icons.psychology_rounded;
    else if (code.contains("SELF_TRANSFER")) primaryIcon = Icons.loop_rounded;

    // Add primary reason to list
    allReasons.add({
      'reason': primaryReason,
      'icon': primaryIcon,
      'priority': primaryPriority,
    });

    // ═══════════════════════════════════════════════════════════════════════
    // ADD SECONDARY REASONS (from fraud features)
    // ═══════════════════════════════════════════════════════════════════════
    
    // Low trust score / Stranger
    if (_fraudFeatures != null && trustDepth == 0) {
      allReasons.add({
        'reason': AppLocalizations.of(context)?.translate('risk.low_trust') ?? "Low trust score with this receiver.",
        'icon': Icons.handshake_outlined,
        'priority': 2,
      });
    }

    // First time payment
    if (_fraudFeatures != null && (_fraudFeatures!['is_new_receiver'] ?? 0) == 1) {
      allReasons.add({
        'reason': AppLocalizations.of(context)?.translate('risk.never_paid_before') ?? "You have never paid this person before.",
        'icon': Icons.person_outline_rounded,
        'priority': 2,
      });
    }

    // Add generic secondary reasons if we don't have enough specific ones
    if (allReasons.length < 2) {
      // Add amount-related reason if it's a spike
      if (code.contains("F5") || code.contains("SPIKE") || code.contains("F8")) {
        allReasons.add({
          'reason': AppLocalizations.of(context)?.translate('risk.amount_higher_avg') ?? "Amount is much higher than your average.",
          'icon': Icons.trending_up_rounded,
          'priority': 2,
        });
      }
      
      // Add verification reminder
      if (allReasons.length < 3) {
        allReasons.add({
          'reason': AppLocalizations.of(context)?.translate('risk.rec_call_confirm') ?? "Call the person and confirm their identity before proceeding.",
          'icon': Icons.phone_rounded,
          'priority': 3,
        });
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SORT BY PRIORITY AND TAKE TOP 3
    // ═══════════════════════════════════════════════════════════════════════
    
    // Sort by priority (1 = highest priority)
    allReasons.sort((a, b) => a['priority'].compareTo(b['priority']));
    
    // Take only top 3 reasons
    final top3Reasons = allReasons.take(3).toList();
    
    // Build widgets for top 3 reasons
    for (int i = 0; i < top3Reasons.length; i++) {
      if (i > 0) {
        items.add(const SizedBox(height: 16));
      }
      items.add(_buildRiskItem(
        top3Reasons[i]['reason'],
        top3Reasons[i]['icon'],
        false,
        textColor,
      ));
    }

    return items;
  }

  Widget _buildRiskItem(
    String desc,
    IconData icon,
    bool isSafe,
    Color textColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: isSafe
              ? const Color(0xFF4CAF50)
              : (_isHighRisk
                    ? const Color(0xFFD32F2F)
                    : const Color(0xFFFFA000)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            desc,
            style: TextStyle(
              fontSize: 14,
              color: textColor.withValues(alpha: 0.9),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class MaxValueTextInputFormatter extends TextInputFormatter {
  final double maxValue;
  final VoidCallback? onMaxValueExceeded;

  MaxValueTextInputFormatter(this.maxValue, {this.onMaxValueExceeded});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Block leading '0' or '.' to enforce amount >= 1
    if (newValue.text.startsWith('0') || newValue.text.startsWith('.')) {
      return oldValue;
    }

    final newDouble = double.tryParse(newValue.text);
    if (newDouble == null) {
      return oldValue; // Revert if not a number
    }

    if (newDouble > maxValue) {
      onMaxValueExceeded?.call(); // Notify callback
      return oldValue; // Revert if > maxValue
    }

    return newValue; // Allow
  }
}
