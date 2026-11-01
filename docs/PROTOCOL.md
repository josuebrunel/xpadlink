# XPadLink wire format

UDP, little endian, default port 9777. Every packet starts with magic `0xA7`, then a type byte.

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

## Rules

- The phone sends state when it changes and at least every 100 ms, so a lost packet heals fast.
- The server drops state with a stale or duplicate `seq` (wraparound aware).
- A client silent for 3 s loses its virtual pad.
- Discover replies are limited to one per 200 ms per source address.

Source of truth: `server/proto/proto.go` and `app/lib/protocol.dart`. Keep them in sync.
