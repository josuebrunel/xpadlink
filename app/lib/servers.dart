import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A server the user saved, identified by its "host:port" address.
class SavedServer {
  const SavedServer({
    required this.label,
    required this.address,
    required this.token,
  });

  final String label;
  final String address;
  final String token;

  Map<String, String> toJson() =>
      {'label': label, 'address': address, 'token': token};

  factory SavedServer.fromJson(Map<String, dynamic> j) => SavedServer(
        label: (j['label'] as String?) ?? '',
        address: j['address'] as String,
        token: (j['token'] as String?) ?? '',
      );
}

/// Persists saved servers as a JSON string list in SharedPreferences.
class ServerStore {
  static const _key = 'servers';

  Future<List<SavedServer>> load() async {
    final p = await SharedPreferences.getInstance();
    final out = <SavedServer>[];
    for (final raw in p.getStringList(_key) ?? const <String>[]) {
      try {
        out.add(SavedServer.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // Skip an entry that fails to parse rather than losing the whole list.
      }
    }
    return out;
  }

  /// Adds the server, or replaces the one with the same address.
  Future<List<SavedServer>> save(SavedServer s) async {
    final all = await load();
    final i = all.indexWhere((e) => e.address == s.address);
    if (i >= 0) {
      all[i] = s;
    } else {
      all.add(s);
    }
    await _write(all);
    return all;
  }

  Future<List<SavedServer>> remove(String address) async {
    final all = await load()
      ..removeWhere((e) => e.address == address);
    await _write(all);
    return all;
  }

  Future<void> _write(List<SavedServer> all) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, [for (final s in all) jsonEncode(s.toJson())]);
  }
}
