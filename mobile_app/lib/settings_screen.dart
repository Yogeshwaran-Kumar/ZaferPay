import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  bool _hasMpin = true;
  bool _appLockEnabled = true; // New persistent flag
  String _pinUpdatedAtText = 'Update the PIN used for transactions';

  int _summaryFrequency = 1;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
    _loadUserState();
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

  Future<void> _loadUserState() async {
    final user = await _api.getMe();
    if (user != null) {
      final bool serverLock = user['app_lock_enabled'] ?? true;
      final bool serverBio = user['biometric_enabled'] ?? false;

      // Update local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_lock_enabled', serverLock);
      await prefs.setBool('biometric_enabled', serverBio);

      // Update global state
      MyApp.appLockEnabled = serverLock;
      MyApp.biometricEnabled = serverBio;

      if (mounted) {
        setState(() {
          _hasMpin = user['has_mpin'] ?? true;
          _appLockEnabled = serverLock;
          _biometricEnabled = serverBio;
          _biometric.setBiometricEnabled(_biometricEnabled);

          _summaryFrequency = user['summary_frequency'] ?? 1;

          final pinUpdatedAt = user['pin_updated_at'];
          if (pinUpdatedAt != null) {
            try {
              final date = DateTime.parse(pinUpdatedAt);
              final diff = DateTime.now().difference(date).inDays;
              if (diff == 0) {
                _pinUpdatedAtText = 'Last changed: Today';
              } else {
                _pinUpdatedAtText = 'Last changed: $diff days ago';
              }
            } catch (_) {}
          }
        });
      }
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
    final iconColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color,
            fontSize: 20,
          ),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        iconTheme: Theme.of(context).iconTheme,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Security',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 12),

              _buildSwitchTile(
                icon: Icons.security_outlined,
                title: 'App Lock',
                subtitle: 'Require PIN to open ZaferPay',
                value: _appLockEnabled,
                onChanged: (value) async {
                  if (value) {
                    if (!_hasMpin) {
                      await Navigator.pushNamed(
                        context,
                        '/change-mpin',
                        arguments: {'isSetOnly': true},
                      );
                    } else {
                      await _api.updateSettings(appLockEnabled: true);
                      MyApp.appLockEnabled = true;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('app_lock_enabled', true);
                    }
                    _loadUserState();
                  } else {
                    bool? confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Disable App Lock?'),
                        content: const Text(
                          'Your app will open without a PIN.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Disable'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true) {
                      await _api.updateSettings(appLockEnabled: false);
                      MyApp.appLockEnabled = false;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('app_lock_enabled', false);
                      _loadUserState();
                    }
                  }
                },
                isDark: isDark,
                iconColor: iconColor,
              ),

              if (_hasMpin)
                _buildActionTile(
                  icon: Icons.password_outlined,
                  title: 'Change App Login PIN',
                  subtitle: 'Update the PIN used to open ZaferPay',
                  onTap: () async {
                    await Navigator.pushNamed(context, '/change-mpin');
                    _loadUserState();
                  },
                  isDark: isDark,
                  iconColor: iconColor,
                ),

              _buildActionTile(
                icon: Icons.pin_outlined,
                title: 'Change UPI PIN',
                subtitle: _pinUpdatedAtText,
                onTap: () async {
                  await Navigator.pushNamed(context, '/change-upi-pin');
                  _loadUserState();
                },
                isDark: isDark,
                iconColor: iconColor,
              ),

              _buildSwitchTile(
                icon: Icons.fingerprint_outlined,
                title: 'Biometric Login',
                subtitle: _biometricAvailable
                    ? 'Use fingerprint or face to unlock the app'
                    : 'Not available on this device',
                value: _biometricAvailable && _biometricEnabled,
                onChanged: _biometricAvailable
                    ? (value) async {
                        bool confirmed = false;
                        if (value) {
                          confirmed = await _biometric.authenticate(
                            reason:
                                'Confirm your biometric to ENABLE this feature',
                          );
                        } else {
                          confirmed = await _biometric.authenticate(
                            reason:
                                'Security Check: Confirm biometric to DISABLE this feature',
                          );
                        }

                        if (confirmed) {
                          await _biometric.setBiometricEnabled(value);
                          await _api.updateSettings(biometricEnabled: value);

                          if (mounted) {
                            setState(() {
                              _biometricEnabled = value;
                            });
                          }
                        }
                      }
                    : null,
                isDark: isDark,
                iconColor: iconColor,
              ),

              const SizedBox(height: 32),
              Text(
                'Preferences',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 12),

              _buildSummaryFrequencyTile(isDark, iconColor),

              const SizedBox(height: 32),
              Text(
                'Appearance',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 12),

              ValueListenableBuilder<ThemeMode>(
                valueListenable: themeNotifier,
                builder: (context, mode, _) {
                  return _buildActionTile(
                    icon: mode == ThemeMode.dark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                    title: 'Theme',
                    subtitle: mode == ThemeMode.dark
                        ? 'Dark Mode'
                        : 'Light Mode',
                    onTap: () {
                      _showThemeBottomSheet(isDark);
                    },
                    isDark: isDark,
                    iconColor: iconColor,
                  );
                },
              ),

              const SizedBox(height: 48),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.logout_rounded,
                  color: Colors.red,
                  size: 28,
                ),
                title: const Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
                onTap: _handleLogout,
              ),

              const SizedBox(height: 40),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: Colors.grey.shade400,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Powered by ZaferPay',
                      style: GoogleFonts.outfit(
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool)? onChanged,
    required bool isDark,
    required Color iconColor,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: iconColor, size: 28),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 16,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          fontSize: 13,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: const Color(
          0xFF00B9F1,
        ), // wait the error says Use activeColor on what? or activeTrackColor?
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
    required Color iconColor,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: iconColor, size: 28),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 16,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          fontSize: 13,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
        size: 24,
      ),
      onTap: onTap,
    );
  }

  String _getFrequencyLabel(int p) {
    if (p == 1) return 'Daily';
    if (p == 7) return 'Weekly';
    if (p == 14) return 'Bi-Weekly';
    if (p == 30) return 'Monthly';
    return '$p days';
  }

  Widget _buildSummaryFrequencyTile(bool isDark, Color iconColor) {
    return _buildActionTile(
      icon: Icons.notifications_outlined,
      title: 'Summary Notifications',
      subtitle: 'Frequency: ${_getFrequencyLabel(_summaryFrequency)}',
      onTap: () {
        _showFrequencyBottomSheet(isDark);
      },
      isDark: isDark,
      iconColor: iconColor,
    );
  }

  void _showFrequencyBottomSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                'Summary Frequency',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              ...[1, 7, 14, 30].map((f) {
                return ListTile(
                  title: Text(_getFrequencyLabel(f)),
                  trailing: _summaryFrequency == f
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF00B9F1),
                        )
                      : null,
                  onTap: () async {
                    Navigator.pop(context);
                    if (_summaryFrequency != f) {
                      setState(() {
                        _summaryFrequency = f;
                      });
                      await _api.updateSettings(summaryFrequency: f);
                    }
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showThemeBottomSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                'Theme',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Light Mode'),
                trailing: themeNotifier.value == ThemeMode.light
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF00B9F1),
                      )
                    : null,
                onTap: () {
                  themeNotifier.value = ThemeMode.light;
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Dark Mode'),
                trailing: themeNotifier.value == ThemeMode.dark
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF00B9F1),
                      )
                    : null,
                onTap: () {
                  themeNotifier.value = ThemeMode.dark;
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
