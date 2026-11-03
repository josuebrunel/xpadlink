import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'log.dart';

/// A way to reach xpadlinkd: the same packets over UDP or Bluetooth.
abstract class PadLink {
  /// Called for each packet from the server.
  late void Function(Uint8List) onPacket;

  /// Called once when the link dies on its own (not after [close]).
  late void Function(String why) onBroken;

  Future<void> open();

  /// False if the packet was dropped. Throws if the link is gone.
  bool send(Uint8List data);

  void close();
}

/// Wi-Fi: one UDP socket. Prefers the previous local port, so the server still
/// sees the same address and keeps our session (and player slot).
class UdpLink extends PadLink {
  UdpLink(this.host, this.port, this.preferredPort);

  static final _log = Log('udp');

  final InternetAddress host;
  final int port;
  final int preferredPort;
  RawDatagramSocket? _sock;

  int get localPort => _sock?.port ?? 0;

  @override
  Future<void> open() async {
    RawDatagramSocket s;
    try {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, preferredPort);
    } on SocketException {
      if (preferredPort == 0) rethrow;
      _log.w('local port $preferredPort is taken, using a new one');
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }
    _sock = s;
    _log.i('socket bound on local port ${s.port}');
    s.listen(
      (e) {
        if (e != RawSocketEvent.read) return;
        for (var d = s.receive(); d != null; d = s.receive()) {
          onPacket(d.data);
        }
      },
      onError: (Object e, StackTrace st) {
        _log.e('socket error', e, st);
        onBroken('error');
      },
      onDone: () => onBroken('closed'),
    );
  }

  @override
  bool send(Uint8List data) {
    final s = _sock;
    if (s == null) return false;
    return s.send(data, host, port) > 0;
  }

  @override
  void close() {
    _sock?.close();
    _sock = null;
  }
}

/// Bluetooth: an RFCOMM connection to a paired PC, through MainActivity.
class BtLink extends PadLink {
  BtLink(this.address);

  static final _log = Log('bt');
  static const _method = MethodChannel('xpadlink/bt');
  static const _events = EventChannel('xpadlink/bt/rx');

  final String address;
  StreamSubscription<dynamic>? _sub;
  bool _closed = false;

  /// Paired devices, as (name, address).
  static Future<List<({String name, String address})>> paired() async {
    final list = await _method.invokeListMethod<Map>('paired') ?? const [];
    return [
      for (final d in list)
        (name: d['name'] as String, address: d['address'] as String),
    ];
  }

  @override
  Future<void> open() async {
    _sub = _events.receiveBroadcastStream().listen((e) {
      if (e is Uint8List) {
        onPacket(e);
      } else if (e == 'closed') {
        onBroken('closed');
      }
    }, onError: (Object e) => onBroken('error'));
    try {
      await _method.invokeMethod<void>('connect', {'address': address});
    } catch (e) {
      await _sub?.cancel();
      _sub = null;
      rethrow;
    }
    _log.i('connected to $address');
  }

  @override
  bool send(Uint8List data) {
    if (_closed) return false;
    _method.invokeMethod<void>('send', {'data': data}).catchError(
        (Object e) => _log.e('send failed', e));
    return true;
  }

  @override
  void close() {
    _closed = true;
    _sub?.cancel();
    _sub = null;
    _method.invokeMethod<void>('close').catchError((Object _) {});
  }
}
