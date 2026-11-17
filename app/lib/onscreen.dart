import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
          color: face != null
              ? face.withAlpha(_down ? 255 : 215)
              : (_down ? C.lime.withAlpha(90) : Colors.white.withAlpha(16)),
          shape: widget.round ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: radius,
          border: face != null
              ? null
              : Border.all(
                  color: _down ? C.lime : Colors.white.withAlpha(68),
                  width: 1.5),
          boxShadow: face != null
              ? [
                  BoxShadow(
                      color: face.withAlpha(_down ? 150 : 70),
                      blurRadius: _down ? 22 : 12)
                ]
              : null,
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

/// Fully customizable touch controller pad.
/// In normal play mode, writes straight into the shared [PadState].
/// In edit mode, allows dragging, selecting, scaling, and reconfiguring controls.
class OnScreenPad extends StatelessWidget {
  const OnScreenPad({
    super.key,
    required this.state,
    this.layout,
    this.editMode = false,
    this.selectedId,
    this.onSelect,
    this.onElementMoved,
    this.onMenuPressed,
  });

  final PadState state;
  final PadLayoutConfig? layout;
  final bool editMode;
  final String? selectedId;
  final ValueChanged<String>? onSelect;
  final void Function(String id, double relX, double relY)? onElementMoved;
  final VoidCallback? onMenuPressed;

  Widget _btn(
    String label,
    int bit,
    double size, {
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
        onChanged: (d) {
          if (!editMode) state.setButton(bit, d);
        },
      );

  @override
  Widget build(BuildContext context) {
    final cfg = layout ?? PadLayoutConfig.defaultXbox();

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      if (w <= 0 || h <= 0) return const SizedBox.shrink();

      final baseStick = h * 0.36;
      final baseB = h * 0.13;
      final baseShW = h * 0.26;
      final baseShH = h * 0.11;

      Widget shoulder(String l, void Function(bool) f, double width, double height) =>
          HoldButton(
            label: l,
            w: width,
            h: height,
            round: false,
            hapticsEnabled: cfg.hapticsEnabled,
            onChanged: (d) {
              if (!editMode) f(d);
            },
          );

      // Helper to position an element given its relative center coordinates and dimensions
      Widget buildPositioned({
        required String id,
        required double elemW,
        required double elemH,
        required Widget child,
      }) {
        final elem = cfg.getElement(id);
        if (!elem.visible && !editMode) {
          return const SizedBox.shrink();
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
            isHidden: !elem.visible,
            editMode: editMode,
            onTap: () => onSelect?.call(id),
            onPanUpdate: (dx, dy) {
              if (onElementMoved == null) return;
              var newRelX = (left + elemW / 2 + dx) / w;
              var newRelY = (top + elemH / 2 + dy) / h;
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
        child: shoulder('LT', (d) => state.lt = d ? 255 : 0, ltW, ltH),
      );

      // 2. LB (Left Bumper)
      final lbElem = cfg.getElement(ControlId.lb);
      final lbW = baseShW * lbElem.scale;
      final lbH = baseShH * lbElem.scale;
      final lbWidget = buildPositioned(
        id: ControlId.lb,
        elemW: lbW,
        elemH: lbH,
        child: shoulder('LB', (d) => state.setButton(Btn.lb, d), lbW, lbH),
      );

      // 3. RT (Right Trigger)
      final rtElem = cfg.getElement(ControlId.rt);
      final rtW = baseShW * rtElem.scale;
      final rtH = baseShH * rtElem.scale;
      final rtWidget = buildPositioned(
        id: ControlId.rt,
        elemW: rtW,
        elemH: rtH,
        child: shoulder('RT', (d) => state.rt = d ? 255 : 0, rtW, rtH),
      );

      // 4. RB (Right Bumper)
      final rbElem = cfg.getElement(ControlId.rb);
      final rbW = baseShW * rbElem.scale;
      final rbH = baseShH * rbElem.scale;
      final rbWidget = buildPositioned(
        id: ControlId.rb,
        elemW: rbW,
        elemH: rbH,
        child: shoulder('RB', (d) => state.setButton(Btn.rb, d), rbW, rbH),
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
              state.lx = axisToInt16(x);
              state.ly = axisToInt16(y);
            }
          },
        ),
      );

      // 6. Right Stick
      final rsElem = cfg.getElement(ControlId.rightStick);
      final rsSize = baseStick * rsElem.scale;
      final rsWidget = buildPositioned(
        id: ControlId.rightStick,
        elemW: rsSize,
        elemH: rsSize,
        child: Stick(
          size: rsSize,
          onChanged: (x, y) {
            if (!editMode) {
              state.rx = axisToInt16(x);
              state.ry = axisToInt16(y);
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
            round: false, w: l3W, haptics: cfg.hapticsEnabled),
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
            round: false, w: r3W, haptics: cfg.hapticsEnabled),
      );

      // 9. D-Pad
      final dpElem = cfg.getElement(ControlId.dpad);
      final dpBtn = baseB * dpElem.scale;
      final dpSize = dpBtn * 3;
      final dpWidget = buildPositioned(
        id: ControlId.dpad,
        elemW: dpSize,
        elemH: dpSize,
        child: SizedBox(
          width: dpSize,
          height: dpSize,
          child: Stack(children: [
            Positioned(
                left: dpBtn,
                top: 0,
                child: _btn('▲', Btn.dUp, dpBtn,
                    round: false, haptics: cfg.hapticsEnabled)),
            Positioned(
                left: dpBtn,
                bottom: 0,
                child: _btn('▼', Btn.dDown, dpBtn,
                    round: false, haptics: cfg.hapticsEnabled)),
            Positioned(
                left: 0,
                top: dpBtn,
                child: _btn('◀', Btn.dLeft, dpBtn,
                    round: false, haptics: cfg.hapticsEnabled)),
            Positioned(
                right: 0,
                top: dpBtn,
                child: _btn('▶', Btn.dRight, dpBtn,
                    round: false, haptics: cfg.hapticsEnabled)),
          ]),
        ),
      );

      // 10. ABXY Face Buttons
      final abElem = cfg.getElement(ControlId.abxy);
      final abBtn = baseB * abElem.scale;
      final abSize = abBtn * 3;
      final abWidget = buildPositioned(
        id: ControlId.abxy,
        elemW: abSize,
        elemH: abSize,
        child: SizedBox(
          width: abSize,
          height: abSize,
          child: Stack(children: [
            Positioned(
                left: abBtn,
                top: 0,
                child: _btn('Y', Btn.y, abBtn,
                    color: C.y, haptics: cfg.hapticsEnabled)),
            Positioned(
                left: abBtn,
                bottom: 0,
                child: _btn('A', Btn.a, abBtn,
                    color: C.a, haptics: cfg.hapticsEnabled)),
            Positioned(
                left: 0,
                top: abBtn,
                child: _btn('X', Btn.x, abBtn,
                    color: C.x, haptics: cfg.hapticsEnabled)),
            Positioned(
                right: 0,
                top: abBtn,
                child: _btn('B', Btn.b, abBtn,
                    color: C.b, haptics: cfg.hapticsEnabled)),
          ]),
        ),
      );

      // 11. Center Navigation (View / Guide / Menu)
      final cElem = cfg.getElement(ControlId.center);
      final cBtnW = baseB * 1.5 * cElem.scale;
      final cBtnH = baseB * 0.5 * cElem.scale;
      final cGuide = baseB * 0.95 * cElem.scale;
      final cGap = 14 * cElem.scale;
      final cTotalW = cBtnW * 2 + cGuide + cGap * 2;
      final cTotalH = cGuide;
      final cWidget = buildPositioned(
        id: ControlId.center,
        elemW: cTotalW,
        elemH: cTotalH,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _btn('VIEW', Btn.back, cBtnH,
              round: false, w: cBtnW, haptics: cfg.hapticsEnabled),
          SizedBox(width: cGap),
          _btn('', Btn.guide, cGuide,
              haptics: cfg.hapticsEnabled,
              child: ClipOval(
                  child: Image.asset('assets/logo.png',
                      width: cGuide * 0.84, height: cGuide * 0.84))),
          SizedBox(width: cGap),
          _btn('MENU', Btn.start, cBtnH,
              round: false, w: cBtnW, haptics: cfg.hapticsEnabled),
        ]),
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

      final stack = Stack(children: [
        ltWidget,
        lbWidget,
        rtWidget,
        rbWidget,
        cWidget,
        menuWidget,
        lsWidget,
        l3Widget,
        dpWidget,
        abWidget,
        rsWidget,
        r3Widget,
      ]);

      if (editMode) {
        return stack;
      }

      return Opacity(
        opacity: cfg.opacity.clamp(0.1, 1.0),
        child: stack,
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
    required this.isHidden,
    required this.editMode,
    required this.onTap,
    required this.onPanUpdate,
    required this.child,
  });

  final String id;
  final double width, height;
  final bool isSelected;
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
        : (isHidden ? Colors.white.withAlpha(50) : C.cyan.withAlpha(140));

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
            width: isSelected ? 2.0 : 1.0,
            style: isHidden ? BorderStyle.solid : BorderStyle.solid,
          ),
          color: isSelected
              ? C.lime.withAlpha(30)
              : (isHidden ? Colors.black.withAlpha(120) : Colors.transparent),
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
                    ControlId.displayName(id).toUpperCase(),
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
