import 'package:flutter/material.dart';

import 'input_config.dart';
import 'theme.dart';

/// Modal bottom sheet for configuring physical Volume Triggers and Touch-Look
/// empty-screen camera controls.
Future<void> showInputSettingsSheet({
  required BuildContext context,
  InputSettingsConfig? initialConfig,
  int initialTab = 0,
  ValueChanged<InputSettingsConfig>? onChanged,
}) async {
  final store = InputSettingsStore();
  var cfg = initialConfig?.clone() ?? await store.load();
  var tab = initialTab.clamp(0, 1);

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      side: BorderSide(color: C.line),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final maxHeight = MediaQuery.of(context).size.height * 0.90;

        void commit(VoidCallback mutate) {
          setSheetState(mutate);
          store.save(cfg);
          onChanged?.call(cfg.clone());
        }

        Widget card(List<Widget> children, {Color? border}) => Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: C.panel2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border ?? C.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            );

        Widget segBtn(
          String label,
          bool selected,
          VoidCallback onTap, {
          Color accent = C.cyan,
        }) =>
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? accent.withAlpha(36) : C.panel2,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: selected ? accent : C.line),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(
                      11,
                      color: selected ? accent : C.mute,
                      w: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );

        Widget presetChip(String label, VoidCallback onTap) => ActionChip(
              label: Text(label, style: mono(10.5, color: C.ink)),
              backgroundColor: C.bg,
              side: const BorderSide(color: C.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onPressed: onTap,
            );

        Widget bindingCard(
          String title,
          VolumeButtonBinding binding,
        ) =>
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: C.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: display(12.5, color: C.cyan, spacing: 1)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: C.panel2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: C.line),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<TriggerTarget>(
                        value: binding.target,
                        isExpanded: true,
                        dropdownColor: C.panel2,
                        iconEnabledColor: C.mute,
                        style: mono(12, color: C.ink),
                        items: [
                          for (final t in TriggerTarget.values)
                            DropdownMenuItem<TriggerTarget>(
                              value: t,
                              child: Text(
                                t.label,
                                overflow: TextOverflow.ellipsis,
                                style: mono(12, color: C.ink),
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          commit(() => binding.target = v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      segBtn(
                        'HOLD',
                        binding.mode == TriggerPressMode.hold,
                        () => commit(() => binding.mode = TriggerPressMode.hold),
                      ),
                      const SizedBox(width: 6),
                      segBtn(
                        'TOGGLE',
                        binding.mode == TriggerPressMode.toggle,
                        () => commit(() => binding.mode = TriggerPressMode.toggle),
                      ),
                    ],
                  ),
                ],
              ),
            );

        Widget volumeTab() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                card([
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Intercept Physical Volume Keys',
                                style: display(13.5)),
                            const SizedBox(height: 2),
                            Text(
                              'Active only during gameplay. Outside play, volume keys adjust Android audio normally.',
                              style: mono(10.5, color: C.mute),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: cfg.volumeTriggers.enabled,
                        activeThumbColor: C.lime,
                        onChanged: (v) =>
                            commit(() => cfg.volumeTriggers.enabled = v),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 10),
                const Eyebrow('// Quick presets'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    presetChip(
                      'Shooter (VOL+ RT / VOL- LT)',
                      () => commit(() {
                        cfg.volumeTriggers.enabled = true;
                        cfg.volumeTriggers.volumeUp = VolumeButtonBinding(
                          target: TriggerTarget.rt,
                          mode: TriggerPressMode.hold,
                        );
                        cfg.volumeTriggers.volumeDown = VolumeButtonBinding(
                          target: TriggerTarget.lt,
                          mode: TriggerPressMode.hold,
                        );
                      }),
                    ),
                    presetChip(
                      'Shoulder (VOL+ RB / VOL- LB)',
                      () => commit(() {
                        cfg.volumeTriggers.enabled = true;
                        cfg.volumeTriggers.volumeUp = VolumeButtonBinding(
                          target: TriggerTarget.rb,
                          mode: TriggerPressMode.hold,
                        );
                        cfg.volumeTriggers.volumeDown = VolumeButtonBinding(
                          target: TriggerTarget.lb,
                          mode: TriggerPressMode.hold,
                        );
                      }),
                    ),
                    presetChip(
                      'Face (VOL+ A / VOL- B)',
                      () => commit(() {
                        cfg.volumeTriggers.enabled = true;
                        cfg.volumeTriggers.volumeUp = VolumeButtonBinding(
                          target: TriggerTarget.a,
                          mode: TriggerPressMode.hold,
                        );
                        cfg.volumeTriggers.volumeDown = VolumeButtonBinding(
                          target: TriggerTarget.b,
                          mode: TriggerPressMode.hold,
                        );
                      }),
                    ),
                    presetChip(
                      'System Volume (Off)',
                      () => commit(() {
                        cfg.volumeTriggers.enabled = false;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, c) {
                    if (c.maxWidth >= 520) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: bindingCard(
                              'VOLUME UP (+)',
                              cfg.volumeTriggers.volumeUp,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: bindingCard(
                              'VOLUME DOWN (-)',
                              cfg.volumeTriggers.volumeDown,
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        bindingCard(
                          'VOLUME UP (+)',
                          cfg.volumeTriggers.volumeUp,
                        ),
                        const SizedBox(height: 8),
                        bindingCard(
                          'VOLUME DOWN (-)',
                          cfg.volumeTriggers.volumeDown,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                card([
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Auto-Swap on Flip Screen (180 deg)',
                                style: display(13)),
                            Text(
                              'Swap Vol+ and Vol- actions automatically when screen is flipped.',
                              style: mono(10.5, color: C.mute),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: cfg.volumeTriggers.swapOnFlip,
                        activeThumbColor: C.lime,
                        onChanged: (v) =>
                            commit(() => cfg.volumeTriggers.swapOnFlip = v),
                      ),
                    ],
                  ),
                  const Divider(color: C.line, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Haptic Feedback on Trigger',
                                style: display(13)),
                            Text(
                              'Light vibration buzz when a volume key activates.',
                              style: mono(10.5, color: C.mute),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: cfg.volumeTriggers.hapticsEnabled,
                        activeThumbColor: C.lime,
                        onChanged: (v) =>
                            commit(() => cfg.volumeTriggers.hapticsEnabled = v),
                      ),
                    ],
                  ),
                ]),
              ],
            );

        Widget modeCard({
          required String title,
          required String desc,
          required bool selected,
          required VoidCallback onTap,
        }) =>
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: selected ? C.lime.withAlpha(20) : C.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected ? C.lime : C.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: display(
                        12.5,
                        color: selected ? C.lime : C.ink,
                        spacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(desc, style: mono(10, color: C.mute)),
                  ],
                ),
              ),
            );

        Widget touchLookTab() {
          final tl = cfg.touchLook;
          final isRelative = tl.mode == TouchLookMode.relativeSwipe;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              card([
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Enable Touch-Look Camera',
                              style: display(13.5)),
                          const SizedBox(height: 2),
                          Text(
                            'Drag empty screen space to steer Right Stick (RX/RY).',
                            style: mono(10.5, color: C.mute),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: tl.enabled,
                      activeThumbColor: C.lime,
                      onChanged: (v) => commit(() => tl.enabled = v),
                    ),
                  ],
                ),
              ]),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, c) {
                  final relCard = modeCard(
                    title: 'SWIPE RELATIF (TRACKPAD)',
                    desc:
                        'Moves camera as your finger slides and stops when your finger stops.',
                    selected: isRelative,
                    onTap: () =>
                        commit(() => tl.mode = TouchLookMode.relativeSwipe),
                  );
                  final floatCard = modeCard(
                    title: 'FLOATING STICK',
                    desc:
                        'Touch origin becomes stick center; hold toward edge for continuous turn.',
                    selected: !isRelative,
                    onTap: () =>
                        commit(() => tl.mode = TouchLookMode.floatingStick),
                  );
                  if (c.maxWidth >= 520) {
                    return Row(
                      children: [
                        Expanded(child: relCard),
                        const SizedBox(width: 10),
                        Expanded(child: floatCard),
                      ],
                    );
                  }
                  return Column(
                    children: [relCard, const SizedBox(height: 8), floatCard],
                  );
                },
              ),
              const SizedBox(height: 10),
              card([
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Active Touch Area', style: display(13)),
                    SizedBox(
                      width: 210,
                      child: Row(
                        children: [
                          segBtn(
                            'RIGHT HALF',
                            tl.zone == TouchLookZone.rightHalf,
                            () =>
                                commit(() => tl.zone = TouchLookZone.rightHalf),
                          ),
                          const SizedBox(width: 6),
                          segBtn(
                            'FULL SCREEN',
                            tl.zone == TouchLookZone.fullScreen,
                            () => commit(
                                () => tl.zone = TouchLookZone.fullScreen),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(color: C.line, height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Camera Sensitivity', style: mono(12)),
                    Text('${tl.sensitivity.toStringAsFixed(1)}x',
                        style: mono(12, color: C.lime)),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: C.lime,
                    thumbColor: C.lime,
                  ),
                  child: Slider(
                    value: tl.sensitivity,
                    min: 0.3,
                    max: 3.0,
                    divisions: 27,
                    onChanged: (v) =>
                        commit(() => tl.sensitivity = (v * 10).round() / 10),
                  ),
                ),
                Opacity(
                  opacity: isRelative ? 1.0 : 0.45,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Game Deadzone Boost (Swipe mode)',
                              style: mono(12)),
                          Text('${(tl.deadzoneBoost * 100).round()}%',
                              style: mono(12, color: C.cyan)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: C.cyan,
                          thumbColor: C.cyan,
                        ),
                        child: Slider(
                          value: tl.deadzoneBoost,
                          min: 0.0,
                          max: 0.35,
                          divisions: 35,
                          onChanged: isRelative
                              ? (v) => commit(
                                    () => tl.deadzoneBoost =
                                        (v * 100).round() / 100,
                                  )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              card([
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Invert Horizontal (X)', style: mono(12)),
                    Switch(
                      value: tl.invertX,
                      activeThumbColor: C.lime,
                      onChanged: (v) => commit(() => tl.invertX = v),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Invert Vertical (Y)', style: mono(12)),
                    Switch(
                      value: tl.invertY,
                      activeThumbColor: C.lime,
                      onChanged: (v) => commit(() => tl.invertY = v),
                    ),
                  ],
                ),
                const Divider(color: C.line, height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Auto-Hide On-Screen Right Stick',
                              style: display(13)),
                          Text(
                            'Hide right joystick while Touch-Look is active to free space.',
                            style: mono(10.5, color: C.mute),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: tl.hideRightStick,
                      activeThumbColor: C.lime,
                      onChanged: (v) => commit(() => tl.hideRightStick = v),
                    ),
                  ],
                ),
                const Divider(color: C.line, height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Show Touch Reticle & Zone Guide',
                              style: display(13)),
                          Text(
                            'Display subtle cyan indicator while dragging camera.',
                            style: mono(10.5, color: C.mute),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: tl.showVisualFeedback,
                      activeThumbColor: C.lime,
                      onChanged: (v) => commit(() => tl.showVisualFeedback = v),
                    ),
                  ],
                ),
              ]),
            ],
          );
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune, size: 20, color: C.lime),
                      const SizedBox(width: 8),
                      Text(
                        'CUSTOM TRIGGERS & TOUCH-LOOK',
                        style: display(15, spacing: 1.4),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: C.mute),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < 2; i++) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setSheetState(() => tab = i),
                            child: Container(
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: tab == i ? C.lime : C.panel2,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: tab == i ? C.lime : C.line,
                                ),
                              ),
                              child: Text(
                                i == 0
                                    ? 'VOLUME TRIGGERS'
                                    : 'TOUCH-LOOK CAMERA',
                                style: mono(
                                  11.5,
                                  color: tab == i ? C.bg : C.mute,
                                  w: FontWeight.w600,
                                  spacing: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (i == 0) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: tab == 0 ? volumeTab() : touchLookTab(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () async {
                          final fresh = await store.reset();
                          if (!ctx.mounted) return;
                          setSheetState(() => cfg = fresh);
                          onChanged?.call(cfg.clone());
                        },
                        child: const Text('RESET DEFAULTS'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: C.lime,
                          foregroundColor: C.bg,
                        ),
                        onPressed: () async {
                          await store.save(cfg);
                          onChanged?.call(cfg.clone());
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        child: const Text('DONE'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
