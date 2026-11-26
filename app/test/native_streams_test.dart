import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpadlink/native_streams.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    NativeStreams.resetForTest();
  });

  test(
      'NativeStreams.motion fans out to concurrent listeners and only cancels native sink when last listener leaves',
      () async {
    var listens = 0;
    var cancels = 0;
    const channel = MethodChannel('xpadlink/motion');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listen') listens++;
      if (call.method == 'cancel') cancels++;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    final received1 = <dynamic>[];
    final received2 = <dynamic>[];

    final sub1 = NativeStreams.motion.listen(received1.add);
    final sub2 = NativeStreams.motion.listen(received2.add);
    await Future<void>.delayed(Duration.zero);
    expect(listens, 1);
    expect(cancels, 0);

    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'xpadlink/motion',
      codec.encodeSuccessEnvelope(<double>[0, 0, 1, 1, 2, 3]),
      null,
    );
    expect(received1.length, 1);
    expect(received2.length, 1);

    // Secondary consumer (Calibration / Measure Zero Point) closes: native sink must stay alive
    await sub2.cancel();
    expect(cancels, 0);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'xpadlink/motion',
      codec.encodeSuccessEnvelope(<double>[0, 0, 1, 4, 5, 6]),
      null,
    );
    expect(received1.length, 2);

    // Primary consumer closes: native sink cancels once
    await sub1.cancel();
    expect(cancels, 1);
  });

  test(
      'NativeStreams.gamepad fans out to concurrent listeners and only cancels native sink when last listener leaves',
      () async {
    var listens = 0;
    var cancels = 0;
    const channel = MethodChannel('xpadlink/gamepad');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listen') listens++;
      if (call.method == 'cancel') cancels++;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    final received1 = <dynamic>[];
    final received2 = <dynamic>[];

    final sub1 = NativeStreams.gamepad.listen(received1.add);
    final sub2 = NativeStreams.gamepad.listen(received2.add);
    await Future<void>.delayed(Duration.zero);
    expect(listens, 1);
    expect(cancels, 0);

    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'xpadlink/gamepad',
      codec.encodeSuccessEnvelope({'name': 'pad', 'buttons': 1}),
      null,
    );
    expect(received1.length, 1);
    expect(received2.length, 1);

    await sub2.cancel();
    expect(cancels, 0);

    await sub1.cancel();
    expect(cancels, 1);
  });
}
