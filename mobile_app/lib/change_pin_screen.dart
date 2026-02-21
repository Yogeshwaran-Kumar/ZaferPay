import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _api = ApiService();
  static const _securityChannel = MethodChannel('com.company.safepay/security');
  String _enteredPin = '';
  String _firstPin = '';
  String _currentPin = '';
  String _username = '';
  // 0: Enter Current PIN
  // 1: Enter New PIN
  // 2: Confirm New PIN
  int _step = 0;
  bool _isLoading = false;
  String _upiId = '';
  int _pinAttempts = 0;

  @override
  void initState() {
    super.initState();
    _secureScreen();
    _fetchUser();
  }

  Future<void> _secureScreen() async {
    try {
      await _securityChannel.invokeMethod('secureScreen');
    } catch (_) {}
  }

  Future<void> _removeSecureScreen() async {
    try {
      await _securityChannel.invokeMethod('unsecureScreen');
    } catch (_) {}
  }

  Future<void> _fetchUser() async {
    final user = await _api.getMe();
    if (user != null && mounted) {
      setState(() {
        _upiId = user['upi_id'] ?? '';
        _username = user['username'] ?? '';
      });
    }
  }

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
            _handlePinComplete();
          }
        }
      }
    });
  }

  Future<void> _handlePinComplete() async {
    if (_step == 0) {
      // Step 0: Verify Current PIN
      await _verifyCurrentPin();
    } else if (_step == 1) {
      // Step 1: Finished entering NEW PIN
      setState(() {
        _firstPin = _enteredPin;
        _enteredPin = '';
        _step = 2; // Move to Confirm
      });
    } else if (_step == 2) {
      // Step 2: Finished Confirmation
      if (_enteredPin == _firstPin) {
        // Validation: New PIN cannot be same as Old PIN is handled by backend usually,
        // but user requirement doesn't specify.
        // Match! Call API
        await _changePinOnServer();
      } else {
        // Mismatch
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PIN mismatch! Please enter new PIN again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
        // Requirement: "asked again to enter the new pin and conform pin"
        setState(() {
          _enteredPin = '';
          _firstPin = '';
          _step = 1; // Restart New PIN entry
        });
      }
    }
  }

  Future<void> _handleIncorrectPin() async {
    setState(() {
      _pinAttempts++;
      _enteredPin = ''; // Reset
    });

    if (_pinAttempts == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect Current PIN'),
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

    await Future.delayed(const Duration(seconds: 4));
    await _api.logout();

    if (!mounted) return;
    _removeSecureScreen();
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<void> _verifyCurrentPin() async {
    if (_username.isEmpty) {
      // Should catch this edge case
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: User details not loaded')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // We use the login endpoint to verify the PIN
    final error = await _api.login(_username, _enteredPin, forceLogin: false);

    setState(() => _isLoading = false);

    if (error == null) {
      // Success - PIN is correct, save it for backend verification
      setState(() {
        _currentPin = _enteredPin;
        _enteredPin = '';
        _step = 1; // Move to New PIN
      });
    } else {
      // Failed
      if (mounted) _handleIncorrectPin();
    }
  }

  Future<void> _changePinOnServer() async {
    setState(() => _isLoading = true);
    final success = await _api.changePin(_currentPin, _enteredPin);
    setState(() => _isLoading = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN Changed Successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _removeSecureScreen();
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to change PIN. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
        // On server failure, maybe just reset current step?
        // Or restart whole flow? Let's restart New PIN flow to be safe.
        setState(() {
          _enteredPin = '';
          _firstPin = '';
          _step = 1;
        });
      }
    }
  }

  String get _title {
    switch (_step) {
      case 0:
        return "Enter Current PIN";
      case 1:
        return "Enter New PIN";
      case 2:
        return "Confirm New PIN";
      default:
        return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).iconTheme.color,
          ),
          onPressed: () {
            _removeSecureScreen();
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Section
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
                    Text(
                      _title,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_upiId.isNotEmpty)
                      Text(
                        _upiId,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.grey[400] : Colors.black54,
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

            // Keypad
            Expanded(
              flex: 3,
              child: Container(
                color: isDark ? Colors.grey[900] : Colors.grey[50],
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
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Center(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceKey() {
    return Expanded(
      child: InkWell(
        onTap: () => _onKeypadTap('BACK'),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Center(
          child: Icon(
            Icons.backspace_outlined,
            size: 28,
            color: Theme.of(context).iconTheme.color,
          ),
        ),
      ),
    );
  }
}
