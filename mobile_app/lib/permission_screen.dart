import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

/// A mandatory permission gateway screen.
/// Push this screen and await the result.
/// Returns `true` if both Phone & Contacts permissions are granted.
/// Returns `false` (or null via back) if denied.
class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  bool _isLoading = false;
  bool _returnedFromSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _returnedFromSettings) {
      _returnedFromSettings = false;
      // Re-check permissions when user comes back from Settings
      _checkAndReturn();
    }
  }

  Future<void> _checkAndReturn() async {
    final phoneGranted = await Permission.phone.isGranted;
    final contactsGranted = await Permission.contacts.isGranted;

    if (phoneGranted && contactsGranted && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);

    // Request both permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.phone,
      Permission.contacts,
    ].request();

    final phoneStatus = statuses[Permission.phone]!;
    final contactsStatus = statuses[Permission.contacts]!;

    if (phoneStatus.isGranted && contactsStatus.isGranted) {
      if (!mounted) return;
      Navigator.pop(context, true);
      return;
    }

    if (mounted) {
      setState(() => _isLoading = false);

      // If any is permanently denied, show dialog to open settings
      if (phoneStatus.isPermanentlyDenied ||
          contactsStatus.isPermanentlyDenied) {
        _showSettingsDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Phone and Contacts permissions are mandatory to use ZaferPay.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
          'ZaferPay strictly requires Phone and Contacts access for secure device binding and payments. Please enable them in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _returnedFromSettings = true;
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // User cannot skip this screen
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Color(0xFFE1F5FE)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 32.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(),

                  // Security Icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF00B9F1).withValues(alpha: 0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00B9F1).withValues(alpha: 0.1),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.security_rounded,
                      size: 60,
                      color: Color(0xFF00B9F1),
                    ),
                  ),
                  const SizedBox(height: 32),

                  Text(
                    'Essential Permissions',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'To ensure absolute security and provide a seamless payment experience, ZaferPay requires access to your Phone and Contacts.',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      color: Colors.black54,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Permission List
                  _buildPermissionItem(
                    icon: Icons.phone_android_rounded,
                    title: 'Phone State Access',
                    subtitle:
                        'Mandatory for secure device binding (SIM verification).',
                  ),
                  const SizedBox(height: 24),
                  _buildPermissionItem(
                    icon: Icons.contacts_rounded,
                    title: 'Contacts Access',
                    subtitle:
                        'Navigate your contacts easily for blazing fast UPI payments.',
                  ),

                  const Spacer(),

                  // Allow Access Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _requestPermissions,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B9F1),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Allow Access',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'These permissions are strictly required.',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF00B9F1).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF00B9F1), size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
