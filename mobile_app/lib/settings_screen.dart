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
  bool _isLoadingSettings = true;

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
          _isLoadingSettings = false;

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

              // ── App Lock Toggle ──────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.3 : 0.05,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B9F1).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.security_rounded,
                      color: Color(0xFF00B9F1),
                      size: 24,
                    ),
                  ),
                  title: Text(
                    'App Lock',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  subtitle: Text(
                    'Require PIN to open ZaferPay',
                    style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                  value: _appLockEnabled,
                  onChanged: (value) async {
                    if (value) {
                      if (!_hasMpin) {
                        // If no PIN set, must set one first
                        await Navigator.pushNamed(
                          context,
                          '/change-mpin',
                          arguments: {'isSetOnly': true},
                        );
                      } else {
                        // Persist to Backend
                        await _api.updateSettings(appLockEnabled: true);
                        MyApp.appLockEnabled = true;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('app_lock_enabled', true);
                      }
                      _loadUserState(); // Refresh state
                    } else {
                      // Turning OFF lock screen
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
                        // Persist to Backend
                        await _api.updateSettings(appLockEnabled: false);
                        MyApp.appLockEnabled = false;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('app_lock_enabled', false);
                        _loadUserState(); // Refresh state
                      }
                    }
                  },
                  activeThumbColor: const Color(0xFF00B9F1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── PIN Settings Cards ──────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.3 : 0.05,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    if (_hasMpin) ...[
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF8A2BE2,
                            ).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.password_rounded,
                            color: Color(0xFF8A2BE2),
                            size: 24,
                          ),
                        ),
                        title: const Text(
                          'Change App Login PIN',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          'Update the PIN used to open ZaferPay',
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          await Navigator.pushNamed(context, '/change-mpin');
                          _loadUserState(); // Reload state unconditionally
                        },
                      ),
                      Divider(
                        height: 1,
                        indent: 20,
                        endIndent: 20,
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                      ),
                    ],
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6200EE).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.pin_rounded,
                          color: Color(0xFF6200EE),
                          size: 24,
                        ),
                      ),
                      title: const Text(
                        'Change UPI PIN',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        _pinUpdatedAtText,
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await Navigator.pushNamed(context, '/change-upi-pin');
                        _loadUserState(); // Reload state unconditionally
                      },
                    ),
                    Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade200,
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      secondary: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A2A7).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.fingerprint_rounded,
                          color: Color(0xFF00A2A7),
                          size: 24,
                        ),
                      ),
                      title: const Text(
                        'Biometric Login',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
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
                          fontSize: 13,
                        ),
                      ),
                      value: _biometricAvailable && _biometricEnabled,
                      onChanged: _biometricAvailable
                          ? (value) async {
                              bool confirmed = false;
                              if (value) {
                                // Enabling: Confirm via auth
                                confirmed = await _biometric.authenticate(
                                  reason:
                                      'Confirm your biometric to ENABLE this feature',
                                );
                              } else {
                                // Disabling: Security Check - Must auth to disable
                                confirmed = await _biometric.authenticate(
                                  reason:
                                      'Security Check: Confirm biometric to DISABLE this feature',
                                );
                              }

                              if (confirmed) {
                                await _biometric.setBiometricEnabled(value);
                                // Persist to Backend for multi-device/reinstall support
                                await _api.updateSettings(
                                  biometricEnabled: value,
                                );

                                if (mounted) {
                                  setState(() {
                                    _biometricEnabled = value;
                                  });
                                }
                              }
                            }
                          : null,
                      activeThumbColor: const Color(0xFF00B9F1),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Preferences ──────────────────────────────────────────────────
              if (!_isLoadingSettings) ...[
                Text(
                  'Preferences',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.grey[400] : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.3 : 0.05,
                        ),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(children: [_buildSummaryFrequencyTile(isDark)]),
                ),
                const SizedBox(height: 32),
              ],

              // ── Appearance ──────────────────────────────────────────────────
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.3 : 0.05,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ExpansionTile(
                  shape: const Border(), // Remove expanded border
                  collapsedShape: const Border(), // Remove collapsed border
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B9F1).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      color: const Color(0xFF00B9F1),
                      size: 24,
                    ),
                  ),
                  title: const Text(
                    'Theme',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
                        return RadioGroup<ThemeMode>(
                          groupValue: mode,
                          onChanged: (val) {
                            if (val != null) {
                              themeNotifier.value = val;
                            }
                          },
                          child: Column(
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
                                activeColor: const Color(0xFF00B9F1),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Logout ──────────────────────────────────────────────────────
              InkWell(
                onTap: _handleLogout,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.logout_rounded, color: Colors.red),
                      const SizedBox(width: 8),
                      const Text(
                        'Logout',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Center(
                child: Text(
                  'Powered by ZaferPay',
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

  String _getFrequencyLabel(int p) {
    if (p == 1) return 'Daily';
    if (p == 7) return 'Weekly';
    if (p == 14) return 'Bi-Weekly';
    if (p == 30) return 'Monthly';
    return '$p days';
  }

  Widget _buildSummaryFrequencyTile(bool isDark) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF00B9F1).withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.notifications_active_rounded,
          color: Color(0xFF00B9F1),
          size: 24,
        ),
      ),
      title: const Text(
        'Summary Notifications',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(
        'Frequency: ${_getFrequencyLabel(_summaryFrequency)}',
        style: TextStyle(
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          fontSize: 13,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () {
        _showFrequencyBottomSheet(isDark);
      },
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
}
