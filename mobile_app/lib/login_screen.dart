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
  bool _isUnlocking = false; // Track unlock animation state
  bool _hasError = false; // Track error state for incorrect PIN
  int _pinAttempts = 0; // Track incorrect PIN attempts

  // Status text for the PIN screen title
  String get _pinTitle {
    if (widget.isUnlockMode) return 'Unlock App';
    switch (_currentStep) {
      case 1:
        return 'Set New PIN';
      case 2:
        return 'Confirm PIN';
      case 3:
        // Unified title to match "Unlock App" experience (Standardizing UI)
        return 'Unlock App';
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
          // Non-destructive check: Just update UPI ID context if available
          if (result['upi_id'] != null) {
            setState(() => _upiId = result['upi_id']);
          }

          // Note: We deliberately do NOT check for 'has_device_conflict' here to avoid
          // a "logout loop" or auto-logout on startup. Real conflict resolution
          // happens when the user actively submits the PIN.
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
        // Save mobile immediately so if app restarts, we return to PIN screen (Unlock Mode)
        await _api.saveMobile(mobile);
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

  Future<void> _handleIncorrectPin() async {
    setState(() {
      _pinAttempts++;
      _enteredPin = ''; // Reset PIN field
      _hasError = true;
    });

    if (_pinAttempts == 2) {
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

  Future<void> _login({bool force = false, String? pinToUse}) async {
    final pin = pinToUse ?? _enteredPin;

    // 0. Smart Local Verify (Zero Latency)
    // Only attempt fast path if we are NOT forcing a logout/login sequence
    if (!force) {
      final status = await _api.verifyPinSmart(pin);

      if (status == PinVerificationStatus.success) {
        if (mounted) {
          setState(() => _isUnlocking = true);
          await Future.delayed(const Duration(milliseconds: 600));

          if (!mounted) return;
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
        if (mounted) _handleIncorrectPin();
        return; // Stop here, do NOT call network
      } else if (status == PinVerificationStatus.lockedOut) {
        // verifyPinSmart already triggers logout()
        if (mounted) _handleLockedOut();
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
        setState(() => _isUnlocking = true);
        await Future.delayed(const Duration(milliseconds: 600));

        if (!mounted) return;
        if (widget.isUnlockMode) {
          Navigator.pop(context); // Unlock successful
        } else {
          // Optimistic Navigation:
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } else if (error == 'INCORRECT_PIN') {
      // Incorrect PIN
      // Incorrect PIN
      if (mounted) _handleIncorrectPin();
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
        backgroundColor: const Color(0xFF1E2032), // Dark card bg
        icon: const Icon(Icons.devices, color: Color(0xFF8B5CF6), size: 48),
        title: Text(
          'Already Logged In',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are currently logged in on another device.',
              style: TextStyle(color: Colors.white.withOpacity(0.8)),
            ),
            const SizedBox(height: 12),
            const Text(
              'What would you like to do?',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 20,
                  color: Colors.greenAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Logout from other device and login here',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.greenAccent.shade100,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.cancel_outlined,
                  size: 20,
                  color: Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Stay logged in on other device',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orangeAccent.shade100,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // User chooses to keep other device - stay on mobile entry screen
              setState(() {
                _forceLogoutApproved = false;
              });
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: Colors.white.withOpacity(0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text('No, Keep Other Device'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // User approves force logout - proceed to PIN entry
              setState(() {
                _forceLogoutApproved = true;
                _currentStep = 3; // Move to PIN entry
                _enteredPin = '';
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              elevation: 4,
            ),
            child: const Text('Yes, Login Here'),
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
      if (_hasError) {
        setState(() => _hasError = false);
      }
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
    return Container(
      alignment: const Alignment(0.0, -0.3), // Move slightly upper
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // SafePay Logo
              _buildSafePayLogo(),
              const SizedBox(height: 20),

              // Welcome Text
              const Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your phone number to continue',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 40),

              // Phone Number Input
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2032), // Dark card bg
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    // Country Code
                    Container(
                      padding: const EdgeInsets.only(right: 16),
                      child: const Text(
                        '🇮🇳 +91',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // Divider
                    Container(
                      height: 24,
                      width: 1,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    const SizedBox(width: 16),
                    // Input
                    Expanded(
                      child: TextField(
                        controller: _mobileController,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Phone Number',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                          ),
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Continue Button
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF8B5CF6), // Purple
                      Color(0xFF3B82F6), // Blue
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleMobileSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
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
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 40),

              // Terms
              Text(
                'By continuing, you agree to SafePay\'s\nTerms of Service and Privacy Policy',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.4),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSafePayLogo() {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 220,
        maxHeight: 220,
      ), // Decreased size
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Image.asset(
        'assets/safepay_logo.png',
        fit: BoxFit.contain,
        // Use errorBuilder to fallback gracefully if asset isn't found immediately (dev hot reload)
        errorBuilder: (context, error, stackTrace) {
          return Column(
            children: [
              const Icon(Icons.shield_outlined, size: 80, color: Colors.white),
              const SizedBox(height: 8),
              const Text(
                "SafePay",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStepPin() {
    return Column(
      children: [
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20), // Add top padding for safety
                _buildSafePayLogo(),

                // Lock Icon or Title
                if (_currentStep == 3)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(scale: animation, child: child);
                      },
                      child: _isUnlocking
                          ? Container(
                              key: const ValueKey('unlock'),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF8B5CF6).withOpacity(0.2),
                                border: Border.all(
                                  color: const Color(0xFF8B5CF6),
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.lock_open_rounded,
                                size: 32,
                                color: Color(0xFF8B5CF6),
                              ),
                            )
                          : Container(
                              key: const ValueKey('lock'),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _hasError
                                    ? Colors.red.withOpacity(0.1)
                                    : Colors.white.withOpacity(0.05),
                                border: Border.all(
                                  color: _hasError
                                      ? Colors.redAccent
                                      : Colors.white.withOpacity(0.2),
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.lock_outline_rounded,
                                size: 32,
                                color: _hasError
                                    ? Colors.redAccent
                                    : Colors.white,
                              ),
                            ),
                    ),
                  )
                else
                  Text(
                    _pinTitle,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),

                const SizedBox(height: 8),
                if (_currentStep == 1)
                  const Text(
                    "Create a 4-digit PIN",
                    style: TextStyle(color: Colors.white70),
                  )
                else if (_currentStep == 2)
                  const Text(
                    "Re-enter PIN to confirm",
                    style: TextStyle(color: Colors.white70),
                  )
                else if (_upiId.isNotEmpty && !_isUnlocking)
                  Text(
                    _upiId,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),

                const SizedBox(height: 32),
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
                            ? const Color(0xFF8B5CF6) // Purple filled
                            : Colors.white.withOpacity(0.1), // Empty
                        border: Border.all(
                          color: filled
                              ? const Color(0xFF8B5CF6)
                              : Colors.white.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
                if (_isLoading) ...[
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                ],
                const SizedBox(height: 20), // Bottom padding
              ],
            ),
          ),
        ),
        // Keypad
        Expanded(
          flex: 3,
          child: Container(
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
                    // Empty Space (Left)
                    const Expanded(child: SizedBox(height: 56)),
                    const SizedBox(width: 16),
                    // '0' Key (Center)
                    Expanded(
                      child: InkWell(
                        onTap: () => _onKeypadTap('0'),
                        borderRadius: BorderRadius.circular(24),
                        child: const SizedBox(
                          height: 56,
                          child: Center(
                            child: Text(
                              "0",
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.normal,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Backspace Button (Right)
                    Expanded(
                      child: InkWell(
                        onTap: () => _onKeypadTap('BACK'),
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          height: 56,
                          child: const Center(
                            child: Icon(
                              Icons.backspace_outlined,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                if (_currentStep == 3)
                  TextButton(
                    onPressed: () async {
                      await _api.removeSavedMobile(); // Clear saved session
                      setState(() {
                        _currentStep = 0;
                        _enteredPin = '';
                        _mobileController.clear();
                      });
                    },
                    child: const Text(
                      "Not you? Change Number",
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKeyRow(List<String> keys) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: keys.map((key) {
          return Expanded(
            child: InkWell(
              onTap: () => _onKeypadTap(key),
              borderRadius: BorderRadius.circular(32),
              child: SizedBox(
                height: double.infinity,
                child: Center(
                  child: Text(
                    key,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.normal,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show splash/loading while checking auth status
    if (_isCheckingAuth) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF141E30), Color(0xFF243B55)],
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
        ),
      );
    }

    return PopScope(
      canPop: !widget.isUnlockMode,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0F172A),
                Color(0xFF1E1B4B),
              ], // Slate to Dark Indigo
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: _currentStep == 0 ? _buildStep1Mobile() : _buildStepPin(),
          ),
        ),
      ),
    );
  }
}
