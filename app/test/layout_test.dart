import 'package:flutter_test/flutter_test.dart';
import 'package:xpadlink/layout.dart';

void main() {
  test('default xbox layout contains all standard controls', () {
    final cfg = PadLayoutConfig.defaultXbox();
    for (final id in ControlId.all) {
      final elem = cfg.getElement(id);
      expect(elem.id, id);
      expect(elem.visible, isTrue);
      expect(elem.scale, 1.0);
      expect(elem.relX >= 0.0 && elem.relX <= 1.0, isTrue);
      expect(elem.relY >= 0.0 && elem.relY <= 1.0, isTrue);
    }
  });

  test('pad layout config round trips through json', () {
    final cfg = PadLayoutConfig.defaultXbox();
    cfg.opacity = 0.55;
    cfg.hapticsEnabled = false;
    cfg.snapToGrid = true;
    cfg.getElement(ControlId.dpad).scale = 1.35;
    cfg.getElement(ControlId.l3).visible = false;
    cfg.getElement(ControlId.leftStick).relX = 0.32;
    cfg.getElement(ControlId.leftStick).relY = 0.44;

    final json = cfg.toJson();
    final restored = PadLayoutConfig.fromJson(json);

    expect(restored.opacity, 0.55);
    expect(restored.hapticsEnabled, isFalse);
    expect(restored.snapToGrid, isTrue);
    expect(restored.getElement(ControlId.dpad).scale, 1.35);
    expect(restored.getElement(ControlId.l3).visible, isFalse);
    expect(restored.getElement(ControlId.leftStick).relX, 0.32);
    expect(restored.getElement(ControlId.leftStick).relY, 0.44);
  });

  test('resetElement restores default position and scale for that element', () {
    final cfg = PadLayoutConfig.defaultXbox();
    final dpad = cfg.getElement(ControlId.dpad);
    dpad.scale = 1.8;
    dpad.relX = 0.05;
    dpad.relY = 0.05;
    dpad.visible = false;

    cfg.resetElement(ControlId.dpad);

    final restoredDpad = cfg.getElement(ControlId.dpad);
    expect(restoredDpad.scale, 1.0);
    expect(restoredDpad.relX, 0.24);
    expect(restoredDpad.relY, 0.76);
    expect(restoredDpad.visible, isTrue);
  });

  test('playStation preset has symmetrical sticks at bottom', () {
    final cfg = PadLayoutConfig.playStation();
    final ls = cfg.getElement(ControlId.leftStick);
    final rs = cfg.getElement(ControlId.rightStick);
    final dpad = cfg.getElement(ControlId.dpad);
    final abxy = cfg.getElement(ControlId.abxy);

    // Both sticks near bottom
    expect(ls.relY, 0.76);
    expect(rs.relY, 0.76);
    // D-pad and ABXY near top
    expect(dpad.relY, 0.38);
    expect(abxy.relY, 0.38);
  });

  test('southpaw preset swaps sticks and action buttons', () {
    final cfg = PadLayoutConfig.southpaw();
    final rs = cfg.getElement(ControlId.rightStick);
    final ls = cfg.getElement(ControlId.leftStick);
    final dpad = cfg.getElement(ControlId.dpad);
    final abxy = cfg.getElement(ControlId.abxy);

    // Right stick on the left side
    expect(rs.relX < 0.5, isTrue);
    // Left stick on the right side
    expect(ls.relX > 0.5, isTrue);
    // ABXY on the left side, D-pad on the right side
    expect(abxy.relX < 0.5, isTrue);
    expect(dpad.relX > 0.5, isTrue);
  });

  test('retro2D preset hides analog sticks and enlarges dpad/abxy', () {
    final cfg = PadLayoutConfig.retro2D();
    expect(cfg.getElement(ControlId.leftStick).visible, isFalse);
    expect(cfg.getElement(ControlId.rightStick).visible, isFalse);
    expect(cfg.getElement(ControlId.l3).visible, isFalse);
    expect(cfg.getElement(ControlId.r3).visible, isFalse);
    expect(cfg.getElement(ControlId.dpad).scale, 1.35);
    expect(cfg.getElement(ControlId.abxy).scale, 1.35);
  });

  test('claw preset stacks triggers and bumpers vertically', () {
    final cfg = PadLayoutConfig.claw();
    final lt = cfg.getElement(ControlId.lt);
    final lb = cfg.getElement(ControlId.lb);
    final rt = cfg.getElement(ControlId.rt);
    final rb = cfg.getElement(ControlId.rb);

    expect(lt.relX, lb.relX);
    expect(lt.relY < lb.relY, isTrue);
    expect(rt.relX, rb.relX);
    expect(rt.relY < rb.relY, isTrue);
  });

  test('deep clone creates independent copy', () {
    final cfg = PadLayoutConfig.defaultXbox();
    final clone = cfg.clone();

    clone.opacity = 0.2;
    clone.getElement(ControlId.lt).relX = 0.99;

    expect(cfg.opacity, 0.85);
    expect(cfg.getElement(ControlId.lt).relX, 0.10);
  });
}
