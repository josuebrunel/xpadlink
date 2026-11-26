import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shared broadcast streams for native EventChannels so concurrent listeners
/// (e.g. ControllerScreen + CalibrationScreen / gyro bias sampling) share a
/// single platform EventSink without cancelling each other.
class NativeStreams {
  NativeStreams._();

  static const _gamepadChannel = EventChannel('xpadlink/gamepad');
  static const _motionChannel = EventChannel('xpadlink/motion');

  static Stream<dynamic>? _gamepad;
  static Stream<dynamic>? _motion;

  static Stream<dynamic> get gamepad =>
      _gamepad ??= _gamepadChannel.receiveBroadcastStream();

  static Stream<dynamic> get motion =>
      _motion ??= _motionChannel.receiveBroadcastStream();

  @visibleForTesting
  static void resetForTest() {
    _gamepad = null;
    _motion = null;
  }
}
