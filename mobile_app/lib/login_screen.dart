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
    if (widget.isUnlockMode) {
      _loadUserForUnlock();
    } else {
      _checkSavedLogin();
    }
  }

  Future<void> _loadUserForUnlock() async {
    // In unlock mode, we assume user is already logged in (locally)
    // We just need to load their mobile number to verify PIN against.
    final savedMobile = await _api.getSavedMobile();
    if (savedMobile != null) {
      setState(() {
        _mobileController.text = savedMobile;
        _currentStep = 3; // Direct to PIN
      });
      // Optionally fetch UPI ID for display, but not strictly required for lock screen
      // _api.checkMobile(savedMobile)...
    } else {
      // If no saved mobile, we can't unlock. Force full login.
      setState(() {
        // Should probably just be Step 0, but as "Unlock", maybe we should force them to login.
        _currentStep = 0;
      });
    }
  }

  Future<void> _checkSavedLogin() async {
    final savedMobile = await _api.getSavedMobile();
    if (savedMobile != null && savedMobile.isNotEmpty) {
      if (mounted) {
        setState(() => _isLoading = true);
        try {
          // Fetch user details to get real UPI ID
          final result = await _api.checkMobile(savedMobile);

          if (mounted) {
            setState(() {
              _mobileController.text = savedMobile;
              // Use real UPI ID from DB
              _upiId = result['upi_id'] ?? '';
              _currentStep = 3;
              _isLoading = false;
            });
          }
        } catch (e) {
          // Fallback if offline/error
          if (mounted) {
            setState(() {
              _mobileController.text = savedMobile;
              _upiId = '';
              _currentStep = 3;
              _isLoading = false;
            });
          }
        }
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

  // New dialog shown BEFORE PIN entry (after mobile number check)
  void _showForceLoginDialogEarly() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.devices, color: Color(0xFF6200EE), size: 48),
        title: const Text(
          'Already Logged In',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are currently logged in on another device.',
              style: TextStyle(fontSize: 15),
            ),
            SizedBox(height: 12),
            Text(
              'What would you like to do?',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            SizedBox(height: 8),
            Row(
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
            SizedBox(height: 6),
            Row(
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
              foregroundColor: Colors.grey[700],
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
              backgroundColor: const Color(0xFF6200EE),
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
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.phonelink_lock,
              size: 64,
              color: Color(0xFF6200EE),
            ),
            const SizedBox(height: 32),
            Text(
              'Welcome',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your mobile number or email to continue',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            TextField(
              controller: _mobileController,
              keyboardType:
                  TextInputType.emailAddress, // Changed to allow email
              // maxLength: 10, // Removed length restriction
              decoration: const InputDecoration(
                labelText: 'Mobile Number or Email',
                hintText: 'Phone or Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_android),
                counterText: "",
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleMobileSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6200EE),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Proceed Next', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepPin() {
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
                color: Color(0xFF6200EE),
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.grey[700]),
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
        // Keypad
        Expanded(
          flex: 3,
          child: Container(
            color: Colors.grey[50],
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
                if (_currentStep == 3 && !widget.isUnlockMode)
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

  @override
  Widget build(BuildContext context) {
    // If in unlock mode, prevent back button from closing the screen
    return PopScope(
      canPop: !widget.isUnlockMode,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _currentStep == 0
            ? AppBar(title: const Text('MockBank Login'))
            : null, // No AppBar for PIN screen
        body: SafeArea(
          child: _currentStep == 0 ? _buildStep1Mobile() : _buildStepPin(),
        ),
      ),
    );
  }
}
