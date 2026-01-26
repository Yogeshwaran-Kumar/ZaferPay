import 'package:flutter/material.dart';
import 'api_service.dart';

class PaymentPinScreen extends StatefulWidget {
  final String receiverUpi;
  final double amount;
  final String receiverName;
  final String? category; // Add category
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
  final _api = ApiService();
  String _enteredPin = '';
  bool _isLoading = false;
  int _failedAttempts = 0;

  void _onKeypadTap(String value) {
    if (_isLoading) return;

    setState(() {
      if (value == 'BACK') {
        if (_enteredPin.isNotEmpty) {
          _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        }
      } else {
        if (_enteredPin.length < 4) {
          _enteredPin += value;
          // Removed auto-verify to allow Pay button usage
        }
      }
    });
  }

  // State for In-Place Success UI
  bool _showSuccess = false;

  Future<void> _verifyPin() async {
    setState(() => _isLoading = true);

    try {
      final result = await _api.createTransactionOptimistic(
        widget.receiverUpi,
        widget.amount,
        _enteredPin,
        mcc: widget.mcc,
        receiverName: widget.receiverName,
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (result.containsKey('detail') &&
            result['detail'] == 'Incorrect PIN') {
          // Instant Error (Local or Remote)
          _handleIncorrectPin();
        } else if (result['status'] == 'LOCKED') {
          // Instant Logout
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/login', (route) => false);
        } else if (result.containsKey('detail') &&
            result['status'] != 'SUCCESS') {
          // Other error
          _handleError(result['detail']);
        } else {
          // Success! Show Success Screen In-Place
          setState(() {
            _showSuccess = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _handleError(e.toString());
      }
    }
  }

  void _handleIncorrectPin() {
    _failedAttempts++;
    _enteredPin = ''; // Clear PIN

    if (_failedAttempts >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment Cancelled: Too many WRONG PIN attempts!'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      // Navigate to Home
      Navigator.of(context).popUntil((route) => route.settings.name == '/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect PIN! 1 Attempt remaining'),
          backgroundColor: Colors.orange,
          duration: Duration(milliseconds: 1500),
        ),
      );
    }
  }

  void _handleError(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Incorrect PIN'),
        backgroundColor: Colors.red,
      ),
    );
    _enteredPin = '';
  }

  @override
  Widget build(BuildContext context) {
    // If success, Show Success UI
    if (_showSuccess) {
      return _buildSuccessUI();
    }

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

            if (_isLoading) ...[
              const SizedBox(height: 24),
              const CircularProgressIndicator(strokeWidth: 2),
            ],

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
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
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

  Widget _buildSuccessUI() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = const Color(0xFF4CAF50); // Success Green

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Big Green Check
            ScaleTransition(
              scale: const AlwaysStoppedAnimation(
                1.0,
              ), // Could animate this later
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.1),
                ),
                child: Icon(Icons.check_circle, size: 80, color: color),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Payment Successful',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '₹${widget.amount}',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Paid to ${widget.receiverName}',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 64),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).popUntil((route) => route.settings.name == '/home');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.grey[800] : Colors.black,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
