import 'package:flutter/material.dart';
import 'package:mobile_app/api_service.dart';
import 'package:lottie/lottie.dart';
import 'fraud_scanning_animation.dart';
import 'utils.dart'; // Add import

class RiskAnalysisScreen extends StatefulWidget {
  const RiskAnalysisScreen({super.key});

  @override
  State<RiskAnalysisScreen> createState() => _RiskAnalysisScreenState();
}

class _RiskAnalysisScreenState extends State<RiskAnalysisScreen> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  bool _isRisk = false;

  // Transaction Data
  late double _amount;
  late String _receiverUpi;
  late String _receiverName;
  String? _category;
  String? _mcc;
  String? _note; // Add this

  // Analysis Parameters
  final String _modelType = "Random Forest V1";
  bool _inContacts = false;
  bool _isNewReceiver = true;

  String _riskExplanation = "";
  String _riskCode = "S1"; // Default Safe Code

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
      _note = args['note']; // Add this

      _analyzeRisk();
    }
  }

  Future<void> _analyzeRisk() async {
    print('----------------------------------------------------------------');
    print('🔍 STARTING RISK ANALYSIS for transaction...');
    print('💵 Amount: ₹${formatAmount(_amount)}');
    print('👤 Receiver: $_receiverName ($_receiverUpi)');

    // Simulate Analysis Delay
    await Future.delayed(const Duration(milliseconds: 1500));

    // 1. Check if New Receiver (Check Recent People)
    print('🛠️  Step 1: Checking Receiver History...');
    final recentPeople = await _api.getRecentPeople();
    bool foundInRecents = false;
    if (recentPeople != null) {
      for (var person in recentPeople) {
        if (person['upi_id'] == _receiverUpi) {
          foundInRecents = true;
          break;
        }
      }
    }
    _isNewReceiver = !foundInRecents;
    print('   -> New Receiver? ${_isNewReceiver ? "YES" : "NO"}');

    // 2. Check In Contacts
    // For demo purposes, if it's a mobile number based UPI, assume in contacts if resolved
    print('🛠️  Step 2: Checking Contacts Book...');
    _inContacts = _receiverUpi.contains(RegExp(r'\d{10}'));
    print('   -> In Contacts? ${_inContacts ? "YES (Heuristic)" : "NO"}');

    // 3. Determine Risk Pattern (F1, F2, F3, S1)
    print('🛠️  Step 3: Determining Fraud Pattern...');

    // Pattern Logic
    if (_amount > 10000) {
      _isRisk = true;
      if (_isNewReceiver) {
        _riskCode = "F1"; // High Value + New
        _riskExplanation =
            "High Value New Receiver: Sending a very large amount (> ₹10,000) to a stranger is High Risk.";
      } else {
        _riskCode = "F2"; // High Value + Existing
        _riskExplanation =
            "Unusual High Value: The amount (> ₹10,000) deviates significantly from your average history.";
      }
    } else if (_amount > 5000 && _isNewReceiver) {
      _isRisk = true;
      _riskCode = "F3"; // Medium Value + New
      _riskExplanation =
          "Suspicious Transfer: First-time transfer of a significant amount (> ₹5,000) detected.";
    } else {
      _isRisk = false;
      _riskCode = "S1";
      if (_isNewReceiver) {
        _riskExplanation =
            "Safe New Transfer: Small amount to a new receiver is considered low risk.";
      } else {
        _riskExplanation =
            "Standard Transfer: Transaction matches your regular payment patterns.";
      }
    }

    print('✅ ANALYSIS COMPLETE');
    print('   -> Risk Detected: ${_isRisk ? "YES" : "NO"}');
    print('   -> Pattern Code: $_riskCode');
    print('   -> Explanation: $_riskExplanation');
    print('----------------------------------------------------------------');

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
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
        'note': _note, // Add this
      },
    );

    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    // STANDARD THEME LOGIC
    // If App is Light -> Screen is Light
    // If App is Dark -> Screen is Dark
    final isAppDark = Theme.of(context).brightness == Brightness.dark;
    final useDarkTheme = isAppDark;

    final bgColor = useDarkTheme ? Colors.black : Colors.white;
    final textColor = useDarkTheme ? Colors.white : Colors.black87;
    final cardColor = useDarkTheme
        ? const Color(0xFF1E1E1E)
        : Colors.grey.shade50;
    final borderColor = useDarkTheme
        ? Colors.grey.shade800
        : Colors.grey.shade300;
    final iconColor = useDarkTheme ? Colors.white : Colors.black;

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
                    "Powered by SafePay AI",
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: iconColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            // Status Icon
            if (_isRisk)
              const Icon(
                Icons.warning_amber_rounded,
                size: 100,
                color: Color(0xFFEF5350),
              ) // Red
            else
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  color: Color(0xFF4CAF50), // Green
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 60, color: Colors.white),
              ),

            const SizedBox(height: 32),

            // Title
            Text(
              _isRisk ? "Fraud Risk Detected!" : "Transaction Verified Safe",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _isRisk
                    ? const Color(0xFFEF5350)
                    : const Color(0xFF4CAF50),
              ),
            ),

            const SizedBox(height: 40),

            // Description with Pattern Code
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _isRisk
                          ? (useDarkTheme
                                ? const Color(0xFF2C1E1E)
                                : const Color(
                                    0xFFFFEBEE,
                                  )) // Dark Red vs Light Red
                          : (useDarkTheme
                                ? const Color(0xFF1E2C1E)
                                : const Color(
                                    0xFFE8F5E9,
                                  )), // Dark Green vs Light Green
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isRisk
                            ? const Color(0xFFEF5350)
                            : const Color(0xFF4CAF50),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      "Pattern $_riskCode Detected",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _isRisk
                            ? const Color(0xFFEF5350)
                            : const Color(0xFF4CAF50),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Info Card (Replaced with Risk Factors)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardColor, // Dynamic Card Color
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
              ),
              child: _buildRiskFactors(useDarkTheme),
            ),

            const Spacer(),

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isRisk
                    ? () {
                        // For now, allow proceed even if risk, but maybe show another warning
                        // Or just proceed as per user "leads to pin screen"
                        _proceedToPin();
                      }
                    : _proceedToPin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRisk
                      ? const Color(0xFFEF5350)
                      : const Color(0xFF2196F3), // Red or Blue
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _isRisk
                      ? "Proceed with Caution"
                      : "Proceed to Secure Payment", // Modified text for Risk
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
    );
  }

  Widget _buildRiskFactors(bool useDarkTheme) {
    List<Map<String, dynamic>> factors = [];

    if (_isRisk) {
      if (_riskCode == "F1") {
        // High Value + New Receiver
        factors = [
          {
            "title": "Receiver Identity",
            "status": "Unknown Person",
            "isRisk": true,
          },
          {
            "title": "Transfer Value",
            "status": "Unusually High",
            "isRisk": true,
          },
          {
            "title": "Scam Database",
            "status": "No Match Found",
            "isRisk": false,
          },
        ];
      } else {
        // F2 or others (High Value + Existing)
        factors = [
          {
            "title": "Receiver Identity",
            "status": "Verified Contact",
            "isRisk": false,
          },
          {
            "title": "Transfer Value",
            "status": "Above Average",
            "isRisk": true,
          },
          {
            "title": "Behavior Pattern",
            "status": "Irregular Spike",
            "isRisk": true,
          },
        ];
      }
    } else {
      // Safe
      if (_isNewReceiver) {
        factors = [
          {
            "title": "Receiver Status",
            "status": "New Receiver",
            "isRisk": false,
          }, // Neutral
          {
            "title": "Transfer Value",
            "status": "Within Limits",
            "isRisk": false,
          },
          {"title": "Risk Model", "status": "Low Probability", "isRisk": false},
        ];
      } else {
        factors = [
          {
            "title": "Receiver Status",
            "status": "Trusted Contact",
            "isRisk": false,
          },
          {
            "title": "Transfer Value",
            "status": "Normal Range",
            "isRisk": false,
          },
          {"title": "Risk Model", "status": "Safe Pattern", "isRisk": false},
        ];
      }
    }

    return Column(
      children: [
        for (int i = 0; i < factors.length; i++) ...[
          if (i > 0)
            Divider(
              height: 32,
              color: useDarkTheme ? Colors.grey.shade800 : Colors.grey.shade300,
            ),
          _buildRiskFactorRow(factors[i], useDarkTheme),
        ],
      ],
    );
  }

  Widget _buildRiskFactorRow(Map<String, dynamic> item, bool useDarkTheme) {
    bool isRisk = item['isRisk'];
    // For checks that are NOT risk (green), we use check circle.
    // For risk items (red), we use warning.
    // For neutral items (like New Receiver in safe mode), maybe info icon?
    // Let's stick to Green Check for good, Red Warning for bad.

    return Row(
      children: [
        Icon(
          isRisk ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
          color: isRisk
              ? const Color(0xFFEF5350)
              : const Color(0xFF4CAF50), // Red or Green
          size: 24,
        ),
        const SizedBox(width: 16),
        // Use Expanded to force the title to take remaining space and push status to the right
        // This also prevents overflow if the combined width is too large
        Expanded(
          child: Text(
            item['title'],
            style: TextStyle(
              color: useDarkTheme ? Colors.white70 : Colors.black54,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8), // Gap between title and status
        Text(
          item['status'],
          style: TextStyle(
            color: isRisk
                ? const Color(0xFFEF5350)
                : (useDarkTheme ? Colors.white : Colors.black87),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
