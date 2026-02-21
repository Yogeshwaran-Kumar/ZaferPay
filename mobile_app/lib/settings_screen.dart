import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'main.dart';
import 'api_service.dart';
import 'services/biometric_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = const FlutterSecureStorage();
  final _api = ApiService();
  final _biometric = BiometricService();

  bool _biometricEnabled = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final available = await _biometric.isBiometricAvailable();
    final enabled = await _biometric.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
      });
    }
  }

  Future<void> _handleLogout() async {
    // Show confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      // Clear ALL data IMMEDIATELY on UI thread to prevent flashes
      await _api.wipeAllCaches();

      // Call backend logout...
      await _api.logout();
      // Clear all local storage
      await _storage.deleteAll();
      if (mounted) {
        // Navigate to login screen and remove all previous routes
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color,
          ),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        iconTheme: Theme.of(context).iconTheme,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Security',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 16),

              // ── Change PIN ──────────────────────────────────────────────────
              ListTile(
                leading: const Icon(Icons.lock_reset, color: Color(0xFF6200EE)),
                title: Text(
                  'Change PIN',
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                subtitle: Text(
                  'Update your account security PIN',
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                onTap: () {
                  Navigator.pushNamed(context, '/change-pin');
                },
                tileColor: Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Biometric Login ─────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                ),
                child: SwitchListTile(
                  secondary: Icon(
                    Icons.fingerprint,
                    color: _biometricAvailable
                        ? const Color(0xFF00B9F1)
                        : Colors.grey,
                  ),
                  title: Text(
                    'Biometric Login',
                    style: TextStyle(
                      color: _biometricAvailable
                          ? Theme.of(context).textTheme.bodyLarge?.color
                          : Colors.grey,
                    ),
                  ),
                  subtitle: Text(
                    _biometricAvailable
                        ? 'Use fingerprint or face to unlock the app'
                        : 'Not available on this device',
                    style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                  value: _biometricAvailable && _biometricEnabled,
                  onChanged: _biometricAvailable
                      ? (value) async {
                          // 1. Enabling: Confirm via auth
                          if (value) {
                            final confirmed = await _biometric.authenticate(
                              reason:
                                  'Confirm your biometric to ENABLE this feature',
                            );
                            if (!confirmed) return;
                          }
                          // 2. Disabling: Security Check - Must auth to disable
                          else {
                            final confirmed = await _biometric.authenticate(
                              reason:
                                  'Security Check: Confirm biometric to DISABLE this feature',
                            );
                            if (!confirmed) return;
                          }

                          await _biometric.setBiometricEnabled(value);
                          if (mounted) {
                            setState(() => _biometricEnabled = value);
                          }
                        }
                      : null,
                  activeThumbColor: const Color(0xFF00B9F1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Appearance ──────────────────────────────────────────────────
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                ),
                child: ExpansionTile(
                  shape: const Border(), // Remove expanded border
                  collapsedShape: const Border(), // Remove collapsed border
                  leading: const Icon(
                    Icons.brightness_6,
                    color: Color(0xFF00B9F1),
                  ),
                  title: Text(
                    'Theme',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  subtitle: ValueListenableBuilder<ThemeMode>(
                    valueListenable: themeNotifier,
                    builder: (context, mode, _) {
                      return Text(
                        mode == ThemeMode.light ? 'Light Mode' : 'Dark Mode',
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      );
                    },
                  ),
                  iconColor: isDark ? Colors.white70 : Colors.black54,
                  collapsedIconColor: isDark ? Colors.white70 : Colors.black54,
                  children: [
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: themeNotifier,
                      builder: (context, mode, _) {
                        return Column(
                          children: [
                            RadioListTile<ThemeMode>(
                              title: Text(
                                'Light Mode',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                              ),
                              value: ThemeMode.light,
                              // ignore: deprecated_member_use
                              groupValue: mode,
                              // ignore: deprecated_member_use
                              onChanged: (val) {
                                if (val != null) {
                                  themeNotifier.value = val;
                                }
                              },
                              activeColor: const Color(0xFF00B9F1),
                            ),
                            RadioListTile<ThemeMode>(
                              title: Text(
                                'Dark Mode',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                              ),
                              value: ThemeMode.dark,
                              // ignore: deprecated_member_use
                              groupValue: mode,
                              // ignore: deprecated_member_use
                              onChanged: (val) {
                                if (val != null) {
                                  themeNotifier.value = val;
                                }
                              },
                              activeColor: const Color(0xFF00B9F1),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Logout ──────────────────────────────────────────────────────
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: _handleLogout,
                tileColor: Colors.red.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.red.withValues(alpha: 0.1)),
                ),
              ),
              const SizedBox(height: 30),
              Center(
                child: Text(
                  'Powered by SafePay',
                  style: GoogleFonts.outfit(
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
