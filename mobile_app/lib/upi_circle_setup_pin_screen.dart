import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'utils.dart';

/// A full-screen PIN entry screen used when inviting a member to a UPI Circle, updating limits, or removing members.
class UPICircleSetupPinScreen extends StatefulWidget {
  final String secondaryUpi;
  final String secondaryName;
  final double limit;
  final String? delegationType;
  final bool isUpdate;
  final bool isRemove;
  final int? circleId;

  const UPICircleSetupPinScreen({
    super.key,
    required this.secondaryUpi,
    required this.secondaryName,
    required this.limit,
    this.delegationType,
    this.isUpdate = false,
    this.isRemove = false,
    this.circleId,
  });

  @override
  State<UPICircleSetupPinScreen> createState() =>
      _UPICircleSetupPinScreenState();
}

class _UPICircleSetupPinScreenState extends State<UPICircleSetupPinScreen> {
  String _enteredPin = '';
  bool _isVerifying = false;
  String? _errorMessage;
  final ApiService _api = ApiService();
  static const _securityChannel = MethodChannel(
    'com.company.zaferpay/security',
  );

  @override
  void initState() {
    super.initState();
    _secureScreen();
  }

  @override
  void dispose() {
    _removeSecureScreen();
    super.dispose();
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

  void _onKeypadTap(String value) {
    if (_isVerifying) return;
    setState(() {
      _errorMessage = null;
      if (value == 'BACK') {
        if (_enteredPin.isNotEmpty) {
          _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        }
      } else if (_enteredPin.length < 4) {
        _enteredPin += value;
      }
    });
  }

  Future<void> _verifyPin() async {
    setState(() => _isVerifying = true);

    final status = await _api.verifyUpiPin(_enteredPin);

    if (!mounted) return;

    if (status == PinVerificationStatus.success) {
      if (widget.isRemove) {
        final bool success = await _api.removeCircleMember(widget.circleId!);
        if (!mounted) return;
        Navigator.pop(context, {
          'success': success,
          'message': success ? "Member Removed!" : "Failed to remove member",
        });
      } else if (widget.isUpdate) {
        final bool success = await _api.updateCircleLimit(
          widget.circleId!,
          widget.limit,
        );
        if (!mounted) return;
        Navigator.pop(context, {
          'success': success,
          'message': success ? "Limit Updated!" : "Failed to update limit",
        });
      } else {
        // Send the invitation
        final result = await _api.inviteToCircle(
          widget.secondaryUpi,
          widget.limit,
          widget.delegationType!,
        );

        if (!mounted) return;

        final bool success = result['success'] ?? false;
        final String message =
            result['message'] ??
            (success ? "Invitation Sent!" : "Failed to send invitation");

        // Pop with result
        Navigator.pop(context, {'success': success, 'message': message});
      }
    } else if (status == PinVerificationStatus.lockedOut) {
      await _api.logout();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } else if (status == PinVerificationStatus.expired) {
      setState(() {
        _enteredPin = '';
        _isVerifying = false;
      });
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('PIN Expired'),
          content: const Text(
            'Your UPI PIN has expired. Please update it to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/change-upi-pin');
              },
              child: const Text('Update PIN'),
            ),
          ],
        ),
      );
    } else {
      // Incorrect PIN
      final remaining = 3 - _api.failedAttempts;
      setState(() {
        _enteredPin = '';
        _isVerifying = false;
        _errorMessage =
            'Incorrect PIN. $remaining attempt${remaining == 1 ? '' : 's'} remaining.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      // ── Close button ──────────────────────────────────────
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          icon: Icon(
                            Icons.close,
                            color: Theme.of(context).iconTheme.color,
                            size: 28,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),

                      // ── Circle Invitation Summary Card ────────────────────
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Theme.of(context).cardColor
                              : const Color(0xFFF8F5F2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.isRemove
                                        ? 'Remove from Circle'
                                        : widget.isUpdate
                                        ? 'Update Circle Limit'
                                        : 'Invite to UPI Circle',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    widget.secondaryName,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Limit: ₹${formatAmount(widget.limit)} / month',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Icon badge
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF003B50)
                                    : const Color(0xFFE0F7FA),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                widget.isRemove
                                    ? Icons.person_remove_rounded
                                    : widget.isUpdate
                                    ? Icons.security_rounded
                                    : Icons.group_add_rounded,
                                color: widget.isRemove
                                    ? Colors.red
                                    : const Color(0xFF00B9F1),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Expanded(flex: 1, child: SizedBox()),

                      // ── PIN prompt ────────────────────────────────────────
                      Text(
                        'Enter your UPI PIN',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.isRemove
                            ? 'Confirm to remove member from circle'
                            : widget.isUpdate
                            ? 'Confirm to update your circle limit'
                            : 'Confirm to invite to your UPI Circle',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ── PIN dots ──────────────────────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(4, (index) {
                          final filled = index < _enteredPin.length;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: filled
                                  ? (isDark ? Colors.white : Colors.black)
                                  : Colors.transparent,
                              border: Border.all(
                                color: filled
                                    ? (isDark ? Colors.white : Colors.black)
                                    : Colors.grey.shade400,
                                width: 1.5,
                              ),
                            ),
                          );
                        }),
                      ),

                      // ── Error / Loading ───────────────────────────────────
                      const SizedBox(height: 16),
                      if (_isVerifying)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF00B9F1),
                          ),
                        )
                      else if (_errorMessage != null)
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade400,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),

                      const Expanded(flex: 2, child: SizedBox()),

                      // ── Security disclaimer ───────────────────────────────
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
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
                              'Never share your UPI PIN with anyone',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Keypad ────────────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.only(
                          bottom: 24,
                          left: 16,
                          right: 16,
                        ),
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
                                // Backspace
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _onKeypadTap('BACK'),
                                    splashColor: Colors.transparent,
                                    highlightColor: Colors.transparent,
                                    child: Container(
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.grey[800]
                                            : Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.backspace_outlined,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // 0
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _onKeypadTap('0'),
                                    splashColor: Colors.transparent,
                                    highlightColor: Colors.transparent,
                                    child: SizedBox(
                                      height: 56,
                                      child: Center(
                                        child: Text(
                                          '0',
                                          style: TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.normal,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Confirm button
                                Expanded(
                                  child: InkWell(
                                    onTap:
                                        _enteredPin.length == 4 && !_isVerifying
                                        ? _verifyPin
                                        : null,
                                    borderRadius: BorderRadius.circular(24),
                                    child: Container(
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color:
                                            _enteredPin.length == 4 &&
                                                !_isVerifying
                                            ? const Color(0xFF1A237E)
                                            : Colors.grey.shade400,
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'Confirm',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildKeyRow(List<String> keys) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) {
        return Expanded(
          child: InkWell(
            onTap: () => _onKeypadTap(key),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: SizedBox(
              height: 56,
              child: Center(
                child: Text(
                  key,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.normal,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
