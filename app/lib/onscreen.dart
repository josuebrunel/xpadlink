import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'input_config.dart';
import 'layout.dart';
import 'protocol.dart';
import 'theme.dart';

/// Multi-touch safe: every widget tracks its own pointer with a Listener.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.label,
    required this.onChanged,
    required this.w,
    required this.h,
    this.round = true,
    this.color,
    this.child,
    this.fontSize,
    this.hapticsEnabled = false,
    this.externalActive = false,
  });

  final String label;
  final ValueChanged<bool> onChanged;
  final double w, h;
  final bool round;

  /// A face colour fills the button (ABXY). Without one it is a glass key.
  final Color? color;

  /// Replaces the label, for the guide button's logo.
  final Widget? child;
  final double? fontSize;
  final bool hapticsEnabled;
  final bool externalActive;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
    widget.onChanged(v);
    if (v && widget.hapticsEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final face = widget.color;
    final radius = widget.round ? null : BorderRadius.circular(widget.h * 0.34);
    final active = _down || widget.externalActive;
    final extOnly = widget.externalActive && !_down;
    final glassFill = extOnly
        ? C.cyan.withAlpha(75)
        : (_down ? C.lime.withAlpha(90) : Colors.white.withAlpha(16));
    final borderColor =
        extOnly ? C.cyan : (_down ? C.lime : Colors.white.withAlpha(68));

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.w,
        height: widget.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: face != null ? face.withAlpha(active ? 255 : 215) : glassFill,
          shape: widget.round ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: radius,
          border: face != null
              ? (extOnly ? Border.all(color: C.cyan, width: 2) : null)
              : Border.all(color: borderColor, width: 1.5),
          boxShadow: face != null
              ? [
                  BoxShadow(
                      color: (extOnly ? C.cyan : face).withAlpha(active ? 150 : 70),
                      blurRadius: active ? 22 : 12)
                ]
              : (extOnly
                  ? [BoxShadow(color: C.cyan.withAlpha(110), blurRadius: 14)]
                  : null),
        ),
        child: widget.child ??
            Text(widget.label,
                style: display(widget.fontSize ?? widget.h * 0.34,
                    color: face != null ? C.bg : C.ink, spacing: 1)),
      ),
    );
  }
}

class Stick extends StatefulWidget {
  const Stick({super.key, required this.size, required this.onChanged});

  final double size;

  /// x and y in -1..1, y positive is down.
  final void Function(double x, double y) onChanged;

  @override
  State<Stick> createState() => _StickState();
}

class _StickState extends State<Stick> {
  int? _pointer;
  Offset _v = Offset.zero;

  double get _knobR => widget.size * 0.22;
  double get _travel => widget.size / 2 - _knobR;

  void _update(Offset local) {
    final c = Offset(widget.size / 2, widget.size / 2);
    var d = (local - c) / _travel;
    if (d.distance > 1) d = d / d.distance;
    setState(() => _v = d);
    widget.onChanged(d.dx, d.dy);
  }

  void _release() {
    _pointer = null;
    setState(() => _v = Offset.zero);
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final held = _pointer != null;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (_pointer != null) return;
        _pointer = e.pointer;
        _update(e.localPosition);
      },
      onPointerMove: (e) {
        if (e.pointer == _pointer) _update(e.localPosition);
      },
      onPointerUp: (e) {
        if (e.pointer == _pointer) _release();
      },
      onPointerCancel: (e) {
        if (e.pointer == _pointer) _release();
      },
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(0, -0.2),
                  colors: [Color(0x14FFFFFF), Color(0x06FFFFFF)],
                ),
                border: Border.all(
                    color: held
                        ? C.lime.withAlpha(150)
                        : Colors.white.withAlpha(58),
                    width: 1.5),
              ),
            ),
          ),
          Positioned(
            left: s / 2 - _knobR + _v.dx * _travel,
            top: s / 2 - _knobR + _v.dy * _travel,
            child: Container(
              width: _knobR * 2,
              height: _knobR * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  colors: [Color(0x66FFFFFF), Color(0x22FFFFFF)],
                ),
                border: Border.all(
                    color: held ? C.lime : Colors.white.withAlpha(102),
                    width: 1.5),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Empty-space drag layer that translates finger drags into right-stick (RX/RY)
/// camera motion without disturbing controls sitting above it.
class TouchLookLayer extends StatefulWidget {
  const TouchLookLayer({
    super.key,
    required this.width,
    required this.height,
    required this.config,
    required this.onChanged,
  });

  final double width;
  final double height;
  final TouchLookConfig config;
  final void Function(double x, double y, bool active) onChanged;

  @override
  State<TouchLookLayer> createState() => _TouchLookLayerState();
}

class _TouchLookLayerState extends State<TouchLookLayer> {
  int? _activePointer;
  Offset? _anchor;
  Offset? _pointerPos;
  Offset _knobOffset = Offset.zero;
  double _velX = 0;
  double _velY = 0;
  final Stopwatch _sw = Stopwatch()..start();
  int _lastMoveMs = 0;
  Timer? _decayTimer;

  @override
  void didUpdateWidget(TouchLookLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final disabled = !widget.config.enabled && oldWidget.config.enabled;
    final modeChanged = widget.config.mode != oldWidget.config.mode;
    final zoneChanged = widget.config.zone != oldWidget.config.zone;
    if (disabled || modeChanged || zoneChanged) {
      _resetInternal(notifyState: false);
    }
  }

  @override
  void dispose() {
    _decayTimer?.cancel();
    _decayTimer = null;
    if (_activePointer != null) {
      _activePointer = null;
      widget.onChanged(0, 0, false);
    }
    super.dispose();
  }

  void _resetInternal({required bool notifyState}) {
    _decayTimer?.cancel();
    _decayTimer = null;
    final wasActive = _activePointer != null;
    _activePointer = null;
    _anchor = null;
    _pointerPos = null;
    _knobOffset = Offset.zero;
    _velX = 0;
    _velY = 0;
    if (wasActive) {
      widget.onChanged(0, 0, false);
    }
    if (notifyState && mounted) {
      setState(() {});
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    if (!widget.config.enabled || _activePointer != null) return;
    if (widget.config.zone == TouchLookZone.rightHalf &&
        e.localPosition.dx < widget.width * 0.5) {
      return;
    }

    _activePointer = e.pointer;
    _anchor = e.localPosition;
    _pointerPos = e.localPosition;
    _knobOffset = Offset.zero;
    _velX = 0;
    _velY = 0;
    _lastMoveMs = _sw.elapsedMilliseconds;

    if (widget.config.mode == TouchLookMode.relativeSwipe) {
      _decayTimer?.cancel();
      _decayTimer = Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => _tickRelative(),
      );
    }
    if (widget.config.showVisualFeedback && mounted) {
      setState(() {});
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _activePointer) return;

    if (widget.config.mode == TouchLookMode.floatingStick) {
      final anchor = _anchor;
      if (anchor == null) return;
      final dx = e.localPosition.dx - anchor.dx;
      final dy = e.localPosition.dy - anchor.dy;
      final out = TouchLookMath.computeFloatingStick(
        dx: dx,
        dy: dy,
        canvasHeight: widget.height,
        sensitivity: widget.config.sensitivity,
        invertX: widget.config.invertX,
        invertY: widget.config.invertY,
      );
      widget.onChanged(out.x, out.y, true);

      if (widget.config.showVisualFeedback && mounted) {
        final maxR = math.max(
          40.0,
          (widget.height * 0.16) / math.max(0.4, widget.config.sensitivity),
        );
        var kx = dx / maxR;
        var ky = dy / maxR;
        final kDist = math.sqrt(kx * kx + ky * ky);
        if (kDist > 1.0) {
          kx /= kDist;
          ky /= kDist;
        }
        setState(() => _knobOffset = Offset(kx * 30.0, ky * 30.0));
      }
      return;
    }

    // Relative swipe trackpad mode.
    final nowMs = _sw.elapsedMilliseconds;
    final dtMs = (nowMs - _lastMoveMs).clamp(4, 50);
    _lastMoveMs = nowMs;

    final h = math.max(1.0, widget.height);
    final vx = (e.delta.dx / h) * (1000.0 / dtMs) * 0.42 * widget.config.sensitivity;
    final vy = (e.delta.dy / h) * (1000.0 / dtMs) * 0.42 * widget.config.sensitivity;
    _velX = _velX * 0.35 + vx * 0.65;
    _velY = _velY * 0.35 + vy * 0.65;

    final out = TouchLookMath.computeRelativeVelocity(
      vx: _velX,
      vy: _velY,
      deadzoneBoost: widget.config.deadzoneBoost,
      invertX: widget.config.invertX,
      invertY: widget.config.invertY,
    );
    widget.onChanged(out.x, out.y, out.x != 0.0 || out.y != 0.0);

    if (widget.config.showVisualFeedback && mounted) {
      setState(() => _pointerPos = e.localPosition);
    }
  }

  void _tickRelative() {
    if (!mounted || _activePointer == null) {
      _decayTimer?.cancel();
      _decayTimer = null;
      return;
    }
    if (_sw.elapsedMilliseconds - _lastMoveMs > 28) {
      _velX *= 0.68;
      _velY *= 0.68;
    }
    final out = TouchLookMath.computeRelativeVelocity(
      vx: _velX,
      vy: _velY,
      deadzoneBoost: widget.config.deadzoneBoost,
      invertX: widget.config.invertX,
      invertY: widget.config.invertY,
    );
    final active = out.x != 0.0 || out.y != 0.0;
    if (!active && _velX.abs() < 0.005 && _velY.abs() < 0.005) {
      _velX = 0;
      _velY = 0;
    }
    widget.onChanged(out.x, out.y, active);
  }

  void _onPointerEnd(PointerEvent e) {
    if (e.pointer == _activePointer) {
      _resetInternal(notifyState: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showVis = widget.config.showVisualFeedback;
    final rightOnly = widget.config.zone == TouchLookZone.rightHalf;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (showVis && rightOnly)
              Positioned(
                left: widget.width * 0.5,
                top: 12,
                bottom: 12,
                child: IgnorePointer(
                  child: Container(
                    width: 1,
                    color: C.cyan.withAlpha(_activePointer != null ? 95 : 28),
                  ),
                ),
              ),
            if (showVis &&
                widget.config.mode == TouchLookMode.floatingStick &&
                _anchor != null)
              Positioned(
                left: _anchor!.dx - 46,
                top: _anchor!.dy - 46,
                child: IgnorePointer(
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: C.cyan.withAlpha(18),
                      border: Border.all(
                        color: C.cyan.withAlpha(140),
                        width: 1.5,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 46 - 16 + _knobOffset.dx,
                          top: 46 - 16 + _knobOffset.dy,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: C.cyan.withAlpha(80),
                              border: Border.all(color: C.cyan, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (showVis &&
                widget.config.mode == TouchLookMode.relativeSwipe &&
                _pointerPos != null)
              Positioned(
                left: _pointerPos!.dx - 14,
                top: _pointerPos!.dy - 14,
                child: IgnorePointer(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: C.cyan.withAlpha(36),
                      border: Border.all(color: C.cyan, width: 1.5),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fully customizable touch controller pad.
/// In normal play mode, writes through [mixer] (if provided) or straight into
/// the shared [PadState].
/// In edit mode, allows dragging, selecting, scaling, and reconfiguring controls.
class OnScreenPad extends StatelessWidget {
  const OnScreenPad({
    super.key,
    required this.state,
    this.layout,
    this.editMode = false,
    this.groupMode = false,
    this.selectedId,
    this.onSelect,
    this.onElementMoved,
    this.onMenuPressed,
    this.mixer,
    this.touchLook,
    this.externalActiveTargets = const <TriggerTarget>{},
  });

  final PadState state;
  final PadLayoutConfig? layout;
  final bool editMode;
  final bool groupMode;
  final String? selectedId;
  final ValueChanged<String>? onSelect;
  final void Function(String id, double relX, double relY)? onElementMoved;
  final VoidCallback? onMenuPressed;
  final InputMixer? mixer;
  final TouchLookConfig? touchLook;
  final Set<TriggerTarget> externalActiveTargets;

  void _setButton(int bit, bool down) {
    final m = mixer;
    if (m != null) {
      m.setTouchButton(bit, down);
      m.applyTo(state);
    } else {
      state.setButton(bit, down);
    }
  }

  void _setTouchLook(double x, double y, bool active) {
    final m = mixer;
    if (m != null) {
      m.setTouchLook(x, y, active: active);
      m.applyTo(state);
    } else {
      state.rx = active ? axisToInt16(x) : 0;
      state.ry = active ? axisToInt16(y) : 0;
    }
  }

  Widget _btn(
    String label,
    int bit,
    double size, {
    TriggerTarget target = TriggerTarget.none,
    Color? color,
    bool round = true,
    double? w,
    Widget? child,
    bool haptics = false,
  }) =>
      HoldButton(
        label: label,
        w: w ?? size,
        h: size,
        round: round,
        color: color,
        child: child,
        hapticsEnabled: haptics,
        externalActive:
            !editMode && target != TriggerTarget.none && externalActiveTargets.contains(target),
        onChanged: (d) {
          if (!editMode) _setButton(bit, d);
        },
      );

  @override
  Widget build(BuildContext context) {
    final cfg = layout ?? PadLayoutConfig.defaultXbox();
    final tl = touchLook;
    final tlActive = !editMode && (tl?.enabled ?? false);
    final hideRightStick = tlActive && tl!.hideRightStick;
    final groupMembers = (editMode && groupMode && selectedId != null)
        ? (ControlId.groupOf(selectedId!) ?? const <String>[])
        : const <String>[];

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      if (w <= 0 || h <= 0) return const SizedBox.shrink();

      final baseStick = h * 0.36;
      final baseB = h * 0.13;
      final baseShW = h * 0.26;
      final baseShH = h * 0.11;

      Widget shoulder(
        String l,
        TriggerTarget target,
        void Function(bool) f,
        double width,
        double height,
      ) =>
          HoldButton(
            label: l,
            w: width,
            h: height,
            round: false,
            hapticsEnabled: cfg.hapticsEnabled,
            externalActive: !editMode && externalActiveTargets.contains(target),
            onChanged: (d) {
              if (!editMode) f(d);
            },
          );

      // Helper to position an element given its relative center coordinates and dimensions
      Widget? buildPositioned({
        required String id,
        required double elemW,
        required double elemH,
        required Widget child,
      }) {
        final elem = cfg.getElement(id);
        if (!elem.visible && !editMode) {
          return null;
        }

        // Relative coordinates refer to the element's center
        var left = elem.relX * w - elemW / 2;
        var top = elem.relY * h - elemH / 2;

        // Clamp inside canvas bounds
        final maxLeft = math.max(0.0, w - elemW);
        final maxTop = math.max(0.0, h - elemH);
        left = left.clamp(0.0, maxLeft);
        top = top.clamp(0.0, maxTop);

        return Positioned(
          left: left,
          top: top,
          child: _EditWrapper(
            id: id,
            width: elemW,
            height: elemH,
            isSelected: editMode && selectedId == id,
            isGroupMember:
                editMode && groupMembers.contains(id) && selectedId != id,
            groupBadge: (editMode && groupMode && selectedId == id)
                ? ControlId.groupNameOf(id)
                : null,
            isHidden: !elem.visible,
            editMode: editMode,
            onTap: () => onSelect?.call(id),
            onPanUpdate: (dx, dy) {
              if (onElementMoved == null) return;
              var newRelX = elem.relX + dx / w;
              var newRelY = elem.relY + dy / h;
              if (cfg.snapToGrid) {
                const step = 0.025; // 2.5% grid
                newRelX = (newRelX / step).round() * step;
                newRelY = (newRelY / step).round() * step;
              }
              onElementMoved!(
                id,
                newRelX.clamp(0.01, 0.99),
                newRelY.clamp(0.01, 0.99),
              );
            },
            child: child,
          ),
        );
      }

      // 1. LT (Left Trigger)
      final ltElem = cfg.getElement(ControlId.lt);
      final ltW = baseShW * ltElem.scale;
      final ltH = baseShH * ltElem.scale;
      final ltWidget = buildPositioned(
        id: ControlId.lt,
        elemW: ltW,
        elemH: ltH,
        child: shoulder('LT', TriggerTarget.lt, (d) {
          final m = mixer;
          if (m != null) {
            m.setTouchLt(d ? 255 : 0);
            m.applyTo(state);
          } else {
            state.lt = d ? 255 : 0;
          }
        }, ltW, ltH),
      );

      // 2. LB (Left Bumper)
      final lbElem = cfg.getElement(ControlId.lb);
      final lbW = baseShW * lbElem.scale;
      final lbH = baseShH * lbElem.scale;
      final lbWidget = buildPositioned(
        id: ControlId.lb,
        elemW: lbW,
        elemH: lbH,
        child: shoulder(
          'LB',
          TriggerTarget.lb,
          (d) => _setButton(Btn.lb, d),
          lbW,
          lbH,
        ),
      );

      // 3. RT (Right Trigger)
      final rtElem = cfg.getElement(ControlId.rt);
      final rtW = baseShW * rtElem.scale;
      final rtH = baseShH * rtElem.scale;
      final rtWidget = buildPositioned(
        id: ControlId.rt,
        elemW: rtW,
        elemH: rtH,
        child: shoulder('RT', TriggerTarget.rt, (d) {
          final m = mixer;
          if (m != null) {
            m.setTouchRt(d ? 255 : 0);
            m.applyTo(state);
          } else {
            state.rt = d ? 255 : 0;
          }
        }, rtW, rtH),
      );

      // 4. RB (Right Bumper)
      final rbElem = cfg.getElement(ControlId.rb);
      final rbW = baseShW * rbElem.scale;
      final rbH = baseShH * rbElem.scale;
      final rbWidget = buildPositioned(
        id: ControlId.rb,
        elemW: rbW,
        elemH: rbH,
        child: shoulder(
          'RB',
          TriggerTarget.rb,
          (d) => _setButton(Btn.rb, d),
          rbW,
          rbH,
        ),
      );

      // 5. Left Stick
      final lsElem = cfg.getElement(ControlId.leftStick);
      final lsSize = baseStick * lsElem.scale;
      final lsWidget = buildPositioned(
        id: ControlId.leftStick,
        elemW: lsSize,
        elemH: lsSize,
        child: Stick(
          size: lsSize,
          onChanged: (x, y) {
            if (!editMode) {
              final m = mixer;
              if (m != null) {
                m.setTouchLeftStick(axisToInt16(x), axisToInt16(y));
                m.applyTo(state);
              } else {
                state.lx = axisToInt16(x);
                state.ly = axisToInt16(y);
              }
            }
          },
        ),
      );

      // 6. Right Stick
      final rsElem = cfg.getElement(ControlId.rightStick);
      final rsSize = baseStick * rsElem.scale;
      final Widget? rsWidget = hideRightStick
          ? null
          : buildPositioned(
              id: ControlId.rightStick,
              elemW: rsSize,
              elemH: rsSize,
              child: Stick(
                size: rsSize,
                onChanged: (x, y) {
                  if (!editMode) {
                    final m = mixer;
                    if (m != null) {
                      m.setTouchRightStick(axisToInt16(x), axisToInt16(y));
                      m.applyTo(state);
                    } else {
                      state.rx = axisToInt16(x);
                      state.ry = axisToInt16(y);
                    }
                  }
                },
              ),
            );

      // 7. L3 (Stick Click)
      final l3Elem = cfg.getElement(ControlId.l3);
      final l3W = baseB * 0.8 * l3Elem.scale;
      final l3H = baseB * 0.5 * l3Elem.scale;
      final l3Widget = buildPositioned(
        id: ControlId.l3,
        elemW: l3W,
        elemH: l3H,
        child: _btn('L3', Btn.l3, l3H,
            target: TriggerTarget.l3,
            round: false,
            w: l3W,
            haptics: cfg.hapticsEnabled),
      );

      // 8. R3 (Stick Click)
      final r3Elem = cfg.getElement(ControlId.r3);
      final r3W = baseB * 0.8 * r3Elem.scale;
      final r3H = baseB * 0.5 * r3Elem.scale;
      final r3Widget = buildPositioned(
        id: ControlId.r3,
        elemW: r3W,
        elemH: r3H,
        child: _btn('R3', Btn.r3, r3H,
            target: TriggerTarget.r3,
            round: false,
            w: r3W,
            haptics: cfg.hapticsEnabled),
      );

      Widget? dpadButton(
        String id,
        String label,
        int bit,
        TriggerTarget target,
      ) {
        final elem = cfg.getElement(id);
        final size = baseB * elem.scale;
        return buildPositioned(
          id: id,
          elemW: size,
          elemH: size,
          child: _btn(
            label,
            bit,
            size,
            target: target,
            round: false,
            haptics: cfg.hapticsEnabled,
          ),
        );
      }

      Widget? faceButton(
        String id,
        String label,
        int bit,
        TriggerTarget target,
        Color color,
      ) {
        final elem = cfg.getElement(id);
        final size = baseB * elem.scale;
        return buildPositioned(
          id: id,
          elemW: size,
          elemH: size,
          child: _btn(
            label,
            bit,
            size,
            target: target,
            color: color,
            haptics: cfg.hapticsEnabled,
          ),
        );
      }

      // 9. Individual D-Pad Buttons
      final dpadUpWidget = dpadButton(ControlId.dpadUp, '▲', Btn.dUp, TriggerTarget.dUp);
      final dpadDownWidget =
          dpadButton(ControlId.dpadDown, '▼', Btn.dDown, TriggerTarget.dDown);
      final dpadLeftWidget =
          dpadButton(ControlId.dpadLeft, '◀', Btn.dLeft, TriggerTarget.dLeft);
      final dpadRightWidget =
          dpadButton(ControlId.dpadRight, '▶', Btn.dRight, TriggerTarget.dRight);

      // 10. Individual ABXY Face Buttons
      final btnYWidget = faceButton(ControlId.btnY, 'Y', Btn.y, TriggerTarget.y, C.y);
      final btnAWidget = faceButton(ControlId.btnA, 'A', Btn.a, TriggerTarget.a, C.a);
      final btnXWidget = faceButton(ControlId.btnX, 'X', Btn.x, TriggerTarget.x, C.x);
      final btnBWidget = faceButton(ControlId.btnB, 'B', Btn.b, TriggerTarget.b, C.b);

      // 11. Individual Center Navigation (View / Guide / Menu)
      final viewElem = cfg.getElement(ControlId.btnView);
      final viewW = baseB * 1.5 * viewElem.scale;
      final viewH = baseB * 0.55 * viewElem.scale;
      final viewWidget = buildPositioned(
        id: ControlId.btnView,
        elemW: viewW,
        elemH: viewH,
        child: _btn(
          'VIEW',
          Btn.back,
          viewH,
          target: TriggerTarget.back,
          round: false,
          w: viewW,
          haptics: cfg.hapticsEnabled,
        ),
      );

      final guideElem = cfg.getElement(ControlId.btnGuide);
      final guideSize = baseB * 0.95 * guideElem.scale;
      final guideWidget = buildPositioned(
        id: ControlId.btnGuide,
        elemW: guideSize,
        elemH: guideSize,
        child: _btn(
          '',
          Btn.guide,
          guideSize,
          target: TriggerTarget.guide,
          haptics: cfg.hapticsEnabled,
          child: ClipOval(
            child: Image.asset(
              'assets/logo.png',
              width: guideSize * 0.84,
              height: guideSize * 0.84,
              cacheWidth: 192,
              cacheHeight: 192,
            ),
          ),
        ),
      );

      final startElem = cfg.getElement(ControlId.btnMenu);
      final startW = baseB * 1.5 * startElem.scale;
      final startH = baseB * 0.55 * startElem.scale;
      final startWidget = buildPositioned(
        id: ControlId.btnMenu,
        elemW: startW,
        elemH: startH,
        child: _btn(
          'MENU',
          Btn.start,
          startH,
          target: TriggerTarget.start,
          round: false,
          w: startW,
          haptics: cfg.hapticsEnabled,
        ),
      );

      // 12. Floating Quick Menu Button
      final menuElem = cfg.getElement(ControlId.menuButton);
      final menuBtnSize = baseB * 0.9 * menuElem.scale;
      final menuW = menuBtnSize * 2.3;
      final menuH = menuBtnSize * 0.95;
      final menuWidget = buildPositioned(
        id: ControlId.menuButton,
        elemW: menuW,
        elemH: menuH,
        child: Material(
          color: C.panel.withAlpha(editMode ? 220 : 175),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: editMode ? C.line : C.line.withAlpha(150)),
          ),
          child: InkWell(
            onTap: editMode
                ? null
                : () {
                    if (cfg.hapticsEnabled) {
                      HapticFeedback.lightImpact();
                    }
                    onMenuPressed?.call();
                  },
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: menuW,
              height: menuH,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.menu, size: 16, color: C.lime),
                  const SizedBox(width: 4),
                  Text('MENU', style: display(10.5, color: C.ink, spacing: 1.4)),
                ],
              ),
            ),
          ),
        ),
      );

      final controlsStack = Stack(
        fit: StackFit.expand,
        children: [
          for (final child in <Widget?>[
            ltWidget,
            lbWidget,
            rtWidget,
            rbWidget,
            viewWidget,
            guideWidget,
            startWidget,
            lsWidget,
            l3Widget,
            dpadUpWidget,
            dpadDownWidget,
            dpadLeftWidget,
            dpadRightWidget,
            btnYWidget,
            btnAWidget,
            btnXWidget,
            btnBWidget,
            rsWidget,
            r3Widget,
            menuWidget,
          ])
            if (child != null) child,
        ],
      );

      if (editMode) {
        return controlsStack;
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          if (tlActive)
            Positioned.fill(
              child: TouchLookLayer(
                width: w,
                height: h,
                config: tl!,
                onChanged: _setTouchLook,
              ),
            ),
          Positioned.fill(
            child: Opacity(
              opacity: cfg.opacity.clamp(0.1, 1.0),
              child: controlsStack,
            ),
          ),
        ],
      );
    });
  }
}

/// Visual wrapper for controls during edit and normal mode.
class _EditWrapper extends StatelessWidget {
  const _EditWrapper({
    required this.id,
    required this.width,
    required this.height,
    required this.isSelected,
    this.isGroupMember = false,
    this.groupBadge,
    required this.isHidden,
    required this.editMode,
    required this.onTap,
    required this.onPanUpdate,
    required this.child,
  });

  final String id;
  final double width, height;
  final bool isSelected;
  final bool isGroupMember;
  final String? groupBadge;
  final bool isHidden;
  final bool editMode;
  final VoidCallback onTap;
  final void Function(double dx, double dy) onPanUpdate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!editMode) {
      return child;
    }

    final borderColor = isSelected
        ? C.lime
        : (isGroupMember
            ? C.lime.withAlpha(160)
            : (isHidden ? Colors.white.withAlpha(50) : C.cyan.withAlpha(140)));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanStart: (_) => onTap(),
      onPanUpdate: (d) => onPanUpdate(d.delta.dx, d.delta.dy),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2.0 : (isGroupMember ? 1.5 : 1.0),
          ),
          color: isSelected
              ? C.lime.withAlpha(30)
              : (isGroupMember
                  ? C.lime.withAlpha(16)
                  : (isHidden ? Colors.black.withAlpha(120) : Colors.transparent)),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: C.lime.withAlpha(100),
                    blurRadius: 16,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: isHidden ? 0.35 : 1.0,
              child: IgnorePointer(ignoring: true, child: child),
            ),
            if (isHidden)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: C.bg.withAlpha(220),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: C.b.withAlpha(160)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.visibility_off, size: 12, color: C.b),
                    const SizedBox(width: 4),
                    Text('HIDDEN', style: mono(9, color: C.b, w: FontWeight.w700)),
                  ],
                ),
              ),
            if (isSelected)
              Positioned(
                top: -18,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: C.lime,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(color: C.lime.withAlpha(100), blurRadius: 8)
                    ],
                  ),
                  child: Text(
                    '${ControlId.displayName(id).toUpperCase()}${groupBadge != null ? ' · GROUP' : ''}',
                    style: mono(9, color: C.bg, w: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
