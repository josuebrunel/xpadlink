import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

/// Console blade: a dark dashboard built around the logo's violet, cyan and lime.
class C {
  static const bg = Color(0xFF0A0C10);
  static const panel = Color(0xFF12151B);
  static const panel2 = Color(0xFF181C24);
  static const line = Color(0xFF232833);
  static const ink = Color(0xFFE8ECF3);
  static const mute = Color(0xFF8A93A6);
  static const violet = Color(0xFF5B2BD9);
  static const violetSoft = Color(0xFFB4A2FF);
  static const cyan = Color(0xFF22D3EE);
  static const lime = Color(0xFFA3E635);
  // ABXY, the colours on the logo's pad.
  static const a = Color(0xFF34D399);
  static const b = Color(0xFFF87171);
  static const x = Color(0xFF60A5FA);
  static const y = Color(0xFFFBBF24);
}

/// Font families declared in pubspec.yaml (bundled: no network needed).
class F {
  static const display = 'ChakraPetch';
  static const body = 'Barlow';
  static const mono = 'JetBrainsMono';
}

TextStyle display(double size, {Color color = C.ink, double spacing = 1.2, FontWeight w = FontWeight.w700}) =>
    TextStyle(fontFamily: F.display, fontSize: size, fontWeight: w, letterSpacing: spacing, color: color);

TextStyle mono(double size, {Color color = C.mute, FontWeight w = FontWeight.w400, double spacing = 0}) =>
    TextStyle(fontFamily: F.mono, fontSize: size, fontWeight: w, letterSpacing: spacing, color: color);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.violet,
    brightness: Brightness.dark,
    surface: C.bg,
  ).copyWith(primary: C.lime, onPrimary: C.bg, secondary: C.cyan);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    fontFamily: F.body,
    textTheme: ThemeData.dark().textTheme.apply(fontFamily: F.body, bodyColor: C.ink, displayColor: C.ink),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.panel2,
      contentTextStyle: const TextStyle(fontFamily: F.body, color: C.ink),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: C.line),
      ),
    ),
  );
}

/// Near-black ground with the violet glow and a faint dot grid.
class ConsoleBackdrop extends StatelessWidget {
  const ConsoleBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-1.0, -1.2),
              radius: 1.2,
              colors: [Color(0x665B2BD9), Color(0x00000000)],
            ),
          ),
        ),
      ),
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(1.1, 1.3),
              radius: 0.9,
              colors: [Color(0x2222D3EE), Color(0x00000000)],
            ),
          ),
        ),
      ),
      const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _DotGrid()))),
      Positioned.fill(child: child),
    ]);
  }
}

class _DotGrid extends CustomPainter {
  const _DotGrid();

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 18.0;
    final pts = <double>[];
    for (var y = gap / 2; y < size.height; y += gap) {
      for (var x = gap / 2; x < size.width; x += gap) {
        pts..add(x)..add(y);
      }
    }
    canvas.drawRawPoints(
      PointMode.points,
      Float32List.fromList(pts),
      Paint()
        ..color = const Color(0x14FFFFFF)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DotGrid old) => false;
}

/// Small bordered label, like `WI-FI` or `BT`.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = C.cyan});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: C.line),
        ),
        child: Text(text, style: mono(10, color: color, w: FontWeight.w500, spacing: 1)),
      );
}

/// `// SECTION` label in small tracked mono type.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = C.mute});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: mono(10, color: color, w: FontWeight.w500, spacing: 1.4));
}

/// The console's ring of light: four arcs, the one for this player lit.
class RingOfLight extends StatelessWidget {
  const RingOfLight({super.key, required this.slot, required this.live, this.size = 38});

  /// 0 based player slot, or -1 before the server assigned one.
  final int slot;
  final bool live;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _RingPainter(slot, live)));
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.slot, this.live);

  final int slot;
  final bool live;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - size.width * 0.08;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    final lit = live ? C.lime : C.y;
    for (var i = 0; i < 4; i++) {
      final on = i == (slot < 0 ? 0 : slot % 4);
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * math.pi / 2 + 0.18,
        math.pi / 2 - 0.36,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.1
          ..strokeCap = StrokeCap.round
          ..color = on ? lit : const Color(0x22FFFFFF),
      );
    }
    canvas.drawCircle(size.center(Offset.zero), size.width * 0.12, Paint()..color = lit);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.slot != slot || old.live != live;
}

/// Link type and round-trip time, for example `BT · 12 ms`.
class LinkChip extends StatelessWidget {
  const LinkChip({super.key, required this.bluetooth, this.rttMs});

  final bool bluetooth;
  final int? rttMs;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: C.panel.withAlpha(204),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: C.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(bluetooth ? Icons.bluetooth : Icons.wifi, size: 14, color: C.cyan),
          const SizedBox(width: 6),
          Text('${bluetooth ? 'BT' : 'WI-FI'}${rttMs == null ? '' : ' · $rttMs ms'}',
              style: mono(11, color: C.cyan, w: FontWeight.w500, spacing: .6)),
        ]),
      );
}

/// Square icon button for the in-game bar.
class BarButton extends StatelessWidget {
  const BarButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.on = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool on;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: C.panel.withAlpha(204),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: on ? C.lime.withAlpha(102) : C.line),
          ),
          child: InkWell(
            onTap: onPressed,
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(icon, size: 21, color: on ? C.lime : C.ink),
            ),
          ),
        ),
      );
}
