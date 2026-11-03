import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'client.dart';
import 'discovery.dart';
import 'link.dart';
import 'log.dart';
import 'onscreen.dart';
import 'protocol.dart';
import 'servers.dart';

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
        theme: _theme(),
        home: const ConnectScreen(),
      );

  static ThemeData _theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C6CF0),
      brightness: Brightness.dark,
      surface: const Color(0xFF0E0F14),
    );
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0E0F14),
      cardTheme: CardThemeData(
        color: const Color(0xFF171923),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF262A38)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1F2230),
        border: field,
        enabledBorder: field,
        focusedBorder: field.copyWith(
            borderSide: BorderSide(color: scheme.primary, width: 1.5)),
        isDense: true,
      ),
      tabBarTheme: const TabBarThemeData(
        dividerColor: Color(0xFF262A38),
        labelStyle: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final picker = _picker(context);
          final form = _form(context);
          // Landscape (how the app runs): servers on the left, form on the right.
          if (box.maxWidth >= 640) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _header(context),
                const SizedBox(height: 12),
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(flex: 5, child: picker),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: SingleChildScrollView(child: form)),
                  ]),
                ),
              ]),
            );
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            _header(context),
            const SizedBox(height: 12),
            SizedBox(height: 320, child: picker),
            const SizedBox(height: 16),
            form,
          ]);
        }),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final t = Theme.of(context);
    return Row(children: [
      Icon(Icons.sports_esports, color: t.colorScheme.primary),
      const SizedBox(width: 10),
      Text('XPadLink',
          style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }

  /// Saved servers, nearby servers on Wi-Fi, paired PCs over Bluetooth.
  Widget _picker(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        TabBar(controller: _tabs, tabs: [
          Tab(
              height: 44,
              icon: const Icon(Icons.bookmark_outline, size: 20),
              text: 'Saved${_saved.isEmpty ? '' : ' (${_saved.length})'}'),
          const Tab(height: 44, icon: Icon(Icons.wifi, size: 20), text: 'Wi-Fi'),
          const Tab(
              height: 44,
              icon: Icon(Icons.bluetooth, size: 20),
              text: 'Bluetooth'),
        ]),
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

  Widget _hint(String text, {Color? color, Widget? action}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: color ?? Colors.white54)),
            if (action != null) ...[const SizedBox(height: 12), action],
          ]),
        ),
      );

  Widget _savedTab() {
    if (_saved.isEmpty) {
      return _hint('No saved servers yet. Find one on Wi-Fi or Bluetooth, '
          'then press Save.');
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
      for (final s in _saved)
        ListTile(
          leading: Icon(s.address.startsWith('bt:') ? Icons.bluetooth : Icons.wifi),
          title: Text(s.label),
          subtitle: s.label == s.address ? null : Text(s.address),
          onTap: () => _open(s.address, s.token),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _edit(s),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(s),
            ),
          ]),
        ),
    ]);
  }

  Widget _wifiTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        child: Row(children: [
          Expanded(
              child: Text(
                  _scanning ? 'Looking on this network…' : 'Servers on this network',
                  style: const TextStyle(color: Colors.white54))),
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
                tooltip: 'Scan again',
                icon: const Icon(Icons.refresh),
                onPressed: _scan),
        ]),
      ),
      Expanded(
        child: _found.isEmpty
            ? _hint(_scanning
                ? ' '
                : 'None found. Guest networks block discovery: type the '
                    'address on the right instead.')
            : ListView(children: [
                for (final s in _found)
                  ListTile(
                    leading: const Icon(Icons.computer),
                    title: Text(s.hostname),
                    subtitle: Text(s.address),
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
        _pairedError ?? 'Pair your PC in Android settings first, then list '
            'the paired devices here.',
        color: _pairedError == null ? null : Colors.redAccent,
        action: FilledButton.tonalIcon(
          onPressed: _loadPaired,
          icon: const Icon(Icons.bluetooth_searching),
          label: const Text('Show paired devices'),
        ),
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        child: Row(children: [
          const Expanded(
              child: Text('Paired with this phone',
                  style: TextStyle(color: Colors.white54))),
          IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _loadPaired),
        ]),
      ),
      Expanded(
        child: paired.isEmpty
            ? _hint('No paired devices. Pair your PC in Android settings first.')
            : ListView(children: [
                for (final d in paired)
                  ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(d.name),
                    subtitle: Text(d.address),
                    onTap: () => _pickPaired(d),
                  ),
              ]),
      ),
    ]);
  }

  Widget _form(BuildContext context) {
    final bt = _server.text.startsWith('bt:');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _label,
            decoration: const InputDecoration(
                labelText: 'Label (optional)', hintText: 'Living room PC'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _server,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Server',
              hintText: '192.168.1.20:9777  or  bt:AA:BB:CC:DD:EE:FF',
              prefixIcon: Icon(bt ? Icons.bluetooth : Icons.wifi),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            decoration: const InputDecoration(
                labelText: 'Token',
                hintText: 'printed by xpadlinkd',
                prefixIcon: Icon(Icons.key)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Device name', prefixIcon: Icon(Icons.smartphone)),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: FilledButton.icon(
                    onPressed: _connect,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Connect'))),
            const SizedBox(width: 12),
            OutlinedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save')),
          ]),
        ]),
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
  bool _showOverlay = true;
  String? _error;

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
    _setMotion(true);
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
      _client.setMotion(PadMotion(v.sublist(0, 3), v.sublist(3, 6)));
    }, onError: (Object e) => _log.e('motion channel error', e));
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
    s.lx = m['lx'] as int;
    s.ly = m['ly'] as int;
    s.rx = m['rx'] as int;
    s.ry = m['ry'] as int;
    s.lt = m['lt'] as int;
    s.rt = m['rt'] as int;
    final name = m['name'] as String;
    if (_physical != name) {
      _log.i('physical pad active: $name');
      setState(() {
        _physical = name;
        _showOverlay = false; // physical pad in use: hide touch controls
      });
    }
  }

  @override
  void dispose() {
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
    final status = _error ??
        _client.rejected ??
        (_client.connected
            ? 'Player ${_client.slot + 1}'
                '${_physical != null ? ' · $_physical' : ''}'
            : 'Connecting to ${widget.host}…');

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          if (_showOverlay) OnScreenPad(state: _client.state),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle,
                    size: 10,
                    color: _client.connected ? Colors.green : Colors.orange),
                const SizedBox(width: 6),
                Text(status,
                    style: TextStyle(
                        fontSize: 12,
                        color: (_error != null || _client.rejected != null)
                            ? Colors.redAccent
                            : null)),
                IconButton(
                  tooltip: 'Toggle touch controls',
                  icon: Icon(
                      _showOverlay ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showOverlay = !_showOverlay),
                ),
                IconButton(
                  tooltip: _motionOn ? 'Motion on' : 'Motion off',
                  icon: Icon(_motionOn ? Icons.screen_rotation : Icons.screen_lock_rotation),
                  onPressed: () => setState(() => _setMotion(!_motionOn)),
                ),
                IconButton(
                  tooltip: 'Flip screen',
                  icon: const Icon(Icons.flip),
                  onPressed: _flip,
                ),
                IconButton(
                  tooltip: 'Disconnect',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
