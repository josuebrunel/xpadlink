# XPadLink wire format

UDP (or Bluetooth, see below), little endian, default port 9777. Every packet starts with magic `0xA7`, then a type byte.

| Type | Name | Dir | Payload |
|------|------|-----|---------|
| 1 | hello | phone → PC | `token \0 name`. Sent every 1 s, doubles as keepalive |
| 2 | ack | PC → phone | slot (0 based) |
| 3 | need-hello | PC → phone | none. Sent when state arrives from an unknown address |
| 4 | state | phone → PC | 18 bytes, see below |
| 5 | bye | phone → PC | none |
| 6 | discover | phone → PC | none. Broadcast to `255.255.255.255:9777` |
| 7 | announce | PC → phone | port u16, hostname. Never contains the token |
| 8 | reject | PC → phone | reason: 1 wrong token, 2 server full. Sent in reply to hello |
| 9 | rumble | PC → phone | strong u16, weak u16, ms u16. ms 0 means until stopped, strong and weak 0 means stop |
| 10 | motion | phone → PC | 28 bytes, see below. Up to 60 Hz while motion is on |

## State packet (type 4)

| Offset | Size | Field |
|--------|------|-------|
| 0 | 1 | magic `0xA7` |
| 1 | 1 | type `4` |
| 2 | 2 | seq u16 |
| 4 | 4 | buttons u32 |
| 8 | 2 each | lx, ly, rx, ry (i16, y positive is down) |
| 16 | 1 each | lt, rt (u8, 0 to 255) |

Buttons (bit): A 0, B 1, X 2, Y 3, LB 4, RB 5, Back 6, Start 7, Guide 8, L3 9, R3 10,
D-pad up 11, down 12, left 13, right 14.

## Motion packet (type 10)

| Offset | Size | Field |
|--------|------|-------|
| 2 | 2 | seq u16 |
| 4 | 4 each | accel x, y, z (f32, g) |
| 16 | 4 each | gyro x, y, z (f32, deg/s) |

Axes are the pad frame: x right, y up the screen, z out of the screen, for a phone held landscape.
On a phone without a gyroscope the app computes the gyro values from successive rotation-vector samples; the packet is the same.
The server republishes them over the Cemuhook DSU protocol (UDP `127.0.0.1:26760`) unchanged. Cemu treats DSU motion like SDL gamepad sensors (x right, y toward the top, z toward the player, counter-clockwise positive), which is this frame. A sample older than 500 ms counts as zero.

## Bluetooth

The same packets also travel over a Bluetooth Classic RFCOMM stream, for phones that have no shared Wi-Fi with the PC.
The PC (Linux, BlueZ) registers a server profile with service UUID `6f1d8a52-3c1e-4b7a-9e0d-5a7c2f4b8d11`, so the phone finds the channel by UUID. The phone must be paired with the PC first, in the system settings.

A stream has no packet boundaries, so each packet is prefixed with its length as a u16. A length of 0 or above 512 is invalid: close the connection.

| Offset | Size | Field |
|--------|------|-------|
| 0 | 2 | length of the packet, u16 |
| 2 | length | the packet, exactly as over UDP |

A Bluetooth client is identified by the device address, so a reconnect finds its session and player slot. Discover and announce are not used. Everything else, including hello as keepalive and the 3 s timeout, is the same as over UDP.
Source of truth: `server/bt/bt.go` and `app/kotlin/BtLink.kt`.

## Rules

- The phone sends state when it changes and at least every 100 ms, so a lost packet heals fast.
- The server drops state with a stale or duplicate `seq` (wraparound aware).
- A client silent for 3 s loses its virtual pad.
- Discover replies are limited to one per 200 ms per source address.

Source of truth: `server/proto/proto.go` and `app/lib/protocol.dart`. Keep them in sync.
