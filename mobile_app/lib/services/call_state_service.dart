import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_state/phone_state.dart';

/// Singleton service that detects active phone calls (incoming/outgoing).
/// Uses the `phone_state` package + READ_PHONE_STATE permission.
///
/// Usage:
///   final service = CallStateService.instance;
///   await service.init();
///   bool onCall = service.isOnCall;
///   service.stream.listen((onCall) { ... });
class CallStateService {
  CallStateService._();
  static final CallStateService instance = CallStateService._();

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
    return true;
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
      _controller.add(_isOnCall);
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}
