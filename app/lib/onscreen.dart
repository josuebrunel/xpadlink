import 'package:flutter/material.dart';

import 'protocol.dart';

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
  });

  final String label;
  final ValueChanged<bool> onChanged;
  final double w, h;
  final bool round;
  final Color? color;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? Colors.white;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Container(
        width: widget.w,
        height: widget.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: base.withAlpha(_down ? 230 : 70),
          shape: widget.round ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.round ? null : BorderRadius.circular(12),
          border: Border.all(color: Colors.white54),
        ),
        child: Text(widget.label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
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
                color: Colors.white12,
                border: Border.all(color: Colors.white38),
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
                  shape: BoxShape.circle, color: Colors.white.withAlpha(150)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Xbox style layout. Writes straight into the shared [PadState].
class OnScreenPad extends StatelessWidget {
  const OnScreenPad({super.key, required this.state});

  final PadState state;

  Widget _btn(String label, int bit, double size, {Color? color}) => HoldButton(
        label: label,
        w: size,
        h: size,
        color: color,
        onChanged: (d) => state.setButton(bit, d),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final h = c.maxHeight;
      final stick = h * 0.36;
      final b = h * 0.13;
      final shW = h * 0.26;
      final shH = h * 0.11;

      Widget shoulder(String l, void Function(bool) f) =>
          HoldButton(label: l, w: shW, h: shH, round: false, onChanged: f);

      return Stack(children: [
        // Shoulders and triggers
        Positioned(
          left: 24,
          top: 8,
          child: Row(children: [
            shoulder('LT', (d) => state.lt = d ? 255 : 0),
            const SizedBox(width: 8),
            shoulder('LB', (d) => state.setButton(Btn.lb, d)),
          ]),
        ),
        Positioned(
          right: 24,
          top: 8,
          child: Row(children: [
            shoulder('RB', (d) => state.setButton(Btn.rb, d)),
            const SizedBox(width: 8),
            shoulder('RT', (d) => state.rt = d ? 255 : 0),
          ]),
        ),
        // Back / Guide / Start
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _btn('BK', Btn.back, b * 0.8),
            const SizedBox(width: 12),
            _btn('G', Btn.guide, b * 0.8),
            const SizedBox(width: 12),
            _btn('ST', Btn.start, b * 0.8),
          ]),
        ),
        // Left stick (upper left)
        Positioned(
          left: 40,
          top: h * 0.2,
          child: Stick(
            size: stick,
            onChanged: (x, y) {
              state.lx = axisToInt16(x);
              state.ly = axisToInt16(y);
            },
          ),
        ),
        // L3: stick click, beside the left stick
        Positioned(
          left: 40 + stick + 12,
          top: h * 0.2 + stick / 2 - b * 0.4,
          child: _btn('L3', Btn.l3, b * 0.8),
        ),
        // D-pad (lower left)
        Positioned(
          left: 40 + stick * 0.45,
          bottom: 8,
          child: SizedBox(
            width: b * 3,
            height: b * 3,
            child: Stack(children: [
              Positioned(left: b, top: 0, child: _btn('▲', Btn.dUp, b)),
              Positioned(left: b, bottom: 0, child: _btn('▼', Btn.dDown, b)),
              Positioned(left: 0, top: b, child: _btn('◀', Btn.dLeft, b)),
              Positioned(right: 0, top: b, child: _btn('▶', Btn.dRight, b)),
            ]),
          ),
        ),
        // ABXY (upper right)
        Positioned(
          right: 40,
          top: h * 0.2,
          child: SizedBox(
            width: b * 3,
            height: b * 3,
            child: Stack(children: [
              Positioned(
                  left: b,
                  top: 0,
                  child: _btn('Y', Btn.y, b, color: Colors.amber)),
              Positioned(
                  left: b,
                  bottom: 0,
                  child: _btn('A', Btn.a, b, color: Colors.green)),
              Positioned(
                  left: 0,
                  top: b,
                  child: _btn('X', Btn.x, b, color: Colors.blue)),
              Positioned(
                  right: 0,
                  top: b,
                  child: _btn('B', Btn.b, b, color: Colors.red)),
            ]),
          ),
        ),
        // Right stick (lower right)
        Positioned(
          right: 40 + stick * 0.35,
          bottom: 8,
          child: Stick(
            size: stick,
            onChanged: (x, y) {
              state.rx = axisToInt16(x);
              state.ry = axisToInt16(y);
            },
          ),
        ),
        // R3: stick click, beside the right stick
        Positioned(
          right: 40 + stick * 0.35 + stick + 12,
          bottom: 8 + stick / 2 - b * 0.4,
          child: _btn('R3', Btn.r3, b * 0.8),
        ),
      ]);
    });
  }
}
