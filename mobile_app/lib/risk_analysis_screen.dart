import 'package:flutter/material.dart';
import 'package:mobile_app/api_service.dart';

import 'fraud_scanning_animation.dart';
import 'utils.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode

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
              'Analysis unavailable - proceeding with standard checks';
          _isLoading = false;
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

  /// Maps backend fraud codes to user-friendly text
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
                "Analyzing Transaction...",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Checking recipient pattern...",
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
              const SizedBox(height: 4),
              Text(
                "Verifying scam database...",
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
                      ? "Critical Fraud Risk!"
                      : (_isWarn
                            ? "Security Warning"
                            : "Transaction Verified Safe"),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
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
                              ? "CRITICAL RISK"
                              : (_isRisk
                                    ? "SECURITY WARNING"
                                    : "VERIFIED SAFE"),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
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
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Risk Insight Header
                if (_isRisk && _specificRiskCode != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        "Detailed Analysis",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
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
                          ? (_isBypassable ? "Proceed with Caution" : "Go Back")
                          : "Proceed to Secure Payment",
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
            "Unusual activity detected.",
            Icons.warning_amber_rounded,
            false,
            textColor,
          ),
          const SizedBox(height: 16),
          _buildRiskItem(
            _riskExplanation.isNotEmpty
                ? _riskExplanation
                : "Please revie   w before proceeding.",
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

  // Helper to build list from specific code
  List<Widget> _buildDynamicRiskList(String code, Color textColor) {
    List<Widget> items = [];
    int itemsCount = 0;

    // PRIMARY REASON (The specific code from backend)
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

    // SECONDARY CONTEXT (Add up to 2 more reasons if relevant)
    if (_fraudFeatures != null) {
      // Context 1: Trust Score
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

      // Context 2: Account Age / New
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

      // Context 3: High Amount for conditions
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
          size: 24, // Slightly larger icon
          color: isSafe
              ? const Color(0xFF4CAF50)
              : (_isHighRisk
                    ? const Color(0xFFD32F2F)
                    : const Color(0xFFFFA000)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            desc,
            style: TextStyle(
              fontSize: 16, // Slightly clearer text
              color: textColor.withValues(alpha: 0.9),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
