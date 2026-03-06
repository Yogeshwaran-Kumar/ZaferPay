import 'dart:async';
import 'utils.dart';
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
import 'fraud_scanning_animation.dart';

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

  // Fixed QR Amount state
  bool _isLockedAmount = false;

  // Phone call detection
  bool _isOnCall = false;
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
    await CallStateService.instance.init();
    if (!mounted) return;
    setState(() {
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

    // Check custom spending limit
    bool spendingLimitExceeded = false;
    if (amount != null && _spendingLimit != null && _spendingLimit! > 0) {
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
        ? 'daily'
        : _spendingLimitPeriod == 7
        ? 'weekly'
        : _spendingLimitPeriod == 14
        ? 'bi-weekly'
        : _spendingLimitPeriod == 30
        ? 'monthly'
        : '$_spendingLimitPeriod-day';
    final limit = _spendingLimit ?? 0;
    final remaining = (limit - _spentInPeriod).clamp(0.0, double.infinity);
    return 'Your $periodLabel limit is ₹${limit.toStringAsFixed(0)}. '
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

    // Guard: block payment during active phone call
    if (_isOnCall) {
      _showOnCallDialog();
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount < 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Minimum amount is ₹1")));
      return;
    }

    // Balance Validation (skip for UPI Circle payments — parent's balance is used)
    if (_selectedCircle == null && _balance != null && amount > _balance!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Insufficient balance"),
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
                : 'Transaction blocked. This account has been flagged for fraudulent activity.',
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
      if (mounted) {
        setState(() {
          _riskScore = 'SAFE';
          _isRisk = false;
          _riskExplanation =
              'Analysis unavailable - proceeding with standard checks';
          _isAnalyzingRisk = false;
          _hasAnalyzedRisk = true;

          // AUTO-PROCEED: Proceed if analysis fails (defaults to SAFE)
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted && _hasAnalyzedRisk && !_isAnalyzingRisk) {
              _proceedToPin();
            }
          });
        });
      }
    }
  }

  String _getDefaultExplanation() {
    switch (_riskScore) {
      case 'HIGH':
        return 'High risk transaction detected. Please review carefully.';
      case 'WARN':
        return 'Unusual pattern detected. Proceed with caution.';
      default:
        return 'Transaction appears safe.';
    }
  }

  String? _getHumanReadableExplanation(String? code) {
    if (code == null) return null;

    if (code.contains("F18_DAILY")) {
      return "You've exceeded the daily transfer limit for this receiver.";
    }
    if (code.contains("F1_VELOCITY")) {
      return "Too many transactions in a short time. Please wait a moment.";
    }
    if (code.contains("AI_DETECTED")) {
      return "Our AI detected a highly unusual pattern compared to your history.";
    }
    if (code.contains("F29_GEO")) {
      return "Impossible travel detected. Your location changed too fast.";
    }
    if (code.contains("F15_RAPID_DRAIN")) {
      return "Unusual rapid spending detected from your account.";
    }
    if (code.contains("NEW_RECEIVER")) {
      return "You are sending money to a new person for the first time.";
    }
    if (code.contains("SELF_TRANSFER")) {
      return "You cannot send money to your own UPI ID.";
    }
    if (code.contains("F52_LAYERING")) {
      return "Complex money flow pattern detected (Layering Risk).";
    }
    if (code.contains("F30_WEEKLY")) {
      return "Weekly spending limit exceeded for this receiver.";
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
        'skipFraudCheck': _isRisk, // Already checked
        'acknowledgedRisk': _isRisk ? _riskScore : null,
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
                  Icons.phone_in_talk_rounded,
                  color: Colors.red,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Payment Blocked During Call',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'For your security, UPI payments cannot be made while you are on a phone call.\n\nPlease end the call and try again.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
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
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'I Understand',
                    style: GoogleFonts.outfit(
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
    String title = "Payment Successful";
    Color bgColor = isDark ? const Color(0xFF1E2630) : Colors.white;

    if (status == "BLOCKED") {
      color = const Color(0xFFE53935); // Red 600
      icon = Icons.block_rounded;
      title = "Transaction Blocked";
    } else if (status == "FAILED") {
      color = const Color(0xFFE53935);
      icon = Icons.error_rounded;
      title = "Payment Failed";
    } else if (risk == "WARN") {
      color = const Color(0xFFFB8C00); // Orange 600
      icon = Icons.warning_rounded;
      title = "Warning Detected";
    } else if (status == "SECURITY_RISK") {
      // PHASE 2 ALERT: Integrity/HMAC Failure
      color = const Color(0xFFD32F2F); // Darker Red
      icon = Icons.security_rounded;
      title = "Security Alert";
    } else if (status == "FRAUD_BLOCKED") {
      // PHASE 1 ALERT: AI Block
      color = const Color(0xFFC62828); // Sharp Red
      icon = Icons.gpp_bad_rounded;
      title = "Fraud Detected";
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
                style: GoogleFonts.outfit(
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
                  style: GoogleFonts.outfit(
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
                            "To",
                            style: GoogleFonts.outfit(
                              color: isDark ? Colors.grey[400] : Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _contactName ?? _bankingName ?? _receiverUpi,
                            style: GoogleFonts.outfit(
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
                            "Transaction ID",
                            style: GoogleFonts.outfit(
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
                            style: GoogleFonts.outfit(
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
                  result['custom_message'] ??
                      "Your transaction could not be completed.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
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
                    "Done",
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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
                        _isSpendingLimitExceeded)
                    ? null
                    : _onPayPressed,
                backgroundColor:
                    (_isSelfTransfer ||
                        _isAmountTooHigh ||
                        _isQrLimitExceeded ||
                        _isSpendingLimitExceeded)
                    ? (isDark ? Colors.grey[800] : Colors.grey[300])
                    : const Color(0xFF00B9F1), // Brand Cyan/Blue
                elevation:
                    (_isSelfTransfer ||
                        _isAmountTooHigh ||
                        _isQrLimitExceeded ||
                        _isSpendingLimitExceeded)
                    ? 0
                    : 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                label: Text(
                  _isSelfTransfer
                      ? "Cannot transfer to self"
                      : _isQrLimitExceeded
                      ? "Exceeds ₹2,000 Limit"
                      : _isSpendingLimitExceeded
                      ? "Spending Limit Exceeded"
                      : "Proceed",
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color:
                        (_isSelfTransfer ||
                            _isAmountTooHigh ||
                            _isQrLimitExceeded ||
                            _isSpendingLimitExceeded)
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
                          _isSpendingLimitExceeded)
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
                              style: GoogleFonts.outfit(
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
                                    ? "Paying request to "
                                    : "Paying ",
                                style: GoogleFonts.outfit(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  displayContactName,
                                  style: GoogleFonts.outfit(
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
                                    "Banking name: ${displayBankingName ?? (_rawMcc != null ? 'Verified Merchant' : 'Verified User')}",
                                    style: GoogleFonts.outfit(
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
                                  "Banking name: Unknown",
                                  style: GoogleFonts.outfit(
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
                            style: GoogleFonts.outfit(
                              color: secondaryTextColor,
                              fontSize: 13,
                            ),
                          ),

                          // General QR Awareness Warning
                          if (_paymentSource != null &&
                              _paymentSource!.startsWith('qr_') &&
                              !_isAnalyzingRisk &&
                              !_hasAnalyzedRisk)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32.0,
                                vertical: 12.0,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.warning_rounded,
                                      color: Colors.orange,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        "Attention: QR codes are ONLY for sending money. Never scan a QR code to receive money.",
                                        style: GoogleFonts.outfit(
                                          color: isDark
                                              ? const Color.fromARGB(
                                                  255,
                                                  246,
                                                  31,
                                                  2,
                                                )
                                              : const Color.fromARGB(
                                                  255,
                                                  255,
                                                  1,
                                                  1,
                                                ),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // QR Limit Warning
                          if (_isQrLimitExceeded &&
                              !_isAnalyzingRisk &&
                              !_hasAnalyzedRisk)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32.0,
                                vertical: 12.0,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      color: Color.fromARGB(255, 253, 2, 2),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        "You not able to send more than 2000 rupees by uploading QR code as a alte",
                                        style: GoogleFonts.outfit(
                                          color: const Color.fromARGB(
                                            255,
                                            255,
                                            2,
                                            2,
                                          ),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Self-transfer warning
                          if (_isSelfTransfer &&
                              !_isAnalyzingRisk &&
                              !_hasAnalyzedRisk)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                "Cannot transfer to self",
                                style: GoogleFonts.outfit(
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
                                      'Payment Request: ${_requestReason != null ? (_requestReason == 'wrongly_sent'
                                                ? 'Wrongly Sent'
                                                : _requestReason == 'wrong_amount'
                                                ? 'Wrong Amount'
                                                : 'Other') : ''}',
                                      style: GoogleFonts.outfit(
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

                    SizedBox(
                      height: (_isAnalyzingRisk || _hasAnalyzedRisk) ? 16 : 32,
                    ),

                    // 2. Amount Input Section (Middle - Expanded)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                              style: GoogleFonts.outfit(
                                color: textColor,
                                fontSize: (_isAnalyzingRisk || _hasAnalyzedRisk)
                                    ? 48
                                    : 64, // Shrink text
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                filled: false,
                                prefixText: "₹ ",
                                prefixStyle: GoogleFonts.outfit(
                                  color: textColor,
                                  fontSize:
                                      (_isAnalyzingRisk || _hasAnalyzedRisk)
                                      ? 48
                                      : 64,
                                  fontWeight: FontWeight.w500,
                                ),
                                hintText: "0",
                                hintStyle: GoogleFonts.outfit(
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
                                "Max limit: ₹5,00,000",
                                style: GoogleFonts.outfit(
                                  color: Colors.red[300],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                          // Spending Limit Exceeded Warning
                          if (_isSpendingLimitExceeded &&
                              !_isAnalyzingRisk &&
                              !_hasAnalyzedRisk)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
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
                                    color: Colors.red.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                          'Spending Limit Exceeded',
                                          style: GoogleFonts.outfit(
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
                                      style: GoogleFonts.outfit(
                                        color: isDark
                                            ? Colors.red[300]
                                            : Colors.red[700],
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          SizedBox(
                            height: (_isAnalyzingRisk || _hasAnalyzedRisk)
                                ? 12
                                : 24,
                          ),

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
                                  style: GoogleFonts.outfit(
                                    color: textColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: InputDecoration(
                                    filled: false,
                                    isDense: true,
                                    hintText: "Add note",
                                    hintStyle: GoogleFonts.outfit(
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
                              style: GoogleFonts.outfit(
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
                              "Powered by ZaferPay",
                              style: GoogleFonts.outfit(
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

  Widget _buildScanningState(Color textColor) {
    final screenHeight = MediaQuery.of(context).size.height;
    final animSize = (screenHeight * 0.3).clamp(180.0, 280.0);

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          FraudScanningAnimation(
            isDark: Theme.of(context).brightness == Brightness.dark,
            size: animSize,
          ),
          const SizedBox(height: 24),
          Text(
            "Analyzing Transaction...",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Checking recipient pattern...",
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
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
                  ? "Critical Fraud Risk!"
                  : (_isWarn
                        ? "Security Warning"
                        : "Transaction Verified Safe"),
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
                    _isRisk ? "Proceed with Caution" : "Proceed",
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
                  child: const Text(
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
            "CHOOSE PAYMENT SOURCE",
            style: GoogleFonts.outfit(
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
                      Text(
                        "Personal Balance (₹${_balance?.toStringAsFixed(2) ?? '0.00'})",
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
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
                            Text(
                              "${circle['primary_user_name']}'s Circle",
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              "Limit Left: ₹${remaining.toStringAsFixed(0)}",
                              style: GoogleFonts.outfit(
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
            "Unusual activity detected.",
            Icons.warning_amber_rounded,
            false,
            textColor,
          ),
          const SizedBox(height: 16),
          _buildRiskItem(
            _riskExplanation.isNotEmpty
                ? _riskExplanation
                : "Please review before proceeding.",
            Icons.shield_outlined,
            false,
            textColor,
          ),
        ];
      }
    } else {
      return [
        _buildRiskItem(
          "Receiver identity has been successfully verified by ZaferPay.",
          Icons.verified_rounded,
          true,
          textColor,
        ),
        const SizedBox(height: 16),
        _buildRiskItem(
          "Transaction amount is within your normal spending patterns.",
          Icons.check_circle_outline_rounded,
          true,
          textColor,
        ),
      ];
    }
  }

  List<Widget> _buildDynamicRiskList(String code, Color textColor) {
    List<Widget> items = [];
    int itemsCount = 0;

    String desc = "Potentially unsafe transaction.";
    IconData icon = Icons.warning_amber_rounded;

    if (code.contains("F18") || code.contains("DAILY_LIMIT")) {
      desc = "Daily limit exceeded for this receiver type.";
      icon = Icons.block_flipped;
    } else if (code.contains("F1") || code.contains("VELOCITY")) {
      desc = "Sending too frequently. Please slow down.";
      icon = Icons.speed_rounded;
    } else if (code.contains("AI_DETECTED")) {
      desc = "AI Brain detected highly unusual behavior.";
      icon = Icons.psychology_rounded;
    } else if (code.contains("GEO") || code.contains("LOCATION")) {
      desc = "Impossible travel detected. Location mismatch.";
      icon = Icons.location_off_rounded;
    } else if (code.contains("F40") || code.contains("NEW_RECEIVER")) {
      desc = "High value transfer to a brand new receiver.";
      icon = Icons.person_add_disabled_rounded;
    } else if (code.contains("F52") || code.contains("LAYERING")) {
      desc = "Complex money flow pattern detected (Layering Risk).";
      icon = Icons.account_tree_rounded;
    } else if (code.contains("F5") || code.contains("SPIKE")) {
      desc = "This payment is significantly higher than your usual spending.";
      icon = Icons.trending_up_rounded;
    } else if (code.contains("SELF_TRANSFER")) {
      desc = "Self-transfer is not allowed.";
      icon = Icons.loop_rounded;
    } else {
      desc = _riskExplanation;
    }

    items.add(_buildRiskItem(desc, icon, false, textColor));
    itemsCount++;

    if (_fraudFeatures != null) {
      if (itemsCount < 3 &&
          (_fraudFeatures!['trust_score'] ?? 0) < 50 &&
          !code.contains("F18")) {
        items.add(const SizedBox(height: 16));
        items.add(
          _buildRiskItem(
            "Low trust score with this receiver.",
            Icons.handshake_outlined,
            false,
            textColor,
          ),
        );
        itemsCount++;
      }

      if (itemsCount < 3 &&
          (_fraudFeatures!['is_new_receiver'] ?? 0) == 1 &&
          !code.contains("NEW_RECEIVER")) {
        items.add(const SizedBox(height: 16));
        items.add(
          _buildRiskItem(
            "You have never paid this person before.",
            Icons.person_outline_rounded,
            false,
            textColor,
          ),
        );
        itemsCount++;
      }

      if (itemsCount < 3 && (_fraudFeatures!['amount_percentile'] ?? 0) > 90) {
        items.add(const SizedBox(height: 16));
        items.add(
          _buildRiskItem(
            "Amount is much higher than your average.",
            Icons.show_chart_rounded,
            false,
            textColor,
          ),
        );
        itemsCount++;
      }
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
