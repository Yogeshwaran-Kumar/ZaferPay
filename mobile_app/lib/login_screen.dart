import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/app_localizations.dart';
import 'api_service.dart';
import 'main.dart';
import 'services/notification_service.dart';
import 'services/biometric_service.dart';
import 'services/sim_service.dart';
import 'permission_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool isUnlockMode;
  const LoginScreen({super.key, this.isUnlockMode = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobileController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _hasBankAccount = false;
  bool _isNewUserSignup = false;
  final _api = ApiService();
  final _biometric = BiometricService();
  static const _securityChannel = MethodChannel(
    'com.company.zaferpay/security',
  );

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
  bool _biometricAvailable = false; // Whether biometric is enabled & available
  bool _biometricVerified = false; // True after biometric step passes

  // Status text for the PIN screen title
  String get _pinTitle {
    if (widget.isUnlockMode) {
      return AppLocalizations.of(context)?.translate('login.unlock_app') ??
          'Unlock App';
    }
    switch (_currentStep) {
      case 1:
        return AppLocalizations.of(context)?.translate('login.set_pin') ??
            'Set New PIN';
      case 2:
        return AppLocalizations.of(context)?.translate('login.confirm_pin') ??
            'Confirm PIN';
      case 3:
        // Unified title to match "Unlock App" experience (Standardizing UI)
        return AppLocalizations.of(context)?.translate('login.unlock_app') ??
            'Unlock App';
      default:
        return '';
    }
  }

  @override
  void initState() {
    super.initState();

    // Check for "Identity" (Saved Mobile) instantly from RAM cache
    final syncMobile = _api.getSavedMobileSync();

    // Check if we can bypass entirely
    final bool hasMpin = MyApp.appLockEnabled;
    final bool hasBiometric = MyApp.biometricEnabled;

    if (syncMobile != null && syncMobile.isNotEmpty) {
      if (!hasMpin && !hasBiometric && !widget.isUnlockMode) {
        // Zero-Latency complete bypass to Home Screen (Only if BOTH are disabled)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pushReplacementNamed(context, '/home');
        });
        return;
      }

      // If mPIN is off BUT Biometric is on, we still need to show the unlock screen
      // and trigger the fingerprint prompt natively.
      _currentStep = 3;
      _mobileController.text = syncMobile;
      _isCheckingAuth = false;
      _populateCachedUserForUnlock();
      _tryBiometricUnlock();
    } else if (widget.isUnlockMode || (!hasMpin && hasBiometric)) {
      // If we are globally unlocking OR if mPIN is disabled but Biometric is required
      // fallback to the biometric prompt natively.
      _currentStep = 3;
      _isCheckingAuth = false;
      _populateCachedUserForUnlock();
      _tryBiometricUnlock();
    } else {
      _isCheckingAuth = true;
      _checkSavedLogin();
    }

    // Clear snackbars when user edits the number
    _mobileController.addListener(() {
      ScaffoldMessenger.of(context).clearSnackBars();
    });

    if (_currentStep > 0) {
      _secureScreen();
    }
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

  @override
  void dispose() {
    _removeSecureScreen();
    _mobileController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Step 1 of dual-factor unlock: verify biometric.
  /// On success → set _biometricVerified = true, then user must ALSO enter PIN.
  /// On failure/cancel → user can still enter PIN (or tap the fingerprint button to retry).
  Future<void> _tryBiometricUnlock() async {
    final available = await _biometric.isBiometricAvailable();
    final enabled = await _biometric.isBiometricEnabled();
    if (mounted) setState(() => _biometricAvailable = available && enabled);

    if (!available || !enabled) return;

    // Small delay so the screen renders before the system dialog appears
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final success = await _biometric.authenticate(
      reason:
          AppLocalizations.of(context)?.translate('login.biometric_reason') ??
          'Step 1 of 2: Verify your biometric to proceed',
    );

    if (!mounted) return;

    if (success) {
      // Biometric passed

      // If mPIN is completely disabled, this biometric check WAS the only lock.
      // We can securely bypass to home directly without asking for a PIN.
      if (!MyApp.appLockEnabled && !widget.isUnlockMode) {
        if (mounted) Navigator.pushReplacementNamed(context, '/home');
        return;
      } else if (!MyApp.appLockEnabled && widget.isUnlockMode) {
        if (mounted) Navigator.pop(context, true);
        return;
      }

      // Otherwise, show a checkmark and wait for PIN (step 2)
      setState(() => _biometricVerified = true);
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

            // If app lock is disabled OR user has no mPIN, bypass entirely
            final bool appLockEnabled = user['app_lock_enabled'] ?? true;
            final bool hasMpin = user['has_mpin'] ?? true;

            if ((!appLockEnabled || !hasMpin) && !widget.isUnlockMode) {
              if (mounted) Navigator.pushReplacementNamed(context, '/home');
              return;
            }
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

  // ═══════════════════════════════════════════════════════════════════════════
  // MANDATORY PERMISSION CHECK: Phone + Contacts
  // First tries an inline request. If that fails (denied/permanently denied),
  // pushes the full PermissionScreen as a mandatory gateway.
  // Returns true if BOTH permissions are granted, false otherwise.
  // ═══════════════════════════════════════════════════════════════════════════
  Future<bool> _ensurePermissions() async {
    // Quick check: already granted?
    final phoneGranted = await Permission.phone.isGranted;
    final contactsGranted = await Permission.contacts.isGranted;

    if (phoneGranted && contactsGranted) return true;

    // Try inline request first (system dialog)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.phone,
      Permission.contacts,
    ].request();

    if (statuses[Permission.phone]!.isGranted &&
        statuses[Permission.contacts]!.isGranted) {
      return true;
    }

    // Inline request failed → Push the full PermissionScreen
    if (!mounted) return false;

    // Mark as requesting permission so app lock doesn't trigger
    MyApp.isRequestingPermission = true;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const PermissionScreen(),
        fullscreenDialog: true,
      ),
    );

    MyApp.isRequestingPermission = false;

    return result == true;
  }

  // Handle "Proceed Next" button
  Future<void> _handleMobileSubmit() async {
    final mobile = _mobileController.text.trim();
    if (mobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
                  context,
                )?.translate('login.enter_mobile_error') ??
                'Please enter a valid Mobile Number or Email',
          ),
        ),
      );
      return;
    }

    // Clear any previous error snackbars (e.g. from previous failed SIM check)
    ScaffoldMessenger.of(context).clearSnackBars();

    setState(() => _isLoading = true);

    // --- Device Binding: SIM Match Check ---
    // We only check this on mobile (Android/iOS)
    if (!kIsWeb) {
      // 1. Initialize Service (request permissions if needed)
      await SimService.instance.init();

      // 2. Compute Match
      final simVerification = await SimService.instance.verifySimMatch(mobile);

      if (!simVerification.isValid) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(simVerification.error ?? 'Device Binding Failed'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
        return;
      }
    }
    // ---------------------------------------

    final result = await _api.checkMobile(mobile);

    setState(() => _isLoading = false);

    if (result['status'] == 'new') {
      if (result['exists'] == true) {
        // User exists but needs to set PIN
        // ═════════════════════════════════════════════════════════════════
        // MANDATORY: Ensure Phone + Contacts permissions (existing user)
        // ═════════════════════════════════════════════════════════════════
        final permissionsGranted = await _ensurePermissions();
        if (!permissionsGranted) return;

        _secureScreen();
        setState(() {
          _currentStep = 1; // Create PIN
          _enteredPin = '';
          _upiId = result['upi_id'] ?? '';
        });
      } else {
        // User does not exist - Show error message (NO permission check here)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(
                      context,
                    )?.translate('login.user_not_found') ??
                    'User does not exist in our app. Please create an account.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } else if (result['exists'] == true && result['status'] == 'existing') {
      // Existing user - proceed to PIN entry
      // ═════════════════════════════════════════════════════════════════════
      // MANDATORY: Ensure Phone + Contacts permissions (existing user)
      // ═════════════════════════════════════════════════════════════════════
      final permissionsGranted = await _ensurePermissions();
      if (!permissionsGranted) return;

      _secureScreen();
      setState(() {
        _currentStep = 3; // Enter PIN
        _enteredPin = '';
        _upiId = result['upi_id'] ?? '';
      });
      // Save mobile immediately so if app restarts, we return to PIN screen (Unlock Mode)
      await _api.saveMobile(mobile);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['detail'] ?? 'Connection Error')),
        );
      }
    }
  }

  Future<void> _validateAndProceedSignup() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.translate('login.name_required') ??
                'Name is required',
          ),
        ),
      );
      return;
    }
    if (_mobileController.text.trim().length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.translate('login.invalid_phone') ??
                'Please enter a valid 10-digit phone number',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _api.validateSignup(
        _mobileController.text.trim(),
        _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
      );

      if (result['valid'] == true) {
        // ═════════════════════════════════════════════════════════════════
        // MANDATORY: Ensure Phone + Contacts permissions (valid signup)
        // ═════════════════════════════════════════════════════════════════
        if (mounted) setState(() => _isLoading = false);
        final permissionsGranted = await _ensurePermissions();
        if (!permissionsGranted) return;

        setState(() {
          _currentStep = 1; // proceed to create PIN
          _enteredPin = '';
          _firstPin = '';
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['detail'] ?? 'Validation failed'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
        bool success = false;

        if (_isNewUserSignup) {
          final signupError = await _api.signup(
            _nameController.text.trim(),
            _mobileController.text.trim(),
            _emailController.text.trim().isEmpty
                ? null
                : _emailController.text.trim(),
            pin,
            _hasBankAccount,
          );

          if (signupError == null) {
            success = true;
          } else {
            success = false;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(signupError),
                  backgroundColor: signupError.contains('already registered')
                      ? Colors.orange
                      : Colors.red,
                ),
              );

              // If it's a conflict error, maybe go back to signup detail or stay here?
              // User likely wants to fix the email or mobile, so staying on PIN confirmation
              // might be confusing if they can't change it here.
              // However, since they are in Step 2 (Confirm PIN), we should probably
              // let them go back to Step 4 (Signup Details) if they want.
            }
          }
        } else {
          success = await _api.setPin(_mobileController.text, pin);
        }

        setState(() => _isLoading = false);

        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _isNewUserSignup
                      ? (AppLocalizations.of(
                              context,
                            )?.translate('login.signup_success') ??
                            'Account Created! Logging you in.')
                      : (AppLocalizations.of(
                              context,
                            )?.translate('login.pin_set_success') ??
                            'PIN Set Successfully! Login now.'),
                ),
              ),
            );
          }
          // Auto login after setting
          _login(force: false, pinToUse: pin);
        } else if (_isNewUserSignup) {
          // Error already handled above with specific message
          // Just reset slightly so they can try again or go back
          setState(() {
            _enteredPin = '';
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _isNewUserSignup
                      ? (AppLocalizations.of(
                              context,
                            )?.translate('login.signup_failed') ??
                            'Failed to create account. Try again.')
                      : (AppLocalizations.of(
                              context,
                            )?.translate('login.pin_set_failed') ??
                            'Failed to set PIN. Try again.'),
                ),
              ),
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
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.translate('login.pin_mismatch') ??
                  'PIN mismatch',
            ),
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
    if (!mounted) return;
    setState(() {
      _enteredPin = ''; // Reset PIN field
      _hasError = true;
    });

    if (_api.failedAttempts == 2) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(
            AppLocalizations.of(
                  context,
                )?.translate('login.pin_security_warning') ??
                "Security Warning",
          ),
          content: Text(
            AppLocalizations.of(
                  context,
                )?.translate('login.pin_failed_attempts') ??
                "Warning: You have tried too many times. One more failed attempt will log you out.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                AppLocalizations.of(
                      context,
                    )?.translate('login.pin_i_understand') ??
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
    // 3rd Strike -> Logout with Dialog
    showDialog(
      context: context,
      barrierDismissible: false, // User cannot close this
      builder: (ctx) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)?.translate('login.pin_locked_out') ??
              "Account Locked",
        ),
        content: Text(
          AppLocalizations.of(context)?.translate('login.pin_locked_out_msg') ??
              "Too many incorrect attempts so your account has been logged out.",
        ),
      ),
    );

    // Wait for user to read it (shortened to less than 1 second)
    await Future.delayed(const Duration(milliseconds: 500));

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

          // Sync Notification Token (background/unlock mode)
          try {
            NotificationService.instance.initialize();
            NotificationService.instance.resetBadgeCount();
          } catch (_) {}

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
      await _api
          .syncUserSettings(); // Restores biometric settings etc. from backend

      // Sync Notification Token
      try {
        NotificationService.instance.initialize(askPermission: true);
        NotificationService.instance.resetBadgeCount();
      } catch (_) {}

      if (mounted) {
        setState(() => _isUnlocking = true);
        await Future.delayed(const Duration(milliseconds: 600));

        if (!mounted) return;
        if (widget.isUnlockMode) {
          Navigator.pop(context, true); // Unlock successful
        } else {
          // Optimistic Navigation:
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } else if (error == 'INCORRECT_PIN') {
      // Incorrect PIN
      if (mounted) _handleIncorrectPin();
    } else if (error == 'LOCKED_OUT') {
      if (mounted) _handleLockedOut();
    } else if (error == 'CONNECTION_ERROR') {
      // Connection error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                    context,
                  )?.translate('login.connection_error') ??
                  'Connection error',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
      setState(() => _enteredPin = '');
    } else if (error == 'LOGGED_IN_ELSEWHERE') {
      if (mounted) {
        _showDeviceConflictDialogAfterPin(pin);
      }
    } else {
      // Any other error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                    context,
                  )?.translate('login.connection_error') ??
                  'Connection error',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      setState(() => _enteredPin = '');
    }
  }

  // Dialog shown AFTER correct PIN entry when device conflict detected
  void _showDeviceConflictDialogAfterPin(String pin) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFF1E2032), // Dark card bg
        icon: const Icon(Icons.devices, color: Color(0xFF00B9F1), size: 48),
        title: Text(
          AppLocalizations.of(context)?.translate('login.already_logged_in') ??
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
              AppLocalizations.of(
                    context,
                  )?.translate('login.logged_in_elsewhere_msg') ??
                  'This account is login in another device. For login in this device click logout button.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // User chooses to keep other device - cancel login and go back to mobile entry
              setState(() {
                _currentStep = 0;
                _enteredPin = '';
                _forceLogoutApproved = false;
              });
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text(
              AppLocalizations.of(context)?.translate('details.cancel') ??
                  'Cancel',
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // User approves force logout - retry login with force: true
              _login(force: true, pinToUse: pin);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00B9F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              elevation: 4,
            ),
            child: Text(
              AppLocalizations.of(context)?.translate('settings.logout') ??
                  'Logout',
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

    // Strict Mode: Block PIN entry if biometric is required but not verified
    if (_biometricAvailable && !_biometricVerified && _currentStep == 3) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.translate('login.verify_biometric') ??
                'Please verify using Biometric first',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      // Auto-trigger biometric again for convenience
      _tryBiometricUnlock();
      return;
    }

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
              // ZaferPay Logo
              _buildZaferPayLogo(),
              const SizedBox(height: 20),

              // Welcome Text
              Text(
                AppLocalizations.of(context)?.translate('login.welcome_back') ??
                    'Welcome Back',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)?.translate('login.enter_phone') ??
                    'Enter your phone number to continue',
                style: const TextStyle(color: Colors.black54, fontSize: 16),
              ),

              const SizedBox(height: 40),

              // Phone Number Input
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
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
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    // Divider
                    Container(height: 24, width: 1, color: Colors.black12),
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
                          color: Colors.black87,
                          letterSpacing: 1.0,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText:
                              AppLocalizations.of(
                                context,
                              )?.translate('login.phone_number') ??
                              'Phone Number',
                          hintStyle: const TextStyle(color: Colors.black38),
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
                      Color(0xFF00B9F1), // Blue
                      Color(0xFF0091EA), // Darker Blue
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00B9F1).withValues(alpha: 0.3),
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
                      : Text(
                          AppLocalizations.of(
                                context,
                              )?.translate('login.continue') ??
                              'Continue',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // Signup Button
              TextButton(
                onPressed: () {
                  setState(() {
                    _isNewUserSignup = true;
                    _currentStep = 4;
                    _mobileController.clear();
                    _nameController.clear();
                    _emailController.clear();
                  });
                },
                child: RichText(
                  text: TextSpan(
                    text:
                        AppLocalizations.of(
                          context,
                        )?.translate('login.no_account') ??
                        "Don't have an account? ",
                    style: const TextStyle(color: Colors.black54, fontSize: 14),
                    children: [
                      TextSpan(
                        text:
                            AppLocalizations.of(
                              context,
                            )?.translate('login.create_account') ??
                            "Create account",
                        style: const TextStyle(
                          color: Color(0xFF00B9F1),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Terms
              Text(
                'By continuing, you agree to ZaferPay\'s\nTerms of Service and Privacy Policy',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black45,
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

  Widget _buildZaferPayLogo() {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 220,
        maxHeight: 220,
      ), // Decreased size
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Image.asset(
        'assets/zaferpay_logo_slight.png',
        fit: BoxFit.contain,
        // Use errorBuilder to fallback gracefully if asset isn't found immediately (dev hot reload)
        errorBuilder: (context, error, stackTrace) {
          return Column(
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 80,
                color: Color(0xFF00B9F1),
              ),
              const SizedBox(height: 8),
              const Text(
                "ZaferPay",
                style: TextStyle(
                  color: Color(0xFF00B9F1),
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
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20), // Add top padding for safety
                    _buildZaferPayLogo(),

                    // Lock Icon or Title
                    if (_currentStep == 3)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          transitionBuilder: (child, animation) {
                            return ScaleTransition(
                              scale: animation,
                              child: child,
                            );
                          },
                          child: _isUnlocking
                              ? Container(
                                  key: const ValueKey('unlock'),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(
                                      0xFF00B9F1,
                                    ).withValues(alpha: 0.2),
                                    border: Border.all(
                                      color: const Color(0xFF00B9F1),
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.lock_open_rounded,
                                    size: 32,
                                    color: Color(0xFF00B9F1),
                                  ),
                                )
                              : Container(
                                  key: const ValueKey('lock'),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _hasError
                                        ? Colors.red.withValues(alpha: 0.1)
                                        : Colors.black.withValues(alpha: 0.05),
                                    border: Border.all(
                                      color: _hasError
                                          ? Colors.redAccent
                                          : Colors.black12,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.lock_outline_rounded,
                                    size: 32,
                                    color: _hasError
                                        ? Colors.redAccent
                                        : Colors.black87,
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
                          color: Colors.black87,
                        ),
                      ),

                    const SizedBox(height: 8),
                    if (_currentStep == 1)
                      Text(
                        AppLocalizations.of(
                              context,
                            )?.translate('login.create_pin_msg') ??
                            "Create a 4-digit PIN",
                        style: const TextStyle(color: Colors.black54),
                      )
                    else if (_currentStep == 2)
                      Text(
                        AppLocalizations.of(
                              context,
                            )?.translate('login.confirm_pin_msg') ??
                            "Re-enter PIN to confirm",
                        style: const TextStyle(color: Colors.black54),
                      )
                    else if (_upiId.isNotEmpty && !_isUnlocking)
                      Text(
                        _upiId,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                        ),
                      ),

                    const SizedBox(height: 8),
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
                                ? const Color(0xFF00B9F1) // Blue filled
                                : Colors.black12, // Empty
                            border: Border.all(
                              color: filled
                                  ? const Color(0xFF00B9F1)
                                  : Colors.black26,
                              width: 2,
                            ),
                          ),
                        );
                      }),
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 32),
                      const CircularProgressIndicator(color: Color(0xFF00B9F1)),
                    ],
                    const SizedBox(height: 20), // Bottom padding
                  ],
                ),
              ),
              // Back Button for Signup/PIN flow (On top of scroller)
              if (_currentStep == 1 || _currentStep == 2)
                Positioned(
                  top: 0,
                  left: 0,
                  child: IconButton(
                    padding: const EdgeInsets.all(20),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.black87,
                      size: 32,
                    ),
                    onPressed: () {
                      if (_currentStep == 2) {
                        setState(() {
                          _currentStep = 1;
                          _enteredPin = '';
                          _firstPin = '';
                        });
                      } else if (_currentStep == 1) {
                        setState(() {
                          if (_isNewUserSignup) {
                            _currentStep = 4;
                          } else {
                            _currentStep = 0;
                            _mobileController.clear();
                          }
                          _enteredPin = '';
                        });
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        // Keypad or Biometric-Only Prompt
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
            child:
                (!MyApp.appLockEnabled &&
                    MyApp.biometricEnabled &&
                    _currentStep == 3)
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppLocalizations.of(
                              context,
                            )?.translate('login.app_lock_disabled') ??
                            "App Lock is disabled.",
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(
                              context,
                            )?.translate('login.verify_biometric') ??
                            "Verify Biometric to Continue",
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 32),
                      GestureDetector(
                        onTap: _tryBiometricUnlock,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(
                              0xFF00B9F1,
                            ).withValues(alpha: 0.1),
                          ),
                          child: const Icon(
                            Icons.fingerprint,
                            size: 64,
                            color: Color(0xFF00B9F1),
                          ),
                        ),
                      ),
                      const Expanded(child: SizedBox()),
                      TextButton(
                        onPressed: () async {
                          await _api.removeSavedMobile();
                          _removeSecureScreen();
                          setState(() {
                            _currentStep = 0;
                            _enteredPin = '';
                            _mobileController.clear();
                          });
                        },
                        child: Text(
                          AppLocalizations.of(
                                context,
                              )?.translate('login.change_number') ??
                              "Not you? Change Number",
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  )
                : Column(
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
                          const Expanded(child: SizedBox(height: 72)),

                          // '0' Key (Center)
                          Expanded(
                            child: _buildAnimatedKey(
                              label: "0",
                              onTap: () => _onKeypadTap('0'),
                            ),
                          ),

                          // Backspace Button (Right)
                          Expanded(
                            child: _buildAnimatedKey(
                              icon: Icons.backspace_outlined,
                              onTap: () => _onKeypadTap('BACK'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),
                      if (_currentStep == 3)
                        TextButton(
                          onPressed: () async {
                            await _api
                                .removeSavedMobile(); // Clear saved session
                            _removeSecureScreen();
                            setState(() {
                              _currentStep = 0;
                              _enteredPin = '';
                              _mobileController.clear();
                            });
                          },
                          child: Text(
                            AppLocalizations.of(
                                  context,
                                )?.translate('login.change_number') ??
                                "Not you? Change Number",
                            style: const TextStyle(color: Colors.black54),
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

  Widget _buildStep4Signup() {
    return SafeArea(
      child: Stack(
        children: [
          Container(
            alignment: const Alignment(0.0, -0.3),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Builder(
                  builder: (context) {
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildZaferPayLogo(),
                        const SizedBox(height: 20),

                        Text(
                          AppLocalizations.of(
                                context,
                              )?.translate('login.welcome') ??
                              'Welcome to Safe Pay',
                          style: GoogleFonts.outfit(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter your details to register',
                          style: TextStyle(color: Colors.black54, fontSize: 16),
                        ),
                        const SizedBox(height: 40),

                        TextField(
                          controller: _nameController,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                AppLocalizations.of(
                                  context,
                                )?.translate('login.user_name') ??
                                'User Name',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Colors.black12,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Colors.black12,
                              ),
                            ),
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 20),

                        TextField(
                          controller: _mobileController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                AppLocalizations.of(
                                  context,
                                )?.translate('login.phone_number') ??
                                'Phone Number',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Colors.black12,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Colors.black12,
                              ),
                            ),
                            prefixIcon: const Icon(Icons.phone_android),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 20),

                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                AppLocalizations.of(
                                  context,
                                )?.translate('login.email_optional') ??
                                'Gmail (Optional)',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Colors.black12,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Colors.black12,
                              ),
                            ),
                            prefixIcon: const Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 20),

                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: SwitchListTile(
                            title: Text(
                              AppLocalizations.of(
                                    context,
                                  )?.translate('login.has_bank_account') ??
                                  'Do you have a bank account?',
                            ),
                            subtitle: Text(
                              _hasBankAccount
                                  ? (AppLocalizations.of(
                                          context,
                                        )?.translate('login.parent_user') ??
                                        'Parent User')
                                  : (AppLocalizations.of(
                                          context,
                                        )?.translate('login.child_user') ??
                                        'Child User'),
                              style: TextStyle(
                                color: _hasBankAccount
                                    ? Colors.blue
                                    : Colors.orange,
                              ),
                            ),
                            value: _hasBankAccount,
                            onChanged: (val) {
                              setState(() => _hasBankAccount = val);
                            },
                            activeTrackColor: const Color(
                              0xFF00B9F1,
                            ).withValues(alpha: 0.5),
                            activeThumbColor: const Color(0xFF00B9F1),
                          ),
                        ),
                        const SizedBox(height: 40),

                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : _validateAndProceedSignup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00B9F1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Next',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          // Back Button for Signup Details (Step 4)
          Positioned(
            top: 0,
            left: 0,
            child: IconButton(
              padding: const EdgeInsets.all(20),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.black87,
                size: 32,
              ),
              onPressed: () {
                setState(() {
                  _currentStep = 0;
                  _isNewUserSignup = false;
                  _mobileController.clear();
                  _nameController.clear();
                  _emailController.clear();
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyRow(List<String> keys) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: keys.map((key) {
          return Expanded(
            child: _buildAnimatedKey(
              label: key,
              onTap: () => _onKeypadTap(key),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAnimatedKey({
    String? label,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return _BouncingButton(
      onTap: onTap,
      child: Container(
        height: 72, // Increased touch target
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent, // Or subtle fill
        ),
        child: icon != null
            ? Icon(icon, size: 28, color: Colors.black87)
            : Text(
                label ?? "",
                style: const TextStyle(
                  fontSize: 32, // Larger font
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
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
            colors: [Colors.white, Color(0xFFE1F5FE)],
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF00B9F1)),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (widget.isUnlockMode) {
          // In unlock mode, we don't allow popping the screen via system back
          return;
        }

        if (_currentStep == 1) {
          setState(() {
            if (_isNewUserSignup) {
              _currentStep = 4;
            } else {
              _currentStep = 0;
              _mobileController.clear();
            }
            _enteredPin = '';
          });
        } else if (_currentStep == 2) {
          setState(() {
            _currentStep = 1;
            _enteredPin = '';
            _firstPin = '';
          });
        } else if (_currentStep == 4) {
          setState(() {
            _currentStep = 0;
            _isNewUserSignup = false;
            _mobileController.clear();
            _nameController.clear();
            _emailController.clear();
          });
        } else if (_currentStep == 3 && !widget.isUnlockMode) {
          setState(() {
            _currentStep = 0;
            _enteredPin = '';
            _mobileController.clear();
          });
        } else {
          // If we are at Step 0 or anything else, we can close the app/screen
          SystemNavigator.pop();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white,
                  Color(0xFFE1F5FE),
                ], // White to Light Blue 50
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: _currentStep == 0
                  ? _buildStep1Mobile()
                  : _currentStep == 4
                  ? _buildStep4Signup()
                  : _buildStepPin(),
            ),
          ),
        ),
      ),
    );
  }
}

// Helper Widget for Bouncing Animation
class _BouncingButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _BouncingButton({required this.child, required this.onTap});

  @override
  _BouncingButtonState createState() => _BouncingButtonState();
}

class _BouncingButtonState extends State<_BouncingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 1.0, // Disabled bouncing for visual silence (GPay Style)
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        _controller.forward();
        HapticFeedback.lightImpact(); // Haptic feedback
      },
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          color: Colors.transparent, // Hit test
          child: widget.child,
        ),
      ),
    );
  }
}
