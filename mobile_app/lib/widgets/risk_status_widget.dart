import 'package:flutter/material.dart';

class RiskStatusWidget extends StatelessWidget {
  final bool isRisk;
  final bool isHighRisk;
  final String riskScore; // 'SAFE', 'WARN', 'HIGH'
  final String title;
  final String description;
  final List<Widget> riskFactors;
  final VoidCallback onProceed;
  final String proceedButtonText;
  final bool showBackButton;

  const RiskStatusWidget({
    super.key,
    required this.isRisk,
    this.isHighRisk = false,
    this.riskScore = 'SAFE',
    required this.title,
    required this.description,
    required this.riskFactors,
    required this.onProceed,
    this.proceedButtonText = "Proceed",
    this.showBackButton = true,
  });

  Color get _backgroundColor {
    if (riskScore == 'HIGH' || isHighRisk) {
      return const Color(0xFFEF5350); // Red
    }
    if (riskScore == 'WARN') return Colors.orange; // Orange
    return const Color(0xFF4CAF50); // Green
  }

  IconData get _statusIcon {
    if (riskScore == 'HIGH' || isHighRisk) return Icons.warning_amber_rounded;
    if (riskScore == 'WARN') return Icons.warning_amber_rounded;
    return Icons.check;
  }

  String get _statusLabel {
    if (riskScore == 'HIGH' || isHighRisk) return "CRITICAL RISK";
    if (riskScore == 'WARN') return "SECURITY WARNING";
    return "VERIFIED SAFE";
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
                if (showBackButton)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: Icon(Icons.close, color: iconColor),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                const SizedBox(height: 20),

                // Status Icon
                if (isRisk)
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 100,
                    color: _backgroundColor,
                  )
                else
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: _backgroundColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_statusIcon, size: 60, color: Colors.white),
                  ),

                const SizedBox(height: 32),

                // Title
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _backgroundColor,
                  ),
                ),

                const SizedBox(height: 40),

                // Description with Risk Details
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: [
                      // Risk Score Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _backgroundColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _backgroundColor,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          _statusLabel,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: _backgroundColor,
                          ),
                        ),
                      ),

                      // Risk Explanation
                      if (description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            description,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: isRisk
                                  ? _backgroundColor
                                  : secondaryTextColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Risk Insight Header
                if (isRisk)
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

                // Main Info Section (Dynamic Risk Factors)
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
                    children: riskFactors,
                  ),
                ),

                const SizedBox(height: 40),

                // Action Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: onProceed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRisk
                          ? _backgroundColor
                          : const Color(0xFF2196F3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      proceedButtonText,
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
}
