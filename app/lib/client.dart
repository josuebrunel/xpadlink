import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log.dart';
import 'protocol.dart';

/// UDP client. UI code mutates [state]; a 60 Hz timer sends it when it changed
/// and at least every 100 ms otherwise, so a lost packet heals quickly.
class PadClient extends ChangeNotifier {
  final PadState state = PadState();

  static final _log = Log('client');

  bool connected = false;

  /// Called when a game asks the controller to vibrate.
  void Function(int strong, int weak, int ms)? onRumble;

  /// Latest sensor sample, sent at up to 60 Hz when set (null: motion off).
  PadMotion? motion;
  int _motionSeq = 0;
  bool _motionFresh = false;

  /// Called by the UI for each sensor sample.
  void setMotion(PadMotion m) {
    motion = m;
    _motionFresh = true;
  }

  /// Set while the server refuses us (wrong token, server full); cleared on ack.
  String? rejected;
  int slot = -1;

  RawDatagramSocket? _sock;
  InternetAddress? _host;
  int _port = 9777;
  String _token = '';
  String _name = 'phone';
  Timer? _timer;
  int _seq = 0;
  PadState _lastSent = PadState();
  bool _disposed = false;

  // Socket recovery: reopen with backoff after a network blip.
  int _localPort = 0;
  bool _reopening = false;
  int _reopenAttempts = 0;
  int _zeroWrites = 0;
  Timer? _reopenTimer;

  // Link health counters, summarised every 5 s.
  int _helloSent = 0, _statesSent = 0, _acks = 0, _sendFailures = 0;
  int _maxAckGapMs = 0;
  DateTime _lastStats = _epoch;

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSend = _epoch;
  DateTime _lastHello = _epoch;
  DateTime _lastAck = _epoch;

  Future<void> start(String host, int port, String token, String name) async {
    _log.i('starting, server=$host:$port name=$name');
    final List<InternetAddress> addrs;
    try {
      addrs = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
    } catch (e, st) {
      _log.e('lookup $host failed', e, st);
      rethrow;
    }
    if (addrs.isEmpty) {
      _log.e('cannot resolve $host');
      throw SocketException('Cannot resolve $host');
    }
    _host = addrs.first;
    _log.i('resolved $host to ${_host!.address}');
    _port = port;
    _token = token;
    _name = name;
    try {
      await _openSocket();
    } catch (e, st) {
      _log.e('socket bind failed', e, st);
      rethrow;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  /// Binds the UDP socket, preferring the previous local port so the server
  /// still sees the same address and keeps our session (and player slot).
  Future<void> _openSocket() async {
    RawDatagramSocket s;
    try {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _localPort);
    } on SocketException {
      if (_localPort == 0) rethrow;
      _log.w('local port $_localPort is taken, using a new one');
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }
    _localPort = s.port;
    _sock = s;
    _log.i('socket bound on local port ${s.port}');
    s.listen(
      (e) => _onSocket(s, e),
      onError: (Object e, StackTrace st) {
        _log.e('socket error', e, st);
        _socketBroken(s, 'error');
      },
      onDone: () => _socketBroken(s, 'closed'),
    );
  }

  /// 500 ms doubling per failed attempt, capped at 5 s.
  int _backoffMs() => (500 << _reopenAttempts.clamp(0, 4)).clamp(500, 5000);

  /// The socket died (Wi-Fi dropped, interface changed): drop it and retry with
  /// backoff. Events from an older socket are ignored.
  void _socketBroken(RawDatagramSocket s, String why) {
    if (_disposed || !identical(s, _sock) || _reopening) return;
    _reopening = true;
    _sock = null;
    s.close();
    _setConnected(false, 'socket $why');
    final ms = _backoffMs();
    _log.w('socket $why, reopening in $ms ms (attempt ${_reopenAttempts + 1})');
    _reopenTimer = Timer(Duration(milliseconds: ms), _reopen);
  }

  Future<void> _reopen() async {
    if (_disposed) return;
    try {
      await _openSocket();
      _reopening = false;
      _lastHello = _epoch; // say hello right away
      _log.i('socket reopened');
    } catch (e) {
      _reopenAttempts++;
      final ms = _backoffMs();
      _log.e('reopen failed, retrying in $ms ms', e);
      _reopenTimer = Timer(Duration(milliseconds: ms), _reopen);
    }
  }

  void _onSocket(RawDatagramSocket s, RawSocketEvent e) {
    if (e != RawSocketEvent.read || !identical(s, _sock)) return;
    for (var d = s.receive(); d != null; d = s.receive()) {
      final b = d.data;
      if (b.length < 2 || b[0] != kMagic) continue;
      if (b[1] == kAck && b.length >= 3) {
        final now = DateTime.now();
        final gap = now.difference(_lastAck).inMilliseconds;
        if (_lastAck != _epoch && gap > _maxAckGapMs) _maxAckGapMs = gap;
        _acks++;
        _lastAck = now;
        _reopenAttempts = 0;
        if (rejected != null) {
          rejected = null;
          if (!_disposed) notifyListeners();
        }
        if (slot != b[2]) _log.i('assigned player ${b[2] + 1}');
        slot = b[2];
        _setConnected(true, 'ack');
      } else if (b[1] == kNeedHello) {
        // Server forgot us (restart or timeout): say hello again right away.
        _log.w('server asked for hello (restarted or timed us out)');
        _lastHello = _epoch;
        _setConnected(false, 'need-hello');
      } else if (b[1] == kReject && b.length >= 3) {
        final why = switch (b[2]) {
          kRejectBadToken => 'Wrong token',
          kRejectFull => 'Server full',
          _ => 'Rejected by server',
        };
        if (rejected != why) {
          _log.w('server rejected us: $why');
          rejected = why;
          if (!_disposed) notifyListeners();
        }
      } else if (b[1] == kRumble) {
        final r = parseRumble(b);
        if (r != null) onRumble?.call(r.strong, r.weak, r.ms);
      } else {
        _log.d('ignored packet type ${b[1]} len ${b.length}');
      }
    }
  }

  void _tick() {
    final now = DateTime.now();

    // Hello doubles as keepalive and liveness probe.
    if (now.difference(_lastHello).inMilliseconds >= 1000) {
      _send(encodeHello(_token, _name));
      _helloSent++;
      _lastHello = now;
    }
    if (connected && now.difference(_lastAck).inMilliseconds > 3000) {
      _setConnected(false, 'no ack for ${now.difference(_lastAck).inMilliseconds} ms');
    }
    _logStats(now);
    if (!connected) return;

    final m = motion;
    if (m != null && _motionFresh) {
      _send(encodeMotion(_motionSeq++, m));
      _motionFresh = false;
    }

    final changed = !state.sameAs(_lastSent);
    if (changed || now.difference(_lastSend).inMilliseconds >= 100) {
      _send(encodeState(_seq++, state));
      _statesSent++;
      _lastSent = state.clone();
      _lastSend = now;
    }
  }

  void _send(Uint8List data) {
    final h = _host;
    final s = _sock;
    if (h == null || s == null) return; // reopening
    try {
      final n = s.send(data, h, _port);
      if (n > 0) {
        _zeroWrites = 0;
        return;
      }
      // Kernel send buffer full or no route: the datagram was dropped.
      _sendFailures++;
      _log.e('send dropped (0 bytes written)');
      if (++_zeroWrites >= 3) _socketBroken(s, 'stopped accepting data');
    } catch (e) {
      _sendFailures++;
      _log.e('send failed', e);
      _socketBroken(s, 'send failed');
    }
  }

  void _logStats(DateTime now) {
    if (now.difference(_lastStats).inSeconds < 5) return;
    if (_lastStats != _epoch) {
      _log.i('link: connected=$connected hello=$_helloSent state=$_statesSent '
          'ack=$_acks sendFail=$_sendFailures maxAckGap=${_maxAckGapMs}ms (5 s)');
    }
    _helloSent = _statesSent = _acks = _sendFailures = _maxAckGapMs = 0;
    _lastStats = now;
  }

  void _setConnected(bool v, String why) {
    if (connected == v) return;
    connected = v;
    _log.i(v ? 'connected as player ${slot + 1}' : 'disconnected ($why)');
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _log.i('disposing');
    _disposed = true;
    _timer?.cancel();
    _reopenTimer?.cancel();
    _send(encodeBye());
    _sock?.close();
    super.dispose();
  }
}
