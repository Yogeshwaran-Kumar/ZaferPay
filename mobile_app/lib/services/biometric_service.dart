import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles biometric authentication (fingerprint / face unlock).
/// Works as a thin wrapper around `local_auth` with a user-preference toggle.
class BiometricService {
  BiometricService._();
  static final BiometricService _instance = BiometricService._();
  factory BiometricService() => _instance;

  final LocalAuthentication _auth = LocalAuthentication();
  static const String _prefKey = 'biometric_enabled';

  // ─── Availability ───────────────────────────────────────────────────────────

  /// Returns true if the device has biometric hardware AND enrolled biometrics.
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;

      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ─── User Preference ────────────────────────────────────────────────────────

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  // ─── Authentication ─────────────────────────────────────────────────────────

  /// Triggers the system biometric prompt.
  /// Returns `true` on success, `false` on failure/cancel.
  Future<bool> authenticate({
    String reason = 'Use your biometric to unlock SafePay',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true, // Keep prompt alive when app goes background
          biometricOnly:
              false, // Allow device credential (PIN/pattern) fallback
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Convenience: check enabled + available + authenticate in one call.
  /// Returns `true` only when biometrics are enabled, available, and the
  /// user successfully authenticates.
  Future<bool> tryBiometricUnlock() async {
    final enabled = await isBiometricEnabled();
    if (!enabled) return false;
    final available = await isBiometricAvailable();
    if (!available) return false;
    return authenticate();
  }
}
