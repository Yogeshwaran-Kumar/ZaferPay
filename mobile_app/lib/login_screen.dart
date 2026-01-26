import 'package:flutter/material.dart';
import 'api_service.dart';

class LoginScreen extends StatefulWidget {
  final bool isUnlockMode;
  const LoginScreen({super.key, this.isUnlockMode = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobileController = TextEditingController();
  final _api = ApiService();

  // Steps:
  // 0 = Mobile Entry
  // 1 = Create PIN (Set PIN 1st time)
  // 2 = Confirm PIN (Set PIN 2nd time)
  // 3 = Login (Enter PIN)
  int _currentStep = 0;

  String _firstPin = ''; // Used during creation
  String _enteredPin = ''; // Current buffer
  String _upiId = ''; // User's UPI ID
  bool _isCheckingAuth = true;
  bool _isLoading = false;
  bool _forceLogoutApproved = false; // Track if user approved force logout

  // Status text for the PIN screen title
  String get _pinTitle {
    if (widget.isUnlockMode) return 'Unlock App';
    switch (_currentStep) {
      case 1:
        return 'Set New PIN';
      case 2:
        return 'Confirm PIN';
      case 3:
        return 'Enter PIN'; // Login
      default:
        return '';
    }
  }

  @override
  void initState() {
    super.initState();
    // In unlock mode, start directly at PIN screen (Step 3) to avoid flash of mobile entry
    if (widget.isUnlockMode) {
      _currentStep = 3;
      _isCheckingAuth = false; // Already "checked" implicitly by mode

      // 0. Sync RAM Fetch (0.0s Latency)
      // This ensures UPI ID appears in the very first frame if app is just resuming
      final user = _api.getUserSync();
      if (user != null) {
        _upiId = user['upi_id'] ?? '';
      }

      _populateCachedUserForUnlock();
    } else {
      _isCheckingAuth = true;
      // Always check for saved login to populate UPI ID and correct state
      _checkSavedLogin();
    }
  }

  Future<void> _populateCachedUserForUnlock() async {
    final savedMobile = await _api.getSavedMobile();
    if (mounted && savedMobile != null) {
      setState(() {
        _mobileController.text = savedMobile;
      });
      // Try to get cached UPI ID
      try {
        final user = await _api.getCachedMe();
        if (mounted && user != null) {
          setState(() {
            _upiId = user['upi_id'] ?? '';
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _checkSavedLogin() async {
    final savedMobile = await _api.getSavedMobile();
    if (savedMobile != null && savedMobile.isNotEmpty) {
      if (mounted) {
        // Zero Latency: Show PIN immediately
        // Try to get cached UPI ID for context
        try {
          final user = await _api.getCachedMe();
          if (user != null) {
            setState(() => _upiId = user['upi_id'] ?? '');
          }
        } catch (_) {}

        setState(() {
          _mobileController.text = savedMobile;
          _isLoading = false; // NO Spinner!
          _isCheckingAuth = false;
          _currentStep = 3; // Show PIN Pad Instantly
        });

        // Background Validity Check (Fire & Forget/Async Update)
        _api.checkMobile(savedMobile).then((result) async {
          if (!mounted) return;
          if (result['has_device_conflict'] == true) {
            // Oh no, conflict found. NOW we interrupt.
            await _api.removeSavedMobile();
            setState(() {
              _currentStep = 0; // Go back to mobile entry
              _mobileController.text = savedMobile;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Session expired (Device Conflict). Please login again.',
                  ),
                ),
              );
            }
          } else {
            if (result['upi_id'] != null) {
              setState(() => _upiId = result['upi_id']);
            }
          }
        });
      }
    } else {
      // No saved user, show login (Step 0)
      if (mounted) {
        setState(() {
          _isCheckingAuth = false;
          _isLoading = false; // Ensure no spinner even here
          _currentStep = 0;
        });
      }
    }
  }

  // Handle "Proceed Next" button
  Future<void> _handleMobileSubmit() async {
    final mobile = _mobileController.text.trim();
    final input = _mobileController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Mobile Number or Email'),
        ),
      );
      return;
    }

    // Basic validation: Check if it's alphanumeric (email) or digits (phone)
    // For now, we trust the backend to handle the lookup

    setState(() => _isLoading = true);

    final result = await _api.checkMobile(mobile);

    setState(() => _isLoading = false);

    if (result['status'] == 'new') {
      // User needs to set PIN (either new user or existing without PIN)
      setState(() {
        _currentStep = 1; // Create PIN
        _enteredPin = '';
        _upiId = result['upi_id'] ?? '';
      });
    } else if (result['exists'] == true && result['status'] == 'existing') {
      // Existing user - Check for device conflict
      final hasConflict = result['has_device_conflict'] == true;

      if (hasConflict) {
        // Show device conflict dialog BEFORE PIN entry
        setState(() {
          _upiId = result['upi_id'] ?? '';
        });
        if (mounted) {
          _showForceLoginDialogEarly();
        }
      } else {
        // No conflict - proceed to PIN entry
        setState(() {
          _currentStep = 3; // Enter PIN
          _enteredPin = '';
          _upiId = result['upi_id'] ?? '';
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['detail'] ?? 'Connection Error')),
        );
      }
    }
  }

  Future<void> _handlePinComplete() async {
    final pin = _enteredPin;

    if (_currentStep == 1) {
      // Create PIN -> Move to Confirm
      setState(() {
        _firstPin = pin;
        _currentStep = 2;
        _enteredPin = '';
      });
    } else if (_currentStep == 2) {
      // Confirm PIN
      if (pin == _firstPin) {
        // Match! Set PIN on backend
        setState(() => _isLoading = true);
        final success = await _api.setPin(_mobileController.text, pin);
        setState(() => _isLoading = false);

        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PIN Set Successfully! Login now.')),
            );
          }
          // Auto login after setting
          _login(force: false, pinToUse: pin);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to set PIN. Try again.')),
            );
          }
          // Reset to start
          setState(() {
            _currentStep = 1;
            _enteredPin = '';
            _firstPin = '';
          });
        }
      } else {
        // Mismatch
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN mismatch'),
            backgroundColor: Colors.red,
          ),
        );
        // Reset to Step 1 (Create PIN) as per requirement "asked again 2 times"
        setState(() {
          _currentStep = 1;
          _enteredPin = '';
          _firstPin = '';
        });
      }
    } else if (_currentStep == 3) {
      // Standard Login - use force flag based on earlier decision
      _login(force: _forceLogoutApproved, pinToUse: pin);
    }
  }

  Future<void> _login({bool force = false, String? pinToUse}) async {
    final pin = pinToUse ?? _enteredPin;

    // 0. Smart Local Verify (Zero Latency)
    // Only attempt fast path if we are NOT forcing a logout/login sequence
    if (!force) {
      final status = await _api.verifyPinSmart(pin);

      if (status == PinVerificationStatus.success) {
        if (mounted) {
          if (widget.isUnlockMode) {
            Navigator.pop(context); // Instant unlock
          } else {
            Navigator.pushReplacementNamed(
              context,
              '/home',
            ); // Instant Home load
          }
          return;
        }
      } else if (status == PinVerificationStatus.incorrect) {
        setState(() => _enteredPin = ''); // Clear PIN locally
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Incorrect PIN'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 1), // Fast dismissal
            ),
          );
        }
        return; // Stop here, do NOT call network
      } else if (status == PinVerificationStatus.lockedOut) {
        // verifyPinSmart already triggers logout()
        // We just need to navigate to Login (Reset)
        if (mounted) {
          // If unlock mode, we are basically already at login screen but modal.
          // We should dismiss modal and go to full login?
          // Or just reset UI to Step 0?
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/login', (route) => false);
        }
        return;
      }
      // If PinVerificationStatus.unknown, we fall through to network check (below)
    }

    setState(() => _isLoading = true);

    final error = await _api.login(
      _mobileController.text,
      pin,
      forceLogin: force,
    );

    setState(() => _isLoading = false);

    if (error == null) {
      // Success
      await _api.saveMobile(_mobileController.text);
      if (mounted) {
        if (widget.isUnlockMode) {
          Navigator.pop(context); // Unlock successful
        } else {
          // Optimistic Navigation:
          // Go to home immediately. Home screen is now cached, so it will load instantly.
          // No need to wait for anything else.
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } else if (error == 'INCORRECT_PIN') {
      // Incorrect PIN
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incorrect PIN'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
      setState(() => _enteredPin = '');
    } else if (error == 'CONNECTION_ERROR') {
      // Connection error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection error'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
      setState(() => _enteredPin = '');
    } else {
      // Any other error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection error'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
      setState(() => _enteredPin = '');
    }
  }

  // Dialog shown BEFORE PIN entry (after mobile number check) when device conflict detected
  void _showForceLoginDialogEarly() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Theme.of(context).cardColor,
        icon: const Icon(Icons.devices, color: Color(0xFF5F259F), size: 48),
        title: Text(
          'Already Logged In',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are currently logged in on another device.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'What would you like to do?',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.check_circle_outline, size: 20, color: Colors.green),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Logout from other device and login here',
                    style: TextStyle(fontSize: 13, color: Colors.green),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(Icons.cancel_outlined, size: 20, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Stay logged in on other device',
                    style: TextStyle(fontSize: 13, color: Colors.orange),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              // User chooses to keep other device - stay on mobile entry screen
              setState(() {
                _forceLogoutApproved = false;
              });
            },
            icon: const Icon(Icons.close, size: 18),
            label: const Text('No, Keep Other Device'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[300]
                  : Colors.grey[700],
              side: BorderSide(color: Colors.grey[400]!),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              // User approves force logout - proceed to PIN entry
              setState(() {
                _forceLogoutApproved = true;
                _currentStep = 3; // Move to PIN entry
                _enteredPin = '';
              });
            },
            icon: const Icon(Icons.login, size: 18),
            label: const Text('Yes, Login Here'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5F259F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              elevation: 2,
            ),
          ),
        ],
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actionsAlignment: MainAxisAlignment.spaceBetween,
      ),
    );
  }

  void _onKeypadTap(String value) {
    if (_isLoading) return;

    if (value == 'BACK') {
      if (_enteredPin.isNotEmpty) {
        setState(() {
          _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        });
      }
    } else {
      if (_enteredPin.length < 4) {
        setState(() {
          _enteredPin += value;
        });
        if (_enteredPin.length == 4) {
          _handlePinComplete();
        }
      }
    }
  }

  // --- UI Components ---

  Widget _buildStep1Mobile() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            // App Logo/Branding
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5F259F).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: Color(0xFF5F259F),
                    size: 32,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '2Way',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 60),

            // Welcome Text
            Text(
              'Welcome to 2Way',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 28,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your phone number',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 40),

            // Phone Number Input
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Country Code Container
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                    color: Theme.of(context).cardColor,
                  ),
                  child: Row(
                    children: [
                      const Text('🇮🇳', style: TextStyle(fontSize: 24)),
                      const SizedBox(width: 8),
                      Text(
                        '+91',
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark
                              ? Colors.grey.shade300
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Phone Number Field
                Expanded(
                  child: TextField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Theme.of(context).cardColor,
                      hintText: '9876543210',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.normal,
                        letterSpacing: 0.5,
                      ),
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF5F259F),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Helper Text
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'We\'ll send an OTP to verify your number',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ),

            const SizedBox(height: 100),

            // Continue Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleMobileSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5F259F),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(27),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 40),

            // Terms and Privacy
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'By continuing, you agree to 2Way\'s Terms of Service and Privacy Policy',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStepPin() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 48,
                color: Color(0xFF5F259F),
              ),
              const SizedBox(height: 24),
              Text(_pinTitle, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              if (_currentStep == 1)
                const Text("Create a 4-digit PIN for your account")
              else if (_currentStep == 2)
                const Text("Re-enter PIN to confirm")
              else if (_upiId.isNotEmpty)
                Text(
                  _upiId,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isDark ? Colors.grey.shade400 : Colors.grey[700],
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
                          ? const Color(0xFF5F259F)
                          : Colors.transparent,
                      border: Border.all(
                        color: const Color(0xFF5F259F),
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
        // Keypad
        Expanded(
          flex: 3,
          child: Container(
            color: isDark
                ? Colors.grey[900]
                : Colors.grey[50], // Dark mode safe
            child: Column(
              children: [
                const SizedBox(height: 20),
                Expanded(
                  child: Row(
                    children: [_buildKey('1'), _buildKey('2'), _buildKey('3')],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [_buildKey('4'), _buildKey('5'), _buildKey('6')],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [_buildKey('7'), _buildKey('8'), _buildKey('9')],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      const Expanded(child: SizedBox()), // Empty
                      _buildKey('0'),
                      _buildBackspaceKey(),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Only show "Change Number" if in Login Mode (Step 3) or if manually backing out
                if (_currentStep == 3)
                  TextButton(
                    onPressed: () {
                      // Clear state to go back
                      setState(() {
                        _currentStep = 0;
                        _enteredPin = '';
                        _mobileController.clear();
                      });
                    },
                    child: const Text("Not you? Change Number"),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKey(String value) {
    return Expanded(
      child: InkWell(
        onTap: () => _onKeypadTap(value),
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

  @override
  Widget build(BuildContext context) {
    // Show splash/loading while checking auth status (avoids flash of Mobile Entry)
    if (_isCheckingAuth) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF5F259F)),
        ),
      );
    }

    // If in unlock mode, prevent back button from closing the screen
    return PopScope(
      canPop: !widget.isUnlockMode,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: _currentStep == 0
            ? AppBar(
                elevation: 0,
                backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
              )
            : null, // No AppBar for PIN screen
        body: SafeArea(
          child: _currentStep == 0 ? _buildStep1Mobile() : _buildStepPin(),
        ),
      ),
    );
  }
}
