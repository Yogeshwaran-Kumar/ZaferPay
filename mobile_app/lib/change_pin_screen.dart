import 'package:flutter/material.dart';
import 'api_service.dart';

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _api = ApiService();
  String _enteredPin = '';
  String _firstPin = '';
  int _step = 0; // 0: Enter New, 1: Confirm
  bool _isLoading = false;
  String _upiId = '';

  @override
  void initState() {
    super.initState();
    _fetchUser();
  }

  Future<void> _fetchUser() async {
    final user = await _api.getMe();
    if (user != null && mounted) {
      setState(() {
        _upiId = user['upi_id'] ?? '';
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
      // Finished entering NEW PIN
      setState(() {
        _firstPin = _enteredPin;
        _enteredPin = '';
        _step = 1; // Move to Confirm
      });
    } else {
      // Finished Confirmation
      if (_enteredPin == _firstPin) {
        // Match! Call API
        await _changePinOnServer();
      } else {
        // Mismatch
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN mismatch'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _enteredPin = '';
          _firstPin = '';
          _step = 0; // Restart
        });
      }
    }
  }

  Future<void> _changePinOnServer() async {
    setState(() => _isLoading = true);
    final success = await _api.changePin(_enteredPin);
    setState(() => _isLoading = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN Changed Successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to change PIN. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _enteredPin = '';
          _firstPin = '';
          _step = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _step == 0 ? "Enter New PIN" : "Confirm New PIN";
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
          onPressed: () => Navigator.pop(context),
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
                      title,
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
}
