import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'link.dart';
import 'log.dart';
import 'protocol.dart';

/// Client over Wi-Fi (UDP) or Bluetooth. UI code mutates [state]; a 60 Hz timer sends it when it changed
/// and at least every 100 ms otherwise, so a lost packet heals quickly.
class PadClient extends ChangeNotifier {
  final PadState state = PadState();

  static final _log = Log('client');

  bool connected = false;

  /// Round trip of the last hello and its ack, in ms. Null until measured.
  int? rttMs;

  /// True when the server is reached over Bluetooth.
  bool get bluetooth => _btAddress != null;

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

  PadLink? _link;
  InternetAddress? _host;
  String? _btAddress; // set when the server is a paired PC, else UDP
  int _port = 9777;
  String _token = '';
  String _name = 'phone';
  Timer? _timer;
  int _seq = 0;
  PadState _lastSent = PadState();
  bool _disposed = false;

  // Link recovery: reopen with backoff after a network blip.
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

  /// [host] is "bt:AA:BB:CC:DD:EE:FF" for a paired PC over Bluetooth, otherwise
  /// a Wi-Fi host name or IP and [port].
  Future<void> start(String host, int port, String token, String name) async {
    _log.i('starting, server=$host:$port name=$name');
    _port = port;
    _token = token;
    _name = name;
    if (host.startsWith('bt:')) {
      _btAddress = host.substring(3);
    } else {
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
    }
    try {
      await _openLink();
    } catch (e, st) {
      _log.e('link open failed', e, st);
      rethrow;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  /// Opens the link (UDP socket or Bluetooth connection).
  Future<void> _openLink() async {
    final bt = _btAddress;
    final PadLink l = bt != null ? BtLink(bt) : UdpLink(_host!, _port, _localPort);
    l
      ..onPacket = ((b) => _onPacket(l, b))
      ..onBroken = ((why) => _linkBroken(l, why));
    await l.open();
    if (l is UdpLink) _localPort = l.localPort;
    _link = l;
  }

  /// 500 ms doubling per failed attempt, capped at 5 s.
  int _backoffMs() => (500 << _reopenAttempts.clamp(0, 4)).clamp(500, 5000);

  /// The link died (Wi-Fi dropped, Bluetooth lost): drop it and retry with
  /// backoff. Events from an older link are ignored.
  void _linkBroken(PadLink l, String why) {
    if (_disposed || !identical(l, _link) || _reopening) return;
    _reopening = true;
    _link = null;
    l.close();
    _setConnected(false, 'link $why');
    final ms = _backoffMs();
    _log.w('link $why, reopening in $ms ms (attempt ${_reopenAttempts + 1})');
    _reopenTimer = Timer(Duration(milliseconds: ms), _reopen);
  }

  Future<void> _reopen() async {
    if (_disposed) return;
    try {
      await _openLink();
      _reopening = false;
      _lastHello = _epoch; // say hello right away
      _log.i('link reopened');
    } catch (e) {
      _reopenAttempts++;
      final ms = _backoffMs();
      _log.e('reopen failed, retrying in $ms ms', e);
      _reopenTimer = Timer(Duration(milliseconds: ms), _reopen);
    }
  }

  void _onPacket(PadLink l, Uint8List b) {
    if (!identical(l, _link)) return;
    if (b.length < 2 || b[0] != kMagic) return;
    if (b[1] == kAck && b.length >= 3) {
      final now = DateTime.now();
      final gap = now.difference(_lastAck).inMilliseconds;
      if (_lastAck != _epoch && gap > _maxAckGapMs) _maxAckGapMs = gap;
      _acks++;
      _lastAck = now;
      if (_lastHello != _epoch) {
        final rtt = now.difference(_lastHello).inMilliseconds;
        if (rtt >= 0 && rtt < 2000 && rtt != rttMs) {
          rttMs = rtt;
          if (!_disposed) notifyListeners();
        }
      }
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
    final l = _link;
    if (l == null) return; // reopening
    try {
      if (l.send(data)) {
        _zeroWrites = 0;
        return;
      }
      // Kernel send buffer full or no route: the datagram was dropped.
      _sendFailures++;
      _log.e('send dropped (0 bytes written)');
      if (++_zeroWrites >= 3) _linkBroken(l, 'stopped accepting data');
    } catch (e) {
      _sendFailures++;
      _log.e('send failed', e);
      _linkBroken(l, 'send failed');
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
    if (!v) rttMs = null;
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
    _link?.close();
    super.dispose();
  }
}
