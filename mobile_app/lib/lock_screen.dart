import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'login_screen.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _api = ApiService();
  String _enteredPin = '';
  bool _isLoading = false;
  String? _mobileNumber;

  @override
  void initState() {
    super.initState();
    _fetchMobile();
  }

  Future<void> _fetchMobile() async {
    final mobile = await _api.getSavedMobile();
    if (mounted) {
      if (mobile == null) {
        // Should not happen if locked, but if so, go to login
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      } else {
        setState(() {
          _mobileNumber = mobile;
        });
      }
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
            _verifyPin();
          }
        }
      }
    });
  }

  Future<void> _verifyPin() async {
    if (_mobileNumber == null) return;

    setState(() => _isLoading = true);

    // Reuse login to verify PIN
    final error = await _api.login(_mobileNumber!, _enteredPin);

    if (mounted) {
      setState(() => _isLoading = false);

      if (error == null) {
        // Success - Unlock
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          // Fallback if somehow there's nothing below (unlikely in this flow)
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        // Error
        _enteredPin = '';
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incorrect PIN'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  void _handleLogout() async {
    await _api.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent back button
      child: Scaffold(
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
                        Icons.lock_person,
                        size: 64,
                        color: Color(0xFF6200EE),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Unlock App',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter PIN for ${_mobileNumber ?? "..."}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
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
                        onPressed: _handleLogout,
                        child: const Text("Forgot PIN? Logout"),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
