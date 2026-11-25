import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// Identifiers for every individual customizable control on the touch pad.
class ControlId {
  static const leftStick = 'leftStick';
  static const rightStick = 'rightStick';
  static const dpadUp = 'dpadUp';
  static const dpadDown = 'dpadDown';
  static const dpadLeft = 'dpadLeft';
  static const dpadRight = 'dpadRight';
  static const btnA = 'btnA';
  static const btnB = 'btnB';
  static const btnX = 'btnX';
  static const btnY = 'btnY';
  static const lt = 'lt';
  static const lb = 'lb';
  static const rt = 'rt';
  static const rb = 'rb';
  static const l3 = 'l3';
  static const r3 = 'r3';
  static const btnView = 'btnView';
  static const btnGuide = 'btnGuide';
  static const btnMenu = 'btnMenu';
  static const menuButton = 'menuButton';

  // Legacy bundled keys (v1) kept only for migrating previously saved layouts.
  static const legacyDpad = 'dpad';
  static const legacyAbxy = 'abxy';
  static const legacyCenter = 'center';

  static const dpadGroup = [dpadUp, dpadDown, dpadLeft, dpadRight];
  static const abxyGroup = [btnY, btnA, btnX, btnB];
  static const centerGroup = [btnView, btnGuide, btnMenu];

  static const all = [
    leftStick,
    l3,
    dpadUp,
    dpadDown,
    dpadLeft,
    dpadRight,
    btnY,
    btnA,
    btnX,
    btnB,
    rightStick,
    r3,
    lt,
    lb,
    rt,
    rb,
    btnView,
    btnGuide,
    btnMenu,
    menuButton,
  ];

  /// Returns the cluster group for [id] if it belongs to ABXY, D-Pad, or
  /// Center; otherwise null.
  static List<String>? groupOf(String id) {
    if (abxyGroup.contains(id)) return abxyGroup;
    if (dpadGroup.contains(id)) return dpadGroup;
    if (centerGroup.contains(id)) return centerGroup;
    return null;
  }

  /// Human-readable group name for [id], or null if standalone.
  static String? groupNameOf(String id) {
    if (abxyGroup.contains(id)) return 'ABXY';
    if (dpadGroup.contains(id)) return 'D-Pad';
    if (centerGroup.contains(id)) return 'Center';
    return null;
  }

  static String displayName(String id) {
    switch (id) {
      case leftStick:
        return 'Left Stick';
      case rightStick:
        return 'Right Stick';
      case dpadUp:
        return 'D-Pad Up';
      case dpadDown:
        return 'D-Pad Down';
      case dpadLeft:
        return 'D-Pad Left';
      case dpadRight:
        return 'D-Pad Right';
      case btnA:
        return 'A Button';
      case btnB:
        return 'B Button';
      case btnX:
        return 'X Button';
      case btnY:
        return 'Y Button';
      case lt:
        return 'LT Trigger';
      case lb:
        return 'LB Bumper';
      case rt:
        return 'RT Trigger';
      case rb:
        return 'RB Bumper';
      case l3:
        return 'L3 Click';
      case r3:
        return 'R3 Click';
      case btnView:
        return 'View Button';
      case btnGuide:
        return 'Guide Button';
      case btnMenu:
        return 'Menu Button';
      case menuButton:
        return 'Floating Menu';
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
        relX: ((j['relX'] as num?)?.toDouble() ?? 0.5).clamp(0.01, 0.99),
        relY: ((j['relY'] as num?)?.toDouble() ?? 0.5).clamp(0.01, 0.99),
        scale: ((j['scale'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 2.0),
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
    final fallback =
        defaults[id] ?? ControlElementLayout(id: id, relX: 0.5, relY: 0.5);
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

  /// Target element IDs affected by an operation on [id].
  List<String> targetIds(String id, {bool groupMode = false}) {
    if (!groupMode) return [id];
    return ControlId.groupOf(id) ?? [id];
  }

  /// Moves [id] (or its whole group when [groupMode] is true) to [newRelX],
  /// [newRelY]. In group mode, translation delta is clamped across all members
  /// so the formation remains rigid near screen borders.
  void moveControl(
    String id,
    double newRelX,
    double newRelY, {
    bool groupMode = false,
  }) {
    final ids = targetIds(id, groupMode: groupMode);
    if (ids.length <= 1) {
      final elem = getElement(id);
      elem.relX = newRelX.clamp(0.01, 0.99);
      elem.relY = newRelY.clamp(0.01, 0.99);
      return;
    }

    final anchor = getElement(id);
    final dx = newRelX - anchor.relX;
    final dy = newRelY - anchor.relY;

    var minDx = -double.infinity;
    var maxDx = double.infinity;
    var minDy = -double.infinity;
    var maxDy = double.infinity;
    for (final m in ids) {
      final el = getElement(m);
      minDx = math.max(minDx, 0.01 - el.relX);
      maxDx = math.min(maxDx, 0.99 - el.relX);
      minDy = math.max(minDy, 0.01 - el.relY);
      maxDy = math.min(maxDy, 0.99 - el.relY);
    }

    final clampedDx = minDx <= maxDx ? dx.clamp(minDx, maxDx) : 0.0;
    final clampedDy = minDy <= maxDy ? dy.clamp(minDy, maxDy) : 0.0;

    for (final m in ids) {
      final el = getElement(m);
      el.relX = (el.relX + clampedDx).clamp(0.01, 0.99);
      el.relY = (el.relY + clampedDy).clamp(0.01, 0.99);
    }
  }

  static double _roundScale(double v) =>
      ((v * 100).round() / 100).clamp(0.5, 2.0);

  /// Scales [id] (or its whole group around its centroid when [groupMode] is
  /// true) by [delta].
  void scaleControl(
    String id,
    double delta, {
    bool groupMode = false,
  }) {
    final ids = targetIds(id, groupMode: groupMode);
    if (ids.length <= 1) {
      final elem = getElement(id);
      elem.scale = _roundScale(elem.scale + delta);
      return;
    }

    var cx = 0.0;
    var cy = 0.0;
    for (final m in ids) {
      final el = getElement(m);
      cx += el.relX;
      cy += el.relY;
    }
    cx /= ids.length;
    cy /= ids.length;

    final anchor = getElement(id);
    final oldScale = anchor.scale;
    final nextScale = _roundScale(oldScale + delta);
    final ratio = oldScale > 0 ? nextScale / oldScale : 1.0;

    for (final m in ids) {
      final el = getElement(m);
      el.scale = _roundScale(el.scale + delta);
      el.relX = (cx + (el.relX - cx) * ratio).clamp(0.02, 0.98);
      el.relY = (cy + (el.relY - cy) * ratio).clamp(0.02, 0.98);
    }
  }

  /// Toggles visibility of [id] (or all members of its group when [groupMode]
  /// is true).
  void toggleVisibility(String id, {bool groupMode = false}) {
    final ids = targetIds(id, groupMode: groupMode);
    final nextVisible = !getElement(id).visible;
    for (final m in ids) {
      getElement(m).visible = nextVisible;
    }
  }

  /// Resets [id] (or all members of its group when [groupMode] is true) to
  /// Xbox defaults.
  void resetControl(String id, {bool groupMode = false}) {
    for (final m in targetIds(id, groupMode: groupMode)) {
      resetElement(m);
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
        'version': 2,
        'opacity': opacity,
        'hapticsEnabled': hapticsEnabled,
        'snapToGrid': snapToGrid,
        'elements': elements.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory PadLayoutConfig.fromJson(Map<String, dynamic> j) {
    final map = <String, ControlElementLayout>{};
    ControlElementLayout? legacyAbxy;
    ControlElementLayout? legacyDpad;
    ControlElementLayout? legacyCenter;

    if (j['elements'] is Map) {
      final rawMap = j['elements'] as Map;
      for (final entry in rawMap.entries) {
        if (entry.value is! Map) continue;
        final elem = ControlElementLayout.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        final key = elem.id.isNotEmpty ? elem.id : entry.key.toString();
        if (key == ControlId.legacyAbxy) {
          legacyAbxy = elem;
        } else if (key == ControlId.legacyDpad) {
          legacyDpad = elem;
        } else if (key == ControlId.legacyCenter) {
          legacyCenter = elem;
        } else if (ControlId.all.contains(key)) {
          map[key] = elem;
        }
      }
    }

    if (legacyAbxy != null) {
      final expanded = _diamondCluster(
        topId: ControlId.btnY,
        bottomId: ControlId.btnA,
        leftId: ControlId.btnX,
        rightId: ControlId.btnB,
        cx: legacyAbxy.relX,
        cy: legacyAbxy.relY,
        scale: legacyAbxy.scale,
        visible: legacyAbxy.visible,
      );
      expanded.forEach((k, v) => map.putIfAbsent(k, () => v));
    }

    if (legacyDpad != null) {
      final expanded = _diamondCluster(
        topId: ControlId.dpadUp,
        bottomId: ControlId.dpadDown,
        leftId: ControlId.dpadLeft,
        rightId: ControlId.dpadRight,
        cx: legacyDpad.relX,
        cy: legacyDpad.relY,
        scale: legacyDpad.scale,
        visible: legacyDpad.visible,
      );
      expanded.forEach((k, v) => map.putIfAbsent(k, () => v));
    }

    if (legacyCenter != null) {
      final expanded = _centerCluster(
        cx: legacyCenter.relX,
        cy: legacyCenter.relY,
        scale: legacyCenter.scale,
        visible: legacyCenter.visible,
      );
      expanded.forEach((k, v) => map.putIfAbsent(k, () => v));
    }

    // Backfill any missing controls with Xbox defaults.
    final defaults = _buildDefaultXboxElements();
    for (final id in ControlId.all) {
      map.putIfAbsent(id, () => defaults[id]!.clone());
    }

    return PadLayoutConfig(
      elements: map,
      opacity: ((j['opacity'] as num?)?.toDouble() ?? 0.85).clamp(0.1, 1.0),
      hapticsEnabled: (j['hapticsEnabled'] as bool?) ?? true,
      snapToGrid: (j['snapToGrid'] as bool?) ?? false,
    );
  }

  // --- Geometry Cluster Helpers ---

  static Map<String, ControlElementLayout> _diamondCluster({
    required String topId,
    required String bottomId,
    required String leftId,
    required String rightId,
    required double cx,
    required double cy,
    double scale = 1.0,
    bool visible = true,
  }) {
    final dx = 0.065 * scale;
    final dy = 0.13 * scale;
    return {
      topId: ControlElementLayout(
        id: topId,
        relX: cx.clamp(0.02, 0.98),
        relY: (cy - dy).clamp(0.02, 0.98),
        scale: scale,
        visible: visible,
      ),
      bottomId: ControlElementLayout(
        id: bottomId,
        relX: cx.clamp(0.02, 0.98),
        relY: (cy + dy).clamp(0.02, 0.98),
        scale: scale,
        visible: visible,
      ),
      leftId: ControlElementLayout(
        id: leftId,
        relX: (cx - dx).clamp(0.02, 0.98),
        relY: cy.clamp(0.02, 0.98),
        scale: scale,
        visible: visible,
      ),
      rightId: ControlElementLayout(
        id: rightId,
        relX: (cx + dx).clamp(0.02, 0.98),
        relY: cy.clamp(0.02, 0.98),
        scale: scale,
        visible: visible,
      ),
    };
  }

  static Map<String, ControlElementLayout> _centerCluster({
    required double cx,
    required double cy,
    double scale = 1.0,
    bool visible = true,
  }) {
    final dx = 0.10 * scale;
    return {
      ControlId.btnView: ControlElementLayout(
        id: ControlId.btnView,
        relX: (cx - dx).clamp(0.02, 0.98),
        relY: cy.clamp(0.02, 0.98),
        scale: scale,
        visible: visible,
      ),
      ControlId.btnGuide: ControlElementLayout(
        id: ControlId.btnGuide,
        relX: cx.clamp(0.02, 0.98),
        relY: cy.clamp(0.02, 0.98),
        scale: scale,
        visible: visible,
      ),
      ControlId.btnMenu: ControlElementLayout(
        id: ControlId.btnMenu,
        relX: (cx + dx).clamp(0.02, 0.98),
        relY: cy.clamp(0.02, 0.98),
        scale: scale,
        visible: visible,
      ),
    };
  }

  // --- Presets ---

  static Map<String, ControlElementLayout> _buildDefaultXboxElements() => {
        ControlId.lt: ControlElementLayout(
            id: ControlId.lt, relX: 0.10, relY: 0.08),
        ControlId.lb: ControlElementLayout(
            id: ControlId.lb, relX: 0.24, relY: 0.08),
        ..._centerCluster(cx: 0.50, cy: 0.17),
        ControlId.rb: ControlElementLayout(
            id: ControlId.rb, relX: 0.76, relY: 0.08),
        ControlId.rt: ControlElementLayout(
            id: ControlId.rt, relX: 0.90, relY: 0.08),
        ControlId.leftStick: ControlElementLayout(
            id: ControlId.leftStick, relX: 0.16, relY: 0.38),
        ControlId.l3: ControlElementLayout(
            id: ControlId.l3, relX: 0.29, relY: 0.38),
        ..._diamondCluster(
          topId: ControlId.dpadUp,
          bottomId: ControlId.dpadDown,
          leftId: ControlId.dpadLeft,
          rightId: ControlId.dpadRight,
          cx: 0.24,
          cy: 0.76,
        ),
        ..._diamondCluster(
          topId: ControlId.btnY,
          bottomId: ControlId.btnA,
          leftId: ControlId.btnX,
          rightId: ControlId.btnB,
          cx: 0.84,
          cy: 0.38,
        ),
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
          ..._centerCluster(cx: 0.50, cy: 0.17),
          ControlId.rb: ControlElementLayout(
              id: ControlId.rb, relX: 0.76, relY: 0.08),
          ControlId.rt: ControlElementLayout(
              id: ControlId.rt, relX: 0.90, relY: 0.08),
          ..._diamondCluster(
            topId: ControlId.dpadUp,
            bottomId: ControlId.dpadDown,
            leftId: ControlId.dpadLeft,
            rightId: ControlId.dpadRight,
            cx: 0.16,
            cy: 0.38,
          ),
          ControlId.leftStick: ControlElementLayout(
              id: ControlId.leftStick, relX: 0.24, relY: 0.76),
          ControlId.l3: ControlElementLayout(
              id: ControlId.l3, relX: 0.37, relY: 0.76),
          ..._diamondCluster(
            topId: ControlId.btnY,
            bottomId: ControlId.btnA,
            leftId: ControlId.btnX,
            rightId: ControlId.btnB,
            cx: 0.84,
            cy: 0.38,
          ),
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
          ControlId.rt: ControlElementLayout(
              id: ControlId.rt, relX: 0.10, relY: 0.08),
          ControlId.rb: ControlElementLayout(
              id: ControlId.rb, relX: 0.24, relY: 0.08),
          ..._centerCluster(cx: 0.50, cy: 0.17),
          ControlId.lb: ControlElementLayout(
              id: ControlId.lb, relX: 0.76, relY: 0.08),
          ControlId.lt: ControlElementLayout(
              id: ControlId.lt, relX: 0.90, relY: 0.08),
          ControlId.rightStick: ControlElementLayout(
              id: ControlId.rightStick, relX: 0.16, relY: 0.38),
          ControlId.r3: ControlElementLayout(
              id: ControlId.r3, relX: 0.29, relY: 0.38),
          ..._diamondCluster(
            topId: ControlId.btnY,
            bottomId: ControlId.btnA,
            leftId: ControlId.btnX,
            rightId: ControlId.btnB,
            cx: 0.24,
            cy: 0.76,
          ),
          ControlId.leftStick: ControlElementLayout(
              id: ControlId.leftStick, relX: 0.84, relY: 0.38),
          ControlId.l3: ControlElementLayout(
              id: ControlId.l3, relX: 0.71, relY: 0.38),
          ..._diamondCluster(
            topId: ControlId.dpadUp,
            bottomId: ControlId.dpadDown,
            leftId: ControlId.dpadLeft,
            rightId: ControlId.dpadRight,
            cx: 0.76,
            cy: 0.76,
          ),
          ControlId.menuButton: ControlElementLayout(
              id: ControlId.menuButton, relX: 0.50, relY: 0.05, scale: 1.0),
        },
        opacity: 0.85,
        hapticsEnabled: true,
      );

  factory PadLayoutConfig.claw() => PadLayoutConfig(
        elements: {
          ControlId.lt: ControlElementLayout(
              id: ControlId.lt, relX: 0.09, relY: 0.07, scale: 1.1),
          ControlId.lb: ControlElementLayout(
              id: ControlId.lb, relX: 0.09, relY: 0.22, scale: 1.1),
          ControlId.rt: ControlElementLayout(
              id: ControlId.rt, relX: 0.91, relY: 0.07, scale: 1.1),
          ControlId.rb: ControlElementLayout(
              id: ControlId.rb, relX: 0.91, relY: 0.22, scale: 1.1),
          ..._centerCluster(cx: 0.50, cy: 0.16, scale: 0.9),
          ControlId.leftStick: ControlElementLayout(
              id: ControlId.leftStick, relX: 0.18, relY: 0.50, scale: 1.0),
          ControlId.l3: ControlElementLayout(
              id: ControlId.l3, relX: 0.30, relY: 0.50, scale: 0.9),
          ..._diamondCluster(
            topId: ControlId.dpadUp,
            bottomId: ControlId.dpadDown,
            leftId: ControlId.dpadLeft,
            rightId: ControlId.dpadRight,
            cx: 0.26,
            cy: 0.80,
            scale: 0.95,
          ),
          ..._diamondCluster(
            topId: ControlId.btnY,
            bottomId: ControlId.btnA,
            leftId: ControlId.btnX,
            rightId: ControlId.btnB,
            cx: 0.82,
            cy: 0.48,
            scale: 1.05,
          ),
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
          ..._centerCluster(cx: 0.50, cy: 0.17),
          ControlId.rb: ControlElementLayout(
              id: ControlId.rb, relX: 0.74, relY: 0.10, scale: 1.0),
          ControlId.rt: ControlElementLayout(
              id: ControlId.rt, relX: 0.88, relY: 0.10, scale: 1.0),
          ..._diamondCluster(
            topId: ControlId.dpadUp,
            bottomId: ControlId.dpadDown,
            leftId: ControlId.dpadLeft,
            rightId: ControlId.dpadRight,
            cx: 0.22,
            cy: 0.65,
            scale: 1.35,
          ),
          ..._diamondCluster(
            topId: ControlId.btnY,
            bottomId: ControlId.btnA,
            leftId: ControlId.btnX,
            rightId: ControlId.btnB,
            cx: 0.78,
            cy: 0.65,
            scale: 1.35,
          ),
          ControlId.leftStick: ControlElementLayout(
            id: ControlId.leftStick,
            relX: 0.16,
            relY: 0.38,
            visible: false,
          ),
          ControlId.l3: ControlElementLayout(
              id: ControlId.l3, relX: 0.29, relY: 0.38, visible: false),
          ControlId.rightStick: ControlElementLayout(
            id: ControlId.rightStick,
            relX: 0.76,
            relY: 0.76,
            visible: false,
          ),
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
      if (json is Map) {
        return PadLayoutConfig.fromJson(Map<String, dynamic>.from(json));
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
