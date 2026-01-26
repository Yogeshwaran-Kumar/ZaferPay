import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'mcc_helper.dart';

class AmountScreen extends StatefulWidget {
  const AmountScreen({super.key});

  @override
  State<AmountScreen> createState() => _AmountScreenState();
}

class _AmountScreenState extends State<AmountScreen> {
  late String _receiverUpi;
  String? _receiverName;
  String? _category; // Domain/Category for merchants
  double? _balance; // User's current balance
  String? _currentUserUpi; // Current user's UPI ID
  bool _isSelfTransfer = false;
  String? _rawMcc;

  final ApiService _api = ApiService();
  final _amountController = TextEditingController();
  bool _isLoadingName = true;
  bool _userNotFound = false;
  bool _isAmountTooHigh = false;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_validateAmount);
  }

  @override
  void dispose() {
    _amountController.removeListener(_validateAmount);
    _amountController.dispose();
    super.dispose();
  }

  void _validateAmount() {
    final amountText = _amountController.text;
    if (amountText.isEmpty) {
      if (_isAmountTooHigh) {
        setState(() {
          _isAmountTooHigh = false;
        });
      }
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount != null && amount > 500000) {
      if (!_isAmountTooHigh) {
        setState(() {
          _isAmountTooHigh = true;
        });
      }
    } else {
      if (_isAmountTooHigh) {
        setState(() {
          _isAmountTooHigh = false;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _receiverUpi = args?['upi'] ?? '';
    _receiverName = args?['name']; // Can be passed directly
    _category = args?['category'];
    if (args != null) {
      if (args['senderBalance'] != null) {
        _balance = (args['senderBalance'] as num).toDouble();
      }
      if (args['senderUpi'] != null) {
        _currentUserUpi = args['senderUpi'];
      }
    }

    // Always resolve receiver in case it's a phone number that needs to be converted to UPI ID
    // Or if we need to verify the user exists
    if (_isLoadingName) {
      _resolveReceiverAndName();
    }
  }

  Future<void> _resolveReceiverAndName() async {
    // 1. Fetch current user info (Optimized: Check preloaded args first)
    if (_balance == null || _currentUserUpi == null) {
      final userData = await _api.getMe();
      if (mounted && userData != null && userData['balance'] != null) {
        setState(() {
          _balance = (userData['balance'] as num).toDouble();
          _currentUserUpi = userData['upi_id'];
        });
        debugPrint(
          'DEBUG AMOUNT: Fetched balance = $_balance, currentUserUpi = $_currentUserUpi',
        );
      }
    }

    // Check if _receiverUpi looks like a phone number (mostly digits)
    final digitsOnly = _receiverUpi.replaceAll(RegExp(r'[^\d]'), '');
    final isPhoneNumber =
        !_receiverUpi.contains('@') &&
        digitsOnly.length >= 10 &&
        RegExp(r'^\d+$').hasMatch(digitsOnly);

    debugPrint(
      'DEBUG AMOUNT: _receiverUpi="$_receiverUpi", digitsOnly="$digitsOnly", isPhoneNumber=$isPhoneNumber',
    );

    Map<String, dynamic>? info;

    // Check local cache first for instant resolution
    Map<String, dynamic>? cachedUser;
    if (isPhoneNumber) {
      // For phone numbers, we might not have a direct cache unless we implement phone-to-upi mapping cache
      // But if we have a user cache by UPI, we might miss it here.
      // For now, let's skip cache for phone numbers unless we add that specific cache.
    } else {
      cachedUser = await _api.getCachedUser(_receiverUpi);
    }

    if (cachedUser != null) {
      debugPrint('DEBUG AMOUNT: Found user in cache: $cachedUser');
      info = cachedUser;
      _userNotFound = false;
    } else {
      // Network Lookup (Fallback)
      if (isPhoneNumber) {
        // RAM Cache for Phone -> UPI mapping?
        // We can add a simple caching layer for phone lookups in ApiService too
        // For now, try to find in general user cache if we know the UPI

        final phoneLast10 = digitsOnly.length >= 10
            ? digitsOnly.substring(digitsOnly.length - 10)
            : digitsOnly;

        // 1. Try RAM Cache for Phone Lookup
        info = _api.getCachedUserByPhoneSync(phoneLast10);

        if (info == null) {
          debugPrint('DEBUG AMOUNT: Looking up phone last10="$phoneLast10"');
          info = await _api.lookupUserByPhone(phoneLast10);
        }

        debugPrint('DEBUG AMOUNT: Phone lookup result: $info');

        if (info != null && info['upi_id'] != null) {
          // Update _receiverUpi to actual UPI ID (critical for payment to work!)
          debugPrint('DEBUG AMOUNT: Found UPI ID: ${info['upi_id']}');
          setState(() {
            _receiverUpi = info!['upi_id'];
            // Also update name if not already set
            if (_receiverName == null || _receiverName!.isEmpty) {
              _receiverName = info['username'];
            }
            _userNotFound = false; // User confirmed found
          });
          // cache this user for future UPI lookups
          _api.getCachedUser(
            _receiverUpi,
          ); // This effectively caches it if we implemented writing in lookup
        } else {
          debugPrint('DEBUG AMOUNT: No UPI ID found for phone');
          setState(() {
            _userNotFound = true;
          });
        }
      } else {
        // Not a phone number - regular UPI lookup
        info = await _api.lookupUser(_receiverUpi);
        if (info == null) {
          setState(() {
            _userNotFound = true;
          });
        } else {
          setState(() {
            _userNotFound = false;
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        if (info != null) {
          // Set name if not already set

          if (_receiverName == null || _receiverName!.isEmpty) {
            _receiverName = info['username'];
          }
          if (info['mcc'] != null && info['mcc'] != '0000') {
            _rawMcc = info['mcc'];
            _category = MccHelper.getDomain(info['mcc']);
          }
        }
        _isLoadingName = false;

        // Check for self-transfer
        if (!_userNotFound &&
            _currentUserUpi != null &&
            _receiverUpi == _currentUserUpi) {
          debugPrint('DEBUG AMOUNT: Self transfer detected');
          _isSelfTransfer = true;
        } else {
          _isSelfTransfer = false;
        }
      });
    }
  }

  Future<void> _onPayPressed() async {
    if (_isSelfTransfer || _isAmountTooHigh) return;

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter valid amount")));
      return;
    }

    // Balance Validation
    if (_balance != null && amount > _balance!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Insufficient balance. Available: ₹${_balance!.toStringAsFixed(2)}",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await Navigator.pushNamed(
      context,
      '/payment-pin',
      arguments: {
        'receiverUpi': _receiverUpi,
        'amount': amount,
        'name': _receiverName ?? _receiverUpi, // Pass name or fallback to UPI
        'category': _category, // Pass category
        'mcc': _rawMcc,
      },
    );

    if (result != null && result is Map<String, dynamic>) {
      if (mounted) {
        _showResultDialog(result);
      }
    }
  }

  void _showResultDialog(Map<String, dynamic> result) {
    if (result.containsKey('detail')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result['detail'])));
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = result['status'];
    final risk = result['risk_score'];

    // Determine color and icon based on status
    Color color = const Color(0xFF4CAF50); // Material Green 500
    IconData icon = Icons.check_circle_rounded;
    String title = "Payment Successful";
    Color bgColor = isDark
        ? const Color(0xFF424242)
        : Colors.white; // Dark gray in dark mode

    if (status == "BLOCKED") {
      color = const Color(0xFFE53935); // Red 600
      icon = Icons.block_rounded;
      title = "Transaction Blocked";
    } else if (status == "FAILED") {
      color = const Color(0xFFE53935);
      icon = Icons.error_rounded;
      title = "Payment Failed";
    } else if (risk == "WARN") {
      color = const Color(0xFFFB8C00); // Orange 600
      icon = Icons.warning_rounded;
      title = "Warning Detected";
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon Circle with Pulse Effect (simulated vs static)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.1),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.2),
                  ),
                  child: Icon(icon, size: 48, color: color),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              if (status == "SUCCESS") ...[
                Text(
                  "₹${result['amount']}",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 24),
                // Transaction Details Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF303030)
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "To",
                            style: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _receiverName ?? _receiverUpi,
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24, thickness: 0.5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Transaction ID",
                            style: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            result['transaction_id']?.toString().substring(
                                  0,
                                  12,
                                ) ??
                                "N/A",
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Error Case
                Text(
                  "Your transaction could not be completed.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.grey[800]
                        : Colors.black, // Sleek black/dark button
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.pop(context); // Close Dialog
                    Navigator.pop(context, result); // Go back to Home
                  },
                  child: const Text(
                    "Done",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "Make Payment",
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color,
          ),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        iconTheme: Theme.of(context).iconTheme,
      ),
      resizeToAvoidBottomInset: true,
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: isDark
                ? Colors.grey.shade800
                : Colors.grey.shade200,
            child: Text(
              _receiverName != null && _receiverName!.isNotEmpty
                  ? _receiverName![0].toUpperCase()
                  : (_receiverUpi.isNotEmpty
                        ? _receiverUpi[0].toUpperCase()
                        : '?'),
              style: TextStyle(
                fontSize: 32,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              "Paying to",
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          Center(
            child: Text(
              _receiverName ?? _receiverUpi,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          if (_category != null)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.2)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.blue.shade400 : Colors.blue.shade200,
                  ),
                ),
                child: Text(
                  _category!,
                  style: TextStyle(
                    color: isDark ? Colors.blue.shade200 : Colors.blue.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else if (_receiverName != null)
            Center(
              child: Text(
                _receiverUpi,
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            ),

          // Show error if user not found
          if (_userNotFound)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: Text(
                  "External UPI ID",
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // Show error if self-transfer
          if (_isSelfTransfer)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: Text(
                  "can't able to self transfer",
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 40),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              MaxValueTextInputFormatter(
                500000,
                onMaxValueExceeded: () {
                  if (!_isAmountTooHigh) {
                    setState(() {
                      _isAmountTooHigh = true;
                    });
                  }
                },
              ),
            ], // Block > 500k
            readOnly: _isSelfTransfer, // Allow input for userNotFound
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: (_isSelfTransfer)
                  ? Colors.grey
                  : (isDark ? Colors.white : Colors.black),
            ),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              prefixText: "₹ ",
              hintText: "0",
              border: InputBorder.none,
            ),
          ),
          if (_isAmountTooHigh)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  "Amount can't be more than 500000",
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: (_isSelfTransfer || _isAmountTooHigh)
                ? null
                : _onPayPressed,
            icon: const Icon(Icons.send),
            label: const Text("Pay Now"),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: isDark ? Colors.white : Colors.black,
              foregroundColor: isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MaxValueTextInputFormatter extends TextInputFormatter {
  final double maxValue;
  final VoidCallback? onMaxValueExceeded;

  MaxValueTextInputFormatter(this.maxValue, {this.onMaxValueExceeded});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final newDouble = double.tryParse(newValue.text);
    if (newDouble == null) {
      return oldValue; // Revert if not a number
    }

    if (newDouble > maxValue) {
      onMaxValueExceeded?.call(); // Notify callback
      return oldValue; // Revert if > maxValue
    }

    return newValue; // Allow
  }
}
