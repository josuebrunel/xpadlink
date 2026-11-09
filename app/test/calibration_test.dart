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
}
