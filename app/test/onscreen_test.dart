import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpadlink/input_config.dart';
import 'package:xpadlink/layout.dart';
import 'package:xpadlink/onscreen.dart';
import 'package:xpadlink/protocol.dart';

Widget _wrapPad(OnScreenPad pad) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 800, height: 400, child: pad),
      ),
    );

void main() {
  testWidgets(
      'Touch-Look with hideRightStick=true keeps other controls visible and interactive',
      (tester) async {
    final state = PadState();
    final mixer = InputMixer();
    await tester.pumpWidget(_wrapPad(OnScreenPad(
      state: state,
      layout: PadLayoutConfig.defaultXbox(),
      mixer: mixer,
      touchLook: TouchLookConfig(
        enabled: true,
        hideRightStick: true,
        zone: TouchLookZone.rightHalf,
      ),
    )));

    expect(find.byType(Stick), findsOneWidget); // only left stick
    expect(tester.getSize(find.text('A')).width, greaterThan(0));
    expect(tester.getSize(find.text('LT')).width, greaterThan(0));

    // Hold A button while Touch-Look is enabled
    final aCenter = tester.getCenter(find.text('A'));
    final aGesture = await tester.startGesture(aCenter);
    await tester.pump();
    expect(state.buttons & Btn.a, Btn.a);
    expect(state.rx, 0);
    expect(state.ry, 0);

    // Simultaneously drag empty space in right half for Touch-Look
    final lookGesture = await tester.startGesture(const Offset(440, 260));
    await lookGesture.moveBy(const Offset(40, -20));
    await tester.pump(const Duration(milliseconds: 20));
    expect(state.buttons & Btn.a, Btn.a);
    expect(state.rx != 0 || state.ry != 0, isTrue);

    await lookGesture.up();
    await aGesture.up();
    await tester.pump();
    expect(state.buttons & Btn.a, 0);
  });

  testWidgets(
      'Retro 2D preset with hidden sticks keeps visible controls at non-zero size',
      (tester) async {
    final state = PadState();
    await tester.pumpWidget(_wrapPad(OnScreenPad(
      state: state,
      layout: PadLayoutConfig.retro2D(),
    )));

    expect(find.byType(Stick), findsNothing);
    expect(find.text('L3'), findsNothing);
    expect(tester.getSize(find.text('A')).width, greaterThan(0));
    expect(tester.getSize(find.text('▲')).width, greaterThan(0));
    expect(tester.getSize(find.text('LT')).width, greaterThan(0));
  });
}
