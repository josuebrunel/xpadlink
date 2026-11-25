import 'package:flutter_test/flutter_test.dart';
import 'package:xpadlink/input_config.dart';
import 'package:xpadlink/protocol.dart';

void main() {
  group('InputSettingsConfig', () {
    test('defaults match expected safe off-by-default behavior', () {
      final cfg = InputSettingsConfig();
      expect(cfg.volumeTriggers.enabled, isFalse);
      expect(cfg.volumeTriggers.volumeUp.target, TriggerTarget.rt);
      expect(cfg.volumeTriggers.volumeUp.mode, TriggerPressMode.hold);
      expect(cfg.volumeTriggers.volumeDown.target, TriggerTarget.lt);
      expect(cfg.volumeTriggers.volumeDown.mode, TriggerPressMode.hold);
      expect(cfg.volumeTriggers.swapOnFlip, isTrue);
      expect(cfg.volumeTriggers.hapticsEnabled, isTrue);

      expect(cfg.touchLook.enabled, isFalse);
      expect(cfg.touchLook.mode, TouchLookMode.relativeSwipe);
      expect(cfg.touchLook.zone, TouchLookZone.rightHalf);
      expect(cfg.touchLook.sensitivity, 1.2);
      expect(cfg.touchLook.deadzoneBoost, 0.12);
      expect(cfg.touchLook.invertX, isFalse);
      expect(cfg.touchLook.invertY, isFalse);
      expect(cfg.touchLook.hideRightStick, isTrue);
      expect(cfg.touchLook.showVisualFeedback, isTrue);
    });

    test('round trips cleanly through json', () {
      final cfg = InputSettingsConfig(
        volumeTriggers: VolumeTriggerConfig(
          enabled: true,
          volumeUp: VolumeButtonBinding(
            target: TriggerTarget.rb,
            mode: TriggerPressMode.toggle,
          ),
          volumeDown: VolumeButtonBinding(
            target: TriggerTarget.a,
            mode: TriggerPressMode.hold,
          ),
          swapOnFlip: false,
          hapticsEnabled: false,
        ),
        touchLook: TouchLookConfig(
          enabled: true,
          mode: TouchLookMode.floatingStick,
          zone: TouchLookZone.fullScreen,
          sensitivity: 2.4,
          deadzoneBoost: 0.2,
          invertX: true,
          invertY: true,
          hideRightStick: false,
          showVisualFeedback: false,
        ),
      );

      final restored = InputSettingsConfig.fromJson(cfg.toJson());
      expect(restored.volumeTriggers.enabled, isTrue);
      expect(restored.volumeTriggers.volumeUp.target, TriggerTarget.rb);
      expect(restored.volumeTriggers.volumeUp.mode, TriggerPressMode.toggle);
      expect(restored.volumeTriggers.volumeDown.target, TriggerTarget.a);
      expect(restored.volumeTriggers.volumeDown.mode, TriggerPressMode.hold);
      expect(restored.volumeTriggers.swapOnFlip, isFalse);
      expect(restored.volumeTriggers.hapticsEnabled, isFalse);

      expect(restored.touchLook.enabled, isTrue);
      expect(restored.touchLook.mode, TouchLookMode.floatingStick);
      expect(restored.touchLook.zone, TouchLookZone.fullScreen);
      expect(restored.touchLook.sensitivity, 2.4);
      expect(restored.touchLook.deadzoneBoost, 0.2);
      expect(restored.touchLook.invertX, isTrue);
      expect(restored.touchLook.invertY, isTrue);
      expect(restored.touchLook.hideRightStick, isFalse);
      expect(restored.touchLook.showVisualFeedback, isFalse);
    });

    test('clamps out-of-range numbers and handles unknown enums safely', () {
      final restored = InputSettingsConfig.fromJson({
        'volumeTriggers': {
          'enabled': true,
          'volumeUp': {'target': 'unknown_btn', 'mode': 'unknown_mode'},
          'volumeDown': {'target': 'lt', 'mode': 'toggle'},
        },
        'touchLook': {
          'enabled': true,
          'mode': 'bogus',
          'zone': 'bogus',
          'sensitivity': 9.0,
          'deadzoneBoost': -1.0,
        },
      });

      expect(restored.volumeTriggers.volumeUp.target, TriggerTarget.none);
      expect(restored.volumeTriggers.volumeUp.mode, TriggerPressMode.hold);
      expect(restored.volumeTriggers.volumeDown.target, TriggerTarget.lt);
      expect(restored.volumeTriggers.volumeDown.mode, TriggerPressMode.toggle);
      expect(restored.touchLook.mode, TouchLookMode.relativeSwipe);
      expect(restored.touchLook.zone, TouchLookZone.rightHalf);
      expect(restored.touchLook.sensitivity, 3.0);
      expect(restored.touchLook.deadzoneBoost, 0.0);
    });

    test('effectiveBinding and shouldIntercept respect enabled, target, and flip', () {
      final cfg = VolumeTriggerConfig(
        enabled: false,
        volumeUp: VolumeButtonBinding(target: TriggerTarget.rt),
        volumeDown: VolumeButtonBinding(target: TriggerTarget.none),
        swapOnFlip: true,
      );
      expect(cfg.shouldInterceptUp(flipped: false), isFalse);
      expect(cfg.shouldInterceptDown(flipped: false), isFalse);

      cfg.enabled = true;
      expect(cfg.shouldInterceptUp(flipped: false), isTrue);
      expect(cfg.shouldInterceptDown(flipped: false), isFalse);
      expect(cfg.effectiveBinding(isUp: true, flipped: false).target,
          TriggerTarget.rt);

      // When flipped with swapOnFlip=true, physical up gets down's binding (none).
      expect(cfg.shouldInterceptUp(flipped: true), isFalse);
      expect(cfg.shouldInterceptDown(flipped: true), isTrue);
      expect(cfg.effectiveBinding(isUp: false, flipped: true).target,
          TriggerTarget.rt);

      cfg.swapOnFlip = false;
      expect(cfg.shouldInterceptUp(flipped: true), isTrue);
      expect(cfg.shouldInterceptDown(flipped: true), isFalse);
    });
  });

  group('InputMixer', () {
    test('merges touch buttons and volume bindings without clobbering', () {
      final mixer = InputMixer();
      mixer.setVolumeConfig(
        VolumeTriggerConfig(
          enabled: true,
          volumeUp: VolumeButtonBinding(target: TriggerTarget.rt),
          volumeDown: VolumeButtonBinding(target: TriggerTarget.lb),
        ),
        flipped: false,
      );

      mixer.setTouchButton(Btn.a, true);
      mixer.handleVolumeKey(isUp: true, down: true);
      mixer.handleVolumeKey(isUp: false, down: true);

      final out = PadState();
      mixer.applyTo(out);
      expect(out.buttons & Btn.a, Btn.a);
      expect(out.buttons & Btn.lb, Btn.lb);
      expect(out.rt, 255);
      expect(out.lt, 0);
      expect(mixer.activeVolumeTargets, {TriggerTarget.rt, TriggerTarget.lb});

      // Releasing touch A preserves volume LB & RT.
      mixer.setTouchButton(Btn.a, false);
      mixer.applyTo(out);
      expect(out.buttons & Btn.a, 0);
      expect(out.buttons & Btn.lb, Btn.lb);
      expect(out.rt, 255);
    });

    test('triggers take max of touch, volume, and physical pad', () {
      final mixer = InputMixer();
      mixer.setVolumeConfig(
        VolumeTriggerConfig(
          enabled: true,
          volumeUp: VolumeButtonBinding(target: TriggerTarget.rt),
          volumeDown: VolumeButtonBinding(target: TriggerTarget.lt),
        ),
        flipped: false,
      );

      mixer.setPhysicalPad(
        buttons: 0,
        lx: 0,
        ly: 0,
        rx: 0,
        ry: 0,
        lt: 120,
        rt: 0,
      );
      final out = PadState();
      mixer.applyTo(out);
      expect(out.lt, 120);

      mixer.handleVolumeKey(isUp: false, down: true);
      mixer.applyTo(out);
      expect(out.lt, 255);

      mixer.handleVolumeKey(isUp: false, down: false);
      mixer.applyTo(out);
      expect(out.lt, 120);
    });

    test('toggle mode latches on rising edge, ignores repeats, unlatches on second press', () {
      final mixer = InputMixer();
      mixer.setVolumeConfig(
        VolumeTriggerConfig(
          enabled: true,
          volumeUp: VolumeButtonBinding(
            target: TriggerTarget.a,
            mode: TriggerPressMode.toggle,
          ),
          volumeDown: VolumeButtonBinding(target: TriggerTarget.none),
        ),
        flipped: false,
      );

      final out = PadState();

      // First press latches ON
      expect(mixer.handleVolumeKey(isUp: true, down: true), isTrue);
      // Duplicate down event does not toggle off
      expect(mixer.handleVolumeKey(isUp: true, down: true), isFalse);
      mixer.applyTo(out);
      expect(out.buttons & Btn.a, Btn.a);

      // Physical release keeps latched ON
      mixer.handleVolumeKey(isUp: true, down: false);
      mixer.applyTo(out);
      expect(out.buttons & Btn.a, Btn.a);

      // Second press latches OFF
      expect(mixer.handleVolumeKey(isUp: true, down: true), isFalse);
      mixer.applyTo(out);
      expect(out.buttons & Btn.a, 0);
    });

    test('clearVolumeInput clears both held and latched state', () {
      final mixer = InputMixer();
      mixer.setVolumeConfig(
        VolumeTriggerConfig(
          enabled: true,
          volumeUp: VolumeButtonBinding(
            target: TriggerTarget.rt,
            mode: TriggerPressMode.toggle,
          ),
          volumeDown: VolumeButtonBinding(
            target: TriggerTarget.lt,
            mode: TriggerPressMode.hold,
          ),
        ),
        flipped: false,
      );

      mixer.handleVolumeKey(isUp: true, down: true);
      mixer.handleVolumeKey(isUp: true, down: false);
      mixer.handleVolumeKey(isUp: false, down: true);

      final out = PadState();
      mixer.applyTo(out);
      expect(out.rt, 255);
      expect(out.lt, 255);

      mixer.clearVolumeInput();
      mixer.applyTo(out);
      expect(out.rt, 0);
      expect(out.lt, 0);
      expect(mixer.activeVolumeTargets, isEmpty);
    });

    test('arbitrates right stick cleanly among touch-look, touch stick, and physical pad', () {
      final mixer = InputMixer();
      final out = PadState();

      mixer.setTouchLook(0.5, -0.25, active: true);
      mixer.applyTo(out);
      expect(out.rx, axisToInt16(0.5));
      expect(out.ry, axisToInt16(-0.25));

      // Touch-look release returns right stick to 0
      mixer.setTouchLook(0, 0, active: false);
      mixer.applyTo(out);
      expect(out.rx, 0);
      expect(out.ry, 0);

      // Stronger deflection wins
      mixer.setTouchLook(0.3, 0.0, active: true);
      mixer.setTouchRightStick(axisToInt16(0.8), 0);
      mixer.applyTo(out);
      expect(out.rx, axisToInt16(0.8));

      // Physical pad wins if stronger than touch-look
      mixer.setTouchRightStick(0, 0);
      mixer.setPhysicalPad(
        buttons: Btn.x,
        lx: 10000,
        ly: -5000,
        rx: -30000,
        ry: 0,
        lt: 0,
        rt: 0,
      );
      mixer.applyTo(out);
      expect(out.rx, -30000);
      expect(out.lx, 10000);
      expect(out.ly, -5000);
      expect(out.buttons & Btn.x, Btn.x);
    });
  });

  group('TouchLookMath', () {
    test('computeFloatingStick clamps to unit circle and honors invert flags', () {
      final zero = TouchLookMath.computeFloatingStick(
        dx: 0,
        dy: 0,
        canvasHeight: 400,
        sensitivity: 1.0,
        invertX: false,
        invertY: false,
      );
      expect(zero.x, 0.0);
      expect(zero.y, 0.0);

      final clamped = TouchLookMath.computeFloatingStick(
        dx: 500,
        dy: 500,
        canvasHeight: 400,
        sensitivity: 1.0,
        invertX: true,
        invertY: false,
      );
      final mag = clamped.x * clamped.x + clamped.y * clamped.y;
      expect(mag, closeTo(1.0, 0.001));
      expect(clamped.x, lessThan(0));
      expect(clamped.y, greaterThan(0));
    });

    test('computeRelativeVelocity drops sub-threshold noise and boosts above deadzone', () {
      final sub = TouchLookMath.computeRelativeVelocity(
        vx: 0.005,
        vy: 0.005,
        deadzoneBoost: 0.15,
        invertX: false,
        invertY: false,
      );
      expect(sub.x, 0.0);
      expect(sub.y, 0.0);

      final boosted = TouchLookMath.computeRelativeVelocity(
        vx: 0.05,
        vy: 0.0,
        deadzoneBoost: 0.15,
        invertX: false,
        invertY: false,
      );
      expect(boosted.x, greaterThan(0.15));
      expect(boosted.y, 0.0);

      final inverted = TouchLookMath.computeRelativeVelocity(
        vx: 0.0,
        vy: 2.0,
        deadzoneBoost: 0.12,
        invertX: false,
        invertY: true,
      );
      expect(inverted.x, 0.0);
      expect(inverted.y, closeTo(-1.0, 0.0001));
    });
  });
}
