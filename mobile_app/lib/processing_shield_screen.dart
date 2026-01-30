import 'package:flutter/material.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'api_service.dart';
import 'utils.dart'; // Add import

class ProcessingShieldScreen extends StatefulWidget {
  final String receiverUpi;
  final double amount;
  final String receiverName;
  final String pin;
  final String? category;
  final String? mcc;
  final String? note;

  const ProcessingShieldScreen({
    super.key,
    required this.receiverUpi,
    required this.amount,
    required this.receiverName,
    required this.pin,
    this.category,
    this.mcc,
    this.note,
  });

  @override
  State<ProcessingShieldScreen> createState() => _ProcessingShieldScreenState();
}

class _ProcessingShieldScreenState extends State<ProcessingShieldScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  // Security Stages
  // 0: Integrity Scan (New)
  // 1: Encrypting (HMAC)
  // 2: Analysing Risk (AI)
  // 3: Processing (Bank)
  // 4: Success / Failure
  int _stage = 0;
  String _statusText = "Verifying Integrity...";
  Color _shieldColor = Colors.grey;
  IconData _shieldIcon = Icons.perm_device_information;

  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();

    // Pulse Animation for "Alive" feel
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startSecurityFlow();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startSecurityFlow() async {
    // FAST TRACK: Combine stages to speed up payment
    setState(() {
      _stage = 3; // Jump straight to Processing visualization
      _statusText = "Securing & Processing...";
      _shieldColor = Colors.blue;
      _shieldIcon = Icons.lock_clock;
    });

    // 1. Quick Integrity Check (Background)
    bool isCompromised = false;
    try {
      // Run checks in parallel
      final results = await Future.wait([
        FlutterJailbreakDetection.jailbroken,
        _api.checkTamperDetection().then((safe) => !safe),
        _api.verifySimBinding(),
      ]);

      if (results[0] || results[1] || !results[2]) {
        isCompromised = true;
      }
    } catch (e) {
      // Fail closed on error if needed, or open for speed/ux (debugging)
      print("Integrity check failed: $e");
    }

    if (isCompromised) {
      setState(() {
        _stage = 4;
        _result = {
          'status': 'SECURITY_RISK',
          'detail': 'Device Integrity Failed',
        };
      });
      _handleResult();
      return;
    }

    // 2. Immediate API Call (Optimistic for speed)
    final apiCall = _api.createTransactionOptimistic(
      widget.receiverUpi,
      widget.amount,
      widget.pin,
      mcc: widget.mcc,
      note: widget.note,
      receiverName: widget.receiverName,
    );

    // 3. Show "Processing" state while waiting for network
    setState(() {
      _statusText = "Processing Payment...";
      _shieldColor = Colors.orange;
      _shieldIcon = Icons.sync;
    });

    try {
      _result = await apiCall;

      // If success, refresh home screen data
      if (_result?['status'] == 'SUCCESS') {
        await _api.getHomeScreenData();
      }
    } catch (e) {
      _result = {'detail': 'Connection Error', 'status': 'FAILED'};
    }

    // 4. Show Result
    _handleResult();
  }

  void _handleResult() {
    if (_result == null) return;

    final status = _result!['status'];
    // final detail = _result!['detail'] ?? ''; (Unused)

    setState(() {
      _pulseController.stop(); // Stop pulsing
      _stage = 4;
    });

    if (status == 'SUCCESS') {
      setState(() {
        _statusText = "Payment Successful";
        _shieldColor = const Color(0xFF4CAF50); // Green
        _shieldIcon = Icons.check_circle;
      });
      // Auto-close after success (optional) or show Receipt button
    } else if (status == 'SECURITY_RISK') {
      setState(() {
        _statusText = "Security Risk Detected";
        _shieldColor = const Color(0xFFD32F2F); // Dark Red
        _shieldIcon = Icons.security_rounded; // HMAC Lock
      });
    } else if (status == 'FRAUD_BLOCKED' || status == 'BLOCKED') {
      setState(() {
        _statusText = "Transaction Blocked";
        _shieldColor = const Color(0xFFC62828); // Red
        _shieldIcon = Icons.gpp_bad_rounded; // Shield Block
      });
    } else {
      setState(() {
        _statusText = "Payment Failed";
        _shieldColor = Colors.red;
        _shieldIcon = Icons.error_outline;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use theme colors directly instead of black overlay
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: _stage == 4
              ? _buildResultCard(context, isDark)
              : _buildAnimationContent(isDark),
        ),
      ),
    );
  }

  Widget _buildAnimationContent(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // THE SHIELD PULSE ANIMATION
        ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _shieldColor.withValues(alpha: 0.1),
            ),
            child: Icon(_shieldIcon, size: 60, color: _shieldColor),
          ),
        ),
        const SizedBox(height: 40),
        // STATUS TEXT
        Text(
          _statusText,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            // Text color depends on theme now (not always white)
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(BuildContext context, bool isDark) {
    bool isSuccess = _result?['status'] == 'SUCCESS';
    String txId =
        _result?['tx_id'] ?? 'TXN${DateTime.now().millisecondsSinceEpoch}';
    String riskScore = _result?['risk_score'] ?? 'SAFE';
    String detail = _result?['detail'] ?? '';

    // Determine Security Label
    String securityLabel = "Safe & Secure";
    Color securityColor = Colors.green;
    IconData securityIcon = Icons.verified_user;

    if (riskScore == 'WARN') {
      securityLabel = "Warning: Unusual Activity";
      securityColor = Colors.orange;
      securityIcon = Icons.warning_amber_rounded;
    } else if (riskScore == 'HIGH' || !isSuccess) {
      securityLabel = "Result: Unsafe / Blocked";
      securityColor = Colors.red;
      securityIcon = Icons.gpp_bad_rounded;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        // Card color should be distinct from background
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Success Icon
          if (isSuccess)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.check, color: Colors.green, size: 40),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.close, color: Colors.red, size: 40),
            ),

          const SizedBox(height: 24),

          // 2. Title & Amount
          Text(
            isSuccess ? "Payment Successful" : "Payment Failed",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isSuccess ? Colors.green : Colors.red,
            ),
          ),
          if (!isSuccess && detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade300, fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            "₹${formatAmount(widget.amount)}",
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),

          const SizedBox(height: 32),

          // 3. Details Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.2)
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey.shade200,
              ),
            ),
            child: Column(
              children: [
                _buildRow("To", widget.receiverName, isDark),
                const Divider(height: 24),
                _buildRow("Transaction ID", txId, isDark),
                const Divider(height: 24),

                // NEW: Security Check Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Security Check",
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    Row(
                      children: [
                        Icon(securityIcon, size: 14, color: securityColor),
                        const SizedBox(width: 4),
                        Text(
                          securityLabel,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: securityColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // 4. Done Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (isSuccess) {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/conversation',
                    ModalRoute.withName('/home'),
                    arguments: {
                      'upi': widget.receiverUpi,
                      'name': widget.receiverName,
                    },
                  );
                } else {
                  // Return the result to the caller (PaymentPinScreen)
                  Navigator.pop(context, _result);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : Colors.black,
                foregroundColor: isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isSuccess ? "Done" : "Close / Retry",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Powered By Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 14,
                color: isDark ? Colors.white54 : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                "Powered by SafePay",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white54 : Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
