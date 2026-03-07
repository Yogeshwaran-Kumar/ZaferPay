import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'processing_shield_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';
import 'mcc_helper.dart';
import 'services/call_state_service.dart';
import 'utils.dart';

class PaymentPinScreen extends StatefulWidget {
  final String receiverUpi;
  final double amount;
  final String receiverName;
  final String? category;
  final String? mcc;
  final String? note;
  final bool skipFraudCheck;
  final String? acknowledgedRisk;
  final int? requestId;
  final String? paymentSource;
  final bool isCirclePayment;
  final int? circleId;

  const PaymentPinScreen({
    super.key,
    required this.receiverUpi,
    required this.amount,
    required this.receiverName,
    this.category,
    this.mcc,
    this.note,
    this.skipFraudCheck = false,
    this.acknowledgedRisk,
    this.requestId,
    this.paymentSource,
    this.isCirclePayment = false,
    this.circleId,
  });

  @override
  State<PaymentPinScreen> createState() => _PaymentPinScreenState();
}

class _PaymentPinScreenState extends State<PaymentPinScreen> {
  String _enteredPin = '';
  final ApiService _api = ApiService();
  bool _isOnCall = false;
  bool _hasPhonePermission = true;
  StreamSubscription<bool>? _callStateSub;
  static const _securityChannel = MethodChannel(
    'com.company.zaferpay/security',
  );

  @override
  void initState() {
    super.initState();
    _secureScreen();
    _initCallDetection();
  }

  Future<void> _secureScreen() async {
    try {
      await _securityChannel.invokeMethod('secureScreen');
    } catch (_) {}
  }

  Future<void> _removeSecureScreen() async {
    try {
      await _securityChannel.invokeMethod('unsecureScreen');
    } catch (_) {}
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
    _removeSecureScreen();
    _callStateSub?.cancel();
    super.dispose();
  }

  void _onKeypadTap(String value) {
    setState(() {
      if (value == 'BACK') {
        if (_enteredPin.isNotEmpty) {
          _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        }
      } else {
        if (_enteredPin.length < 4) {
          _enteredPin += value;
        }
      }
    });
  }

  Future<void> _verifyPin() async {
    // Guard: block payment during active phone call (directly queries Android OS)
    final bool onCallNow = await CallStateService.isCurrentlyOnCall();

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

    // 1. FAST Local Check (Avoids navigation if PIN is definitely wrong)
    final pinStatus = await _api.verifyUpiPin(
      _enteredPin,
      isCirclePayment: widget.isCirclePayment,
    );

    if (pinStatus == PinVerificationStatus.lockedOut) {
      _handleLockedOut();
      return;
    }
    if (pinStatus == PinVerificationStatus.incorrect) {
      _handleIncorrectPin();
      return;
    }
    if (pinStatus == PinVerificationStatus.expired) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("PIN Expired"),
          content: const Text(
            "Security requirement: Your UPI PIN has expired (6 months old). Please update it to continue.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/change-upi-pin');
              },
              child: const Text("Update PIN"),
            ),
          ],
        ),
      );
      setState(() {
        _enteredPin = '';
      });
      return;
    }

    // 2. Navigate to Visual Security Flow (if PIN is Correct or Unknown)
    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProcessingShieldScreen(
          receiverUpi: widget.receiverUpi,
          amount: widget.amount,
          receiverName: widget.receiverName,
          pin: _enteredPin,
          category: widget.category,
          mcc: widget.mcc,
          note: widget.note,
          skipFraudCheck: widget.skipFraudCheck,
          acknowledgedRisk: widget.acknowledgedRisk,
          requestId: widget.requestId,
          paymentSource: widget.paymentSource,
          isCirclePayment: widget.isCirclePayment,
          circleId: widget.circleId,
          isOnCall: _isOnCall,
        ),
      ),
    );

    if (!mounted) return;

    // 3. Handle Server-Side Rejection (e.g. outdated local cache or unknown)
    if (result != null && result is Map) {
      if (result['status'] == 'FAILED' &&
          (result['detail'] == 'Incorrect PIN' ||
              result['detail'] == 'Session expired')) {
        _handleIncorrectPin();
      } else if (result['status'] == 'SUCCESS') {
        // Navigate to Conversation Screen on Success
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/conversation',
          ModalRoute.withName('/home'),
          arguments: {
            'upi': widget.receiverUpi,
            'name': widget.receiverName,
            'username': widget.receiverName,
          },
        );
      } else {
        if (mounted) Navigator.pop(context, result);
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
                'Security Block',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'For your safety, payments are disabled while you are on an active phone call to prevent potential scams.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
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
                    'Got it',
                    style: GoogleFonts.outfit(
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
        backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
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
                'Security Permission Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'To protect you from fraudulent calls, Safe Pay needs permission to detect if you are on a call during payments.\n\nPlease grant the Phone permission to proceed.',
                textAlign: TextAlign.center,
                style: TextStyle(
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
                    backgroundColor: const Color(0xFF1A237E),
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
                  child: const Text(
                    'Open Settings',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleIncorrectPin() async {
    if (!mounted) return;
    setState(() {
      _enteredPin = ''; // Reset PIN field
    });

    if (_api.failedAttempts == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect PIN. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    } else if (_api.failedAttempts == 2) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Security Warning"),
          content: const Text(
            "Warning: You have tried too many times. One more failed attempt will log you out.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("I Understand"),
            ),
          ],
        ),
      );
    } else if (_api.failedAttempts >= 3) {
      _handleLockedOut();
    }
  }

  Future<void> _handleLockedOut() async {
    // 3rd Strike -> Logout with Dialog
    showDialog(
      context: context,
      barrierDismissible: false, // User cannot close this
      builder: (ctx) => const AlertDialog(
        title: Text("Account Locked"),
        content: Text(
          "Too many incorrect attempts so your account has been logged out.",
        ),
      ),
    );

    // Wait for user to read it (shortened to less than 1 second)
    await Future.delayed(const Duration(milliseconds: 500));

    await _api.logout();

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    // Determine icon based on category (Merchant/Store vs Personal)
    // If category is present, it's likely a merchant.
    final bool isMerchant = MccHelper.isMerchant(widget.mcc);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top Section: Close Button
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  color: Theme.of(context).iconTheme.color,
                  size: 28,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // Top Section: Payment Details Card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? Theme.of(context).cardColor
                    : const Color(0xFFF8F5F2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            "Pay ",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          Text(
                            "₹${formatAmount(widget.amount)}",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(
                            "To ",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            widget.receiverName.toUpperCase(),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Right side icon
                  Row(
                    children: [
                      Text(
                        "₹ ",
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[400],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 12,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isMerchant
                              ? (isDark
                                    ? const Color(0xFF1B5E20)
                                    : const Color(0xFFE8F5E9))
                              : (isDark
                                    ? const Color(0xFF0D47A1)
                                    : const Color(0xFFE3F2FD)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isMerchant ? Icons.store : Icons.person,
                          color: isMerchant
                              ? (isDark ? Colors.green[200] : Colors.green)
                              : (isDark ? Colors.blue[200] : Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Expanded(flex: 1, child: SizedBox()),

            // PIN Entry Section
            Text(
              widget.isCirclePayment ? 'Enter App mPIN' : 'Enter your PIN',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final filled = index < _enteredPin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? (isDark ? Colors.white : Colors.black)
                        : Colors.transparent, // Solid black for filled
                    border: Border.all(
                      color: filled
                          ? (isDark ? Colors.white : Colors.black)
                          : Colors.grey.shade400,
                      width: 1.5,
                    ),
                  ),
                );
              }),
            ),

            const Expanded(flex: 2, child: SizedBox()),

            // Warning Message
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Color(0xFFD97706),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Never enter your UPI PIN to receive money',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            // Keypad Section
            Container(
              padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
              child: Column(
                children: [
                  _buildKeyRow(['1', '2', '3']),
                  const SizedBox(height: 16),
                  _buildKeyRow(['4', '5', '6']),
                  const SizedBox(height: 16),
                  _buildKeyRow(['7', '8', '9']),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // Backspace Button (Left)
                      Expanded(
                        child: InkWell(
                          onTap: () => _onKeypadTap('BACK'),
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey[800]
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.backspace_outlined,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // '0' Key (Center)
                      Expanded(
                        child: InkWell(
                          onTap: () => _onKeypadTap('0'),
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              // Using transparent to match typical keypad look
                              color: Colors.transparent,
                            ),
                            child: Center(
                              child: Text(
                                "0",
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.normal,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Pay Button (Right)
                      Expanded(
                        child: InkWell(
                          onTap: _enteredPin.length == 4 ? _verifyPin : null,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A237E), // Dark Blue
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Center(
                              child: const Text(
                                "Pay",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyRow(List<String> keys) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) {
        return Expanded(
          child: InkWell(
            onTap: () => _onKeypadTap(key),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: SizedBox(
              height: 56,
              // Visual feedback container if needed, else plain
              child: Center(
                child: Text(
                  key,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.normal,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
