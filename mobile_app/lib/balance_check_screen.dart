import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';

class BalanceCheckScreen extends StatefulWidget {
  final String mobileNumber;

  const BalanceCheckScreen({super.key, required this.mobileNumber});

  @override
  State<BalanceCheckScreen> createState() => _BalanceCheckScreenState();
}

class _BalanceCheckScreenState extends State<BalanceCheckScreen> {
  final _api = ApiService();
  String _enteredPin = '';
  bool _isLoading = false;
  bool _isSuccess = false;
  int _pinAttempts = 0;

  @override
  void initState() {
    super.initState();
    _loadCachedBalance();
  }

  Future<void> _loadCachedBalance() async {
    final cached = await _api.getCachedBalance();
    if (mounted && cached != null) {
      // Just log/debug, or if we wanted to show it on this screen we could.
      // But this screen is for PIN entry to REVEAL balance.
      // The showing of balance happens in MoneyScreen.
      // Wait, MoneyScreen calls this screen, awaits result, then shows balance.
      // So this screen verifies PIN.
      // User request: "balance checking loading page"
      // This means the process of verify PIN -> Loading -> Result.
      // We can't pre-verify PIN. But we can make the transition faster.
    }
  }

  void _handleKeyPress(String value) {
    if (_enteredPin.length < 4) {
      setState(() {
        _enteredPin += value;
      });
    }
  }

  void _handleBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  Future<void> _handleIncorrectPin() async {
    setState(() {
      _pinAttempts++;
      _enteredPin = ''; // Reset PIN field
    });

    if (_pinAttempts == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect PIN. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    } else if (_pinAttempts == 2) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Security Warning"),
          content: const Text(
            "Warning: You have tried too many times. One more failed attempt will log you out.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("I Understand"),
            ),
          ],
        ),
      );
    } else if (_pinAttempts >= 3) {
      _handleLockedOut();
    }
  }

  Future<void> _handleLockedOut() async {
    // 3rd Strike -> Logout with Dialog
    showDialog(
      context: context,
      barrierDismissible: false, // User cannot close this
      builder: (ctx) => const AlertDialog(
        title: Text("Account Locked"),
        content: Text(
          "Too many incorrect attempts so your account has been logged out.",
        ),
      ),
    );

    // Wait for user to read it
    await Future.delayed(const Duration(seconds: 4));

    await _api.logout();

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<void> _verifyPin() async {
    if (_enteredPin.length != 4) return;

    // 1. Zero Latency Local Check (Smart)
    final status = await _api.verifyPinSmart(_enteredPin);

    if (status == PinVerificationStatus.success) {
      if (mounted) {
        setState(() => _isSuccess = true);
        // Instant success!
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) Navigator.pop(context, true);
        return;
      }
    } else if (status == PinVerificationStatus.incorrect) {
      // Instant Fail (0.0s)
      if (mounted) _handleIncorrectPin();
      return;
    } else if (status == PinVerificationStatus.lockedOut) {
      // Instant Logout (0.0s)
      if (mounted) _handleLockedOut();
      return;
    }

    // Fallback: If status is unknown (no cache), try Server
    setState(() => _isLoading = true);

    // 2. Server Fallback
    final error = await _api.login(
      widget.mobileNumber,
      _enteredPin,
      forceLogin: false,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (error == null) {
      setState(() => _isSuccess = true);
      // Show success animation briefly then pop
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.pop(context, true);
      }
    } else {
      if (error == 'INCORRECT_PIN') {
        _handleIncorrectPin();
        return;
      }

      // Other errors
      setState(() => _enteredPin = '');

      String msg = error;
      if (error == 'RATE_LIMIT_EXCEEDED') {
        msg = 'Too many attempts. Try again later.';
      } else if (error == 'LOGGED_IN_ELSEWHERE') {
        msg = 'Logged in on another device';
      } else if (error == 'CONNECTION_ERROR') {
        msg = 'Network connection failed';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(
              Icons.close,
              color: Theme.of(context).iconTheme.color,
              size: 28,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Message
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF3F4F6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'You are checking your account balance',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1F2937),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Icon(
                    Icons.currency_rupee,
                    size: 20,
                    color: isDark ? Colors.white : const Color(0xFF5F259F),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(flex: 1),

          // Center Content
          if (_isSuccess)
            Column(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF5F259F),
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'Verified',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF5F259F),
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                Text(
                  'Enter your PIN',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 32),
                // PIN Dots
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
                            ? (isDark ? Colors.white : const Color(0xFF1F2937))
                            : (isDark ? Colors.grey.shade800 : Colors.white),
                        border: Border.all(
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1F2937),
                          width: 1.5,
                        ),
                      ),
                    );
                  }),
                ),
                if (_isLoading) ...[
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(color: Color(0xFF5F259F)),
                ],
              ],
            ),

          const Spacer(flex: 2),

          // Warning
          Padding(
            padding: const EdgeInsets.all(16.0),
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
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: isDark
                        ? Colors.grey.shade400
                        : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),

          // Keypad Area
          SafeArea(
            child: Container(
              color: isDark
                  ? Theme.of(context).scaffoldBackgroundColor
                  : const Color(0xFFF9FAFB),
              padding: const EdgeInsets.only(bottom: 24, top: 12),
              child: Column(
                children: [
                  ...List.generate(3, (row) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(3, (col) {
                          final number = (row * 3 + col + 1).toString();
                          return _buildKey(number, isDark);
                        }),
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Backspace
                        InkWell(
                          onTap: () => _handleBackspace(),
                          borderRadius: BorderRadius.circular(30),
                          child: Container(
                            width: 80,
                            height: 60,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey.shade800
                                  : const Color(0xFFE5E7EB),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Icon(
                              Icons.backspace_outlined,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        // Zero
                        _buildKey('0', isDark),
                        // Check/Submit
                        InkWell(
                          onTap: _verifyPin,
                          borderRadius: BorderRadius.circular(30),
                          child: Container(
                            width: 80,
                            height: 60,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Text(
                              'Check',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String number, bool isDark) {
    return InkWell(
      onTap: () => _handleKeyPress(number),
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 80,
        height: 60,
        alignment: Alignment.center,
        child: Text(
          number,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
