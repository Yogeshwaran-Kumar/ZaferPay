import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// QR Awareness Dialog — shown whenever a QR scan leads to a personal account
// Risk codes: F58_QR_TO_PERSONAL_ACCOUNT_AWARENESS
//             F58_QR_PERSONAL_STRANGER_SPIKE
//             F58_QR_FRIEND_FIRST_TIME_DEBIT_NOTICE
// ─────────────────────────────────────────────────────────────────────────────

enum QrAwarenessLevel {
  /// Direct friend, first QR payment — soft debit notice only
  friendFirstTime,

  /// Stranger or FoF — full personal-account warning
  strangerOrFof,

  /// Stranger + first-time + high amount — high-risk warning
  strangerHighRisk,
}

class QrAwarenessDialog extends StatelessWidget {
  final QrAwarenessLevel level;
  final String receiverName;
  final double amount;

  const QrAwarenessDialog({
    super.key,
    required this.level,
    required this.receiverName,
    required this.amount,
  });

  /// Decide which level to show based on risk_reason codes returned by backend.
  static QrAwarenessLevel levelFromRiskReasons(List<String> violations) {
    if (violations.contains('F58_QR_PERSONAL_STRANGER_SPIKE')) {
      return QrAwarenessLevel.strangerHighRisk;
    }
    if (violations.contains('F58_QR_TO_PERSONAL_ACCOUNT_AWARENESS')) {
      return QrAwarenessLevel.strangerOrFof;
    }
    return QrAwarenessLevel.friendFirstTime;
  }

  /// Show the dialog and return true if user confirms, false if they cancel.
  static Future<bool> show(
    BuildContext context, {
    required QrAwarenessLevel level,
    required String receiverName,
    required double amount,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QrAwarenessDialog(
        level: level,
        receiverName: receiverName,
        amount: amount,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final config = _getConfig();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: config.bgColor,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          Icon(config.icon, color: config.iconColor, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              config.title,
              style: TextStyle(
                color: config.titleColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 20),
          Text(
            config.body,
            style: TextStyle(
              color: config.bodyColor,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          if (level == QrAwarenessLevel.strangerHighRisk) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade700),
              ),
              child: const Text(
                'Do NOT proceed if someone asked you to scan this code to '
                '"get a refund", "verify your account", or "claim a reward".',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
      actions: [
        // Cancel — always available
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          style: OutlinedButton.styleFrom(
            foregroundColor: config.cancelColor,
            side: BorderSide(color: config.cancelColor.withValues(alpha: 0.6)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: const Text('Go back'),
        ),
        // Confirm — present for all levels (not a hard block)
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: config.confirmBg,
            foregroundColor: config.confirmFg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: Text(config.confirmLabel),
        ),
      ],
    );
  }

  _DialogConfig _getConfig() {
    final amountStr = '₹${amount.toStringAsFixed(0)}';
    switch (level) {
      // ── Soft nudge for known friend paying via QR for the first time ──────
      case QrAwarenessLevel.friendFirstTime:
        return _DialogConfig(
          icon: Icons.info_outline,
          iconColor: Colors.blueAccent,
          titleColor: Colors.white,
          title: 'Confirm QR Payment',
          bgColor: const Color(0xFF1C2A3A),
          body:
              'You are about to PAY $receiverName via QR scan.\n\n'
              'Amount: $amountStr will be DEBITED from your account.\n\n'
              'This is a SEND — money goes to them, not to you.\n\n'
              'Tap Confirm only if you intended to pay this person.',
          bodyColor: Colors.white70,
          cancelColor: Colors.white54,
          confirmBg: Colors.blueAccent,
          confirmFg: Colors.white,
          confirmLabel: 'Yes, Pay $amountStr',
        );

      // ── Full warning for stranger or FoF ──────────────────────────────────
      case QrAwarenessLevel.strangerOrFof:
        return _DialogConfig(
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.orange,
          titleColor: Colors.orange.shade200,
          title: 'Personal Account — Not a Shop',
          bgColor: const Color(0xFF1F1800),
          body:
              'You are requesting to PAY $receiverName\n\n'
              'Scanning a QR code will DEBIT money FROM your account. '
              'This is not a merchant — it is a personal UPI account.\n\n'
              'Scammers show personal QR codes claiming you will RECEIVE '
              'money. That is not how UPI works. QR codes only SEND.\n\n'
              'Proceed only if you intend to send $amountStr to this person.',
          bodyColor: Colors.orange.shade100,
          cancelColor: Colors.orange.shade300,
          confirmBg: Colors.orange.shade700,
          confirmFg: Colors.white,
          confirmLabel: 'I understand, Pay $amountStr',
        );

      // ── High risk: stranger + first-time + large amount ───────────────────
      case QrAwarenessLevel.strangerHighRisk:
        return _DialogConfig(
          icon: Icons.dangerous_rounded,
          iconColor: Colors.red.shade300,
          titleColor: Colors.red.shade200,
          title: 'High Risk: First Payment to Unknown Person',
          bgColor: const Color(0xFF1A0000),
          body:
              'You have NEVER paid $receiverName before.\n\n'
              'Sending $amountStr to a stranger via QR is one of the most '
              'common scam methods reported in India.\n\n'
              'This is a personal account, not a verified merchant.',
          bodyColor: Colors.red.shade100,
          cancelColor: Colors.red.shade300,
          confirmBg: Colors.red.shade800,
          confirmFg: Colors.white,
          confirmLabel: 'I accept the risk, Pay $amountStr',
        );
    }
  }
}

class _DialogConfig {
  final IconData icon;
  final Color iconColor;
  final Color titleColor;
  final String title;
  final Color bgColor;
  final String body;
  final Color bodyColor;
  final Color cancelColor;
  final Color confirmBg;
  final Color confirmFg;
  final String confirmLabel;

  const _DialogConfig({
    required this.icon,
    required this.iconColor,
    required this.titleColor,
    required this.title,
    required this.bgColor,
    required this.body,
    required this.bodyColor,
    required this.cancelColor,
    required this.confirmBg,
    required this.confirmFg,
    required this.confirmLabel,
  });
}
