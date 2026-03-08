import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'services/app_localizations.dart';

class ChangePinScreen extends StatefulWidget {
  final bool isMpin;
  final bool isSetOnly;
  final bool isDisableOnly;
  const ChangePinScreen({
    super.key,
    required this.isMpin,
    this.isSetOnly = false,
    this.isDisableOnly = false,
  });

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _api = ApiService();
  static const _securityChannel = MethodChannel(
    'com.company.zaferpay/security',
  );
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

  @override
  void initState() {
    super.initState();
    if (widget.isSetOnly) {
      _step = 1; // Skip Current PIN, go straight to New PIN
    }
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
            SnackBar(
              content: Text(
                AppLocalizations.of(context)?.translate('pin.mismatch') ??
                    'PIN mismatch! Please enter new PIN again.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
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
    if (!mounted) return;
    setState(() {
      _enteredPin = ''; // Reset
    });

    if (_api.failedAttempts == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.translate('pin.incorrect_current') ??
                'Incorrect Current PIN',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } else if (_api.failedAttempts == 2) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(
            AppLocalizations.of(context)?.translate('pin.security_warning') ??
                "Security Warning",
          ),
          content: Text(
            AppLocalizations.of(context)?.translate('pin.too_many_attempts') ??
                "Warning: You have tried too many times. One more failed attempt will log you out.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                AppLocalizations.of(context)?.translate('pin.i_understand') ??
                    "I Understand",
              ),
            ),
          ],
        ),
      );
    } else if (_api.failedAttempts >= 3) {
      _handleLockedOut();
    }
  }

  Future<void> _handleLockedOut() async {
    showDialog(
      context: context,
      barrierDismissible: false, // User cannot close this
      builder: (ctx) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)?.translate('pin.account_locked') ??
              "Account Locked",
        ),
        content: Text(
          AppLocalizations.of(context)?.translate('pin.account_locked_desc') ??
              "Too many incorrect attempts so your account has been logged out.",
        ),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 500));
    await _api.logout();

    if (!mounted) return;
    _removeSecureScreen();
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<void> _verifyCurrentPin() async {
    if (_username.isEmpty) {
      // Should catch this edge case
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.translate('pin.error_user_details') ??
                'Error: User details not loaded',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    if (widget.isMpin) {
      // Check if we are disabling the mPIN
      if (widget.isDisableOnly) {
        final success = await _api.disableMpin(_enteredPin);
        setState(() => _isLoading = false);

        if (success) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(
                      context,
                    )?.translate('pin.app_lock_disabled') ??
                    'App Lock disabled successfully!',
              ),
              backgroundColor: Colors.green,
            ),
          );
          _removeSecureScreen();
          Navigator.pop(context, true); // Return true to indicate change
        } else {
          if (mounted) _handleIncorrectPin();
        }
        return;
      }

      // We use the login endpoint to verify the mPIN
      final error = await _api.login(_username, _enteredPin, forceLogin: false);
      setState(() => _isLoading = false);

      if (error == null) {
        // Success - mPIN is correct, save it
        setState(() {
          _currentPin = _enteredPin;
          _enteredPin = '';
          _step = 1; // Move to New PIN
        });
      } else {
        // Failed
        if (error == 'LOCKED_OUT') {
          _handleLockedOut();
          return;
        }
        if (mounted) _handleIncorrectPin();
      }
    } else {
      // Verify UPI PIN
      final status = await _api.verifyUpiPin(_enteredPin);
      setState(() => _isLoading = false);

      if (status == PinVerificationStatus.success) {
        setState(() {
          _currentPin = _enteredPin;
          _enteredPin = '';
          _step = 1; // Move to New PIN
        });
      } else if (status == PinVerificationStatus.lockedOut) {
        _handleLockedOut();
      } else {
        if (mounted) _handleIncorrectPin();
      }
    }
  }

  Future<void> _changePinOnServer() async {
    setState(() => _isLoading = true);
    bool success = false;

    if (widget.isMpin) {
      if (widget.isSetOnly) {
        success = await _api.enableMpin(_enteredPin);
      } else {
        success = await _api.changeMpin(_currentPin, _enteredPin);
      }
    } else {
      success = await _api.changeUpiPin(_currentPin, _enteredPin);
    }

    setState(() => _isLoading = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.translate('pin.pin_changed') ??
                  'PIN Changed Successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _removeSecureScreen();
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.translate('pin.fail_change') ??
                  'Failed to change PIN. Try again.',
            ),
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
    if (widget.isDisableOnly) {
      return AppLocalizations.of(context)?.translate('pin.confirm_app_lock') ??
          "Confirm App Lock PIN";
    }
    String typeLabel = widget.isMpin
        ? (AppLocalizations.of(context)?.translate('pin.app_login_pin') ??
              "App Login PIN")
        : (AppLocalizations.of(context)?.translate('pin.upi_pin') ?? "UPI PIN");

    switch (_step) {
      case 0:
        return (AppLocalizations.of(context)?.translate('pin.enter_current') ??
                "Enter Current {type}")
            .replaceAll('{type}', typeLabel);
      case 1:
        return (AppLocalizations.of(context)?.translate('pin.enter_new') ??
                "Enter New {type}")
            .replaceAll('{type}', typeLabel);
      case 2:
        return (AppLocalizations.of(context)?.translate('pin.confirm_new') ??
                "Confirm New {type}")
            .replaceAll('{type}', typeLabel);
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
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00B9F1).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        size: 48,
                        color: Color(0xFF00B9F1),
                      ),
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
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          width: filled ? 20 : 16,
                          height: filled ? 20 : 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled
                                ? const Color(0xFF00B9F1)
                                : (isDark
                                      ? Colors.grey.shade800
                                      : Colors.grey.shade300),
                            border: Border.all(
                              color: filled
                                  ? const Color(0xFF00B9F1)
                                  : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow: filled
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF00B9F1,
                                      ).withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
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
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.4 : 0.05,
                      ),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    const SizedBox(height: 10),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildKey('1'),
                          _buildKey('2'),
                          _buildKey('3'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildKey('4'),
                          _buildKey('5'),
                          _buildKey('6'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildKey('7'),
                          _buildKey('8'),
                          _buildKey('9'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          const SizedBox(width: 75, height: 75),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => _onKeypadTap(value),
      borderRadius: BorderRadius.circular(40),
      splashColor: const Color(0xFF00B9F1).withValues(alpha: 0.2),
      highlightColor: const Color(0xFF00B9F1).withValues(alpha: 0.1),
      child: Container(
        width: 75,
        height: 75,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        ),
        alignment: Alignment.center,
        child: Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceKey() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => _onKeypadTap('BACK'),
      borderRadius: BorderRadius.circular(40),
      splashColor: Colors.red.withValues(alpha: 0.2),
      highlightColor: Colors.red.withValues(alpha: 0.1),
      child: Container(
        width: 75,
        height: 75,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.backspace_rounded,
          size: 28,
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        ),
      ),
    );
  }
}
