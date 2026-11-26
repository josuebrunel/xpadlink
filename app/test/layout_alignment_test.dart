import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xpadlink/layout.dart';
import 'package:xpadlink/layout_editor.dart';
import 'package:xpadlink/onscreen.dart';
import 'package:xpadlink/protocol.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'LayoutEditorScreen canvas matches full-screen gameplay canvas 1:1 in edit and test modes',
      (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Reference gameplay canvas: SafeArea(top: false, bottom: false) + Positioned.fill(top: 0, bottom: 0)
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SafeArea(
          top: false,
          bottom: false,
          child: Stack(children: [
            Positioned.fill(
              child: OnScreenPad(
                state: PadState(),
                layout: PadLayoutConfig.defaultXbox(),
              ),
            ),
          ]),
        ),
      ),
    ));
    final playPadRect = tester.getRect(find.byType(OnScreenPad));
    final playLtRect = tester.getRect(find.text('LT'));
    final playARect = tester.getRect(find.text('A'));

    // Standalone editor in edit mode
    await tester.pumpWidget(const MaterialApp(home: LayoutEditorScreen()));
    await tester.pumpAndSettle();
    final editPadRect = tester.getRect(find.byType(OnScreenPad));
    final editLtRect = tester.getRect(find.text('LT'));
    final editARect = tester.getRect(find.text('A'));

    expect(editPadRect, playPadRect);
    expect(editLtRect.center.dx, closeTo(playLtRect.center.dx, 0.5));
    expect(editLtRect.center.dy, closeTo(playLtRect.center.dy, 0.5));
    expect(editARect.center.dx, closeTo(playARect.center.dx, 0.5));
    expect(editARect.center.dy, closeTo(playARect.center.dy, 0.5));

    // Toggle to TESTING mode: canvas must remain identical
    await tester.tap(find.byTooltip('Test touch buttons'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(OnScreenPad)), playPadRect);
  });

  testWidgets(
      'Editor HUD collapses to center pill to expose edge controls and restores cleanly',
      (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: LayoutEditorScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(LayoutBottomToolbar), findsOneWidget);

    await tester.tap(find.byTooltip('Hide editor bars'));
    await tester.pumpAndSettle();
    expect(find.byType(LayoutBottomToolbar), findsNothing);
    expect(find.byType(EditorCollapsedPill), findsOneWidget);

    await tester.tap(find.byType(EditorCollapsedPill));
    await tester.pumpAndSettle();
    expect(find.byType(LayoutBottomToolbar), findsOneWidget);
  });
}
