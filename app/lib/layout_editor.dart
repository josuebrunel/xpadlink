import 'package:flutter/material.dart';

import 'layout.dart';
import 'onscreen.dart';
import 'protocol.dart';
import 'theme.dart';

/// Standalone layout customization and editor screen.
/// Can be accessed offline from the Connect screen or while in a session.
class LayoutEditorScreen extends StatefulWidget {
  const LayoutEditorScreen({super.key});

  @override
  State<LayoutEditorScreen> createState() => _LayoutEditorScreenState();
}

class _LayoutEditorScreenState extends State<LayoutEditorScreen> {
  final _store = LayoutStore();
  final _dummyState = PadState();

  PadLayoutConfig _config = PadLayoutConfig.defaultXbox();
  String _selectedId = ControlId.leftStick;
  bool _groupMode = false;
  bool _dirty = false;
  bool _testingControls = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _store.load();
    if (mounted) {
      setState(() {
        _config = c;
        _dirty = false;
      });
    }
  }

  Future<void> _save() async {
    await _store.save(_config);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Touch layout saved!')),
    );
  }

  void _onElementMoved(String id, double relX, double relY) {
    setState(() {
      _config.moveControl(id, relX, relY, groupMode: _groupMode);
      _selectedId = id;
      _dirty = true;
    });
  }

  void _changeScale(double delta) {
    setState(() {
      _config.scaleControl(_selectedId, delta, groupMode: _groupMode);
      _dirty = true;
    });
  }

  void _toggleVisibility() {
    setState(() {
      _config.toggleVisibility(_selectedId, groupMode: _groupMode);
      _dirty = true;
    });
  }

  void _resetSelected() {
    setState(() {
      _config.resetControl(_selectedId, groupMode: _groupMode);
      _dirty = true;
    });
  }

  void _resetAll() {
    setState(() {
      _config = PadLayoutConfig.defaultXbox();
      _dirty = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset all controls to Xbox default')),
    );
  }

  void _cycleElement(int direction) {
    final ids = ControlId.all;
    final idx = ids.indexOf(_selectedId);
    final nextIdx = (idx + direction + ids.length) % ids.length;
    setState(() => _selectedId = ids[nextIdx]);
  }

  void _showPresets() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: C.line),
      ),
      builder: (ctx) => LayoutPresetsSheet(
        onSelect: (preset) {
          Navigator.pop(ctx);
          setState(() {
            _config = preset;
            _dirty = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Preset applied')),
          );
        },
      ),
    );
  }

  void _showSettings() {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => LayoutSettingsDialog(
          opacity: _config.opacity,
          hapticsEnabled: _config.hapticsEnabled,
          snapToGrid: _config.snapToGrid,
          onOpacityChanged: (v) {
            setDialogState(() => _config.opacity = v);
            setState(() {
              _config.opacity = v;
              _dirty = true;
            });
          },
          onHapticsChanged: (v) {
            setDialogState(() => _config.hapticsEnabled = v);
            setState(() {
              _config.hapticsEnabled = v;
              _dirty = true;
            });
          },
          onSnapChanged: (v) {
            setDialogState(() => _config.snapToGrid = v);
            setState(() {
              _config.snapToGrid = v;
              _dirty = true;
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedElem = _config.getElement(_selectedId);

    return Scaffold(
      backgroundColor: C.bg,
      body: ConsoleBackdrop(
        child: SafeArea(
          child: Stack(
            children: [
              // Controller Canvas
              Positioned.fill(
                top: 56,
                bottom: _testingControls ? 0 : 54,
                child: OnScreenPad(
                  state: _dummyState,
                  layout: _config,
                  editMode: !_testingControls,
                  groupMode: _groupMode,
                  selectedId: _selectedId,
                  onSelect: (id) => setState(() => _selectedId = id),
                  onElementMoved: _onElementMoved,
                ),
              ),

              // Top Bar
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: _buildTopBar(),
              ),

              // Bottom Control Toolbar (when in edit mode)
              if (!_testingControls)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 8,
                  child: LayoutBottomToolbar(
                    selectedElem: selectedElem,
                    groupMode: _groupMode,
                    canGroup: ControlId.groupOf(_selectedId) != null,
                    onToggleGroupMode: () =>
                        setState(() => _groupMode = !_groupMode),
                    onPrev: () => _cycleElement(-1),
                    onNext: () => _cycleElement(1),
                    onScaleDown: () => _changeScale(-0.05),
                    onScaleUp: () => _changeScale(0.05),
                    onToggleVisibility: _toggleVisibility,
                    onReset: _resetSelected,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        Material(
          color: C.panel.withAlpha(204),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: C.line),
          ),
          child: InkWell(
            onTap: () async {
              if (_dirty) {
                await _save();
              }
              if (mounted) Navigator.of(context).maybePop();
            },
            customBorder:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 14, 0),
              child: SizedBox(
                height: 42,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.chevron_left, size: 24, color: C.ink),
                    Text('DONE', style: display(12, spacing: 1.8)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: C.panel.withAlpha(204),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _testingControls ? C.cyan : C.lime,
                  boxShadow: [
                    BoxShadow(
                      color: _testingControls ? C.cyan : C.lime,
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _testingControls ? 'TESTING' : 'CUSTOMIZING',
                style: display(13, spacing: 1.4),
              ),
            ],
          ),
        ),
        const Spacer(),
        BarButton(
          icon: _testingControls ? Icons.edit_outlined : Icons.play_arrow_outlined,
          tooltip: _testingControls ? 'Return to editor' : 'Test touch buttons',
          on: _testingControls,
          onPressed: () =>
              setState(() => _testingControls = !_testingControls),
        ),
        const SizedBox(width: 8),
        BarButton(
          icon: Icons.layers_outlined,
          tooltip: 'Layout presets',
          onPressed: _showPresets,
        ),
        const SizedBox(width: 8),
        BarButton(
          icon: Icons.settings_outlined,
          tooltip: 'Layout settings',
          onPressed: _showSettings,
        ),
        const SizedBox(width: 8),
        BarButton(
          icon: Icons.restart_alt_outlined,
          tooltip: 'Reset all controls',
          onPressed: _resetAll,
        ),
        const SizedBox(width: 8),
        BarButton(
          icon: Icons.save_outlined,
          tooltip: 'Save layout',
          on: _dirty,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// Docked bottom toolbar for manipulating the currently selected control element.
class LayoutBottomToolbar extends StatelessWidget {
  const LayoutBottomToolbar({
    super.key,
    required this.selectedElem,
    this.groupMode = false,
    this.canGroup = false,
    this.onToggleGroupMode,
    required this.onPrev,
    required this.onNext,
    required this.onScaleDown,
    required this.onScaleUp,
    required this.onToggleVisibility,
    required this.onReset,
  });

  final ControlElementLayout selectedElem;
  final bool groupMode;
  final bool canGroup;
  final VoidCallback? onToggleGroupMode;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onScaleDown;
  final VoidCallback onScaleUp;
  final VoidCallback onToggleVisibility;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: C.panel.withAlpha(235),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.line),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: c.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Element switcher
                      IconButton(
                        icon: const Icon(Icons.chevron_left, size: 20, color: C.ink),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Previous control',
                        onPressed: onPrev,
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 104),
                        child: Center(
                          child: Text(
                            ControlId.displayName(selectedElem.id),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: display(13, color: C.lime, spacing: 0.8),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, size: 20, color: C.ink),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Next control',
                        onPressed: onNext,
                      ),

                      if (canGroup && onToggleGroupMode != null) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: groupMode
                              ? 'Group mode: moves/scales entire cluster (tap for single button)'
                              : 'Solo mode: moves/scales single button (tap for whole group)',
                          child: Material(
                            color: groupMode ? C.lime.withAlpha(32) : C.panel2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                              side: BorderSide(
                                color: groupMode ? C.lime : C.line,
                              ),
                            ),
                            child: InkWell(
                              onTap: onToggleGroupMode,
                              borderRadius: BorderRadius.circular(7),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: Text(
                                  groupMode ? 'GROUP' : 'SOLO',
                                  style: mono(
                                    10.5,
                                    color: groupMode ? C.lime : C.cyan,
                                    w: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],

                      Container(
                        width: 1,
                        height: 22,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: C.line,
                      ),

                      // Scale controls (5% steps)
                      Text('SCALE', style: mono(10, color: C.mute, spacing: 1)),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.remove, size: 16, color: C.ink),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Shrink (-5%)',
                        onPressed: onScaleDown,
                      ),
                      Text(
                        '${(selectedElem.scale * 100).round()}%',
                        style: mono(11.5, color: C.ink, w: FontWeight.w600),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 16, color: C.ink),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Enlarge (+5%)',
                        onPressed: onScaleUp,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Visibility toggle
                      IconButton(
                        icon: Icon(
                          selectedElem.visible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: selectedElem.visible ? C.ink : C.b,
                        ),
                        visualDensity: VisualDensity.compact,
                        tooltip:
                            selectedElem.visible ? 'Hide control' : 'Show control',
                        onPressed: onToggleVisibility,
                      ),
                      const SizedBox(width: 4),

                      // Reset element
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20, color: C.mute),
                        visualDensity: VisualDensity.compact,
                        tooltip: groupMode && canGroup
                            ? 'Reset group position & scale'
                            : 'Reset position & scale',
                        onPressed: onReset,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal bottom sheet listing all layout presets.
class LayoutPresetsSheet extends StatelessWidget {
  const LayoutPresetsSheet({super.key, required this.onSelect});

  final ValueChanged<PadLayoutConfig> onSelect;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.layers_outlined, size: 20, color: C.lime),
                  const SizedBox(width: 8),
                  Text('LAYOUT PRESETS', style: display(16, spacing: 1.4)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: C.mute),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTile(
                        title: 'Default (Xbox 360 Style)',
                        subtitle: 'Asymmetric sticks: left stick high, right stick low',
                        icon: Icons.gamepad_outlined,
                        onTap: () => onSelect(PadLayoutConfig.defaultXbox()),
                      ),
                      _buildTile(
                        title: 'PlayStation Symmetrical',
                        subtitle: 'Dual sticks at the bottom, D-pad and ABXY on top',
                        icon: Icons.sports_esports_outlined,
                        onTap: () => onSelect(PadLayoutConfig.playStation()),
                      ),
                      _buildTile(
                        title: 'Southpaw (Left-Handed)',
                        subtitle: 'Inverted: sticks and action clusters swapped',
                        icon: Icons.swap_horiz,
                        onTap: () => onSelect(PadLayoutConfig.southpaw()),
                      ),
                      _buildTile(
                        title: '4-Finger Claw',
                        subtitle: 'Stacked top shoulder triggers for claw index-finger grip',
                        icon: Icons.touch_app_outlined,
                        onTap: () => onSelect(PadLayoutConfig.claw()),
                      ),
                      _buildTile(
                        title: 'Retro / 2D Arcade',
                        subtitle: 'Enlarged D-pad and buttons; analog sticks hidden',
                        icon: Icons.grid_view_outlined,
                        onTap: () => onSelect(PadLayoutConfig.retro2D()),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: C.panel2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: C.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 24, color: C.cyan),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: display(14, spacing: 0.5)),
                      Text(subtitle, style: mono(11, color: C.mute)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20, color: C.mute),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog for global touch controls settings (opacity, haptics, grid snapping).
class LayoutSettingsDialog extends StatelessWidget {
  const LayoutSettingsDialog({
    super.key,
    required this.opacity,
    required this.hapticsEnabled,
    required this.snapToGrid,
    required this.onOpacityChanged,
    required this.onHapticsChanged,
    required this.onSnapChanged,
  });

  final double opacity;
  final bool hapticsEnabled;
  final bool snapToGrid;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<bool> onHapticsChanged;
  final ValueChanged<bool> onSnapChanged;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: C.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: C.line),
      ),
      title: Row(
        children: [
          const Icon(Icons.settings_outlined, color: C.lime, size: 22),
          const SizedBox(width: 10),
          Text('TOUCH SETTINGS', style: display(16, spacing: 1.2)),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Opacity
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Button Opacity', style: display(13, spacing: 0.4)),
                Text('${(opacity * 100).round()}%',
                    style: mono(12, color: C.cyan)),
              ],
            ),
            Slider(
              value: opacity,
              min: 0.1,
              max: 1.0,
              divisions: 18,
              activeColor: C.lime,
              inactiveColor: C.line,
              onChanged: onOpacityChanged,
            ),
            const SizedBox(height: 12),

            // Haptics
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Vibration Feedback', style: display(13, spacing: 0.4)),
              subtitle: Text('Haptic buzz when buttons are pressed',
                  style: mono(11, color: C.mute)),
              value: hapticsEnabled,
              activeColor: C.lime,
              onChanged: onHapticsChanged,
            ),

            // Snap to Grid
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Snap to Grid', style: display(13, spacing: 0.4)),
              subtitle: Text('Snap positions to 2.5% alignment grid',
                  style: mono(11, color: C.mute)),
              value: snapToGrid,
              activeColor: C.lime,
              onChanged: onSnapChanged,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CLOSE', style: display(12, color: C.lime, spacing: 1)),
        ),
      ],
    );
  }
}
