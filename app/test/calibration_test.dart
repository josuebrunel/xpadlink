import 'package:flutter_test/flutter_test.dart';
import 'package:xpadlink/calibration.dart';
import 'package:xpadlink/protocol.dart';

void main() {
  test('defaults pass triggers through and keep the 8% deadzone', () {
    final c = PadCalibration();
    expect(c.lt(0), 0);
    expect(c.lt(200), 200);
    expect(c.lx(1000), 0); // 3% of full, inside the deadzone
    expect(c.lx(32767), 32767);
  });

  test('a trigger that tops out at 200 rescales to 255', () {
    final c = PadCalibration(rtMin: 10, rtMax: 200);
    expect(c.rt(10), 0);
    expect(c.rt(200), 255);
    expect(c.rt(105), 128);
    expect(c.rt(250), 255);
    expect(c.rt(0), 0);
  });

  test('an unusable trigger range is left alone', () {
    final c = PadCalibration(ltMin: 100, ltMax: 110);
    expect(c.lt(105), 105);
  });

  test('stick recenters, rescales to its reach and applies the deadzone', () {
    final c = PadCalibration(lcx: 2000, lrx: 30000);
    expect(c.lx(2000), 0);
    expect(c.lx(2500), 0);
    expect(c.lx(32000), 32767);
    expect(c.lx(-28000), -32767);
  });

  test('pad calibration round trips through json', () {
    final c = PadCalibration(ltMin: 5, ltMax: 220, lcx: 300, deadzone: 0.12);
    final r = PadCalibration.fromJson(c.toJson());
    expect(r.ltMin, 5);
    expect(r.ltMax, 220);
    expect(r.lcx, 300);
    expect(r.deadzone, 0.12);
  });

  test('motion subtracts the gyro bias and flips roll', () {
    final m = MotionCalibration(gyroBias: [1, 2, 3], flipRoll: true);
    final out = m.apply(PadMotion([0.5, 0.1, 1.0], [2, 4, 6]));
    expect(out.accel, [-0.5, 0.1, 1.0]);
    expect(out.gyro, [1, 2, -3]);
  });

  test('motion without flip keeps the axes', () {
    final out = MotionCalibration().apply(PadMotion([0.5, 0, 0], [0, 0, 1]));
    expect(out.accel[0], 0.5);
    expect(out.gyro[2], 1);
  });

  test('motion inverts pitch, yaw, and roll with sensitivity multiplier', () {
    final m = MotionCalibration(
      invertPitch: true,
      invertYaw: true,
      invertRoll: true,
      sensitivity: 2.0,
    );
    final inMotion = PadMotion([0.4, 0.8, 1.0], [10.0, 20.0, 30.0]);
    final out = m.apply(inMotion);

    // Pitch inverts accel y (a[1]) and gyro x (g[0])
    expect(out.accel[1], -0.8);
    expect(out.gyro[0], -20.0); // 10.0 * 2.0 negated

    // Yaw inverts gyro y (g[1])
    expect(out.gyro[1], -40.0); // 20.0 * 2.0 negated

    // Roll inverts accel x (a[0]) and gyro z (g[2])
    expect(out.accel[0], -0.4);
    expect(out.gyro[2], -60.0); // 30.0 * 2.0 negated
  });

  test('motion calibration round trips through json', () {
    final m = MotionCalibration(
      gyroBias: [0.12, -0.34, 0.56],
      invertPitch: true,
      invertYaw: false,
      invertRoll: true,
      sensitivity: 1.5,
      useAccelFallback: true,
    );
    final j = m.toJson();
    final restored = MotionCalibration.fromJson(j);

    expect(restored.gyroBias, [0.12, -0.34, 0.56]);
    expect(restored.invertPitch, isTrue);
    expect(restored.invertYaw, isFalse);
    expect(restored.invertRoll, isTrue);
    expect(restored.sensitivity, 1.5);
    expect(restored.useAccelFallback, isTrue);
  });
}
