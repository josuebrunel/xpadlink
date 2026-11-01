// XPadLink wire format. Keep in sync with server/proto/proto.go.
import 'dart:convert';
import 'dart:typed_data';

const int kMagic = 0xA7;
const int kHello = 1;
const int kAck = 2;
const int kNeedHello = 3;
const int kState = 4;
const int kBye = 5;
const int kDiscover = 6;
const int kAnnounce = 7;
const int kReject = 8;
const int kRejectBadToken = 1;
const int kRejectFull = 2;
const int kStateLen = 18;

/// Button bits, Xbox 360 layout. Same values in proto.go and MainActivity.kt.
class Btn {
  static const a = 1 << 0;
  static const b = 1 << 1;
  static const x = 1 << 2;
  static const y = 1 << 3;
  static const lb = 1 << 4;
  static const rb = 1 << 5;
  static const back = 1 << 6;
  static const start = 1 << 7;
  static const guide = 1 << 8;
  static const l3 = 1 << 9;
  static const r3 = 1 << 10;
  static const dUp = 1 << 11;
  static const dDown = 1 << 12;
  static const dLeft = 1 << 13;
  static const dRight = 1 << 14;
}

/// Sticks are int16 (y positive is down), triggers are 0..255.
class PadState {
  int buttons = 0;
  int lx = 0, ly = 0, rx = 0, ry = 0;
  int lt = 0, rt = 0;

  void setButton(int bit, bool down) {
    buttons = down ? (buttons | bit) : (buttons & ~bit);
  }

  PadState clone() => PadState()
    ..buttons = buttons
    ..lx = lx
    ..ly = ly
    ..rx = rx
    ..ry = ry
    ..lt = lt
    ..rt = rt;

  bool sameAs(PadState o) =>
      buttons == o.buttons &&
      lx == o.lx &&
      ly == o.ly &&
      rx == o.rx &&
      ry == o.ry &&
      lt == o.lt &&
      rt == o.rt;
}

/// Maps -1..1 to int16.
int axisToInt16(double v) => (v.clamp(-1.0, 1.0) * 32767).round();

Uint8List encodeState(int seq, PadState s) {
  final b = ByteData(kStateLen);
  b.setUint8(0, kMagic);
  b.setUint8(1, kState);
  b.setUint16(2, seq & 0xFFFF, Endian.little);
  b.setUint32(4, s.buttons, Endian.little);
  b.setInt16(8, s.lx, Endian.little);
  b.setInt16(10, s.ly, Endian.little);
  b.setInt16(12, s.rx, Endian.little);
  b.setInt16(14, s.ry, Endian.little);
  b.setUint8(16, s.lt);
  b.setUint8(17, s.rt);
  return b.buffer.asUint8List();
}

Uint8List encodeHello(String token, String name) => Uint8List.fromList(
    [kMagic, kHello, ...utf8.encode(token), 0, ...utf8.encode(name)]);

Uint8List encodeBye() => Uint8List.fromList([kMagic, kBye]);

Uint8List encodeDiscover() => Uint8List.fromList([kMagic, kDiscover]);

/// Parses a server announce: port u16 LE, then the hostname. Null if malformed.
({int port, String hostname})? parseAnnounce(Uint8List b) {
  if (b.length < 4 || b[0] != kMagic || b[1] != kAnnounce) return null;
  final port = b[2] | (b[3] << 8);
  return (port: port, hostname: utf8.decode(b.sublist(4), allowMalformed: true));
}
