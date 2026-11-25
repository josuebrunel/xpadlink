import 'package:flutter_test/flutter_test.dart';
import 'package:xpadlink/layout.dart';

void main() {
  test('default xbox layout contains all 20 individual controls', () {
    final cfg = PadLayoutConfig.defaultXbox();
    expect(ControlId.all.length, 20);
    expect(ControlId.all.contains(ControlId.btnA), isTrue);
    expect(ControlId.all.contains(ControlId.btnB), isTrue);
    expect(ControlId.all.contains(ControlId.btnX), isTrue);
    expect(ControlId.all.contains(ControlId.btnY), isTrue);
    expect(ControlId.all.contains(ControlId.dpadUp), isTrue);
    expect(ControlId.all.contains(ControlId.dpadDown), isTrue);
    expect(ControlId.all.contains(ControlId.dpadLeft), isTrue);
    expect(ControlId.all.contains(ControlId.dpadRight), isTrue);
    expect(ControlId.all.contains(ControlId.btnView), isTrue);
    expect(ControlId.all.contains(ControlId.btnGuide), isTrue);
    expect(ControlId.all.contains(ControlId.btnMenu), isTrue);

    for (final id in ControlId.all) {
      final elem = cfg.getElement(id);
      expect(elem.id, id);
      expect(elem.visible, isTrue);
      expect(elem.scale, 1.0);
      expect(elem.relX >= 0.0 && elem.relX <= 1.0, isTrue);
      expect(elem.relY >= 0.0 && elem.relY <= 1.0, isTrue);
    }

    // ABXY diamond orientation
    expect(cfg.getElement(ControlId.btnY).relY < cfg.getElement(ControlId.btnA).relY, isTrue);
    expect(cfg.getElement(ControlId.btnX).relX < cfg.getElement(ControlId.btnB).relX, isTrue);
    // Center cluster sits cleanly below floating menuButton
    expect(cfg.getElement(ControlId.btnGuide).relY > cfg.getElement(ControlId.menuButton).relY, isTrue);
  });

  test('pad layout config round trips through json with version 2', () {
    final cfg = PadLayoutConfig.defaultXbox();
    cfg.opacity = 0.55;
    cfg.hapticsEnabled = false;
    cfg.snapToGrid = true;
    cfg.getElement(ControlId.btnX).scale = 1.35;
    cfg.getElement(ControlId.btnX).relX = 0.62;
    cfg.getElement(ControlId.btnX).relY = 0.48;
    cfg.getElement(ControlId.l3).visible = false;
    cfg.getElement(ControlId.leftStick).relX = 0.32;
    cfg.getElement(ControlId.leftStick).relY = 0.44;

    final json = cfg.toJson();
    expect(json['version'], 2);

    final restored = PadLayoutConfig.fromJson(json);
    expect(restored.opacity, 0.55);
    expect(restored.hapticsEnabled, isFalse);
    expect(restored.snapToGrid, isTrue);
    expect(restored.getElement(ControlId.btnX).scale, 1.35);
    expect(restored.getElement(ControlId.btnX).relX, 0.62);
    expect(restored.getElement(ControlId.btnX).relY, 0.48);
    expect(restored.getElement(ControlId.btnA).scale, 1.0);
    expect(restored.getElement(ControlId.l3).visible, isFalse);
    expect(restored.getElement(ControlId.leftStick).relX, 0.32);
    expect(restored.getElement(ControlId.leftStick).relY, 0.44);
  });

  test('migrates legacy v1 json (abxy, dpad, center) into individual controls', () {
    final legacyJson = <String, dynamic>{
      'opacity': 0.75,
      'hapticsEnabled': true,
      'snapToGrid': false,
      'elements': {
        'lt': {'id': 'lt', 'relX': 0.12, 'relY': 0.08, 'scale': 1.0, 'visible': true},
        'dpad': {'id': 'dpad', 'relX': 0.25, 'relY': 0.70, 'scale': 1.2, 'visible': true},
        'abxy': {'id': 'abxy', 'relX': 0.80, 'relY': 0.45, 'scale': 1.4, 'visible': true},
        'center': {'id': 'center', 'relX': 0.50, 'relY': 0.18, 'scale': 0.9, 'visible': false},
      },
    };

    final migrated = PadLayoutConfig.fromJson(legacyJson);

    // Legacy bundle keys are not kept in elements
    expect(migrated.elements.containsKey(ControlId.legacyAbxy), isFalse);
    expect(migrated.elements.containsKey(ControlId.legacyDpad), isFalse);
    expect(migrated.elements.containsKey(ControlId.legacyCenter), isFalse);

    // Individual buttons inherit position, scale, and visibility from legacy bundle
    for (final id in ControlId.abxyGroup) {
      expect(migrated.getElement(id).scale, 1.4);
      expect(migrated.getElement(id).visible, isTrue);
    }
    expect(migrated.getElement(ControlId.btnX).relX < migrated.getElement(ControlId.btnB).relX, isTrue);
    expect(migrated.getElement(ControlId.btnY).relY < migrated.getElement(ControlId.btnA).relY, isTrue);

    for (final id in ControlId.dpadGroup) {
      expect(migrated.getElement(id).scale, 1.2);
      expect(migrated.getElement(id).visible, isTrue);
    }
    expect(migrated.getElement(ControlId.dpadLeft).relX < 0.25, isTrue);
    expect(migrated.getElement(ControlId.dpadUp).relY < 0.70, isTrue);

    for (final id in ControlId.centerGroup) {
      expect(migrated.getElement(id).scale, 0.9);
      expect(migrated.getElement(id).visible, isFalse);
    }
    expect(migrated.getElement(ControlId.btnGuide).relX, closeTo(0.50, 0.001));
    expect(migrated.getElement(ControlId.btnView).relX < 0.50, isTrue);
    expect(migrated.getElement(ControlId.btnMenu).relX > 0.50, isTrue);
    expect(migrated.getElement(ControlId.lt).relX, 0.12);
  });

  test('SOLO mode moves, scales, hides and resets a single button independently', () {
    final cfg = PadLayoutConfig.defaultXbox();
    final origAX = cfg.getElement(ControlId.btnA).relX;
    final origAY = cfg.getElement(ControlId.btnA).relY;
    final origBX = cfg.getElement(ControlId.btnB).relX;

    cfg.moveControl(ControlId.btnX, 0.62, 0.52, groupMode: false);
    expect(cfg.getElement(ControlId.btnX).relX, closeTo(0.62, 0.0001));
    expect(cfg.getElement(ControlId.btnX).relY, closeTo(0.52, 0.0001));
    expect(cfg.getElement(ControlId.btnA).relX, origAX);
    expect(cfg.getElement(ControlId.btnA).relY, origAY);
    expect(cfg.getElement(ControlId.btnB).relX, origBX);

    cfg.scaleControl(ControlId.btnX, 0.25, groupMode: false);
    expect(cfg.getElement(ControlId.btnX).scale, 1.25);
    expect(cfg.getElement(ControlId.btnA).scale, 1.0);
    expect(cfg.getElement(ControlId.btnB).scale, 1.0);

    cfg.toggleVisibility(ControlId.btnGuide, groupMode: false);
    expect(cfg.getElement(ControlId.btnGuide).visible, isFalse);
    expect(cfg.getElement(ControlId.btnView).visible, isTrue);
    expect(cfg.getElement(ControlId.btnMenu).visible, isTrue);

    cfg.resetControl(ControlId.btnX, groupMode: false);
    expect(cfg.getElement(ControlId.btnX).scale, 1.0);
    expect(cfg.getElement(ControlId.btnX).relX, closeTo(0.775, 0.0001));
  });

  test('GROUP mode moves rigidly with edge clamping and scales around centroid', () {
    final cfg = PadLayoutConfig.defaultXbox();
    final startX = cfg.getElement(ControlId.btnX).relX;
    final startB = cfg.getElement(ControlId.btnB).relX;
    final spanXB = startB - startX;

    // Move group right past edge: rigid clamp must preserve internal spacing
    cfg.moveControl(ControlId.btnX, 0.95, 0.40, groupMode: true);
    expect(cfg.getElement(ControlId.btnB).relX, closeTo(0.99, 0.0001));
    expect(cfg.getElement(ControlId.btnB).relX - cfg.getElement(ControlId.btnX).relX,
        closeTo(spanXB, 0.0001));

    // Reset and test proportional scaling around centroid
    cfg.resetControl(ControlId.btnX, groupMode: true);
    final beforeDist = cfg.getElement(ControlId.btnB).relX - cfg.getElement(ControlId.btnX).relX;
    cfg.scaleControl(ControlId.btnY, 0.20, groupMode: true);
    for (final id in ControlId.abxyGroup) {
      expect(cfg.getElement(id).scale, 1.20);
    }
    final afterDist = cfg.getElement(ControlId.btnB).relX - cfg.getElement(ControlId.btnX).relX;
    expect(afterDist, closeTo(beforeDist * 1.20, 0.001));

    // Group visibility & reset on D-Pad
    cfg.toggleVisibility(ControlId.dpadUp, groupMode: true);
    for (final id in ControlId.dpadGroup) {
      expect(cfg.getElement(id).visible, isFalse);
    }
    cfg.resetControl(ControlId.dpadUp, groupMode: true);
    for (final id in ControlId.dpadGroup) {
      expect(cfg.getElement(id).visible, isTrue);
      expect(cfg.getElement(id).scale, 1.0);
    }

    // Non-grouped control behaves singly even when groupMode=true
    cfg.scaleControl(ControlId.lt, 0.15, groupMode: true);
    expect(cfg.getElement(ControlId.lt).scale, 1.15);
    expect(cfg.getElement(ControlId.lb).scale, 1.0);
  });

  test('playStation preset has symmetrical sticks at bottom', () {
    final cfg = PadLayoutConfig.playStation();
    final ls = cfg.getElement(ControlId.leftStick);
    final rs = cfg.getElement(ControlId.rightStick);

    expect(ls.relY, 0.76);
    expect(rs.relY, 0.76);
    // D-pad left/right and X/B sit at top row around 0.38
    expect(cfg.getElement(ControlId.dpadLeft).relY, 0.38);
    expect(cfg.getElement(ControlId.btnX).relY, 0.38);
  });

  test('southpaw preset swaps sticks and action buttons', () {
    final cfg = PadLayoutConfig.southpaw();
    final rs = cfg.getElement(ControlId.rightStick);
    final ls = cfg.getElement(ControlId.leftStick);

    expect(rs.relX < 0.5, isTrue);
    expect(ls.relX > 0.5, isTrue);
    expect(cfg.getElement(ControlId.btnA).relX < 0.5, isTrue);
    expect(cfg.getElement(ControlId.dpadUp).relX > 0.5, isTrue);
  });

  test('retro2D preset hides analog sticks and enlarges dpad and abxy buttons', () {
    final cfg = PadLayoutConfig.retro2D();
    expect(cfg.getElement(ControlId.leftStick).visible, isFalse);
    expect(cfg.getElement(ControlId.rightStick).visible, isFalse);
    expect(cfg.getElement(ControlId.l3).visible, isFalse);
    expect(cfg.getElement(ControlId.r3).visible, isFalse);
    for (final id in [...ControlId.dpadGroup, ...ControlId.abxyGroup]) {
      expect(cfg.getElement(id).scale, 1.35);
      expect(cfg.getElement(id).visible, isTrue);
    }
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
    clone.getElement(ControlId.btnX).scale = 1.8;

    expect(cfg.opacity, 0.85);
    expect(cfg.getElement(ControlId.lt).relX, 0.10);
    expect(cfg.getElement(ControlId.btnX).scale, 1.0);
  });

  test('GROUP scaleControl shifts cluster rigidly at borders without collapsing spacing', () {
    final cfg = PadLayoutConfig.defaultXbox();
    for (var i = 0; i < 20; i++) {
      cfg.scaleControl(ControlId.dpadDown, 0.05, groupMode: true);
    }
    final upY = cfg.getElement(ControlId.dpadUp).relY;
    final leftY = cfg.getElement(ControlId.dpadLeft).relY;
    final downY = cfg.getElement(ControlId.dpadDown).relY;

    expect(downY, closeTo(0.98, 0.0001));
    // Upper and lower arms must stay equidistant from the horizontal center line
    expect((leftY - upY), closeTo((downY - leftY), 0.001));
    expect((downY - leftY), closeTo(0.26, 0.001));
  });

  test('GROUP scaleControl expands un-maxed members in mixed-scale groups', () {
    final cfg = PadLayoutConfig.defaultXbox();
    cfg.getElement(ControlId.btnX).scale = 2.0;
    final startB = cfg.getElement(ControlId.btnB).relX;
    final startX = cfg.getElement(ControlId.btnX).relX;

    cfg.scaleControl(ControlId.btnX, 0.20, groupMode: true);
    expect(cfg.getElement(ControlId.btnX).scale, 2.0);
    expect(cfg.getElement(ControlId.btnB).scale, 1.2);
    expect(cfg.getElement(ControlId.btnB).relX, greaterThan(startB));
    expect(cfg.getElement(ControlId.btnX).relX, closeTo(startX, 0.0001));
  });

  test('fromJson backfills empty or missing elem.id from map key', () {
    final restored = PadLayoutConfig.fromJson({
      'version': 2,
      'elements': {
        'lt': {'relX': 0.15, 'relY': 0.12, 'scale': 1.1, 'visible': true},
      },
    });
    expect(restored.getElement(ControlId.lt).id, ControlId.lt);
    final reserialized = restored.toJson()['elements'] as Map<String, dynamic>;
    expect((reserialized[ControlId.lt] as Map)['id'], ControlId.lt);
  });

  test('btnGuide clears menuButton vertically in defaultXbox and claw presets', () {
    for (final cfg in [
      PadLayoutConfig.defaultXbox(),
      PadLayoutConfig.playStation(),
      PadLayoutConfig.southpaw(),
      PadLayoutConfig.claw(),
      PadLayoutConfig.retro2D(),
    ]) {
      final menu = cfg.getElement(ControlId.menuButton);
      final guide = cfg.getElement(ControlId.btnGuide);
      final menuH = 0.13 * 0.9 * menu.scale * 0.95;
      final menuBottom = menuH; // top clamped to 0.0 because relY=0.05 < menuH/2
      final guideTop = guide.relY - (0.13 * 0.95 * guide.scale) / 2;
      expect(guideTop, greaterThan(menuBottom));
    }
  });
}
