import 'package:flutter/material.dart';
import 'api_service.dart';

class PaymentPinScreen extends StatefulWidget {
  final String receiverUpi;
  final double amount;
  final String receiverName; // Add this

  const PaymentPinScreen({
    super.key,
    required this.receiverUpi,
    required this.amount,
    required this.receiverName, // Add this
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
          if (_enteredPin.length == 4) {
            _verifyPin();
          }
        }
      }
    });
  }

  Future<void> _verifyPin() async {
    setState(() => _isLoading = true);

    try {
      final result = await _api.createTransaction(
        widget.receiverUpi,
        widget.amount,
        _enteredPin,
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (result.containsKey('detail') &&
            result['detail'] == 'Incorrect PIN') {
          _handleIncorrectPin();
        } else {
          // Success! Return result to PayScreen
          Navigator.pop(context, result);
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
      Navigator.of(context).popUntil(ModalRoute.withName('/home'));
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top Section: Info
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 48,
                      color: Color(0xFF6200EE),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Enter PIN to Pay',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Paying ₹${widget.amount} to',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.receiverName, // Show Name instead of UPI
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        final filled = index < _enteredPin.length;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled
                                ? const Color(0xFF6200EE)
                                : Colors.transparent,
                            border: Border.all(
                              color: const Color(0xFF6200EE),
                              width: 2,
                            ),
                          ),
                        );
                      }),
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 32),
                      const CircularProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom Section: Keypad
            Expanded(
              flex: 3,
              child: Container(
                color: Colors.grey[50],
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Expanded(
                      child: Row(
                        children: [
                          _buildKey('1'),
                          _buildKey('2'),
                          _buildKey('3'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          _buildKey('4'),
                          _buildKey('5'),
                          _buildKey('6'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          _buildKey('7'),
                          _buildKey('8'),
                          _buildKey('9'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          const Expanded(child: SizedBox()),
                          _buildKey('0'),
                          _buildBackspaceKey(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => Navigator.pop(context), // Cancel
                      child: const Text(
                        "Cancel Payment",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKey(String value) {
    return Expanded(
      child: InkWell(
        onTap: () => _onKeypadTap(value),
        child: Center(
          child: Text(
            value,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceKey() {
    return Expanded(
      child: InkWell(
        onTap: () => _onKeypadTap('BACK'),
        child: const Center(child: Icon(Icons.backspace_outlined, size: 28)),
      ),
    );
  }
}
