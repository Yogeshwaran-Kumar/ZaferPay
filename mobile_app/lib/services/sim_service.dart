import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:mobile_number/mobile_number.dart';
import 'package:permission_handler/permission_handler.dart';

class SimService {
  SimService._();
  static final SimService instance = SimService._();

  bool _isInit = false;

  /// Initialize the plugin and request permissions
  Future<void> init() async {
    if (_isInit) return;
    try {
      MobileNumber.listenPhonePermission((isGranted) {
        if (isGranted) {
          _isInit = true;
          debugPrint('[SimService] Phone permission granted via listener.');
        } else {
          debugPrint('[SimService] Phone permission denied via listener.');
        }
      });
    } catch (e) {
      debugPrint('[SimService] Failed to listen to phone permission: $e');
    }

    // Explicitly request if not already granted
    if (!await Permission.phone.isGranted) {
      await Permission.phone.request();
    }
    _isInit = true;
  }

  /// Check if the device has a valid SIM card
  Future<bool> hasSimCard() async {
    try {
      if (!kIsWeb) {
        if (!await Permission.phone.isGranted) return false;
        final List<SimCard>? sims = await MobileNumber.getSimCards;
        return sims != null && sims.isNotEmpty;
      }
      return false; // Web doesn't support SIM
    } catch (e) {
      debugPrint('[SimService] Error checking SIM presence: $e');
      // If the error explicitly says "Phone number is not available", it implies
      // the plugin failed to read the number (likely due to OS restrictions or carrier),
      // BUT the SIM itself is likely present and active.
      // We return true to allow the user to proceed to the next step (Soft Verification).
      if (e.toString().contains('Phone number is not available') ||
          e.toString().contains('UNAVAILABLE')) {
        return true;
      }
      return false;
    }
  }

  /// Get the mobile number of the first SIM card.
  /// Returns null if permission denied, no SIM, or OS restricts access.
  Future<String?> getMobileNumber() async {
    try {
      if (!kIsWeb) {
        if (!await Permission.phone.isGranted) return null;
        // On modern Android (11+), this often returns empty even with permission.
        final String? number = await MobileNumber.mobileNumber;
        return (number != null && number.isNotEmpty) ? number : null;
      }
    } catch (e) {
      debugPrint('[SimService] Error getting mobile number: $e');
    }
    return null;
  }

  /// Verifies if the user's input matches the SIM card.
  ///
  /// Strategy:
  /// 1. If NO Sim -> FAIL (Device Binding requires SIM)
  /// 2. If Sim Number available -> STRICT MATCH
  /// 3. If Sim Number hidden (null/empty) -> ALLOW (Soft match) to prevent blocking valid users
  Future<SimVerificationResult> verifySimMatch(String userInput) async {
    // 1. Permission Check
    if (!await Permission.phone.isGranted) {
      final status = await Permission.phone.request();
      if (!status.isGranted) {
        return SimVerificationResult(
          isValid: false,
          error: 'Phone permission is required for security verification.',
        );
      }
    }

    // 2. Presence Check
    final hasSim = await hasSimCard();
    if (!hasSim) {
      return SimVerificationResult(
        isValid: false,
        error: 'No SIM card detected. Please insert a SIM to continue.',
      );
    }

    // 3. Number Match
    final simNumber = await getMobileNumber();

    // Normalize logic (remove non-digits, country codes if needed)
    // For now, checks if the simNumber *contains* the userInput or vice-versa to handle +91 formats

    if (simNumber != null && simNumber.isNotEmpty) {
      final normalizedInput = _normalize(userInput);
      final normalizedSim = _normalize(simNumber);

      // Strict Match
      // We check if one ends with the other to handle +91 vs 0 vs raw
      if (normalizedSim.endsWith(normalizedInput) ||
          normalizedInput.endsWith(normalizedSim)) {
        return SimVerificationResult(isValid: true);
      } else {
        return SimVerificationResult(
          isValid: false,
          error:
              'The entered number ($userInput) does not match the SIM card detected on this device.',
        );
      }
    }

    // 4. Fallback (Hidden Number) -> Allow
    return SimVerificationResult(isValid: true, isSoftMatch: true);
  }

  String _normalize(String number) {
    return number.replaceAll(RegExp(r'\D'), ''); // Remove all non-digit chars
  }
}

class SimVerificationResult {
  final bool isValid;
  final String? error;
  final bool isSoftMatch; // True if we allowed it because number was hidden

  SimVerificationResult({
    required this.isValid,
    this.error,
    this.isSoftMatch = false,
  });
}
