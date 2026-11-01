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
	if r := h.Handle(proto.MarshalHello("wrong", "x"), addrA, t0); r != nil || h.Len() != 0 {
		t.Fatal("bad token must be ignored")
	}
	r := h.Handle(proto.MarshalHello("secret", "pixel"), addrA, t0)
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
	if r := h.Handle(proto.MarshalHello("secret", "b"), addrB, t0); r != nil {
		t.Fatal("second client must be rejected")
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
