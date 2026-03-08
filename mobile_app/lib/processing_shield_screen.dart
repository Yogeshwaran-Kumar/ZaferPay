import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'api_service.dart';
import 'utils.dart'; // Add import
import 'services/app_localizations.dart';
import 'package:flutter/foundation.dart';

class ProcessingShieldScreen extends StatefulWidget {
  final String receiverUpi;
  final double amount;
  final String receiverName;
  final String pin;
  final String? category;
  final String? mcc;
  final String? note;
  final bool skipFraudCheck;
  final String? acknowledgedRisk;
  final int? requestId; // Payment Request ID
  final String? paymentSource;

  const ProcessingShieldScreen({
    super.key,
    required this.receiverUpi,
    required this.amount,
    required this.receiverName,
    required this.pin,
    this.category,
    this.mcc,
    this.note,
    this.skipFraudCheck = false,
    this.acknowledgedRisk,
    this.requestId,
    this.paymentSource,
    this.isCirclePayment = false,
    this.circleId,
    this.isOnCall = false,
  });

  final bool isCirclePayment;
  final int? circleId;
  final bool isOnCall;

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
  String? _statusTextOverride;
  Color _shieldColor = Colors.grey;
  IconData _shieldIcon = Icons.perm_device_information;

  Map<String, dynamic>? _result;
  Timer? _pollTimer;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSecurityFlow();
    });
  }

  @override
  void dispose() {
    _stopPolling();
    _pulseController.dispose();

    // If we leave the screen while processing a circle payment,
    // and it hasn't been finished yet, we should cancel the request
    // so it doesn't stay on the parent's screen.
    if (_result?['status'] == 'PENDING_APPROVAL' &&
        _result?['request_id'] != null) {
      _api.cancelPaymentRequest(_result!['request_id']);
    }

    super.dispose();
  }

  void _startPolling(int requestId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final req = await _api.getPaymentRequest(requestId);
        if (req != null && req['status'] == 'paid') {
          _stopPolling();
          if (mounted) {
            _result = {
              'status': 'SUCCESS',
              'tx_id': req['id']?.toString() ?? 'SUCCESS',
              'detail':
                  AppLocalizations.of(
                    context,
                  )?.translate('results.parent_approved') ??
                  'Parent approved your payment.',
            };
            _handleResult();
          }
        } else if (req != null &&
            (req['status'] == 'rejected' || req['status'] == 'cancelled')) {
          _stopPolling();
          if (mounted) {
            _result = {
              'status': 'FAILED',
              'detail': req['status'] == 'rejected'
                  ? (AppLocalizations.of(
                          context,
                        )?.translate('results.parent_declined') ??
                        'Parent declined the request.')
                  : (AppLocalizations.of(
                          context,
                        )?.translate('results.request_cancelled') ??
                        'Request was cancelled.'),
            };
            _handleResult();
          }
        }
      } catch (e) {
        if (kDebugMode) print("Polling error: $e");
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _startSecurityFlow() async {
    // FAST TRACK: Combine stages to speed up payment
    setState(() {
      _stage = 3; // Jump straight to Processing visualization
      _statusTextOverride =
          AppLocalizations.of(
            context,
          )?.translate('processing.securing_processing') ??
          "Securing & Processing...";
      _shieldColor = Colors.blue;
      _shieldIcon = Icons.lock_clock;
    });

    // 1. Quick Integrity Check (Background)
    bool isCompromised = false;
    try {
      // Run checks in parallel
      final results =
          await Future.wait([
            FlutterJailbreakDetection.jailbroken,
            _api.checkTamperDetection().then((safe) => !safe),
            _api.verifySimBinding(),
          ]).timeout(
            const Duration(seconds: 3),
            onTimeout: () => [false, false, true], // Fail-open for UX speed
          );

      if (results[0] || results[1] || !results[2]) {
        isCompromised = true;
      }
    } catch (e) {
      // Fail closed on error if needed, or open for speed/ux (debugging)
      if (kDebugMode) print("Integrity check failed: $e");
    }

    if (isCompromised) {
      setState(() {
        _stage = 4;
        _result = {
          'status': 'SECURITY_RISK',
          'detail':
              AppLocalizations.of(
                context,
              )?.translate('results.device_integrity_failed') ??
              'Device Integrity Failed',
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
      skipFraudCheck: widget.skipFraudCheck,
      acknowledgedRisk: widget.acknowledgedRisk,
      requestId: widget.requestId,
      paymentSource: widget.paymentSource,
      isOnCall: widget.isOnCall,
      isCirclePayment: widget.isCirclePayment,
      circleId: widget.circleId,
    );

    // 3. Show "Processing" state while waiting for network
    setState(() {
      _statusTextOverride =
          AppLocalizations.of(
            context,
          )?.translate('processing.processing_payment') ??
          "Processing Payment...";
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
    bool isPending = status == 'PENDING_APPROVAL' || status == 'ACCEPTED';

    setState(() {
      if (!isPending) {
        _stopPolling();
        _pulseController.stop(); // Stop pulsing for final result
        _stage = 4;
      } else {
        _stage = 3; // Keep animation stage for pending
        // Start polling for child only if not already polling
        if (_result?['request_id'] != null) {
          _startPolling(_result!['request_id']);
        } else if (widget.requestId != null) {
          // Fallback if we already have it
          _startPolling(widget.requestId!);
        }
      }
    });

    if (status == 'SUCCESS') {
      setState(() {
        _statusTextOverride =
            AppLocalizations.of(
              context,
            )?.translate('results.payment_successful') ??
            "Payment Successful";
        _shieldColor = const Color(0xFF4CAF50); // Green
        _shieldIcon = Icons.check_circle;
      });
      // Auto-close after success (optional) or show Receipt button
    } else if (status == 'SECURITY_RISK') {
      setState(() {
        _statusTextOverride =
            AppLocalizations.of(
              context,
            )?.translate('results.security_risk_detected') ??
            "Security Risk Detected";
        _shieldColor = const Color(0xFFD32F2F); // Dark Red
        _shieldIcon = Icons.security_rounded; // HMAC Lock
      });
    } else if (status == 'FRAUD_BLOCKED' || status == 'BLOCKED') {
      setState(() {
        _statusTextOverride =
            AppLocalizations.of(
              context,
            )?.translate('results.transaction_blocked') ??
            "Transaction Blocked";
        _shieldColor = const Color(0xFFC62828); // Red
        _shieldIcon = Icons.gpp_bad_rounded; // Shield Block
      });
    } else if (status == 'PENDING_APPROVAL' || status == 'ACCEPTED') {
      setState(() {
        // If parent is currently approving, show "Processing Approval..."
        // If child is waiting, show "Waiting for Parent Approval..."
        _statusTextOverride = widget.requestId != null
            ? (AppLocalizations.of(
                    context,
                  )?.translate('processing.processing_approval') ??
                  "Processing Approval...")
            : (AppLocalizations.of(
                    context,
                  )?.translate('processing.waiting_parent') ??
                  "Waiting for Parent Approval...");
        _shieldColor = Colors.orange;
        _shieldIcon = Icons.hourglass_top_rounded;
      });
    } else {
      setState(() {
        _statusTextOverride =
            AppLocalizations.of(context)?.translate('results.payment_failed') ??
            "Payment Failed";
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
        // STATUS TEXT
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _statusTextOverride ??
                (AppLocalizations.of(
                      context,
                    )?.translate('processing.verifying_integrity') ??
                    "Verifying Integrity..."),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),

        if (_result?['status'] == 'PENDING_APPROVAL' ||
            _result?['status'] == 'ACCEPTED') ...[
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(
                  context,
                )?.translate('processing.txn_processed_after') ??
                "Transaction will be processed once approved",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 60),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, {'status': 'CANCELLED'}),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(
                        context,
                      )?.translate('processing.cancel_request') ??
                      "Cancel Request",
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResultCard(BuildContext context, bool isDark) {
    bool isSuccess = _result?['status'] == 'SUCCESS';
    bool isPending = _result?['status'] == 'PENDING_APPROVAL';

    String txId =
        _result?['tx_id'] ?? 'TXN${DateTime.now().millisecondsSinceEpoch}';
    String riskScore = _result?['risk_score'] ?? 'SAFE';

    String detail = '';
    if (_result?['detail'] != null) {
      if (_result!['detail'] is String) {
        detail = _result!['detail'];
      } else if (_result!['detail'] is Map &&
          _result!['detail']['message'] != null) {
        detail = _result!['detail']['message'];
      }
    }

    // Determine Security Label
    String securityLabel =
        AppLocalizations.of(context)?.translate('results.safe_and_secure') ??
        "Safe & Secure";
    Color securityColor = Colors.green;
    IconData securityIcon = Icons.verified_user;

    if (riskScore == 'WARN') {
      securityLabel =
          AppLocalizations.of(
            context,
          )?.translate('results.unusual_activity_warn') ??
          "Warning: Unusual Activity";
      securityColor = Colors.orange;
      securityIcon = Icons.warning_amber_rounded;
    } else if (riskScore == 'HIGH' || !isSuccess) {
      securityLabel =
          AppLocalizations.of(context)?.translate('results.result_unsafe') ??
          "Result: Unsafe";
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
          // 1. Icon
          if (isSuccess)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.check, color: Colors.green, size: 40),
            )
          else if (isPending)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withValues(alpha: 0.1),
              ),
              child: const Icon(
                Icons.info_outline,
                color: Colors.blue,
                size: 40,
              ),
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
            isSuccess
                ? (AppLocalizations.of(
                        context,
                      )?.translate('results.payment_successful') ??
                      "Payment Successful")
                : (isPending
                      ? (AppLocalizations.of(
                              context,
                            )?.translate('results.approval_required') ??
                            "Approval Required")
                      : (AppLocalizations.of(
                              context,
                            )?.translate('results.payment_failed') ??
                            "Payment Failed")),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isSuccess
                  ? Colors.green
                  : (isPending ? Colors.blue : Colors.red),
            ),
          ),
          if (!isSuccess && detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isPending ? Colors.blue.shade300 : Colors.red.shade300,
                fontSize: 13,
              ),
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
                _buildRow(
                  AppLocalizations.of(context)?.translate('details.to') ?? "To",
                  widget.receiverName,
                  isDark,
                ),
                const Divider(height: 24),
                _buildRow(
                  AppLocalizations.of(context)?.translate('details.txn_id') ??
                      "Transaction ID",
                  txId,
                  isDark,
                ),
                const Divider(height: 24),

                // NEW: Security Check Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(
                            context,
                          )?.translate('results.security_check') ??
                          "Security Check",
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(securityIcon, size: 14, color: securityColor),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              securityLabel,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: securityColor,
                              ),
                            ),
                          ),
                        ],
                      ),
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
                isSuccess
                    ? (AppLocalizations.of(
                            context,
                          )?.translate('results.done') ??
                          "Done")
                    : (isPending
                          ? (AppLocalizations.of(
                                  context,
                                )?.translate('results.ok') ??
                                "OK")
                          : (AppLocalizations.of(
                                  context,
                                )?.translate('results.close_retry') ??
                                "Close / Retry")),
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
                AppLocalizations.of(context)?.translate('common.powered_by') ??
                    "Powered by ZaferPay",
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
        Flexible(
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ),
        const SizedBox(width: 8),
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
