import 'package:flutter/material.dart';
import 'processing_shield_screen.dart';

class PaymentPinScreen extends StatefulWidget {
  final String receiverUpi;
  final double amount;
  final String receiverName;
  final String? category;
  final String? mcc;

  const PaymentPinScreen({
    super.key,
    required this.receiverUpi,
    required this.amount,
    required this.receiverName,
    this.category,
    this.mcc,
  });

  @override
  State<PaymentPinScreen> createState() => _PaymentPinScreenState();
}

class _PaymentPinScreenState extends State<PaymentPinScreen> {
  String _enteredPin = '';

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
    // Navigate to Visual Security Flow (Phase 3)
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ProcessingShieldScreen(
          receiverUpi: widget.receiverUpi,
          amount: widget.amount,
          receiverName: widget.receiverName,
          pin: _enteredPin,
          category: widget.category,
          mcc: widget.mcc,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine icon based on category (Merchant/Store vs Personal)
    // If category is present, it's likely a merchant.
    final bool isMerchant =
        widget.category != null && widget.category!.isNotEmpty;
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
                            "₹${widget.amount}",
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
              'Enter your PIN',
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
                          borderRadius: BorderRadius.circular(24),
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
                          borderRadius: BorderRadius.circular(24),
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
            borderRadius: BorderRadius.circular(32),
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
