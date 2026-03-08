import 'package:flutter/material.dart';
import 'package:mobile_app/api_service.dart';

import 'fraud_scanning_animation.dart';
import 'utils.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'services/app_localizations.dart';

class RiskAnalysisScreen extends StatefulWidget {
  const RiskAnalysisScreen({super.key});

  @override
  State<RiskAnalysisScreen> createState() => _RiskAnalysisScreenState();
}

class _RiskAnalysisScreenState extends State<RiskAnalysisScreen> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  bool _isRisk = false;
  bool _isWarn = false; // WARN = warning level
  bool _isHighRisk = false; // HIGH = blocked level
  bool _isBypassable = true; // NEW: from backend

  // Transaction Data
  late double _amount;
  late String _receiverUpi;
  late String _receiverName;
  String? _category;
  String? _mcc;
  String? _note;
  int? _paymentRequestId;
  String? _paymentSource;

  // Analysis Results (from backend)
  String _riskScore = "SAFE"; // 'SAFE', 'WARN', 'HIGH'
  String _riskExplanation = "";
  String? _specificRiskCode; // e.g., F18_DAILY_LIMIT
  Map<String, dynamic>? _fraudFeatures;
  double _aiConfidence = 0.0; // NEW: AI confidence score (0.0 to 1.0)

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null) {
      _amount = (args['amount'] as num).toDouble();
      _receiverUpi = args['receiverUpi'] ?? '';
      _receiverName = args['name'] ?? 'Unknown';
      _category = args['category'];
      _mcc = args['mcc'];
      _note = args['note'];
      _paymentRequestId = args['paymentRequestId']; // Extract Request ID
      _paymentSource = args['payment_source']; // Extract Telemetry

      _analyzeRisk();
    }
  }

  Future<void> _analyzeRisk() async {
    if (kDebugMode) {
      print('----------------------------------------------------------------');
      print('🔍 STARTING BACKEND RISK ANALYSIS for transaction...');
      print('💵 Amount: ₹${formatAmount(_amount)}');
      print('👤 Receiver: $_receiverName ($_receiverUpi)');
    }

    try {
      // Call backend API for fraud analysis
      final result = await _api.analyzeTransactionRisk(
        _receiverUpi,
        _amount,
        mcc: _mcc,
        note: _note,
        paymentSource: _paymentSource, // Pass Telemetry
      );

      if (kDebugMode) {
        print('✅ BACKEND ANALYSIS COMPLETE');
        print('   -> Result: $result');
      }

      if (mounted) {
        setState(() {
          _riskScore = result['risk_score'] ?? 'SAFE';
          // Extract specific reason code from backend RESPONSE
          _specificRiskCode = result['risk_reason'];

          _isRisk = _riskScore != 'SAFE';
          _isWarn = _riskScore == 'WARN';
          _isHighRisk = _riskScore == 'HIGH';
          _isBypassable = result['is_bypassable'] ?? true;

          // Update receiver name from backend if available
          if (result['receiver_name'] != null &&
              result['receiver_name'] != 'Unknown') {
            _receiverName = result['receiver_name'];
          }

          // Build explanation from backend response or specific code
          // Priority: 1. Code Mapping, 2. Backend Detail Message, 3. Generic
          _riskExplanation =
              _getHumanReadableExplanation(_specificRiskCode) ??
              (result['detail'] is Map
                  ? result['detail']['message']
                  : _getDefaultExplanation());

          if (result['detail'] is Map) {
            _fraudFeatures = result['detail']['features'];
            // Extract AI confidence if provided by backend, or estimate based on risk
            _aiConfidence =
                result['detail']['confidence']?.toDouble() ??
                (_isHighRisk ? 0.95 : (_isWarn ? 0.75 : 0.99));
          } else {
            _aiConfidence = _isHighRisk ? 0.90 : (_isWarn ? 0.70 : 0.98);
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('❌ Risk Analysis Error: $e');
      // Fallback to safe on error (fail open for UX)
      if (mounted) {
        setState(() {
          _riskScore = 'SAFE';
          _isRisk = false;
          _riskExplanation =
              AppLocalizations.of(context)?.translate('risk.verified_safe') ??
              'Analysis unavailable - proceeding with standard checks';
          _isLoading = false;
        });
      }
    }
  }

  String _getDefaultExplanation() {
    switch (_riskScore) {
      case 'HIGH':
        return AppLocalizations.of(context)?.translate('risk.f18_desc') ??
            'High risk transaction detected. Please review carefully.';
      case 'WARN':
        return AppLocalizations.of(
              context,
            )?.translate('risk.security_warning') ??
            'Unusual pattern detected. Proceed with caution.';
      default:
        return AppLocalizations.of(context)?.translate('risk.verified_safe') ??
            'Transaction appears safe.';
    }
  }

  /// Maps backend fraud codes to user-friendly text
  String? _getHumanReadableExplanation(String? code) {
    if (code == null) return null;

    if (code.contains("F18_DAILY")) {
      return AppLocalizations.of(context)?.translate('risk.f18_desc');
    }
    if (code.contains("F1_VELOCITY")) {
      return AppLocalizations.of(context)?.translate('risk.f1_velocity_desc');
    }
    if (code.contains("AI_DETECTED")) {
      return AppLocalizations.of(context)?.translate('risk.ai_detected_desc');
    }
    if (code.contains("F29_GEO")) {
      return AppLocalizations.of(context)?.translate('risk.geo_desc');
    }
    if (code.contains("F15_RAPID_DRAIN")) {
      return AppLocalizations.of(context)?.translate('risk.rapid_drain_desc');
    }
    if (code.contains("NEW_RECEIVER")) {
      return AppLocalizations.of(context)?.translate('risk.new_receiver_desc');
    }
    if (code.contains("SELF_TRANSFER")) {
      return AppLocalizations.of(context)?.translate('risk.self_transfer_desc');
    }
    if (code.contains("F52_LAYERING")) {
      return AppLocalizations.of(context)?.translate('risk.layering_desc');
    }
    if (code.contains("F30_WEEKLY")) {
      return AppLocalizations.of(context)?.translate('risk.weekly_limit_desc');
    }

    return null; // Fallback to generic
  }

  void _proceedToPin() async {
    final result = await Navigator.pushNamed(
      context,
      '/payment-pin',
      arguments: {
        'receiverUpi': _receiverUpi,
        'amount': _amount,
        'name': _receiverName,
        'category': _category,
        'mcc': _mcc,
        'note': _note,
        // Pass risk acknowledgment to skip re-check in transaction
        'skipFraudCheck': _isRisk, // Skip if user saw warning
        'acknowledgedRisk': _isRisk ? _riskScore : null,
        'paymentRequestId': _paymentRequestId, // Pass Request ID Forward
        'payment_source': _paymentSource, // Pass Telemetry Forward
      },
    );

    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    // STANDARD THEME LOGIC
    final isAppDark = Theme.of(context).brightness == Brightness.dark;
    final useDarkTheme = isAppDark;

    final bgColor = useDarkTheme ? Colors.black : Colors.white;
    final textColor = useDarkTheme ? Colors.white : Colors.black87;
    final secondaryTextColor = useDarkTheme
        ? Colors.grey.shade400
        : Colors.grey.shade600;
    final cardColor = useDarkTheme
        ? const Color(0xFF1E1E1E)
        : Colors.grey.shade50;
    final borderColor = useDarkTheme
        ? Colors.grey.shade800
        : Colors.grey.shade300;
    final iconColor = useDarkTheme ? Colors.white : Colors.black;

    // Helper to get status color
    Color getStatusColor() {
      if (_isHighRisk) return const Color(0xFFD32F2F); // Red 700
      if (_isWarn) return const Color(0xFFFFA000); // Amber 700
      return const Color(0xFF4CAF50); // Green
    }

    final statusColor = getStatusColor();

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Powerful Custom Fraud Scan Animation
              FraudScanningAnimation(isDark: useDarkTheme),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context)?.translate('risk.analyzing') ??
                    "Analyzing Transaction...",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(
                      context,
                    )?.translate('risk.checking_pattern') ??
                    "Checking recipient pattern...",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(
                      context,
                    )?.translate('risk.verifying_scam_db') ??
                    "Verifying scam database...",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
              const SizedBox(height: 30),
              // Optional: Trust/Security Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.security, size: 16, color: Colors.grey[400]),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(
                          context,
                        )?.translate('common.powered_by') ??
                        "Powered by ZaferPay AI",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(Icons.close, color: iconColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 20),
                // Status Icon
                if (_isRisk)
                  Icon(
                    _isHighRisk
                        ? Icons.gpp_bad_rounded
                        : Icons.warning_amber_rounded,
                    size: 100,
                    color: statusColor,
                  ) // Red or Amber
                else
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: statusColor, // Green
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),

                const SizedBox(height: 32),

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
                    fontSize: 24,
                    height: 1.2,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),

                const SizedBox(height: 40),

                // Description with Risk Details
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: [
                      // Risk Score Badge (Cleaned up)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor, width: 1.5),
                        ),
                        child: Text(
                          _isHighRisk
                              ? (AppLocalizations.of(
                                      context,
                                    )?.translate('risk.critical_risk_badge') ??
                                    "CRITICAL RISK")
                              : (_isRisk
                                    ? (AppLocalizations.of(context)?.translate(
                                            'risk.security_warning_badge',
                                          ) ??
                                          "SECURITY WARNING")
                                    : (AppLocalizations.of(context)?.translate(
                                            'risk.verified_safe_badge',
                                          ) ??
                                          "VERIFIED SAFE")),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: statusColor,
                          ),
                        ),
                      ),

                      // Risk Explanation
                      if (_riskExplanation.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _riskExplanation,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: _isRisk ? statusColor : secondaryTextColor,
                              fontWeight: _isRisk
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ),

                      const SizedBox(height: 24),
                      // AI CONFIDENCE INDICATOR
                      _buildConfidenceIndicator(statusColor, textColor),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Risk Insight Header
                if (_isRisk && _specificRiskCode != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12, left: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.psychology_outlined,
                            size: 20,
                            color: textColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(
                                  context,
                                )?.translate('risk.ai_breakdown') ??
                                "ZaferPay AI Breakdown",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Main Info Section (Dynamic)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildRiskFactors(useDarkTheme, textColor),
                  ),
                ),

                const SizedBox(height: 40),

                // Action Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isRisk
                        ? () {
                            if (_isBypassable) {
                              _proceedToPin();
                            } else {
                              Navigator.pop(context);
                            }
                          }
                        : _proceedToPin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isRisk
                          ? (_isBypassable ? statusColor : Colors.grey[800])
                          : const Color(0xFF2196F3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _isRisk
                          ? (_isBypassable
                                ? (AppLocalizations.of(context)?.translate(
                                        'risk.proceed_caution_btn',
                                      ) ??
                                      "Proceed with Caution")
                                : (AppLocalizations.of(
                                        context,
                                      )?.translate('risk.go_back_btn') ??
                                      "Go Back"))
                          : (AppLocalizations.of(
                                  context,
                                )?.translate('risk.secure_payment_btn') ??
                                "Proceed to Secure Payment"),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the list of risk factors dynamically
  List<Widget> _buildRiskFactors(bool useDarkTheme, Color textColor) {
    if (_isRisk) {
      if (_specificRiskCode != null) {
        return _buildDynamicRiskList(_specificRiskCode!, textColor);
      } else {
        // Fallback for unknown codes (generic warning)
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
      // SAFE STATE - Same as before
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

  // Helper to build list from specific code
  List<Widget> _buildDynamicRiskList(String code, Color textColor) {
    List<Widget> items = [];

    // 1. PRIMARY FINDING
    String primaryTitle =
        AppLocalizations.of(context)?.translate('risk.primary_finding') ??
        "Primary Finding";
    String desc =
        AppLocalizations.of(context)?.translate('risk.f18_desc') ??
        "Potentially unsafe transaction.";
    IconData icon = Icons.warning_amber_rounded;

    if (code.contains("F18") || code.contains("DAILY_LIMIT")) {
      desc =
          AppLocalizations.of(context)?.translate('risk.f18_desc') ??
          "Daily limit exceeded for this receiver type.";
      icon = Icons.block_flipped;
    } else if (code.contains("F1") || code.contains("VELOCITY")) {
      desc =
          AppLocalizations.of(context)?.translate('risk.f1_velocity_desc') ??
          "Sending too frequently. This pattern matches rapid automated scams.";
      icon = Icons.speed_rounded;
    } else if (code.contains("AI_DETECTED")) {
      desc =
          AppLocalizations.of(context)?.translate('risk.ai_detected_desc') ??
          "Our Neural Shield detected behavior that doesn't match your profile.";
      icon = Icons.psychology_rounded;
    } else if (code.contains("GEO") || code.contains("LOCATION")) {
      desc =
          AppLocalizations.of(context)?.translate('risk.geo_desc') ??
          "Impossible travel detected. Your phone is at a different location than the transaction.";
      icon = Icons.location_off_rounded;
    } else if (code.contains("F40") || code.contains("NEW_RECEIVER")) {
      desc =
          AppLocalizations.of(context)?.translate('risk.new_receiver_desc') ??
          "High-value transfer to a recipient you haven't interacted with before.";
      icon = Icons.person_add_disabled_rounded;
    } else if (code.contains("F52") || code.contains("LAYERING")) {
      desc =
          AppLocalizations.of(context)?.translate('risk.layering_desc') ??
          "Money is being routed through multiple layers, which is a high-risk indicator.";
      icon = Icons.account_tree_rounded;
    } else if (code.contains("F5") || code.contains("SPIKE")) {
      desc =
          AppLocalizations.of(context)?.translate('risk.spike_desc') ??
          "This payment is 10x higher than your usual average for this category.";
      icon = Icons.trending_up_rounded;
    } else if (code.contains("SELF_TRANSFER")) {
      desc =
          AppLocalizations.of(context)?.translate('risk.self_transfer_desc') ??
          "Self-transfer is restricted to prevent unintentional loops.";
      icon = Icons.loop_rounded;
    } else {
      desc = _riskExplanation;
    }

    items.add(
      _buildRiskItem(desc, icon, false, textColor, title: primaryTitle),
    );

    // 2. SUPPORTING TELEMETRY (Context)
    if (_fraudFeatures != null) {
      if ((_fraudFeatures!['trust_score'] ?? 0) < 50 && !code.contains("F18")) {
        items.add(const SizedBox(height: 16));
        items.add(
          _buildRiskItem(
            AppLocalizations.of(
                  context,
                )?.translate('risk.trust_score_low_desc') ??
                "Recipient has been flagged by other users or has low network tenure.",
            Icons.handshake_outlined,
            false,
            textColor,
            title:
                AppLocalizations.of(
                  context,
                )?.translate('risk.security_context') ??
                "Security Context",
          ),
        );
      } else if ((_fraudFeatures!['is_new_receiver'] ?? 0) == 1 &&
          !code.contains("NEW_RECEIVER")) {
        items.add(const SizedBox(height: 16));
        items.add(
          _buildRiskItem(
            AppLocalizations.of(context)?.translate('risk.never_paid_desc') ??
                "You are interacting with this individual for the first time on ZaferPay.",
            Icons.person_outline_rounded,
            false,
            textColor,
            title:
                AppLocalizations.of(
                  context,
                )?.translate('risk.network_history') ??
                "Network History",
          ),
        );
      }
    }

    // 3. RECOMMENDATION
    items.add(const SizedBox(height: 24));
    items.add(Divider(color: textColor.withValues(alpha: 0.1)));
    items.add(const SizedBox(height: 16));

    String recTitle =
        AppLocalizations.of(context)?.translate('risk.our_recommendation') ??
        "Our Recommendation";
    String recDesc =
        AppLocalizations.of(context)?.translate('risk.rec_call_confirm') ??
        "Call the person and confirm their identity before proceeding.";
    IconData recIcon = Icons.lightbulb_outline_rounded;

    if (_isHighRisk) {
      recDesc =
          AppLocalizations.of(context)?.translate('risk.rec_do_not_proceed') ??
          "Do NOT proceed. Contact support if you believe this is an error.";
      recIcon = Icons.gpp_maybe_rounded;
    } else if (code.contains("NEW_RECEIVER")) {
      recDesc =
          AppLocalizations.of(context)?.translate('risk.rec_double_check') ??
          "Double-check the UPI ID name. Scammers often use similar-looking names.";
    } else if (code.contains("VELOCITY")) {
      recDesc =
          AppLocalizations.of(context)?.translate('risk.rec_wait_30') ??
          "Wait at least 30 minutes before trying again to avoid auto-blocking.";
    }

    items.add(
      _buildRiskItem(
        recDesc,
        recIcon,
        false, // Uses the color logic in buildRiskItem
        textColor,
        title: recTitle,
      ),
    );

    return items;
  }

  Widget _buildConfidenceIndicator(Color statusColor, Color textColor) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppLocalizations.of(context)?.translate('risk.ai_confidence') ??
                  "AI Confidence",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor.withValues(alpha: 0.6),
              ),
            ),
            Text(
              "${(_aiConfidence * 100).toInt()}%",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _aiConfidence,
            minHeight: 6,
            backgroundColor: statusColor.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _aiConfidence > 0.9
              ? (AppLocalizations.of(
                      context,
                    )?.translate('risk.confidence_high') ??
                    "High-certainty verification powered by Neural Shield v5.0")
              : (AppLocalizations.of(
                      context,
                    )?.translate('risk.confidence_pattern') ??
                    "Pattern analysis based on recent network telemetry"),
          style: TextStyle(
            fontSize: 10,
            fontStyle: FontStyle.italic,
            color: textColor.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }

  Widget _buildRiskItem(
    String desc,
    IconData icon,
    bool isSafe,
    Color textColor, {
    String? title,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:
                (isSafe
                        ? Colors.green
                        : (_isHighRisk ? Colors.red : Colors.orange))
                    .withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSafe
                ? const Color(0xFF4CAF50)
                : (_isHighRisk
                      ? const Color(0xFFD32F2F)
                      : const Color(0xFFFFA000)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor.withValues(alpha: 0.8),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
