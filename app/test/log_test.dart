import 'package:flutter_test/flutter_test.dart';
import 'package:xpadlink/log.dart';

void main() {
  setUp(() {
    Log.resetThrottleForTest();
  });

  test('Log.e caps tracked throttle entries at maxThrottleEntries', () {
    final log = Log('test');
    for (var i = 0; i < Log.maxThrottleEntries + 50; i++) {
      log.e('unique error $i');
    }
    expect(Log.trackedErrorCount, lessThanOrEqualTo(Log.maxThrottleEntries));
  });

  test('Log.e suppresses duplicate errors within throttle window', () {
    final log = Log('test');
    log.e('same error');
    log.e('same error');
    expect(Log.trackedErrorCount, 1);
  });
}
