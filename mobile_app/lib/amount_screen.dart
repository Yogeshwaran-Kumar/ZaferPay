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

  // Request payment state
  bool _isRequestPayment = false;
  int? _paymentRequestId;
  String? _requestReason;

  // Phone call detection
  bool _isOnCall = false;
  StreamSubscription<bool>? _callStateSub;

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
      if (_isAmountTooHigh) {
        setState(() {
          _isAmountTooHigh = false;
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

    if (amount != null && amount > 500000) {
      if (!_isAmountTooHigh || _isQrLimitExceeded != qrLimitExceeded) {
        setState(() {
          _isAmountTooHigh = true;
          _isQrLimitExceeded = qrLimitExceeded;
        });
      }
    } else {
      if (_isAmountTooHigh || _isQrLimitExceeded != qrLimitExceeded) {
        setState(() {
          _isAmountTooHigh = false;
          _isQrLimitExceeded = qrLimitExceeded;
        });
      }
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
            : (prefill as num).toStringAsFixed(
                prefill == prefill.roundToDouble() ? 0 : 2,
              );
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
        });
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

  Future<void> _onPayPressed() async {
    if (_isSelfTransfer || _isAmountTooHigh || _isQrLimitExceeded) return;

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

    // Balance Validation
    if (_balance != null && amount > _balance!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Insufficient balance"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await Navigator.pushNamed(
      context,
      '/risk-analysis', // Go to Risk Analysis first
      arguments: {
        'receiverUpi': _receiverUpi,
        'amount': amount,
        'name': _bankingName ?? _contactName ?? _receiverUpi,
        'category': _category,
        'mcc': _rawMcc,
        'note': _noteController.text.trim(), // Pass Note
        'paymentRequestId': _paymentRequestId, // Pass Request ID
        'payment_source': _paymentSource, // Pass Telemetry
      },
    );

    if (result != null && result is Map<String, dynamic>) {
      // Mark request as paid if this was a request payment
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
    if (result.containsKey('detail')) {
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
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0, // Prevent color change on scroll
        leading: IconButton(
          icon: Icon(Icons.close, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      // Use floating action button for the 'Proceed' action to match screenshot style
      floatingActionButton: SizedBox(
        width: MediaQuery.of(context).size.width - 32,
        child: FloatingActionButton.extended(
          onPressed: (_isSelfTransfer || _isAmountTooHigh || _isQrLimitExceeded)
              ? null
              : _onPayPressed,
          backgroundColor:
              (_isSelfTransfer || _isAmountTooHigh || _isQrLimitExceeded)
              ? (isDark ? Colors.grey[800] : Colors.grey[300])
              : const Color(0xFF00B9F1), // Brand Cyan/Blue
          elevation: (_isSelfTransfer || _isAmountTooHigh || _isQrLimitExceeded)
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
                : "Proceed",
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: (_isSelfTransfer || _isAmountTooHigh || _isQrLimitExceeded)
                  ? Colors.grey[500]
                  : Colors.white,
            ),
          ),
          icon: Icon(
            (_isSelfTransfer || _isQrLimitExceeded)
                ? Icons.block_rounded
                : Icons.arrow_forward_rounded,
            color: (_isSelfTransfer || _isAmountTooHigh || _isQrLimitExceeded)
                ? Colors.grey[500]
                : Colors.white,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
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
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: getAvatarColor(displayContactName),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: GoogleFonts.outfit(
                          fontSize: 32,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // "Paying [Name]" header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isRequestPayment ? "Paying request to " : "Paying ",
                          style: GoogleFonts.outfit(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          displayContactName,
                          style: GoogleFonts.outfit(
                            color: textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
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
                          Text(
                            "Banking name: ${displayBankingName ?? 'Verified Merchant'}",
                            style: GoogleFonts.outfit(
                              color: secondaryTextColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified,
                            color: Colors.greenAccent, // Verified tick
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
                        _paymentSource!.startsWith('qr_'))
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
                                        ? const Color.fromARGB(255, 246, 31, 2)
                                        : const Color.fromARGB(255, 255, 1, 1),
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
                    if (_isQrLimitExceeded)
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
                                    color: const Color.fromARGB(255, 255, 2, 2),
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
                    if (_isSelfTransfer)
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
                    if (_isRequestPayment)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
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

              const SizedBox(height: 32),

              const SizedBox(height: 32),

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
                        autofocus: !_isRequestPayment,
                        readOnly: _isRequestPayment,
                        enabled: !_isRequestPayment,
                        inputFormatters: _isRequestPayment
                            ? []
                            : [
                                MaxValueTextInputFormatter(
                                  500000,
                                  onMaxValueExceeded: () {
                                    if (!_isAmountTooHigh) {
                                      setState(() => _isAmountTooHigh = true);
                                    }
                                  },
                                ),
                              ],
                        style: GoogleFonts.outfit(
                          color: textColor,
                          fontSize: 64, // Large text like screenshot
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          filled: false,
                          prefixText: "₹ ",
                          prefixStyle: GoogleFonts.outfit(
                            color: textColor,
                            fontSize: 64,
                            fontWeight: FontWeight.w500,
                          ),
                          hintText: "0",
                          hintStyle: GoogleFonts.outfit(
                            color: isDark ? Colors.grey[700] : Colors.grey[300],
                            fontSize: 64,
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),

                    // Amount Too High Warning
                    if (_isAmountTooHigh)
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

                    const SizedBox(height: 24),

                    // "Add note" Pill Button
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
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // 3. Powered By Info (Always Visible)
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
