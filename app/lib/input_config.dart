import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'protocol.dart';

/// Every Xbox 360 control a physical volume button can trigger, plus [none].
enum TriggerTarget {
  none('none', 'System Volume (Off)', 'OFF', 0),
  rt('rt', 'RT (Right Trigger)', 'RT', 0),
  lt('lt', 'LT (Left Trigger)', 'LT', 0),
  rb('rb', 'RB (Right Bumper)', 'RB', Btn.rb),
  lb('lb', 'LB (Left Bumper)', 'LB', Btn.lb),
  a('a', 'A (Bottom Face)', 'A', Btn.a),
  b('b', 'B (Right Face)', 'B', Btn.b),
  x('x', 'X (Left Face)', 'X', Btn.x),
  y('y', 'Y (Top Face)', 'Y', Btn.y),
  l3('l3', 'L3 (Left Stick Click)', 'L3', Btn.l3),
  r3('r3', 'R3 (Right Stick Click)', 'R3', Btn.r3),
  dUp('dUp', 'D-Pad Up', 'D-UP', Btn.dUp),
  dDown('dDown', 'D-Pad Down', 'D-DN', Btn.dDown),
  dLeft('dLeft', 'D-Pad Left', 'D-LT', Btn.dLeft),
  dRight('dRight', 'D-Pad Right', 'D-RT', Btn.dRight),
  back('back', 'View / Back', 'VIEW', Btn.back),
  start('start', 'Menu / Start', 'MENU', Btn.start),
  guide('guide', 'Guide (Logo)', 'GUIDE', Btn.guide);

  const TriggerTarget(this.id, this.label, this.shortLabel, this.buttonBit);

  final String id;
  final String label;
  final String shortLabel;

  /// Xbox button bitmask from [Btn], or 0 for [none], [lt], and [rt].
  final int buttonBit;

  bool get isAnalogTrigger => this == lt || this == rt;

  static TriggerTarget fromId(String? id) {
    for (final t in values) {
      if (t.id == id) return t;
    }
    return none;
  }
}

/// How pressing a physical volume button activates its mapped target.
enum TriggerPressMode {
  hold('hold', 'Hold'),
  toggle('toggle', 'Toggle');

  const TriggerPressMode(this.id, this.label);

  final String id;
  final String label;

  static TriggerPressMode fromId(String? id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return hold;
  }
}

/// Mapping for one physical volume key (Up or Down).
class VolumeButtonBinding {
  VolumeButtonBinding({
    this.target = TriggerTarget.none,
    this.mode = TriggerPressMode.hold,
  });

  TriggerTarget target;
  TriggerPressMode mode;

  VolumeButtonBinding clone() =>
      VolumeButtonBinding(target: target, mode: mode);

  Map<String, dynamic> toJson() => {
        'target': target.id,
        'mode': mode.id,
      };

  factory VolumeButtonBinding.fromJson(Map<String, dynamic> j) =>
      VolumeButtonBinding(
        target: TriggerTarget.fromId(j['target'] as String?),
        mode: TriggerPressMode.fromId(j['mode'] as String?),
      );
}

/// Configuration for intercepting Android hardware Volume Up / Volume Down.
class VolumeTriggerConfig {
  VolumeTriggerConfig({
    this.enabled = false,
    VolumeButtonBinding? volumeUp,
    VolumeButtonBinding? volumeDown,
    this.swapOnFlip = true,
    this.hapticsEnabled = true,
  })  : volumeUp = volumeUp ??
            VolumeButtonBinding(
              target: TriggerTarget.rt,
              mode: TriggerPressMode.hold,
            ),
        volumeDown = volumeDown ??
            VolumeButtonBinding(
              target: TriggerTarget.lt,
              mode: TriggerPressMode.hold,
            );

  bool enabled;
  VolumeButtonBinding volumeUp;
  VolumeButtonBinding volumeDown;
  bool swapOnFlip;
  bool hapticsEnabled;

  VolumeButtonBinding effectiveBinding({
    required bool isUp,
    required bool flipped,
  }) {
    if (!enabled) return VolumeButtonBinding(target: TriggerTarget.none);
    final swapped = flipped && swapOnFlip;
    if (isUp) return swapped ? volumeDown : volumeUp;
    return swapped ? volumeUp : volumeDown;
  }

  bool shouldInterceptUp({required bool flipped}) =>
      effectiveBinding(isUp: true, flipped: flipped).target !=
      TriggerTarget.none;

  bool shouldInterceptDown({required bool flipped}) =>
      effectiveBinding(isUp: false, flipped: flipped).target !=
      TriggerTarget.none;

  VolumeTriggerConfig clone() => VolumeTriggerConfig(
        enabled: enabled,
        volumeUp: volumeUp.clone(),
        volumeDown: volumeDown.clone(),
        swapOnFlip: swapOnFlip,
        hapticsEnabled: hapticsEnabled,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'volumeUp': volumeUp.toJson(),
        'volumeDown': volumeDown.toJson(),
        'swapOnFlip': swapOnFlip,
        'hapticsEnabled': hapticsEnabled,
      };

  factory VolumeTriggerConfig.fromJson(Map<String, dynamic> j) {
    VolumeButtonBinding parseBinding(dynamic raw, VolumeButtonBinding fallback) {
      if (raw is Map) {
        return VolumeButtonBinding.fromJson(Map<String, dynamic>.from(raw));
      }
      return fallback;
    }

    return VolumeTriggerConfig(
      enabled: (j['enabled'] as bool?) ?? false,
      volumeUp: parseBinding(
        j['volumeUp'],
        VolumeButtonBinding(target: TriggerTarget.rt),
      ),
      volumeDown: parseBinding(
        j['volumeDown'],
        VolumeButtonBinding(target: TriggerTarget.lt),
      ),
      swapOnFlip: (j['swapOnFlip'] as bool?) ?? true,
      hapticsEnabled: (j['hapticsEnabled'] as bool?) ?? true,
    );
  }
}

/// Camera drag mechanics mapped to the virtual Xbox 360 right stick.
enum TouchLookMode {
  relativeSwipe('relativeSwipe', 'Swipe Relatif'),
  floatingStick('floatingStick', 'Floating Stick');

  const TouchLookMode(this.id, this.label);

  final String id;
  final String label;

  static TouchLookMode fromId(String? id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return relativeSwipe;
  }
}

/// Which empty region of the screen responds to Touch-Look drags.
enum TouchLookZone {
  rightHalf('rightHalf', 'Right Half'),
  fullScreen('fullScreen', 'Full Screen');

  const TouchLookZone(this.id, this.label);

  final String id;
  final String label;

  static TouchLookZone fromId(String? id) {
    for (final z in values) {
      if (z.id == id) return z;
    }
    return rightHalf;
  }
}

/// Configuration for empty-screen Touch-Look camera control.
class TouchLookConfig {
  TouchLookConfig({
    this.enabled = false,
    this.mode = TouchLookMode.relativeSwipe,
    this.zone = TouchLookZone.rightHalf,
    this.sensitivity = 1.2,
    this.deadzoneBoost = 0.12,
    this.invertX = false,
    this.invertY = false,
    this.hideRightStick = true,
    this.showVisualFeedback = true,
  });

  bool enabled;
  TouchLookMode mode;
  TouchLookZone zone;
  double sensitivity;
  double deadzoneBoost;
  bool invertX;
  bool invertY;
  bool hideRightStick;
  bool showVisualFeedback;

  TouchLookConfig clone() => TouchLookConfig(
        enabled: enabled,
        mode: mode,
        zone: zone,
        sensitivity: sensitivity,
        deadzoneBoost: deadzoneBoost,
        invertX: invertX,
        invertY: invertY,
        hideRightStick: hideRightStick,
        showVisualFeedback: showVisualFeedback,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'mode': mode.id,
        'zone': zone.id,
        'sensitivity': sensitivity,
        'deadzoneBoost': deadzoneBoost,
        'invertX': invertX,
        'invertY': invertY,
        'hideRightStick': hideRightStick,
        'showVisualFeedback': showVisualFeedback,
      };

  factory TouchLookConfig.fromJson(Map<String, dynamic> j) => TouchLookConfig(
        enabled: (j['enabled'] as bool?) ?? false,
        mode: TouchLookMode.fromId(j['mode'] as String?),
        zone: TouchLookZone.fromId(j['zone'] as String?),
        sensitivity:
            ((j['sensitivity'] as num?)?.toDouble() ?? 1.2).clamp(0.3, 3.0),
        deadzoneBoost:
            ((j['deadzoneBoost'] as num?)?.toDouble() ?? 0.12).clamp(0.0, 0.35),
        invertX: (j['invertX'] as bool?) ?? false,
        invertY: (j['invertY'] as bool?) ?? false,
        hideRightStick: (j['hideRightStick'] as bool?) ?? true,
        showVisualFeedback: (j['showVisualFeedback'] as bool?) ?? true,
      );
}

/// Combined custom input settings persisted on the phone.
class InputSettingsConfig {
  InputSettingsConfig({
    VolumeTriggerConfig? volumeTriggers,
    TouchLookConfig? touchLook,
  })  : volumeTriggers = volumeTriggers ?? VolumeTriggerConfig(),
        touchLook = touchLook ?? TouchLookConfig();

  VolumeTriggerConfig volumeTriggers;
  TouchLookConfig touchLook;

  InputSettingsConfig clone() => InputSettingsConfig(
        volumeTriggers: volumeTriggers.clone(),
        touchLook: touchLook.clone(),
      );

  Map<String, dynamic> toJson() => {
        'volumeTriggers': volumeTriggers.toJson(),
        'touchLook': touchLook.toJson(),
      };

  factory InputSettingsConfig.fromJson(Map<String, dynamic> j) {
    final vtRaw = j['volumeTriggers'];
    final tlRaw = j['touchLook'];
    return InputSettingsConfig(
      volumeTriggers: vtRaw is Map
          ? VolumeTriggerConfig.fromJson(Map<String, dynamic>.from(vtRaw))
          : VolumeTriggerConfig(),
      touchLook: tlRaw is Map
          ? TouchLookConfig.fromJson(Map<String, dynamic>.from(tlRaw))
          : TouchLookConfig(),
    );
  }
}

/// Persistent storage for custom volume trigger & touch-look configuration.
class InputSettingsStore {
  static const _key = 'input.custom.settings';

  Future<InputSettingsConfig> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return InputSettingsConfig();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return InputSettingsConfig.fromJson(Map<String, dynamic>.from(decoded));
      }
      return InputSettingsConfig();
    } catch (_) {
      return InputSettingsConfig();
    }
  }

  Future<void> save(InputSettingsConfig cfg) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(cfg.toJson()));
  }

  Future<InputSettingsConfig> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
    return InputSettingsConfig();
  }
}

/// Pure math helpers for Touch-Look camera deflection in -1..1 space.
class TouchLookMath {
  /// Floating stick: anchor-relative offset scaled to unit circle.
  static ({double x, double y}) computeFloatingStick({
    required double dx,
    required double dy,
    required double canvasHeight,
    required double sensitivity,
    required bool invertX,
    required bool invertY,
  }) {
    final maxR = math.max(
      40.0,
      (canvasHeight * 0.16) / math.max(0.4, sensitivity),
    );
    var nx = dx / maxR;
    var ny = dy / maxR;
    final dist = math.sqrt(nx * nx + ny * ny);
    if (dist > 1.0) {
      nx /= dist;
      ny /= dist;
    }
    return (x: invertX ? -nx : nx, y: invertY ? -ny : ny);
  }

  /// Relative swipe: smoothed velocity with radial deadzone boost so slow
  /// pans stay responsive above typical Xbox game inner deadzones.
  static ({double x, double y}) computeRelativeVelocity({
    required double vx,
    required double vy,
    required double deadzoneBoost,
    required bool invertX,
    required bool invertY,
  }) {
    final mag = math.sqrt(vx * vx + vy * vy);
    if (mag < 0.015) return (x: 0.0, y: 0.0);
    final boost = deadzoneBoost.clamp(0.0, 0.35);
    final scaled = math.min(1.0, boost + (1.0 - boost) * math.min(1.0, mag));
    final ox = (vx / mag) * scaled;
    final oy = (vy / mag) * scaled;
    return (x: invertX ? -ox : ox, y: invertY ? -oy : oy);
  }
}

/// Combines touch controls, hardware volume triggers, Touch-Look, and physical
/// gamepad state without any source overwriting another.
class InputMixer {
  VolumeTriggerConfig _volCfg = VolumeTriggerConfig();
  bool _flipped = false;

  int _touchButtons = 0;
  int _touchLt = 0;
  int _touchRt = 0;
  int _touchLx = 0;
  int _touchLy = 0;
  int _touchRx = 0;
  int _touchRy = 0;

  bool _tlActive = false;
  int _tlRx = 0;
  int _tlRy = 0;

  bool _volPhysUp = false;
  bool _volPhysDown = false;
  bool _volLatchUp = false;
  bool _volLatchDown = false;

  int _physButtons = 0;
  int _physLx = 0;
  int _physLy = 0;
  int _physRx = 0;
  int _physRy = 0;
  int _physLt = 0;
  int _physRt = 0;

  void setVolumeConfig(VolumeTriggerConfig cfg, {required bool flipped}) {
    final oldUp = _volCfg.effectiveBinding(isUp: true, flipped: _flipped);
    final oldDown = _volCfg.effectiveBinding(isUp: false, flipped: _flipped);
    final newUp = cfg.effectiveBinding(isUp: true, flipped: flipped);
    final newDown = cfg.effectiveBinding(isUp: false, flipped: flipped);

    _volCfg = cfg.clone();
    _flipped = flipped;

    if (!cfg.enabled) {
      clearVolumeInput();
      return;
    }
    if (oldUp.target != newUp.target || oldUp.mode != newUp.mode) {
      _volPhysUp = false;
      _volLatchUp = false;
    }
    if (oldDown.target != newDown.target || oldDown.mode != newDown.mode) {
      _volPhysDown = false;
      _volLatchDown = false;
    }
  }

  /// Processes one physical volume key edge. Returns true when a mapped trigger
  /// transitions to active (useful for haptic feedback).
  bool handleVolumeKey({required bool isUp, required bool down}) {
    final binding = _volCfg.effectiveBinding(isUp: isUp, flipped: _flipped);
    if (binding.target == TriggerTarget.none) return false;

    final prev = isUp ? _volPhysUp : _volPhysDown;
    if (prev == down) return false;

    if (isUp) {
      _volPhysUp = down;
    } else {
      _volPhysDown = down;
    }

    if (binding.mode == TriggerPressMode.toggle) {
      if (!down) return false;
      final nextLatch = !(isUp ? _volLatchUp : _volLatchDown);
      if (isUp) {
        _volLatchUp = nextLatch;
      } else {
        _volLatchDown = nextLatch;
      }
      return nextLatch;
    }

    return down;
  }

  void clearVolumeInput() {
    _volPhysUp = false;
    _volPhysDown = false;
    _volLatchUp = false;
    _volLatchDown = false;
  }

  /// Parses one event from the native `xpadlink/volume_keys` channel.
  /// Always honors `'clear'` (focus loss / pause), and ignores key presses
  /// when [allowInput] is false (modal sheet / layout editor active).
  bool handleVolumeEvent(dynamic event, {bool allowInput = true}) {
    if (event is! Map) return false;
    final key = event['key'];
    if (key == 'clear') {
      clearVolumeInput();
      return false;
    }
    if (!allowInput || (key != 'up' && key != 'down')) return false;
    return handleVolumeKey(isUp: key == 'up', down: event['down'] == true);
  }

  void setTouchButton(int bit, bool down) {
    _touchButtons = down ? (_touchButtons | bit) : (_touchButtons & ~bit);
  }

  void setTouchLt(int v) => _touchLt = v.clamp(0, 255);

  void setTouchRt(int v) => _touchRt = v.clamp(0, 255);

  void setTouchLeftStick(int x, int y) {
    _touchLx = x;
    _touchLy = y;
  }

  void setTouchRightStick(int x, int y) {
    _touchRx = x;
    _touchRy = y;
  }

  void setTouchLook(double x, double y, {required bool active}) {
    _tlActive = active;
    _tlRx = active ? axisToInt16(x) : 0;
    _tlRy = active ? axisToInt16(y) : 0;
  }

  void setPhysicalPad({
    required int buttons,
    required int lx,
    required int ly,
    required int rx,
    required int ry,
    required int lt,
    required int rt,
  }) {
    _physButtons = buttons;
    _physLx = lx;
    _physLy = ly;
    _physRx = rx;
    _physRy = ry;
    _physLt = lt.clamp(0, 255);
    _physRt = rt.clamp(0, 255);
  }

  bool _isKeyActive(bool isUp) {
    final binding = _volCfg.effectiveBinding(isUp: isUp, flipped: _flipped);
    if (binding.target == TriggerTarget.none) return false;
    return binding.mode == TriggerPressMode.toggle
        ? (isUp ? _volLatchUp : _volLatchDown)
        : (isUp ? _volPhysUp : _volPhysDown);
  }

  Set<TriggerTarget> get activeVolumeTargets {
    final out = <TriggerTarget>{};
    if (_isKeyActive(true)) {
      out.add(_volCfg.effectiveBinding(isUp: true, flipped: _flipped).target);
    }
    if (_isKeyActive(false)) {
      out.add(_volCfg.effectiveBinding(isUp: false, flipped: _flipped).target);
    }
    return out;
  }

  static ({int x, int y}) _pickStrongest(
    int ax,
    int ay,
    int bx,
    int by,
  ) {
    final a2 = ax * ax + ay * ay;
    final b2 = bx * bx + by * by;
    return b2 > a2 ? (x: bx, y: by) : (x: ax, y: ay);
  }

  void applyTo(PadState out) {
    var volButtons = 0;
    var volLt = 0;
    var volRt = 0;
    for (final target in activeVolumeTargets) {
      if (target == TriggerTarget.lt) {
        volLt = 255;
      } else if (target == TriggerTarget.rt) {
        volRt = 255;
      } else if (target.buttonBit != 0) {
        volButtons |= target.buttonBit;
      }
    }

    out.buttons = _touchButtons | volButtons | _physButtons;
    out.lt = math.max(_touchLt, math.max(volLt, _physLt));
    out.rt = math.max(_touchRt, math.max(volRt, _physRt));

    final left = _pickStrongest(_touchLx, _touchLy, _physLx, _physLy);
    out.lx = left.x;
    out.ly = left.y;

    var right = _pickStrongest(_touchRx, _touchRy, _physRx, _physRy);
    if (_tlActive) {
      right = _pickStrongest(right.x, right.y, _tlRx, _tlRy);
    }
    out.rx = right.x;
    out.ry = right.y;
  }
}
