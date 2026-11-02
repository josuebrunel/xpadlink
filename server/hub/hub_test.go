package hub

import (
	"net/netip"
	"testing"
	"time"

	"xpadlink/proto"
	"xpadlink/vpad"
)

type fakePad struct {
	updates []proto.State
	closed  bool
}

func (f *fakePad) Update(s proto.State) error { f.updates = append(f.updates, s); return nil }
func (f *fakePad) Close() error               { f.closed = true; return nil }

func newTestHub(max int) (*Hub, *[]*fakePad) {
	var pads []*fakePad
	h := New(Config{
		Token: "secret", MaxPads: max, Timeout: time.Second,
		Port: 9777, Hostname: "testhost",
		New: vpad.Factory(func(string) (vpad.Pad, error) {
			p := &fakePad{}
			pads = append(pads, p)
			return p, nil
		}),
	})
	return h, &pads
}

var (
	addrA = netip.MustParseAddrPort("10.0.0.2:5000")
	addrB = netip.MustParseAddrPort("10.0.0.3:5000")
	t0    = time.Unix(1000, 0)
)

func TestHelloAuthAndAck(t *testing.T) {
	h, pads := newTestHub(2)
	r := h.Handle(proto.MarshalHello("wrong", "x"), addrA, t0)
	if len(r) != 3 || r[1] != proto.TypeReject || r[2] != proto.RejectBadToken || h.Len() != 0 {
		t.Fatalf("bad token must be rejected without a session: %v", r)
	}
	r = h.Handle(proto.MarshalHello("secret", "pixel"), addrA, t0)
	if len(r) != 3 || r[1] != proto.TypeAck || r[2] != 0 {
		t.Fatalf("bad ack: %v", r)
	}
	// repeated hello keeps the same pad
	h.Handle(proto.MarshalHello("secret", "pixel"), addrA, t0)
	if len(*pads) != 1 {
		t.Fatalf("pads created: %d", len(*pads))
	}
}

func TestStateFlowAndStale(t *testing.T) {
	h, pads := newTestHub(2)
	h.Handle(proto.MarshalHello("secret", "p"), addrA, t0)
	h.Handle(proto.State{Seq: 5, LX: 100}.Marshal(), addrA, t0)
	h.Handle(proto.State{Seq: 4, LX: 999}.Marshal(), addrA, t0) // stale
	h.Handle(proto.State{Seq: 6, LX: 200}.Marshal(), addrA, t0)
	u := (*pads)[0].updates
	if len(u) != 2 || u[0].LX != 100 || u[1].LX != 200 {
		t.Fatalf("updates: %+v", u)
	}
}

func TestSeqWraparound(t *testing.T) {
	h, pads := newTestHub(1)
	h.Handle(proto.MarshalHello("secret", "p"), addrA, t0)
	h.Handle(proto.State{Seq: 65535}.Marshal(), addrA, t0)
	h.Handle(proto.State{Seq: 0, LX: 7}.Marshal(), addrA, t0)
	if u := (*pads)[0].updates; len(u) != 2 || u[1].LX != 7 {
		t.Fatalf("wraparound dropped: %+v", u)
	}
}

func TestUnknownSenderGetsNeedHello(t *testing.T) {
	h, _ := newTestHub(1)
	r := h.Handle(proto.State{}.Marshal(), addrA, t0)
	if len(r) != 2 || r[1] != proto.TypeNeedHello {
		t.Fatalf("reply: %v", r)
	}
}

func TestMaxPadsAndSlotReuse(t *testing.T) {
	h, _ := newTestHub(1)
	h.Handle(proto.MarshalHello("secret", "a"), addrA, t0)
	if r := h.Handle(proto.MarshalHello("secret", "b"), addrB, t0); len(r) != 3 || r[1] != proto.TypeReject || r[2] != proto.RejectFull {
		t.Fatalf("second client must be rejected as full: %v", r)
	}
	h.Handle([]byte{proto.Magic, proto.TypeBye}, addrA, t0)
	if r := h.Handle(proto.MarshalHello("secret", "b"), addrB, t0); len(r) != 3 || r[2] != 0 {
		t.Fatalf("slot not reused: %v", r)
	}
}

func TestReap(t *testing.T) {
	h, pads := newTestHub(1)
	h.Handle(proto.MarshalHello("secret", "a"), addrA, t0)
	h.Reap(t0.Add(500 * time.Millisecond))
	if h.Len() != 1 {
		t.Fatal("reaped too early")
	}
	h.Reap(t0.Add(2 * time.Second))
	if h.Len() != 0 || !(*pads)[0].closed {
		t.Fatal("expected pad closed after timeout")
	}
}

func TestDiscoverAnnouncesWithoutToken(t *testing.T) {
	h, _ := newTestHub(1)
	r := h.Handle(proto.MarshalDiscover(), addrA, t0)
	port, host, err := proto.ParseAnnounce(r)
	if err != nil || port != 9777 || host != "testhost" {
		t.Fatalf("announce: %v %d %q", err, port, host)
	}
	if h.Len() != 0 {
		t.Fatal("discover must not create a session")
	}
}

func TestDiscoverRateLimit(t *testing.T) {
	h, _ := newTestHub(1)
	h.Handle(proto.MarshalDiscover(), addrA, t0)
	if r := h.Handle(proto.MarshalDiscover(), addrA, t0.Add(50*time.Millisecond)); r != nil {
		t.Fatal("probe inside the gap must be dropped")
	}
	if r := h.Handle(proto.MarshalDiscover(), addrB, t0.Add(50*time.Millisecond)); r == nil {
		t.Fatal("other sources are limited independently")
	}
	if r := h.Handle(proto.MarshalDiscover(), addrA, t0.Add(300*time.Millisecond)); r == nil {
		t.Fatal("probe after the gap must be answered")
	}
}

type rumblePad struct {
	fakePad
	fn func(strong, weak, ms uint16)
}

func (r *rumblePad) OnRumble(fn func(strong, weak, ms uint16)) { r.fn = fn }

func TestRumbleIsSentToTheClient(t *testing.T) {
	var pad *rumblePad
	var sentTo netip.AddrPort
	var sent []byte
	h := New(Config{
		Token: "secret", MaxPads: 1, Timeout: time.Second,
		New:  vpad.Factory(func(string) (vpad.Pad, error) { pad = &rumblePad{}; return pad, nil }),
		Send: func(to netip.AddrPort, b []byte) { sentTo, sent = to, b },
	})
	h.Handle(proto.MarshalHello("secret", "p"), addrA, t0)
	if pad == nil || pad.fn == nil {
		t.Fatal("hub must register a rumble handler")
	}
	pad.fn(1000, 2000, 300)
	st, wk, ms, err := proto.ParseRumble(sent)
	if err != nil || sentTo != addrA || st != 1000 || wk != 2000 || ms != 300 {
		t.Fatalf("sent %v to %v: %d %d %d %v", sent, sentTo, st, wk, ms, err)
	}
}

type fakeSink struct {
	last    proto.Motion
	calls   int
	removed []byte
}

func (f *fakeSink) Update(_ byte, _ proto.State, m proto.Motion) { f.last, f.calls = m, f.calls+1 }
func (f *fakeSink) Remove(slot byte)                             { f.removed = append(f.removed, slot) }

func TestMotionForwardedAndExpires(t *testing.T) {
	sink := &fakeSink{}
	h := New(Config{Token: "secret", Motion: sink, New: vpad.Factory(func(string) (vpad.Pad, error) { return &fakePad{}, nil })})
	if r := h.Handle(proto.Motion{Seq: 1}.Marshal(), addrA, t0); len(r) != 2 || r[1] != proto.TypeNeedHello {
		t.Fatalf("motion from unknown address should ask for hello: %v", r)
	}
	h.Handle(proto.MarshalHello("secret", "p"), addrA, t0)
	m := proto.Motion{Seq: 2, Gyro: [3]float32{0, 90, 0}}
	h.Handle(m.Marshal(), addrA, t0)
	if sink.last != m {
		t.Fatalf("sink got %+v", sink.last)
	}
	h.Handle(proto.Motion{Seq: 1}.Marshal(), addrA, t0) // stale
	if sink.last != m {
		t.Fatal("stale motion applied")
	}
	// A state packet long after the last motion must not replay the old tilt.
	h.Handle(proto.State{Seq: 1}.Marshal(), addrA, t0.Add(time.Second))
	if sink.last != (proto.Motion{}) {
		t.Fatalf("expired motion still applied: %+v", sink.last)
	}
	h.Close()
	if len(sink.removed) != 1 || sink.removed[0] != 0 {
		t.Fatalf("slot not released: %v", sink.removed)
	}
}
