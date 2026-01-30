import 'utils.dart';
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
  String? _contactName; // Name from Contacts/Args
  String? _bankingName; // Name from Banking (API)
  String? _category; // Domain/Category for merchants
  double? _balance; // User's current balance
  String? _currentUserUpi; // Current user's UPI ID
  bool _isSelfTransfer = false;
  String? _rawMcc;

  final ApiService _api = ApiService();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController(); // Add this
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
    _noteController.dispose(); // Add this
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
    _contactName = args?['name']; // Store Contact Name from Args
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
            // Store banking name
            _bankingName = info['username'];
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
          // Set banking name
          _bankingName = info['username'];

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
    if (amount == null || amount < 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Minimum amount is ₹1")));
      return;
    }

    // Balance Validation
    if (_balance != null && amount > _balance!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Insufficient balance. Available: ₹${formatAmount(_balance)}",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await Navigator.pushNamed(
      context,
      '/risk-analysis', // Go to Risk Analysis first
      arguments: {
        'receiverUpi': _receiverUpi,
        'amount': amount,
        'name':
            _bankingName ??
            _contactName ??
            _receiverUpi, // Prefer Banking > Contact for Risk? Or Display?
        // Risk screen likely wants the "True" name, which is Banking.
        // But keeping logical consistency.
        'category': _category,
        'mcc': _rawMcc,
        'note': _noteController.text.trim(), // Pass Note
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
    } else if (status == "SECURITY_RISK") {
      // PHASE 2 ALERT: Integrity/HMAC Failure
      color = const Color(0xFFD32F2F); // Darker Red
      icon = Icons.security_rounded;
      title = "Security Alert";
    } else if (status == "FRAUD_BLOCKED") {
      // PHASE 1 ALERT: AI Block
      color = const Color(0xFFC62828); // Sharp Red
      icon = Icons.gpp_bad_rounded;
      title = "Fraud Detected";
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
                  "₹${formatAmount(result['amount'])}",
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
                            _contactName ?? _bankingName ?? _receiverUpi,
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
    // Determine Theme Colors to match "Safe Pay" aesthetic
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Background: Deep Slate Blue (like screenshot) or White
    final bgColor = isDark ? const Color(0xFF0F1115) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey[600];

    // Logic for Name Display
    final displayContactName = _contactName ?? _bankingName ?? _receiverUpi;
    final displayBankingName =
        _bankingName ??
        (!_userNotFound && _bankingName != null ? _bankingName : null);

    // Initial for Avatar
    final initial = displayContactName.isNotEmpty
        ? displayContactName[0].toUpperCase()
        : "?";

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Optional: Help/Feedback icon if needed, usually top right
        ],
      ),
      // Use floating action button for the 'Proceed' action to match screenshot style
      floatingActionButton: FloatingActionButton(
        onPressed: (_isSelfTransfer || _isAmountTooHigh) ? null : _onPayPressed,
        backgroundColor: (_isSelfTransfer || _isAmountTooHigh)
            ? Colors.grey
            : const Color(0xFF00B9F1), // Brand Cyan/Blue
        elevation: 4,
        child: const Icon(Icons.arrow_forward, color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),

            // 1. Receiver Info Section (Top)
            Center(
              child: Column(
                children: [
                  // Avatar
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFF0078FF,
                      ), // Google Blue style avatar
                      shape: BoxShape.circle,
                      border: Border.all(color: bgColor, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 28,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // "Paying [Name]" (Contact Name preferred)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Paying ",
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        displayContactName,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // "Banking name: [Name]" + Verified Tick
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!_userNotFound) ...[
                        Text(
                          "Banking name: ${displayBankingName ?? 'Verified Merchant'}",
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified,
                          color: Colors.greenAccent, // Verified tick
                          size: 14,
                        ),
                      ] else ...[
                        Text(
                          "Banking name: Unknown",
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Mobile / UPI ID
                  Text(
                    _receiverUpi, // e.g. "PhonePe • ...@ibl"
                    style: TextStyle(color: secondaryTextColor, fontSize: 13),
                  ),

                  // Self-transfer warning
                  if (_isSelfTransfer)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        "Cannot transfer to self",
                        style: TextStyle(color: Colors.red[300], fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),

            // 2. Amount Input Section (Middle - Expanded)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Amount TextField
                    IntrinsicWidth(
                      child: TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        autofocus: true, // Open keyboard immediately
                        inputFormatters: [
                          MaxValueTextInputFormatter(
                            500000,
                            onMaxValueExceeded: () {
                              if (!_isAmountTooHigh) {
                                setState(() => _isAmountTooHigh = true);
                              }
                            },
                          ),
                        ],
                        style: TextStyle(
                          color: textColor,
                          fontSize: 64, // Large text like screenshot
                          fontWeight: FontWeight.normal,
                        ),
                        decoration: InputDecoration(
                          filled:
                              false, // Prevent theme from adding background color
                          prefixText: "₹ ",
                          prefixStyle: TextStyle(
                            color: textColor,
                            fontSize: 64,
                            fontWeight: FontWeight.normal,
                          ),
                          hintText: "0",
                          hintStyle: TextStyle(
                            color: isDark ? Colors.grey[700] : Colors.grey[300],
                            fontSize: 64,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),

                    // Amount Too High Warning
                    if (_isAmountTooHigh)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          "Max limit: ₹5,00,000",
                          style: TextStyle(
                            color: Colors.red[300],
                            fontSize: 12,
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    // "Add note" Pill Button
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2630)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: IntrinsicWidth(
                        child: TextField(
                          controller: _noteController,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            filled: false,
                            isDense: true,
                            hintText: "Add note",
                            hintStyle: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Security Badge / Bottom Info (Always Visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: Colors.blue[300],
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "Powered by SafePay",
                    style: TextStyle(color: Colors.blue[300], fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
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

    // Block leading '0' or '.' to enforce amount >= 1
    if (newValue.text.startsWith('0') || newValue.text.startsWith('.')) {
      return oldValue;
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
