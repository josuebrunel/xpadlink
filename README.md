# XPadLink

Use an Android phone, or a gamepad plugged into the phone, as a gamepad on Linux.

```
phone (Flutter)  --UDP, 18 bytes @ 60 Hz-->  xpadlinkd (Go)  --/dev/uinput-->  virtual Xbox 360 pad
```

The virtual device reports Xbox 360 vendor/product IDs (045e:028e), so SDL, Steam, Proton and
RetroArch recognise it without mapping. One virtual pad is created per phone (up to 4).

## Server (Linux)

No dependencies, standard library only. Needs Go 1.22+.

```sh
cd server
go build -o xpadlinkd ./cmd/xpadlinkd

# one-time: uinput access
sudo modprobe uinput
echo uinput | sudo tee /etc/modules-load.d/uinput.conf
sudo cp ../99-xpadlink-uinput.rules /etc/udev/rules.d/
sudo udevadm control --reload && sudo udevadm trigger
sudo usermod -aG input $USER        # log out and in again

./xpadlinkd                          # prints a random token and your LAN address
```

Open UDP port 9777 in your firewall if you have one (`sudo ufw allow 9777/udp`).

Flags: `-listen :9777`, `-token <secret>`, `-max 4`, `-timeout 3s`, `-dry` (log instead of using uinput), `-log-level debug|info|warn|error` (structured `slog` output; `-dry` defaults to debug).

### Test without the phone

```sh
./xpadlinkd -token abc &
go run ./cmd/xpadsim -token abc -for 20s     # circles the left stick, taps A
evtest                                       # pick "XPadLink - Xbox Controller 1 (xpadsim)"
```

`go test ./...` covers the protocol and session logic.

## Android app

Needs the Flutter SDK and a phone with USB debugging.

```sh
cd app
./setup.sh                  # flutter create + copies our code + INTERNET permission
cd xpadlink_app && flutter run
```

The app scans the local subnet on start (UDP broadcast) and lists nearby servers; tap one, then enter
the token printed by `xpadlinkd`. Discovery only works within one subnet, so you can also type
`<server-ip>:9777` and save servers for later.

- Touch mode: on-screen sticks, D-pad, ABXY, LB/RB, LT/RT (digital), Back/Guide/Start.
- Physical pad: plug in or pair a controller, press a button. `MainActivity.kt` intercepts the
  key and motion events (Flutter does not deliver stick axes), the touch overlay hides, and the
  controller state is forwarded instead.

## Wire format

All little endian. Every packet starts with magic `0xA7`, then a type byte.

| Type | Dir | Payload |
|------|-----|---------|
| 1 hello | C to S | `token \0 name`, sent every 1 s (also the keepalive) |
| 2 ack | S to C | slot (0 based) |
| 3 need-hello | S to C | none, sent when state arrives from an unknown address |
| 4 state | C to S | seq u16, buttons u32, lx ly rx ry i16, lt rt u8 (18 bytes total) |
| 5 bye | C to S | none |
| 6 discover | C to S | none, broadcast to `255.255.255.255:9777` |
| 7 announce | S to C | port u16, hostname (no token) |

State is sent whenever it changes and at least every 100 ms, so a dropped packet heals fast.
Stale or duplicate sequence numbers are discarded. A client silent for 3 s loses its device.

## Known gaps

- Not compiled on a real device or against real `/dev/uinput` yet.
- No rumble, no gyro..
- LAN only, no encryption. The token only stops other people on the network from injecting input.
- Server assumes a 64-bit or 32-bit Linux where `struct input_event` matches Go's `syscall.Timeval`.
- Controllers that put the right stick on RX/RY instead of Z/RZ need a small mapping change in `MainActivity.kt`.
