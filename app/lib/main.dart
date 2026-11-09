import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calibration.dart';
import 'client.dart';
import 'discovery.dart';
import 'link.dart';
import 'log.dart';
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
    _load().then((_) {
      // Nothing saved yet: start where a new server is found.
      if (_saved.isEmpty && mounted) _tabs.index = _tabWifi;
      return _scan();
    });
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
        child: Image.asset('assets/logo.png', width: 36, height: 36),
      ),
      const SizedBox(width: 12),
      Text.rich(TextSpan(children: [
        TextSpan(text: 'XPAD', style: display(20, spacing: 3.2)),
        TextSpan(text: 'LINK', style: display(20, color: C.lime, spacing: 3.2)),
      ])),
      const Spacer(),
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
      Text(
        _server.text.startsWith('bt:') ? 'BLUETOOTH · RFCOMM · SLOT AUTO' : 'WI-FI · UDP · SLOT AUTO',
        style: mono(10, spacing: .8),
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

class _ControllerScreenState extends State<ControllerScreen> {
  static const _channel = EventChannel('xpadlink/gamepad');
  static const _motionChannel = EventChannel('xpadlink/motion');
  static const _rumbleChannel = MethodChannel('xpadlink/rumble');
  static final _log = Log('screen');

  final _client = PadClient();
  StreamSubscription<dynamic>? _padSub;
  StreamSubscription<dynamic>? _motionSub;
  bool _motionOn = true;
  bool _flipped = false; // landscape right instead of left
  String? _physical; // name of a physical pad once one has sent input
  final _calStore = CalibrationStore();
  PadCalibration _padCal = PadCalibration();
  MotionCalibration _motionCal = MotionCalibration();
  bool _showOverlay = true;
  String? _error;
  Timer? _readout; // refreshes the stick values while the touch controls are hidden

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(_landscape);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _client.addListener(() => setState(() {}));
    _client.onRumble = _onRumble;
    _client
        .start(widget.host, widget.port, widget.token, widget.name)
        .catchError((Object e) {
      _log.e('client start failed', e);
      if (mounted) setState(() => _error = '$e');
    });
    _padSub = _channel.receiveBroadcastStream().listen(_onPhysical,
        onError: (Object e) => _log.e('gamepad channel error', e));
    _calStore.loadMotion().then((c) => _motionCal = c);
    _setMotion(true);
    _readout = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (mounted && !_showOverlay) setState(() {});
    });
  }

  /// Forces the other landscape, for when the system doesn't follow the sensor.
  void _flip() {
    setState(() => _flipped = !_flipped);
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
    _motionSub = _motionChannel.receiveBroadcastStream().listen((dynamic e) {
      final v = (e as List).cast<double>();
      _client.setMotion(_motionCal.apply(PadMotion(v.sublist(0, 3), v.sublist(3, 6))));
    }, onError: (Object e) => _log.e('motion channel error', e));
  }

  Future<void> _loadPadCal(String name) async {
    final c = await _calStore.loadPad(name);
    if (mounted && _physical == name) _padCal = c;
  }

  Future<void> _openCalibration() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CalibrationScreen(padName: _physical),
    ));
    // Pick up whatever was saved while the screen was open.
    _motionCal = await _calStore.loadMotion();
    final name = _physical;
    if (name != null) _padCal = await _calStore.loadPad(name);
  }

  void _onRumble(int strong, int weak, int ms) {
    _rumbleChannel.invokeMethod<void>(
        'vibrate', {'strong': strong, 'weak': weak, 'ms': ms}).catchError(
        (Object e) => _log.e('vibrate failed', e));
  }

  void _onPhysical(dynamic event) {
    final m = Map<String, dynamic>.from(event as Map);
    final s = _client.state;
    s.buttons = m['buttons'] as int;
    s.lx = _padCal.lx(m['lx'] as int);
    s.ly = _padCal.ly(m['ly'] as int);
    s.rx = _padCal.rx(m['rx'] as int);
    s.ry = _padCal.ry(m['ry'] as int);
    s.lt = _padCal.lt(m['lt'] as int);
    s.rt = _padCal.rt(m['rt'] as int);
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
    _readout?.cancel();
    _padSub?.cancel();
    _motionSub?.cancel();
    _client.onRumble = null;
    _rumbleChannel.invokeMethod<void>('vibrate', {'strong': 0, 'weak': 0, 'ms': 0});
    _client.dispose();
    SystemChrome.setPreferredOrientations(_landscape);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: ConsoleBackdrop(
        child: SafeArea(
          child: Stack(children: [
            // Stays mounted while hidden, so a held touch isn't dropped mid-press.
            Positioned.fill(
              top: 58,
              child: IgnorePointer(
                ignoring: !_showOverlay,
                child: AnimatedOpacity(
                  opacity: _showOverlay ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: OnScreenPad(state: _client.state),
                ),
              ),
            ),
            if (!_showOverlay) Positioned.fill(top: 58, child: _hiddenView()),
            Positioned(top: 8, left: 12, right: 12, child: _bar()),
          ]),
        ),
      ),
    );
  }

  /// Back, player ring, link chip, and the view toggles.
  Widget _bar() {
    final up = _client.connected;
    final problem = _error ?? _client.rejected;
    return Row(children: [
      _BackButton(onPressed: () => Navigator.of(context).maybePop()),
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
            child: Image.asset('assets/logo.png', width: 84, height: 84),
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
