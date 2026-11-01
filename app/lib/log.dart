import 'package:flutter/foundation.dart';

/// Minimal leveled logger. Output goes to logcat (`adb logcat -s flutter`),
/// prefixed with "xpadlink" so it can be grepped next to the Kotlin side,
/// which logs with the tag "xpadlink".
class Log {
  Log(this.scope);

  final String scope;

  /// Identical error messages are throttled so a failing 60 Hz send loop
  /// doesn't flood logcat.
  static final _lastByMsg = <String, DateTime>{};
  static const _throttle = Duration(seconds: 2);

  void d(String msg) => _out('D', msg);
  void i(String msg) => _out('I', msg);
  void w(String msg) => _out('W', msg);

  void e(String msg, [Object? err, StackTrace? st]) {
    final full = err == null ? msg : '$msg: $err';
    final now = DateTime.now();
    final last = _lastByMsg[full];
    if (last != null && now.difference(last) < _throttle) return;
    _lastByMsg[full] = now;
    _out('E', full);
    if (st != null) _out('E', st.toString());
  }

  void _out(String level, String msg) {
    final t = DateTime.now().toIso8601String().substring(11, 23);
    debugPrint('xpadlink $t $level [$scope] $msg');
  }
}
