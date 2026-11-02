import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'client.dart';
import 'discovery.dart';
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
        theme: ThemeData.dark(useMaterial3: true),
        home: const ConnectScreen(),
      );
}

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  static final _log = Log('connect');

  final _store = ServerStore();
  final _label = TextEditingController();
  final _server = TextEditingController();
  final _token = TextEditingController();
  final _name = TextEditingController(text: 'phone');
  List<SavedServer> _saved = [];
  final List<FoundServer> _found = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _load().then((_) => _scan());
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
    _label.text = s.label == s.address ? '' : s.label;
    _server.text = s.address;
    _token.text = s.token;
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
    if (i > 0) {
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
      appBar: AppBar(title: const Text('XPadLink')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        if (_saved.isNotEmpty) ...[
          Text('Saved servers', style: Theme.of(context).textTheme.titleSmall),
          for (final s in _saved)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.label),
              subtitle: s.label == s.address ? null : Text(s.address),
              onTap: () => _open(s.address, s.token),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit),
                  onPressed: () => _edit(s),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(s),
                ),
              ]),
            ),
          const Divider(height: 32),
        ],
        Row(children: [
          Text('Nearby servers', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          if (_scanning)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            IconButton(
                tooltip: 'Scan again',
                icon: const Icon(Icons.refresh),
                onPressed: _scan),
        ]),
        if (_found.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                _scanning
                    ? 'Looking for servers on this network…'
                    : 'None found. Enter the address below.',
                style: const TextStyle(color: Colors.white54)),
          ),
        for (final s in _found)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.computer),
            title: Text(s.hostname),
            subtitle: Text(s.address),
            onTap: () => _pick(s),
          ),
        const Divider(height: 32),
        TextField(
          controller: _label,
          decoration: const InputDecoration(
              labelText: 'Label (optional)', hintText: 'Living room PC'),
        ),
        TextField(
          controller: _server,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
              labelText: 'Server (host:port)', hintText: '192.168.1.20:9777'),
        ),
        TextField(
          controller: _token,
          decoration: const InputDecoration(
              labelText: 'Token', hintText: 'printed by xpadlinkd'),
        ),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Device name'),
        ),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
              child: FilledButton(
                  onPressed: _connect, child: const Text('Connect'))),
          const SizedBox(width: 12),
          OutlinedButton(onPressed: _save, child: const Text('Save')),
        ]),
      ]),
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
