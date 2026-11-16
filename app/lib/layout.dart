import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// Identifiers for every customizable control on the touch pad.
class ControlId {
  static const leftStick = 'leftStick';
  static const rightStick = 'rightStick';
  static const dpad = 'dpad';
  static const abxy = 'abxy';
  static const lt = 'lt';
  static const lb = 'lb';
  static const rt = 'rt';
  static const rb = 'rb';
  static const l3 = 'l3';
  static const r3 = 'r3';
  static const center = 'center';
  static const menuButton = 'menuButton';

  static const all = [
    leftStick,
    l3,
    dpad,
    abxy,
    rightStick,
    r3,
    lt,
    lb,
    rt,
    rb,
    center,
    menuButton,
  ];

  static String displayName(String id) {
    switch (id) {
      case leftStick:
        return 'Left Stick';
      case rightStick:
        return 'Right Stick';
      case dpad:
        return 'D-Pad';
      case abxy:
        return 'ABXY Buttons';
      case lt:
        return 'LT (Left Trigger)';
      case lb:
        return 'LB (Left Bumper)';
      case rt:
        return 'RT (Right Trigger)';
      case rb:
        return 'RB (Right Bumper)';
      case l3:
        return 'L3 (Left Click)';
      case r3:
        return 'R3 (Right Click)';
      case center:
        return 'View / Guide / Menu';
      case menuButton:
        return 'Floating Menu Button';
      default:
        return id;
    }
  }
}

/// Layout configuration for a single control element on screen.
/// [relX] and [relY] are normalized coordinates (0.0 to 1.0) indicating
/// the element's center relative to the available canvas dimensions.
class ControlElementLayout {
  ControlElementLayout({
    required this.id,
    required this.relX,
    required this.relY,
    this.scale = 1.0,
    this.visible = true,
  });

  final String id;
  double relX;
  double relY;
  double scale;
  bool visible;

  ControlElementLayout clone() => ControlElementLayout(
        id: id,
        relX: relX,
        relY: relY,
        scale: scale,
        visible: visible,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'relX': relX,
        'relY': relY,
        'scale': scale,
        'visible': visible,
      };

  factory ControlElementLayout.fromJson(Map<String, dynamic> j) =>
      ControlElementLayout(
        id: j['id'] as String? ?? '',
        relX: (j['relX'] as num?)?.toDouble() ?? 0.5,
        relY: (j['relY'] as num?)?.toDouble() ?? 0.5,
        scale: ((j['scale'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 2.5),
        visible: (j['visible'] as bool?) ?? true,
      );
}

/// Full on-screen touch controller layout configuration.
class PadLayoutConfig {
  PadLayoutConfig({
    Map<String, ControlElementLayout>? elements,
    this.opacity = 0.85,
    this.hapticsEnabled = true,
    this.snapToGrid = false,
  }) : elements = elements ?? _buildDefaultXboxElements();

  final Map<String, ControlElementLayout> elements;
  double opacity;
  bool hapticsEnabled;
  bool snapToGrid;

  ControlElementLayout getElement(String id) {
    if (elements.containsKey(id)) {
      return elements[id]!;
    }
    final defaults = _buildDefaultXboxElements();
    final fallback = defaults[id] ??
        ControlElementLayout(id: id, relX: 0.5, relY: 0.5);
    elements[id] = fallback;
    return fallback;
  }

  void setElement(ControlElementLayout elem) {
    elements[elem.id] = elem;
  }

  void resetElement(String id) {
    final defaults = _buildDefaultXboxElements();
    if (defaults.containsKey(id)) {
      elements[id] = defaults[id]!.clone();
    }
  }

  PadLayoutConfig clone() {
    final copy = <String, ControlElementLayout>{};
    for (final entry in elements.entries) {
      copy[entry.key] = entry.value.clone();
    }
    return PadLayoutConfig(
      elements: copy,
      opacity: opacity,
      hapticsEnabled: hapticsEnabled,
      snapToGrid: snapToGrid,
    );
  }

  Map<String, dynamic> toJson() => {
        'opacity': opacity,
        'hapticsEnabled': hapticsEnabled,
        'snapToGrid': snapToGrid,
        'elements': elements.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory PadLayoutConfig.fromJson(Map<String, dynamic> j) {
    final map = <String, ControlElementLayout>{};
    if (j['elements'] is Map) {
      final rawMap = j['elements'] as Map;
      for (final entry in rawMap.entries) {
        if (entry.value is Map) {
          final elem = ControlElementLayout.fromJson(
              Map<String, dynamic>.from(entry.value as Map));
          map[elem.id] = elem;
        }
      }
    }
    // Ensure all standard controls exist
    final defaults = _buildDefaultXboxElements();
    for (final id in ControlId.all) {
      if (!map.containsKey(id)) {
        map[id] = defaults[id]!.clone();
      }
    }

    return PadLayoutConfig(
      elements: map,
      opacity: ((j['opacity'] as num?)?.toDouble() ?? 0.85).clamp(0.1, 1.0),
      hapticsEnabled: (j['hapticsEnabled'] as bool?) ?? true,
      snapToGrid: (j['snapToGrid'] as bool?) ?? false,
    );
  }

  // --- Presets ---

  static Map<String, ControlElementLayout> _buildDefaultXboxElements() => {
        ControlId.lt: ControlElementLayout(
            id: ControlId.lt, relX: 0.10, relY: 0.08),
        ControlId.lb: ControlElementLayout(
            id: ControlId.lb, relX: 0.24, relY: 0.08),
        ControlId.center: ControlElementLayout(
            id: ControlId.center, relX: 0.50, relY: 0.09),
        ControlId.rb: ControlElementLayout(
            id: ControlId.rb, relX: 0.76, relY: 0.08),
        ControlId.rt: ControlElementLayout(
            id: ControlId.rt, relX: 0.90, relY: 0.08),
        ControlId.leftStick: ControlElementLayout(
            id: ControlId.leftStick, relX: 0.16, relY: 0.38),
        ControlId.l3: ControlElementLayout(
            id: ControlId.l3, relX: 0.29, relY: 0.38),
        ControlId.dpad: ControlElementLayout(
            id: ControlId.dpad, relX: 0.24, relY: 0.76),
        ControlId.abxy: ControlElementLayout(
            id: ControlId.abxy, relX: 0.84, relY: 0.38),
        ControlId.rightStick: ControlElementLayout(
            id: ControlId.rightStick, relX: 0.76, relY: 0.76),
        ControlId.r3: ControlElementLayout(
            id: ControlId.r3, relX: 0.63, relY: 0.76),
        ControlId.menuButton: ControlElementLayout(
            id: ControlId.menuButton, relX: 0.50, relY: 0.05, scale: 1.0),
      };

  factory PadLayoutConfig.defaultXbox() => PadLayoutConfig(
        elements: _buildDefaultXboxElements(),
        opacity: 0.85,
        hapticsEnabled: true,
        snapToGrid: false,
      );

  factory PadLayoutConfig.playStation() => PadLayoutConfig(
        elements: {
          ControlId.lt: ControlElementLayout(
              id: ControlId.lt, relX: 0.10, relY: 0.08),
          ControlId.lb: ControlElementLayout(
              id: ControlId.lb, relX: 0.24, relY: 0.08),
          ControlId.center: ControlElementLayout(
              id: ControlId.center, relX: 0.50, relY: 0.09),
          ControlId.rb: ControlElementLayout(
              id: ControlId.rb, relX: 0.76, relY: 0.08),
          ControlId.rt: ControlElementLayout(
              id: ControlId.rt, relX: 0.90, relY: 0.08),
          // Symmetrical sticks at the bottom, D-pad and ABXY on top
          ControlId.dpad: ControlElementLayout(
              id: ControlId.dpad, relX: 0.16, relY: 0.38),
          ControlId.leftStick: ControlElementLayout(
              id: ControlId.leftStick, relX: 0.24, relY: 0.76),
          ControlId.l3: ControlElementLayout(
              id: ControlId.l3, relX: 0.37, relY: 0.76),
          ControlId.abxy: ControlElementLayout(
              id: ControlId.abxy, relX: 0.84, relY: 0.38),
          ControlId.rightStick: ControlElementLayout(
              id: ControlId.rightStick, relX: 0.76, relY: 0.76),
          ControlId.r3: ControlElementLayout(
              id: ControlId.r3, relX: 0.63, relY: 0.76),
          ControlId.menuButton: ControlElementLayout(
              id: ControlId.menuButton, relX: 0.50, relY: 0.05, scale: 1.0),
        },
        opacity: 0.85,
        hapticsEnabled: true,
      );

  factory PadLayoutConfig.southpaw() => PadLayoutConfig(
        elements: {
          // Inverted: Sticks and actions swapped left/right
          ControlId.rt: ControlElementLayout(
              id: ControlId.rt, relX: 0.10, relY: 0.08),
          ControlId.rb: ControlElementLayout(
              id: ControlId.rb, relX: 0.24, relY: 0.08),
          ControlId.center: ControlElementLayout(
              id: ControlId.center, relX: 0.50, relY: 0.09),
          ControlId.lb: ControlElementLayout(
              id: ControlId.lb, relX: 0.76, relY: 0.08),
          ControlId.lt: ControlElementLayout(
              id: ControlId.lt, relX: 0.90, relY: 0.08),
          ControlId.rightStick: ControlElementLayout(
              id: ControlId.rightStick, relX: 0.16, relY: 0.38),
          ControlId.r3: ControlElementLayout(
              id: ControlId.r3, relX: 0.29, relY: 0.38),
          ControlId.abxy: ControlElementLayout(
              id: ControlId.abxy, relX: 0.24, relY: 0.76),
          ControlId.leftStick: ControlElementLayout(
              id: ControlId.leftStick, relX: 0.84, relY: 0.38),
          ControlId.l3: ControlElementLayout(
              id: ControlId.l3, relX: 0.71, relY: 0.38),
          ControlId.dpad: ControlElementLayout(
              id: ControlId.dpad, relX: 0.76, relY: 0.76),
          ControlId.menuButton: ControlElementLayout(
              id: ControlId.menuButton, relX: 0.50, relY: 0.05, scale: 1.0),
        },
        opacity: 0.85,
        hapticsEnabled: true,
      );

  factory PadLayoutConfig.claw() => PadLayoutConfig(
        elements: {
          // Triggers and bumpers stacked vertically on outer edges for 4-finger claw
          ControlId.lt: ControlElementLayout(
              id: ControlId.lt, relX: 0.09, relY: 0.07, scale: 1.1),
          ControlId.lb: ControlElementLayout(
              id: ControlId.lb, relX: 0.09, relY: 0.22, scale: 1.1),
          ControlId.rt: ControlElementLayout(
              id: ControlId.rt, relX: 0.91, relY: 0.07, scale: 1.1),
          ControlId.rb: ControlElementLayout(
              id: ControlId.rb, relX: 0.91, relY: 0.22, scale: 1.1),
          ControlId.center: ControlElementLayout(
              id: ControlId.center, relX: 0.50, relY: 0.08, scale: 0.9),
          ControlId.leftStick: ControlElementLayout(
              id: ControlId.leftStick, relX: 0.18, relY: 0.50, scale: 1.0),
          ControlId.l3: ControlElementLayout(
              id: ControlId.l3, relX: 0.30, relY: 0.50, scale: 0.9),
          ControlId.dpad: ControlElementLayout(
              id: ControlId.dpad, relX: 0.26, relY: 0.80, scale: 0.95),
          ControlId.abxy: ControlElementLayout(
              id: ControlId.abxy, relX: 0.82, relY: 0.48, scale: 1.05),
          ControlId.rightStick: ControlElementLayout(
              id: ControlId.rightStick, relX: 0.74, relY: 0.80, scale: 1.0),
          ControlId.r3: ControlElementLayout(
              id: ControlId.r3, relX: 0.60, relY: 0.80, scale: 0.9),
          ControlId.menuButton: ControlElementLayout(
              id: ControlId.menuButton, relX: 0.50, relY: 0.05, scale: 1.0),
        },
        opacity: 0.85,
        hapticsEnabled: true,
      );

  factory PadLayoutConfig.retro2D() => PadLayoutConfig(
        elements: {
          ControlId.lt: ControlElementLayout(
              id: ControlId.lt, relX: 0.12, relY: 0.10, scale: 1.0),
          ControlId.lb: ControlElementLayout(
              id: ControlId.lb, relX: 0.26, relY: 0.10, scale: 1.0),
          ControlId.center: ControlElementLayout(
              id: ControlId.center, relX: 0.50, relY: 0.10, scale: 1.0),
          ControlId.rb: ControlElementLayout(
              id: ControlId.rb, relX: 0.74, relY: 0.10, scale: 1.0),
          ControlId.rt: ControlElementLayout(
              id: ControlId.rt, relX: 0.88, relY: 0.10, scale: 1.0),
          // Large D-pad & ABXY, sticks & stick clicks hidden for retro 2D games
          ControlId.dpad: ControlElementLayout(
              id: ControlId.dpad, relX: 0.22, relY: 0.65, scale: 1.35),
          ControlId.abxy: ControlElementLayout(
              id: ControlId.abxy, relX: 0.78, relY: 0.65, scale: 1.35),
          ControlId.leftStick: ControlElementLayout(
              id: ControlId.leftStick,
              relX: 0.16,
              relY: 0.38,
              visible: false),
          ControlId.l3: ControlElementLayout(
              id: ControlId.l3, relX: 0.29, relY: 0.38, visible: false),
          ControlId.rightStick: ControlElementLayout(
              id: ControlId.rightStick,
              relX: 0.76,
              relY: 0.76,
              visible: false),
          ControlId.r3: ControlElementLayout(
              id: ControlId.r3, relX: 0.63, relY: 0.76, visible: false),
          ControlId.menuButton: ControlElementLayout(
              id: ControlId.menuButton, relX: 0.50, relY: 0.05, scale: 1.0),
        },
        opacity: 0.90,
        hapticsEnabled: true,
      );
}

/// Persistent storage for the user's customized touch controls layout.
class LayoutStore {
  static const _layoutKey = 'touch.layout.custom';

  Future<PadLayoutConfig> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_layoutKey);
    if (raw == null) return PadLayoutConfig.defaultXbox();
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return PadLayoutConfig.fromJson(json);
      }
      return PadLayoutConfig.defaultXbox();
    } catch (_) {
      return PadLayoutConfig.defaultXbox();
    }
  }

  Future<void> save(PadLayoutConfig config) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_layoutKey, jsonEncode(config.toJson()));
  }

  Future<PadLayoutConfig> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_layoutKey);
    return PadLayoutConfig.defaultXbox();
  }
}
