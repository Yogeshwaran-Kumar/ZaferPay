import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_state/phone_state.dart';

/// Singleton service that detects active phone calls (incoming/outgoing).
/// Uses the `phone_state` package + READ_PHONE_STATE permission.
class CallStateService with WidgetsBindingObserver {
  CallStateService._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final CallStateService instance = CallStateService._();

  static const MethodChannel _channel = MethodChannel(
    'com.company.zaferpay/security',
  );

  bool _isOnCall = false;
  StreamSubscription<PhoneState>? _subscription;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  /// Whether the device is currently on a call.
  bool get isOnCall => _isOnCall;

  /// Stream that emits `true` when a call starts and `false` when it ends.
  Stream<bool> get stream => _controller.stream;

  /// Checks if the READ_PHONE_STATE permission is granted.
  Future<bool> hasPermission() async {
    if (kIsWeb) return true;
    return await Permission.phone.isGranted;
  }

  /// Initialises the call state listener. Safe to call multiple times.
  /// Returns true if initialized with permission, false otherwise.
  Future<bool> init() async {
    if (_subscription != null) return true; // already listening

    // Request permission (Android requires READ_PHONE_STATE)
    if (!kIsWeb) {
      final status = await Permission.phone.request();
      if (!status.isGranted) {
        debugPrint('[CallStateService] Phone state permission denied.');
        return false;
      }
    }

    _subscription = PhoneState.stream.listen(_onPhoneStateChanged);

    // Try checking instantaneous state via native channel
    if (!kIsWeb) {
      try {
        final bool isNowOnCall =
            await _channel.invokeMethod('checkCallState') ?? false;
        if (_isOnCall != isNowOnCall) {
          _isOnCall = isNowOnCall;
          _controller.add(_isOnCall);
          debugPrint(
            '[CallStateService] Initial call state via native: $_isOnCall',
          );
        }
      } catch (e) {
        debugPrint('[CallStateService] Error checking native state: $e');
      }
    }

    return true;
  }

  /// Directly queries Android OS for the current call state.
  /// This is completely independent of the phone_state stream.
  /// Returns true if the user is currently on a call.
  static Future<bool> isCurrentlyOnCall() async {
    if (kIsWeb) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>('checkCallState');
      debugPrint('[CallStateService] Native isCurrentlyOnCall => $result');
      return result ?? false;
    } catch (e) {
      debugPrint('[CallStateService] Native call check failed: $e');
      // Fail-closed: if we can't check, assume on call for safety
      return false;
    }
  }

  void _onPhoneStateChanged(PhoneState state) {
    final bool wasOnCall = _isOnCall;

    switch (state.status) {
      case PhoneStateStatus.CALL_INCOMING:
      case PhoneStateStatus.CALL_STARTED:
        _isOnCall = true;
        break;
      case PhoneStateStatus.CALL_ENDED:
      case PhoneStateStatus.NOTHING:
        _isOnCall = false;
        break;
    }

    if (_isOnCall != wasOnCall) {
      debugPrint('[CallStateService] Call state changed to: $_isOnCall');
      _controller.add(_isOnCall);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app comes back to the foreground, ensure our listener is active if we have permission.
    if (state == AppLifecycleState.resumed) {
      hasPermission().then((granted) {
        if (granted && _subscription == null) {
          init();
        }
      });
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}
