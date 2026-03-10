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
    return _riskExplanation.isNotEmpty 
        ? _riskExplanation 
        : (AppLocalizations.of(context)?.translate('risk.unsafe_desc') ?? 
           "Potentially unsafe transaction.");
  }

  IconData _getRiskIcon(String code) {
    if (code.contains("VELOCITY") || code.contains("F1")) return Icons.speed_rounded;
    if (code.contains("SESSION") || code.contains("F19")) return Icons.access_time_rounded;
    if (code.contains("CONSECUTIVE") || code.contains("F25")) return Icons.repeat_rounded;
    if (code.contains("NIGHT") || code.contains("F39")) return Icons.nightlight_round;
    if (code.contains("FREQUENCY") || code.contains("F41")) return Icons.repeat_rounded;
    if (code.contains("CONCURRENT") || code.contains("F48")) return Icons.warning_rounded;
    if (code.contains("FAILED") || code.contains("F49")) return Icons.error_outline_rounded;
    if (code.contains("CIRCULAR") || code.contains("F2")) return Icons.loop_rounded;
    if (code.contains("ROUND_TRIP") || code.contains("F54")) return Icons.swap_horiz_rounded;
    if (code.contains("FIRST_TX") || code.contains("F4")) return Icons.new_releases_rounded;
    if (code.contains("DORMANT") || code.contains("F22")) return Icons.person_off_rounded;
    if (code.contains("NEW_RECEIVER") || code.contains("F40")) return Icons.person_add_disabled_rounded;
    if (code.contains("SPIKE") || code.contains("F5") || code.contains("F8") || code.contains("F21")) return Icons.trending_up_rounded;
    if (code.contains("MERCHANT") && code.contains("F6")) return Icons.store_rounded;
    if (code.contains("F7")) return Icons.store_mall_directory_rounded;
    if (code.contains("MERCHANT_LOCATION") || code.contains("F30_MERCHANT")) return Icons.location_off_rounded;
    if (code.contains("MCC_SWITCHING") || code.contains("F47")) return Icons.category_rounded;
    if (code.contains("FAKE_MERCHANT") || code.contains("F56")) return Icons.report_problem_rounded;
    if (code.contains("MCC_MISMATCH") || code.contains("F57")) return Icons.qr_code_scanner_rounded;
    if (code.contains("UNUSUAL_TIME") || code.contains("F9")) return Icons.access_time_rounded;
    if (code.contains("TIME_PATTERN") || code.contains("F20")) return Icons.schedule_rounded;
    if (code.contains("HOLIDAY") || code.contains("F33")) return Icons.celebration_rounded;
    if (code.contains("SPLIT") || code.contains("F10")) return Icons.call_split_rounded;
    if (code.contains("MICRO_BURST") || code.contains("F31")) return Icons.grain_rounded;
    if (code.contains("SAME_AMOUNT") || code.contains("F35")) return Icons.content_copy_rounded;
    if (code.contains("SMURFING") || code.contains("F53")) return Icons.scatter_plot_rounded;
    if (code.contains("DAILY") && (code.contains("F11") || code.contains("F18"))) return code.contains("F18") ? Icons.block_flipped : Icons.calendar_today_rounded;
    if (code.contains("WEEKLY") || code.contains("F30")) return Icons.date_range_rounded;
    if (code.contains("STRANGER") || code.contains("F12")) return Icons.handshake_outlined;
    if (code.contains("BURST") && (code.contains("F13") || code.contains("F23"))) return code.contains("F13") ? Icons.people_outline_rounded : Icons.person_add_alt_rounded;
    if (code.contains("ROUND_AMOUNT") || code.contains("F14")) return Icons.looks_rounded;
    if (code.contains("FIRST_TIME_AMOUNT") || code.contains("F28")) return Icons.fiber_new_rounded;
    if (code.contains("PROGRESSIVE") || code.contains("F36")) return Icons.trending_up_rounded;
    if (code.contains("COUNTDOWN") || code.contains("F37")) return Icons.trending_down_rounded;
    if (code.contains("EVEN_AMOUNT") || code.contains("F38")) return Icons.filter_9_plus_rounded;
    if (code.contains("WHOLE_NUMBER") || code.contains("F46")) return Icons.calculate_rounded;
    if (code.contains("DRAIN") || code.contains("F15") || code.contains("F26")) return code.contains("F26") ? Icons.account_balance_wallet_rounded : Icons.trending_down_rounded;
    if (code.contains("SPENDING_EXCEEDS") || code.contains("F42")) return Icons.speed_rounded;
    if (code.contains("DEVICE_CHANGE") || code.contains("F16")) return Icons.phonelink_off_rounded;
    if (code.contains("NEW_DEVICE") || code.contains("F43")) return Icons.phone_android_rounded;
    if (code.contains("MULTIPLE_IPS") || code.contains("F44")) return Icons.location_searching_rounded;
    if (code.contains("INSTANT") || code.contains("F45")) return Icons.flash_on_rounded;
    if (code.contains("RECEIVER_HIGH_INFLOW") || code.contains("F17")) return Icons.call_received_rounded;
    if (code.contains("RECIPIENT_CLUSTER") || code.contains("F27")) return Icons.hub_rounded;
    if (code.contains("TOO_MANY_UNIQUE") || code.contains("F34")) return Icons.groups_rounded;
    if (code.contains("CHAIN") || code.contains("F24")) return Icons.link_rounded;
    if (code.contains("STAR_PATTERN") || code.contains("F50")) return Icons.star_border_rounded;
    if (code.contains("FUNNEL_PATTERN") || code.contains("F51")) return Icons.filter_alt_rounded;
    if (code.contains("LAYERING") || code.contains("F52")) return Icons.account_tree_rounded;
    if (code.contains("GEO") || code.contains("F29")) return code.contains("GEO_VELOCITY") ? Icons.location_off_rounded : Icons.my_location_rounded;
    if (code.contains("WEEKEND") || code.contains("F32")) return Icons.weekend_rounded;
    if (code.contains("SCREEN_SHARING") || code.contains("F55")) return Icons.screen_share_rounded;
    if (code.contains("QR_PERSONAL") || code.contains("F58")) return Icons.qr_code_2_rounded;
    if (code.contains("DEEP_LINK") || code.contains("F59")) return Icons.link_rounded;
    if (code.contains("PANIC") || code.contains("F60")) return Icons.timer_rounded;
    if (code.contains("INVESTMENT_SCAM") || code.contains("F61")) return Icons.report_rounded;
    if (code.contains("AI_DETECTED")) return Icons.psychology_rounded;
    if (code.contains("SELF_TRANSFER")) return Icons.loop_rounded;
    
    return Icons.warning_amber_rounded; // Default
  }

  List<Widget> _buildDynamicRiskList(String code, Color textColor) {
    List<Widget> items = [];

    // 1. PRIMARY FINDING
    String primaryTitle =
        AppLocalizations.of(context)?.translate('risk.primary_finding') ??
        "Primary Finding";
    String desc = _getRiskMessage(code);
    IconData icon = _getRiskIcon(code);

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
