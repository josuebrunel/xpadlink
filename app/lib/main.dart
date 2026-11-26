import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calibration.dart';
import 'client.dart';
import 'discovery.dart';
import 'input_config.dart';
import 'input_settings_sheet.dart';
import 'layout.dart';
import 'layout_editor.dart';
import 'link.dart';
import 'log.dart';
import 'native_streams.dart';
import 'onscreen.dart';
import 'protocol.dart';
import 'servers.dart';
import 'theme.dart';

const _landscape = [
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(_landscape);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final log = Log('app');
  // Route every uncaught error (framework, async, platform) to the log.
  FlutterError.onError =
      (d) => log.e('flutter error', d.exceptionAsString(), d.stack);
  PlatformDispatcher.instance.onError = (e, st) {
    log.e('uncaught error', e, st);
    return true;
  };
  runZonedGuarded(
    () => runApp(const XPadLinkApp()),
    (e, st) => log.e('zone error', e, st),
  );
}

class XPadLinkApp extends StatelessWidget {
  const XPadLinkApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'XPadLink',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const ConnectScreen(),
      );
}

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with SingleTickerProviderStateMixin {
  static final _log = Log('connect');

  final _store = ServerStore();
  final _label = TextEditingController();
  final _server = TextEditingController();
  final _token = TextEditingController();
  final _name = TextEditingController(text: 'phone');
  List<SavedServer> _saved = [];
  final List<FoundServer> _found = [];
  bool _scanning = false;
  List<({String name, String address})>? _paired; // null until the user asks
  String? _pairedError;

  // Tabs: saved servers, then the two ways to find a new one.
  late final _tabs = TabController(length: 3, vsync: this);
  static const _tabWifi = 1;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(_landscape);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load().then((_) {
      // Nothing saved yet: start where a new server is found.
      if (_saved.isEmpty && mounted) _tabs.index = _tabWifi;
      return _scan();
    });
  }

  void _openMotionSettings() {
    showMotionSettingsSheet(context: context);
  }

  void _openInputSettings() {
    showInputSettingsSheet(context: context);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _label.dispose();
    _server.dispose();
    _token.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _found.clear();
    });
    try {
      await Discovery.scan((s) {
        if (mounted) setState(() => _found.add(s));
      });
    } catch (e, st) {
      _log.e('discovery failed', e, st);
    }
    if (mounted) setState(() => _scanning = false);
  }

  /// Lists Bluetooth devices paired with the phone. Asks for the Bluetooth
  /// permission on Android 12 and later, so only when the user taps for it.
  Future<void> _loadPaired() async {
    try {
      final list = await BtLink.paired();
      if (mounted) {
        setState(() {
          _paired = list;
          _pairedError = null;
        });
      }
    } on PlatformException catch (e) {
      _log.e('list paired failed', e);
      if (mounted) setState(() => _pairedError = e.message ?? 'Bluetooth unavailable');
    }
  }

  /// Fills the form from a paired PC. The address is "bt:" plus the MAC.
  void _pickPaired(({String name, String address}) d) {
    final address = 'bt:${d.address}';
    final saved = _saved.where((e) => e.address == address);
    setState(() {
      _label.text = saved.isNotEmpty ? saved.first.label : d.name;
      _server.text = address;
      _token.text = saved.isNotEmpty ? saved.first.token : '';
    });
  }

  /// Fills the form from a discovered server, reusing a saved token if any.
  void _pick(FoundServer s) {
    final saved = _saved.where((e) => e.address == s.address);
    setState(() {
      _label.text = saved.isNotEmpty ? saved.first.label : s.hostname;
      _server.text = s.address;
      _token.text = saved.isNotEmpty ? saved.first.token : '';
    });
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final saved = await _store.load();
    _server.text = p.getString('server') ?? '';
    _token.text = p.getString('token') ?? '';
    _name.text = p.getString('name') ?? 'phone';
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _save() async {
    final address = _server.text.trim();
    if (address.isEmpty) return;
    final label = _label.text.trim().isEmpty ? address : _label.text.trim();
    final saved = await _store.save(
        SavedServer(label: label, address: address, token: _token.text.trim()));
    _log.i('saved server $label ($address)');
    if (!mounted) return;
    setState(() => _saved = saved);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Saved "$label"')));
  }

  Future<void> _delete(SavedServer s) async {
    final saved = await _store.remove(s.address);
    _log.i('deleted server ${s.label} (${s.address})');
    if (mounted) setState(() => _saved = saved);
  }

  void _edit(SavedServer s) {
    setState(() {
      _label.text = s.label == s.address ? '' : s.label;
      _server.text = s.address;
      _token.text = s.token;
    });
  }

  Future<void> _connect() => _open(_server.text.trim(), _token.text.trim());

  Future<void> _open(String address, String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('server', address);
    await p.setString('token', token);
    await p.setString('name', _name.text.trim());

    var host = address;
    var port = 9777;
    final i = host.lastIndexOf(':');
    if (i > 0 && !address.startsWith('bt:')) {
      port = int.tryParse(host.substring(i + 1)) ?? 9777;
      host = host.substring(0, i);
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ControllerScreen(
        host: host,
        port: port,
        token: token,
        name: _name.text.trim().isEmpty ? 'phone' : _name.text.trim(),
      ),
    ));
  }

  bool _showToken = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ConsoleBackdrop(
        child: SafeArea(
          top: false,
          bottom: false,
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 640;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _header(),
                const SizedBox(height: 12),
                Expanded(
                  child: wide
                      ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(flex: 11, child: _picker()),
                          const SizedBox(width: 16),
                          Expanded(flex: 9, child: _form(scroll: true)),
                        ])
                      : ListView(children: [
                          SizedBox(height: 300, child: _picker()),
                          const SizedBox(height: 16),
                          _form(scroll: false),
                        ]),
                ),
              ]),
            );
          }),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.asset(
          'assets/logo.png',
          width: 36,
          height: 36,
          cacheWidth: 108,
          cacheHeight: 108,
        ),
      ),
      const SizedBox(width: 12),
      Text.rich(TextSpan(children: [
        TextSpan(text: 'XPAD', style: display(20, spacing: 3.2)),
        TextSpan(text: 'LINK', style: display(20, color: C.lime, spacing: 3.2)),
      ])),
      const SizedBox(width: 8),
      Expanded(
        child: Align(
          alignment: Alignment.centerRight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              OutlinedButton.icon(
                onPressed: _openMotionSettings,
                icon: const Icon(Icons.screen_rotation_outlined, size: 15, color: C.cyan),
                label: Text('GYRO', style: display(11, color: C.cyan, spacing: 1.2)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: C.line),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: _openInputSettings,
                icon: const Icon(Icons.gamepad_outlined, size: 15, color: C.lime),
                label: Text('INPUT', style: display(11, color: C.lime, spacing: 1.2)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: C.line),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const LayoutEditorScreen(),
                )),
                icon: const Icon(Icons.dashboard_customize_outlined, size: 15, color: C.ink),
                label: Text('CONTROLS', style: display(11, color: C.ink, spacing: 1.2)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: C.line),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: C.bg.withAlpha(170),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: C.line),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _scanning ? C.cyan : C.lime,
                      boxShadow: [BoxShadow(color: _scanning ? C.cyan : C.lime, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Eyebrow(_scanning ? 'Scanning' : 'Ready'),
                ]),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  BoxDecoration get _panel => BoxDecoration(
        color: C.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.line),
      );

  /// Saved servers, nearby servers on Wi-Fi, paired PCs over Bluetooth.
  Widget _picker() {
    Tab tab(IconData icon, String text) => Tab(
          height: 42,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17),
            const SizedBox(width: 7),
            Text(text.toUpperCase()),
          ]),
        );
    return Container(
      decoration: _panel,
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        TabBar(
          controller: _tabs,
          labelColor: C.ink,
          unselectedLabelColor: C.mute,
          labelStyle: display(12.5, spacing: 1.4, w: FontWeight.w600),
          unselectedLabelStyle: display(12.5, spacing: 1.4, w: FontWeight.w600),
          indicator: const UnderlineTabIndicator(
              borderSide: BorderSide(color: C.lime, width: 2),
              insets: EdgeInsets.symmetric(horizontal: 14)),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: C.line,
          overlayColor: WidgetStatePropertyAll(Colors.white.withAlpha(10)),
          tabs: [
            tab(Icons.bookmark_outline, 'Saved${_saved.isEmpty ? '' : ' ${_saved.length}'}'),
            tab(Icons.wifi, 'Wi-Fi'),
            tab(Icons.bluetooth, 'Bluetooth'),
          ],
        ),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            _savedTab(),
            _wifiTab(),
            _bluetoothTab(),
          ]),
        ),
      ]),
    );
  }

  Widget _hint(String text, {Color color = C.mute, Widget? action}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: C.mute, height: 1.4).copyWith(color: color)),
            if (action != null) ...[const SizedBox(height: 14), action],
          ]),
        ),
      );

  Widget _tileList(List<Widget> tiles) => ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => tiles[i],
      );

  Widget _listHeader(String title, Widget trailing) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 0),
        child: SizedBox(
          height: 36,
          child: Row(children: [
            Expanded(child: Eyebrow(title)),
            trailing,
          ]),
        ),
      );

  Widget _savedTab() {
    if (_saved.isEmpty) {
      return _hint('No saved servers yet. Find one on Wi-Fi or Bluetooth, then press Save.');
    }
    return _tileList([
      for (final s in _saved)
        _ServerTile(
          bluetooth: s.address.startsWith('bt:'),
          title: s.label,
          subtitle: s.address.replaceFirst('bt:', ''),
          tag: s.address.startsWith('bt:') ? 'BT' : 'WI-FI',
          selected: _server.text == s.address,
          onTap: () => _edit(s),
          trailing: IconButton(
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline, size: 20, color: C.mute),
            onPressed: () => _delete(s),
          ),
        ),
    ]);
  }

  Widget _wifiTab() {
    return Column(children: [
      _listHeader(
        '// On this network',
        _scanning
            ? const Padding(
                padding: EdgeInsets.only(right: 14),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: C.cyan)),
              )
            : IconButton(
                tooltip: 'Scan again',
                icon: const Icon(Icons.refresh, size: 20, color: C.mute),
                onPressed: _scan),
      ),
      Expanded(
        child: _found.isEmpty
            ? _hint(_scanning
                ? 'Looking for servers on this network…'
                : 'None found. Guest networks block discovery: type the address on the right instead.')
            : _tileList([
                for (final s in _found)
                  _ServerTile(
                    bluetooth: false,
                    title: s.hostname,
                    subtitle: s.address,
                    tag: 'FOUND',
                    selected: _server.text == s.address,
                    onTap: () => _pick(s),
                  ),
              ]),
      ),
    ]);
  }

  Widget _bluetoothTab() {
    final paired = _paired;
    if (paired == null) {
      return _hint(
        _pairedError ?? 'Pair your PC in Android settings first, then list the paired devices here.',
        color: _pairedError == null ? C.mute : C.b,
        action: FilledButton.tonalIcon(
          onPressed: _loadPaired,
          icon: const Icon(Icons.bluetooth_searching, size: 18),
          label: const Text('Show paired devices'),
        ),
      );
    }
    return Column(children: [
      _listHeader(
        '// Paired with this phone',
        IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 20, color: C.mute),
            onPressed: _loadPaired),
      ),
      Expanded(
        child: paired.isEmpty
            ? _hint('No paired devices. Pair your PC in Android settings first.')
            : _tileList([
                for (final d in paired)
                  _ServerTile(
                    bluetooth: true,
                    title: d.name,
                    subtitle: d.address,
                    tag: 'PAIRED',
                    selected: _server.text == 'bt:${d.address}',
                    onTap: () => _pickPaired(d),
                  ),
              ]),
      ),
    ]);
  }

  Widget _field(String label, TextEditingController c,
      {String? hint, IconData? icon, TextInputType? type, bool secret = false, ValueChanged<String>? onChanged}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: C.line),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Eyebrow(label),
      const SizedBox(height: 4),
      TextField(
        controller: c,
        keyboardType: type,
        obscureText: secret && !_showToken,
        onChanged: onChanged,
        cursorColor: C.lime,
        style: mono(14, color: C.ink, w: FontWeight.w500),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: C.bg,
          hintText: hint,
          hintStyle: mono(13, color: C.mute.withAlpha(150)),
          prefixIcon: icon == null ? null : Icon(icon, size: 18, color: C.mute),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          suffixIcon: !secret
              ? null
              : IconButton(
                  tooltip: _showToken ? 'Hide token' : 'Show token',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility, size: 18, color: C.mute),
                  onPressed: () => setState(() => _showToken = !_showToken),
                ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: const BorderSide(color: C.lime, width: 1.5)),
        ),
      ),
    ]);
  }

  Widget _form({required bool scroll}) {
    final fields = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Eyebrow('// Selected'),
      const SizedBox(height: 4),
      AnimatedBuilder(
        animation: Listenable.merge([_label, _server]),
        builder: (context, _) {
          final addr = _server.text.trim();
          final title = _label.text.trim().isNotEmpty
              ? _label.text.trim()
              : (addr.isEmpty ? 'New server' : (addr.startsWith('bt:') ? 'Bluetooth server' : 'Wi-Fi server'));
          return Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(22, spacing: .4));
        },
      ),
      const SizedBox(height: 10),
      _field('Server', _server,
          hint: '192.168.1.20:9777  or  bt:AA:BB:CC:DD:EE:FF',
          icon: _server.text.startsWith('bt:') ? Icons.bluetooth : Icons.wifi,
          type: TextInputType.url,
          onChanged: (_) => setState(() {})),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _field('Token', _token, hint: 'from xpadlinkd', icon: Icons.key, secret: true)),
        const SizedBox(width: 10),
        Expanded(child: _field('Device name', _name, icon: Icons.smartphone)),
      ]),
      const SizedBox(height: 10),
      _field('Label (optional)', _label, hint: 'Living room PC'),
    ]);

    final actions = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: C.lime.withAlpha(60), blurRadius: 22)],
            ),
            child: FilledButton.icon(
              onPressed: _connect,
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              label: Text('CONNECT', style: display(14, color: C.bg, spacing: 2.4)),
              style: FilledButton.styleFrom(
                backgroundColor: C.lime,
                foregroundColor: C.bg,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.bookmark_add_outlined, size: 18),
          label: Text('SAVE', style: display(13, spacing: 1.6, w: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: C.ink,
            side: const BorderSide(color: C.line),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            _server.text.startsWith('bt:') ? 'BLUETOOTH · RFCOMM · SLOT AUTO' : 'WI-FI · UDP · SLOT AUTO',
            style: mono(10, spacing: .8),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              InkWell(
                onTap: _openInputSettings,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.gamepad_outlined, size: 13, color: C.lime),
                      const SizedBox(width: 4),
                      Text('TRIGGERS & LOOK', style: display(10, color: C.lime, spacing: 0.8)),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: _openMotionSettings,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tune, size: 13, color: C.cyan),
                      const SizedBox(width: 4),
                      Text('GYRO SETTINGS', style: display(10, color: C.cyan, spacing: 0.8)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ]);

    return Container(
      decoration: _panel,
      padding: const EdgeInsets.all(16),
      child: scroll
          ? Column(children: [
              Expanded(child: SingleChildScrollView(child: fields)),
              const SizedBox(height: 12),
              actions,
            ])
          : Column(children: [fields, const SizedBox(height: 16), actions]),
    );
  }
}

/// One server in the picker: link icon, name, mono address, tag.
class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.bluetooth,
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final bool bluetooth;
  final String title, subtitle, tag;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Material(
      color: C.panel2,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: selected ? C.lime : C.line, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: radius),
        child: Container(
          decoration: selected
              ? BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [BoxShadow(color: C.lime.withAlpha(36), blurRadius: 18)],
                )
              : null,
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: C.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: C.line),
              ),
              child: Icon(bluetooth ? Icons.bluetooth : Icons.wifi,
                  size: 20, color: bluetooth ? C.violetSoft : C.cyan),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(16, spacing: .2, w: FontWeight.w600)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(11.5)),
              ]),
            ),
            const SizedBox(width: 8),
            Tag(tag, color: bluetooth ? C.violetSoft : C.cyan),
            ?trailing,
          ]),
        ),
      ),
    );
  }
}

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({
    super.key,
    required this.host,
    required this.port,
    required this.token,
    required this.name,
  });

  final String host, token, name;
  final int port;

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen>
    with WidgetsBindingObserver {
  static const _motionConfig = MethodChannel('xpadlink/motion_config');
  static const _rumbleChannel = MethodChannel('xpadlink/rumble');
  static const _volumeChannel = EventChannel('xpadlink/volume_keys');
  static const _volumeConfig = MethodChannel('xpadlink/volume_config');
  static final _log = Log('screen');

  final _client = PadClient();
  StreamSubscription<dynamic>? _padSub;
  StreamSubscription<dynamic>? _motionSub;
  StreamSubscription<dynamic>? _volumeSub;
  bool _motionOn = true;
  bool _flipped = false; // landscape right instead of left
  String? _physical; // name of a physical pad once one has sent input
  final _calStore = CalibrationStore();
  PadCalibration _padCal = PadCalibration();
  MotionCalibration _motionCal = MotionCalibration();
  final _layoutStore = LayoutStore();
  PadLayoutConfig _layout = PadLayoutConfig.defaultXbox();
  final _inputStore = InputSettingsStore();
  InputSettingsConfig _inputConfig = InputSettingsConfig();
  final _mixer = InputMixer();
  int _modalDepth = 0;
  bool _editingLayout = false;
  bool _editorHudCollapsed = false;
  bool _groupMode = false;
  String _selectedControlId = ControlId.leftStick;
  bool _showOverlay = true;
  String? _error;
  Timer? _readout; // refreshes the stick values while the touch controls are hidden

  void _onClientChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(_landscape);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _client.addListener(_onClientChanged);
    _client.onRumble = _onRumble;
    _client
        .start(widget.host, widget.port, widget.token, widget.name)
        .catchError((Object e) {
      _log.e('client start failed', e);
      if (mounted) setState(() => _error = '$e');
    });
    _padSub = NativeStreams.gamepad.listen(_onPhysical,
        onError: (Object e) => _log.e('gamepad channel error', e));
    _volumeSub = _volumeChannel.receiveBroadcastStream().listen(_onVolumeKey,
        onError: (Object e) => _log.e('volume channel error', e));
    _calStore.loadMotion().then((c) {
      if (mounted) {
        setState(() => _motionCal = c);
        _motionConfig.invokeMethod<void>(
            'setFallbackEnabled', {'enabled': c.useAccelFallback});
      }
    });
    _layoutStore.load().then((l) {
      if (mounted) setState(() => _layout = l);
    });
    _inputStore.load().then((cfg) {
      if (!mounted) return;
      _applyInputConfig(cfg);
    });
    _setMotion(true);
    _readout = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (mounted && !_showOverlay) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _mixer.clearVolumeInput();
      _mixer.applyTo(_client.state);
      if (mounted) setState(() {});
    }
  }

  void _syncVolumeIntercept() {
    final active = _modalDepth == 0 && !_editingLayout;
    if (!active) {
      _mixer.clearVolumeInput();
      _mixer.applyTo(_client.state);
      if (mounted) setState(() {});
    }
    final vt = _inputConfig.volumeTriggers;
    _volumeConfig.invokeMethod<void>('setConfig', {
      'interceptUp': active && vt.shouldInterceptUp(flipped: _flipped),
      'interceptDown': active && vt.shouldInterceptDown(flipped: _flipped),
    }).catchError((Object e) => _log.e('volume config failed', e));
  }

  void _applyInputConfig(InputSettingsConfig next) {
    if (!mounted) return;
    setState(() {
      _inputConfig = next;
      _mixer.setVolumeConfig(next.volumeTriggers, flipped: _flipped);
      if (next.touchLook.enabled && next.touchLook.hideRightStick) {
        _mixer.setTouchRightStick(0, 0);
      }
      if (!next.touchLook.enabled) {
        _mixer.setTouchLook(0, 0, active: false);
      }
      _mixer.applyTo(_client.state);
    });
    _syncVolumeIntercept();
  }

  void _onVolumeKey(dynamic event) {
    final activated = _mixer.handleVolumeEvent(
      event,
      allowInput: _modalDepth == 0 && !_editingLayout,
    );
    _mixer.applyTo(_client.state);
    if (activated && _inputConfig.volumeTriggers.hapticsEnabled) {
      HapticFeedback.lightImpact();
    }
    if (mounted) setState(() {});
  }

  Future<T> _withModalPause<T>(Future<T> Function() fn) async {
    _modalDepth++;
    _syncVolumeIntercept();
    try {
      return await fn();
    } finally {
      if (_modalDepth > 0) _modalDepth--;
      if (mounted) _syncVolumeIntercept();
    }
  }

  /// Forces the other landscape, for when the system doesn't follow the sensor.
  void _flip() {
    setState(() {
      _flipped = !_flipped;
      _mixer.setVolumeConfig(_inputConfig.volumeTriggers, flipped: _flipped);
      _mixer.applyTo(_client.state);
    });
    _syncVolumeIntercept();
    SystemChrome.setPreferredOrientations([
      _flipped ? DeviceOrientation.landscapeRight : DeviceOrientation.landscapeLeft,
    ]);
    _log.i('screen flipped to ${_flipped ? 'landscape right' : 'landscape left'}');
  }

  /// Gyro and accelerometer for games that tilt the controller (Wii U GamePad).
  void _setMotion(bool on) {
    _motionOn = on;
    _motionSub?.cancel();
    _motionSub = null;
    if (!on) {
      _client.motion = null;
      return;
    }
    _motionSub = NativeStreams.motion.listen((dynamic e) {
      final v = (e as List).cast<double>();
      _client.setMotion(_motionCal.apply(PadMotion(v.sublist(0, 3), v.sublist(3, 6))));
    }, onError: (Object e) => _log.e('motion channel error', e));
  }

  Future<void> _loadPadCal(String name) async {
    final c = await _calStore.loadPad(name);
    if (mounted && _physical == name) _padCal = c;
  }

  Future<void> _openCalibration() => _withModalPause(() async {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CalibrationScreen(padName: _physical),
        ));
        // Pick up whatever was saved while the screen was open.
        _motionCal = await _calStore.loadMotion();
        final name = _physical;
        if (name != null) _padCal = await _calStore.loadPad(name);
      });

  void _onRumble(int strong, int weak, int ms) {
    _rumbleChannel.invokeMethod<void>(
        'vibrate', {'strong': strong, 'weak': weak, 'ms': ms}).catchError(
        (Object e) => _log.e('vibrate failed', e));
  }

  void _onPhysical(dynamic event) {
    final m = Map<String, dynamic>.from(event as Map);
    _mixer.setPhysicalPad(
      buttons: m['buttons'] as int,
      lx: _padCal.lx(m['lx'] as int),
      ly: _padCal.ly(m['ly'] as int),
      rx: _padCal.rx(m['rx'] as int),
      ry: _padCal.ry(m['ry'] as int),
      lt: _padCal.lt(m['lt'] as int),
      rt: _padCal.rt(m['rt'] as int),
    );
    _mixer.applyTo(_client.state);
    final name = m['name'] as String;
    if (_physical != name) {
      _log.i('physical pad active: $name');
      _loadPadCal(name);
      setState(() {
        _physical = name;
        _showOverlay = false; // physical pad in use: hide touch controls
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readout?.cancel();
    _padSub?.cancel();
    _motionSub?.cancel();
    _volumeSub?.cancel();
    _mixer.clearVolumeInput();
    _volumeConfig.invokeMethod<void>(
      'setConfig',
      {'interceptUp': false, 'interceptDown': false},
    ).catchError((Object _) {});
    _client.onRumble = null;
    _client.removeListener(_onClientChanged);
    _rumbleChannel.invokeMethod<void>('vibrate', {'strong': 0, 'weak': 0, 'ms': 0});
    _client.dispose();
    SystemChrome.setPreferredOrientations(_landscape);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  void _startLayoutEdit() {
    setState(() {
      _showOverlay = true;
      _editingLayout = true;
      _editorHudCollapsed = false;
    });
    _syncVolumeIntercept();
  }

  Future<void> _saveLayout() async {
    await _layoutStore.save(_layout);
    if (!mounted) return;
    setState(() {
      _editingLayout = false;
      _editorHudCollapsed = false;
    });
    _syncVolumeIntercept();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Touch layout saved!')),
    );
  }

  void _cancelLayoutEdit() async {
    final loaded = await _layoutStore.load();
    if (!mounted) return;
    setState(() {
      _layout = loaded;
      _editingLayout = false;
      _editorHudCollapsed = false;
    });
    _syncVolumeIntercept();
  }

  void _onElementMoved(String id, double relX, double relY) {
    setState(() {
      _layout.moveControl(id, relX, relY, groupMode: _groupMode);
      _selectedControlId = id;
    });
  }

  void _changeScale(double delta) {
    setState(() {
      _layout.scaleControl(_selectedControlId, delta, groupMode: _groupMode);
    });
  }

  void _toggleVisibility() {
    setState(() {
      _layout.toggleVisibility(_selectedControlId, groupMode: _groupMode);
    });
  }

  void _resetSelectedElement() {
    setState(() {
      _layout.resetControl(_selectedControlId, groupMode: _groupMode);
    });
  }

  void _resetAllElements() {
    setState(() {
      _layout = PadLayoutConfig.defaultXbox();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset all controls to Xbox default')),
    );
  }

  void _cycleElement(int direction) {
    final ids = ControlId.all;
    final idx = ids.indexOf(_selectedControlId);
    final nextIdx = (idx + direction + ids.length) % ids.length;
    setState(() => _selectedControlId = ids[nextIdx]);
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
            _layout = preset;
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
          opacity: _layout.opacity,
          hapticsEnabled: _layout.hapticsEnabled,
          snapToGrid: _layout.snapToGrid,
          onOpacityChanged: (v) {
            setDialogState(() => _layout.opacity = v);
            setState(() {
              _layout.opacity = v;
            });
          },
          onHapticsChanged: (v) {
            setDialogState(() => _layout.hapticsEnabled = v);
            setState(() {
              _layout.hapticsEnabled = v;
            });
          },
          onSnapChanged: (v) {
            setDialogState(() => _layout.snapToGrid = v);
            setState(() {
              _layout.snapToGrid = v;
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedElem = _layout.getElement(_selectedControlId);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_editingLayout) {
          _cancelLayoutEdit();
        } else {
          _openGameMenu();
        }
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: ConsoleBackdrop(
          child: SafeArea(
            top: false,
            bottom: false,
            child: Stack(children: [
              // Stays mounted while hidden, so a held touch isn't dropped mid-press.
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_showOverlay && !_editingLayout,
                  child: AnimatedOpacity(
                    opacity: _showOverlay || _editingLayout ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: OnScreenPad(
                      state: _client.state,
                      layout: _layout,
                      editMode: _editingLayout,
                      groupMode: _groupMode,
                      selectedId: _selectedControlId,
                      onSelect: (id) => setState(() => _selectedControlId = id),
                      onElementMoved: _onElementMoved,
                      onMenuPressed: _openGameMenu,
                      mixer: _mixer,
                      touchLook: _inputConfig.touchLook,
                      externalActiveTargets: _mixer.activeVolumeTargets,
                    ),
                  ),
                ),
              ),
              if (!_showOverlay && !_editingLayout)
                Positioned.fill(top: 58, child: _hiddenView()),
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: _editingLayout
                    ? (_editorHudCollapsed ? const SizedBox.shrink() : _editorBar())
                    : (_showOverlay ? const SizedBox.shrink() : _bar()),
              ),
              if (_editingLayout && !_editorHudCollapsed)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 8,
                  child: LayoutBottomToolbar(
                    selectedElem: selectedElem,
                    groupMode: _groupMode,
                    canGroup: ControlId.groupOf(_selectedControlId) != null,
                    onToggleGroupMode: () =>
                        setState(() => _groupMode = !_groupMode),
                    onPrev: () => _cycleElement(-1),
                    onNext: () => _cycleElement(1),
                    onScaleDown: () => _changeScale(-0.05),
                    onScaleUp: () => _changeScale(0.05),
                    onToggleVisibility: _toggleVisibility,
                    onReset: _resetSelectedElement,
                  ),
                ),
              if (_editingLayout && _editorHudCollapsed)
                Align(
                  alignment: Alignment.center,
                  child: EditorCollapsedPill(
                    onExpand: () => setState(() => _editorHudCollapsed = false),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Back, player ring, link chip, and the view toggles.
  Widget _bar() {
    final up = _client.connected;
    final problem = _error ?? _client.rejected;
    return Row(children: [
      _BackButton(onPressed: _openGameMenu),
      const SizedBox(width: 12),
      RingOfLight(slot: _client.slot, live: up),
      const SizedBox(width: 10),
      Flexible(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(
              up ? 'PLAYER ${_client.slot + 1}' : (problem != null ? 'NOT CONNECTED' : 'CONNECTING'),
              style: display(15, spacing: 1.8),
            ),
            problem != null
                ? Eyebrow(problem, color: C.b)
                : Eyebrow(_physical ?? widget.name),
          ]),
        ),
      ),
      const SizedBox(width: 12),
      if (up) LinkChip(bluetooth: _client.bluetooth, rttMs: _client.rttMs),
      const Spacer(),
      BarButton(
        icon: Icons.dashboard_customize_outlined,
        tooltip: 'Customize touch controls',
        onPressed: _startLayoutEdit,
      ),
      const SizedBox(width: 8),
      BarButton(
        icon: _showOverlay ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        tooltip: 'Toggle touch controls',
        onPressed: () => setState(() => _showOverlay = !_showOverlay),
      ),
      const SizedBox(width: 8),
      BarButton(
        icon: Icons.screen_rotation,
        tooltip: _motionOn ? 'Motion on' : 'Motion off',
        on: _motionOn,
        onPressed: () => setState(() => _setMotion(!_motionOn)),
      ),
      const SizedBox(width: 8),
      BarButton(icon: Icons.tune, tooltip: 'Calibrate', onPressed: _openCalibration),
      const SizedBox(width: 8),
      BarButton(icon: Icons.flip, tooltip: 'Flip screen', onPressed: _flip),
    ]);
  }

  Widget _editorBar() {
    return Row(children: [
      Material(
        color: C.panel.withAlpha(204),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: C.line),
        ),
        child: InkWell(
          onTap: _cancelLayoutEdit,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 14, 0),
            child: SizedBox(
              height: 42,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.close, size: 20, color: C.ink),
                const SizedBox(width: 4),
                Text('CANCEL', style: display(12, spacing: 1.8)),
              ]),
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: C.lime,
              boxShadow: [BoxShadow(color: C.lime, blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 8),
          Text('EDIT CONTROLS', style: display(13, spacing: 1.4)),
        ]),
      ),
      const Spacer(),
      BarButton(
        icon: Icons.fullscreen,
        tooltip: 'Hide editor bars',
        onPressed: () => setState(() => _editorHudCollapsed = true),
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
        onPressed: _resetAllElements,
      ),
      const SizedBox(width: 8),
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: C.lime.withAlpha(60), blurRadius: 18)],
        ),
        child: Material(
          color: C.lime,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            onTap: _saveLayout,
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                height: 42,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check, size: 18, color: C.bg),
                  const SizedBox(width: 6),
                  Text('SAVE', style: display(12, color: C.bg, spacing: 1.8)),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _menuActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: C.panel2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: C.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 6),
              Text(title, style: display(13, spacing: 0.8)),
              const SizedBox(height: 2),
              Text(subtitle, style: mono(10, color: C.mute)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openGameMenu() => _withModalPause(() async {
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: C.panel,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            side: BorderSide(color: C.line),
          ),
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setMenuState) {
              final up = _client.connected;
              final tl = _inputConfig.touchLook;
              final vt = _inputConfig.volumeTriggers;
              final upEff = vt.effectiveBinding(isUp: true, flipped: _flipped);
              final downEff = vt.effectiveBinding(isUp: false, flipped: _flipped);
              return SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.90,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header with Status & Close
                          Row(
                            children: [
                              RingOfLight(slot: _client.slot, live: up),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    up ? 'PLAYER ${_client.slot + 1}' : 'NOT CONNECTED',
                                    style: display(15, spacing: 1.5),
                                  ),
                                  Text(
                                    up ? (_physical ?? widget.name) : 'Searching...',
                                    style: mono(11, color: C.mute),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              if (up) LinkChip(bluetooth: _client.bluetooth, rttMs: _client.rttMs),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.close, color: C.ink, size: 20),
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Resume',
                                onPressed: () => Navigator.of(ctx).pop(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Quick Actions Grid
                          Row(
                            children: [
                              Expanded(
                                child: _menuActionCard(
                                  title: 'Resume',
                                  subtitle: 'Back to game',
                                  icon: Icons.play_arrow,
                                  color: C.lime,
                                  onTap: () => Navigator.of(ctx).pop(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _menuActionCard(
                                  title: 'Edit Controls',
                                  subtitle: 'Move & scale buttons',
                                  icon: Icons.dashboard_customize_outlined,
                                  color: C.cyan,
                                  onTap: () {
                                    Navigator.of(ctx).pop();
                                    _startLayoutEdit();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _menuActionCard(
                                  title: _showOverlay ? 'Hide Controls' : 'Show Controls',
                                  subtitle: _showOverlay ? 'Readout view' : 'Touch overlay',
                                  icon: _showOverlay ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: C.a,
                                  onTap: () {
                                    Navigator.of(ctx).pop();
                                    setState(() => _showOverlay = !_showOverlay);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _menuActionCard(
                                  title: 'Flip Screen',
                                  subtitle: '180° rotation',
                                  icon: Icons.screen_rotation_outlined,
                                  color: C.y,
                                  onTap: () {
                                    _flip();
                                    setMenuState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Custom Triggers & Touch-Look Card
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: C.panel2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: C.cyan.withAlpha(85)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.swipe_outlined, size: 20, color: tl.enabled ? C.lime : C.mute),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Touch-Look Camera', style: display(14)),
                                          Text(
                                            tl.enabled
                                                ? '${tl.mode.label} · ${tl.zone.label}${tl.hideRightStick ? ' · Stick hidden' : ''}'
                                                : 'Drag empty screen area for camera off',
                                            style: mono(10.5, color: C.mute),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: tl.enabled,
                                      activeThumbColor: C.lime,
                                      onChanged: (v) {
                                        final next = _inputConfig.clone();
                                        next.touchLook.enabled = v;
                                        _inputStore.save(next);
                                        _applyInputConfig(next);
                                        setMenuState(() {});
                                      },
                                    ),
                                  ],
                                ),
                                const Divider(color: C.line, height: 12),
                                Row(
                                  children: [
                                    Icon(Icons.volume_up_outlined, size: 20, color: vt.enabled ? C.cyan : C.mute),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Volume Key Triggers', style: display(14)),
                                          Text(
                                            vt.enabled
                                                ? 'VOL+ ${upEff.target.shortLabel} (${upEff.mode.label}) · VOL- ${downEff.target.shortLabel} (${downEff.mode.label})'
                                                : 'Disabled (normal Android volume)',
                                            style: mono(10.5, color: C.mute),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: vt.enabled,
                                      activeThumbColor: C.lime,
                                      onChanged: (v) {
                                        final next = _inputConfig.clone();
                                        next.volumeTriggers.enabled = v;
                                        _inputStore.save(next);
                                        _applyInputConfig(next);
                                        setMenuState(() {});
                                      },
                                    ),
                                  ],
                                ),
                                const Divider(color: C.line, height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.gamepad_outlined, size: 18, color: C.cyan),
                                      label: Text('VOLUME TRIGGERS', style: display(11.5, color: C.cyan, spacing: 1.1)),
                                      onPressed: () {
                                        Navigator.of(ctx).pop();
                                        _openInputSettingsDialog(initialTab: 0);
                                      },
                                    ),
                                    TextButton.icon(
                                      icon: const Icon(Icons.swipe_outlined, size: 18, color: C.lime),
                                      label: Text('TOUCH-LOOK TUNING', style: display(11.5, color: C.lime, spacing: 1.1)),
                                      onPressed: () {
                                        Navigator.of(ctx).pop();
                                        _openInputSettingsDialog(initialTab: 1);
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Motion Card with Direct Settings Access
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: C.panel2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: C.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.screen_rotation, size: 20, color: _motionOn ? C.lime : C.mute),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Motion / Gyroscope', style: display(14)),
                                          Text(
                                            _motionOn
                                                ? 'Tilt & rotate phone for Cemu / BotW shrines'
                                                : 'Motion sensing disabled',
                                            style: mono(11, color: C.mute),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: _motionOn,
                                      activeThumbColor: C.lime,
                                      onChanged: (v) {
                                        setState(() => _setMotion(v));
                                        setMenuState(() {});
                                      },
                                    ),
                                  ],
                                ),
                                const Divider(color: C.line, height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.tune, size: 18, color: C.cyan),
                                      label: Text('MOTION & GYRO SETTINGS', style: display(11.5, color: C.cyan, spacing: 1.2)),
                                      onPressed: () {
                                        Navigator.of(ctx).pop();
                                        _openMotionSettingsDialog();
                                      },
                                    ),
                                    TextButton.icon(
                                      icon: const Icon(Icons.sports_esports_outlined, size: 18, color: C.ink),
                                      label: Text('HARDWARE CALIBRATION', style: display(11.5, color: C.ink, spacing: 1.2)),
                                      onPressed: () {
                                        Navigator.of(ctx).pop();
                                        _openCalibration();
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Disconnect & Leave Button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.power_settings_new, color: C.b, size: 18),
                              label: Text('DISCONNECT & LEAVE', style: display(12, color: C.b, spacing: 1.5)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: C.b),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).pop();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      });

  Future<void> _openInputSettingsDialog({int initialTab = 0}) =>
      _withModalPause(() => showInputSettingsSheet(
            context: context,
            initialConfig: _inputConfig,
            initialTab: initialTab,
            onChanged: _applyInputConfig,
          ));

  Future<void> _openMotionSettingsDialog() =>
      _withModalPause(() => showMotionSettingsSheet(
            context: context,
            initialCal: _motionCal,
            isConnected: true,
            motionOn: _motionOn,
            onMotionToggled: (v) {
              if (mounted) setState(() => _setMotion(v));
            },
            onCalChanged: (c) {
              if (mounted) setState(() => _motionCal = c);
            },
          ));

  /// Shown instead of the touch controls: the logo, which pad is live, and its values.
  Widget _hiddenView() {
    final st = _client.state;
    String axis(String n, int v) => '$n ${v >= 0 ? '+' : '-'}${(v.abs() / 32767).toStringAsFixed(2)}';
    final values = [
      axis('LX', st.lx),
      axis('LY', st.ly),
      axis('RX', st.rx),
      axis('RY', st.ry),
      'LT ${st.lt}',
      'RT ${st.rt}',
    ];
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: C.violet.withAlpha(120), blurRadius: 40)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/logo.png',
              width: 84,
              height: 84,
              cacheWidth: 252,
              cacheHeight: 252,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('TOUCH CONTROLS HIDDEN', style: display(16, spacing: 3)),
        const SizedBox(height: 4),
        Eyebrow(_physical != null ? 'Physical pad active · $_physical' : 'Tap the eye to show them'),
        const SizedBox(height: 12),
        Wrap(spacing: 16, children: [for (final v in values) Text(v, style: mono(12, color: C.ink))]),
      ]),
    );
  }
}

/// Labelled so it reads as "leave this view", top left where a thumb expects it.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: C.panel.withAlpha(204),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: C.line),
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 14, 0),
            child: SizedBox(
              height: 42,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.chevron_left, size: 24, color: C.ink),
                Text('BACK', style: display(12, spacing: 1.8)),
              ]),
            ),
          ),
        ),
      );
}

/// Modal bottom sheet for configuring motion, axis inversions, sensitivity, and zero-point calibration.
Future<void> showMotionSettingsSheet({
  required BuildContext context,
  MotionCalibration? initialCal,
  bool isConnected = false,
  bool motionOn = true,
  ValueChanged<bool>? onMotionToggled,
  ValueChanged<MotionCalibration>? onCalChanged,
}) async {
  final calStore = CalibrationStore();
  const motionConfig = MethodChannel('xpadlink/motion_config');
  var cal = initialCal ?? await calStore.loadMotion();
  var isMotionActive = motionOn;
  var measuring = false;

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
      builder: (ctx, setDialogState) {
        final b = cal.gyroBias;
        final maxHeight = MediaQuery.of(context).size.height * 0.90;

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
                      const Icon(Icons.tune, size: 20, color: C.cyan),
                      const SizedBox(width: 8),
                      Text('MOTION & GYROSCOPE TUNING', style: display(15, spacing: 1.4)),
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
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isConnected) ...[
                            // Motion On/Off
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: C.panel2,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: C.line),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Motion Streaming', style: display(14)),
                                      Text('Send tilt & turn rate to server', style: mono(11, color: C.mute)),
                                    ],
                                  ),
                                  Switch(
                                    value: isMotionActive,
                                    activeThumbColor: C.lime,
                                    onChanged: (v) {
                                      setDialogState(() => isMotionActive = v);
                                      onMotionToggled?.call(v);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],

                          // Accelerometer Fallback Toggle
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: C.panel2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: C.line),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Accelerometer / Rotation Fallback', style: display(13.5)),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Disable to use pure low-latency hardware gyroscope. Enable only if phone lacks physical gyro.',
                                        style: mono(11, color: C.mute),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Switch(
                                  value: cal.useAccelFallback,
                                  activeThumbColor: C.lime,
                                  onChanged: (v) {
                                    setDialogState(() => cal.useAccelFallback = v);
                                    motionConfig.invokeMethod<void>(
                                        'setFallbackEnabled', {'enabled': v});
                                    calStore.saveMotion(cal);
                                    onCalChanged?.call(cal);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Breath of the Wild & Cemu Apparatus Shrine Tuning Card
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: C.panel2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: C.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.explore_outlined, size: 18, color: C.cyan),
                                    const SizedBox(width: 8),
                                    Text('BOTW & CEMU APPARATUS TUNING', style: display(13.5, color: C.cyan, spacing: 1.2)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Invert axes if the shrine maze apparatus flips upside down or rolls backwards.',
                                  style: mono(11, color: C.mute),
                                ),
                                const Divider(color: C.line, height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Invert Pitch (forward/back tilt)', style: mono(12)),
                                    Switch(
                                      value: cal.invertPitch,
                                      activeThumbColor: C.lime,
                                      onChanged: (v) {
                                        setDialogState(() => cal.invertPitch = v);
                                        calStore.saveMotion(cal);
                                        onCalChanged?.call(cal);
                                      },
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Invert Yaw (left/right steering)', style: mono(12)),
                                    Switch(
                                      value: cal.invertYaw,
                                      activeThumbColor: C.lime,
                                      onChanged: (v) {
                                        setDialogState(() => cal.invertYaw = v);
                                        calStore.saveMotion(cal);
                                        onCalChanged?.call(cal);
                                      },
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Invert Roll (left/right tilt)', style: mono(12)),
                                    Switch(
                                      value: cal.invertRoll || cal.flipRoll,
                                      activeThumbColor: C.lime,
                                      onChanged: (v) {
                                        setDialogState(() {
                                          cal.invertRoll = v;
                                          cal.flipRoll = v;
                                        });
                                        calStore.saveMotion(cal);
                                        onCalChanged?.call(cal);
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Gyro Sensitivity', style: mono(12)),
                                    Text('${cal.sensitivity.toStringAsFixed(1)}x', style: mono(12, color: C.lime)),
                                  ],
                                ),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: C.lime,
                                    thumbColor: C.lime,
                                  ),
                                  child: Slider(
                                    value: cal.sensitivity,
                                    min: 0.5,
                                    max: 3.0,
                                    divisions: 25,
                                    onChanged: (v) {
                                      setDialogState(() => cal.sensitivity = (v * 10).round() / 10);
                                      onCalChanged?.call(cal);
                                    },
                                    onChangeEnd: (_) => calStore.saveMotion(cal),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Zero Point Bias Card
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: C.panel2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: C.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Gyro Bias (Zero Drift)', style: display(13.5)),
                                    Text(
                                      '${b[0].toStringAsFixed(2)}  ${b[1].toStringAsFixed(2)}  ${b[2].toStringAsFixed(2)}',
                                      style: mono(11.5, color: C.ink),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Lay phone flat and still on a table to eliminate drift.',
                                  style: mono(11, color: C.mute),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.track_changes, size: 18),
                                  label: Text(measuring ? 'MEASURING...' : 'MEASURE ZERO POINT (2s)'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: C.panel,
                                    foregroundColor: C.cyan,
                                    side: const BorderSide(color: C.line),
                                  ),
                                  onPressed: measuring
                                      ? null
                                      : () async {
                                          setDialogState(() => measuring = true);
                                          final samples = <List<double>>[];
                                          final subs = NativeStreams.motion.listen((dynamic data) {
                                            final list = (data as List).cast<double>();
                                            if (list.length >= 6) {
                                              samples.add(list.sublist(3, 6));
                                            }
                                          });
                                          try {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Measuring gyro bias... keep phone still!')),
                                              );
                                            }
                                            await Future<void>.delayed(const Duration(milliseconds: 2000));
                                          } finally {
                                            await subs.cancel();
                                            if (ctx.mounted) {
                                              setDialogState(() => measuring = false);
                                            }
                                          }
                                          if (samples.isNotEmpty) {
                                            final avg = [0.0, 0.0, 0.0];
                                            for (final s in samples) {
                                              avg[0] += s[0];
                                              avg[1] += s[1];
                                              avg[2] += s[2];
                                            }
                                            avg[0] /= samples.length;
                                            avg[1] /= samples.length;
                                            avg[2] /= samples.length;
                                            if (ctx.mounted) {
                                              setDialogState(() => cal.gyroBias = avg);
                                            } else {
                                              cal.gyroBias = avg;
                                            }
                                            await calStore.saveMotion(cal);
                                            onCalChanged?.call(cal);
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Gyro zero point calibrated!')),
                                              );
                                            }
                                          }
                                        },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () async {
                          await calStore.resetMotion();
                          setDialogState(() => cal = MotionCalibration());
                          motionConfig.invokeMethod<void>(
                              'setFallbackEnabled', {'enabled': false});
                          onCalChanged?.call(cal);
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
                          await calStore.saveMotion(cal);
                          if (context.mounted) Navigator.of(ctx).pop();
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
