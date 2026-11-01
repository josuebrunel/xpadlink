import 'dart:async';
import 'dart:io';

import 'log.dart';
import 'protocol.dart';

/// A server that answered a discover probe.
class FoundServer {
  const FoundServer(
      {required this.hostname, required this.host, required this.port});

  final String hostname;
  final String host;
  final int port;

  String get address => '$host:$port';
}

/// Finds xpadlinkd servers on the local subnet: broadcasts a discover probe
/// every 500 ms and collects the unicast announces. Works within one subnet
/// only, so manual entry stays available.
class Discovery {
  static final _log = Log('discovery');

  /// Scans for [duration]; [onFound] fires once per new server address.
  /// Throws if the socket cannot be opened.
  static Future<void> scan(
    void Function(FoundServer) onFound, {
    Duration duration = const Duration(seconds: 4),
  }) async {
    final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    sock.broadcastEnabled = true;
    final seen = <String>{};
    _log.i('scan started on local port ${sock.port}');

    final sub = sock.listen((e) {
      if (e != RawSocketEvent.read) return;
      for (var d = sock.receive(); d != null; d = sock.receive()) {
        final a = parseAnnounce(d.data);
        if (a == null) continue;
        final s = FoundServer(
            hostname: a.hostname, host: d.address.address, port: a.port);
        if (seen.add(s.address)) {
          _log.i('found ${s.hostname} at ${s.address}');
          onFound(s);
        }
      }
    }, onError: (Object e, StackTrace st) => _log.e('scan socket error', e, st));

    void probe() {
      try {
        sock.send(encodeDiscover(), InternetAddress('255.255.255.255'), 9777);
      } catch (e) {
        _log.e('discover send failed', e);
      }
    }

    probe();
    final timer = Timer.periodic(const Duration(milliseconds: 500), (_) => probe());
    await Future<void>.delayed(duration);
    timer.cancel();
    await sub.cancel();
    sock.close();
    _log.i('scan finished, ${seen.length} server(s)');
  }
}
