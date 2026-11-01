// Package hub tracks client sessions and maps each one to a virtual pad.
// A Hub is not safe for concurrent use: drive it from a single goroutine.
package hub

import (
	"crypto/subtle"
	"fmt"
	"io"
	"log/slog"
	"net/netip"
	"strings"
	"time"

	"xpadlink/proto"
	"xpadlink/vpad"
)

type Config struct {
	Token   string        // shared secret clients must present in hello
	MaxPads int           // max simultaneous clients
	Timeout time.Duration // drop a client after this much silence
	New     vpad.Factory

	// Announced to clients that broadcast a discover probe.
	Port     uint16
	Hostname string
	Log      *slog.Logger // nil discards
}

type session struct {
	pad      vpad.Pad
	slot     byte
	name     string
	lastSeen time.Time
	lastSeq  uint16
	haveSeq  bool
}

// discoverMinGap limits announce replies per source address, so the server
// can't be used to amplify traffic at a spoofed address.
const discoverMinGap = 200 * time.Millisecond

type Hub struct {
	cfg          Config
	sessions     map[netip.AddrPort]*session
	lastDiscover map[netip.Addr]time.Time
}

func New(cfg Config) *Hub {
	if cfg.Log == nil {
		cfg.Log = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	if cfg.MaxPads <= 0 {
		cfg.MaxPads = 4
	}
	if cfg.Timeout <= 0 {
		cfg.Timeout = 3 * time.Second
	}
	cfg.Hostname = clean(cfg.Hostname)
	return &Hub{
		cfg:          cfg,
		sessions:     map[netip.AddrPort]*session{},
		lastDiscover: map[netip.Addr]time.Time{},
	}
}

// Handle processes one datagram and returns an optional reply for the sender.
func (h *Hub) Handle(pkt []byte, from netip.AddrPort, now time.Time) []byte {
	if len(pkt) < 2 || pkt[0] != proto.Magic {
		h.cfg.Log.Debug("ignored packet", "from", from, "len", len(pkt))
		return nil
	}
	switch pkt[1] {
	case proto.TypeHello:
		return h.hello(pkt, from, now)
	case proto.TypeState:
		s := h.sessions[from]
		if s == nil {
			return []byte{proto.Magic, proto.TypeNeedHello}
		}
		st, err := proto.ParseState(pkt)
		if err != nil {
			return nil
		}
		if s.haveSeq && !proto.Newer(st.Seq, s.lastSeq) {
			return nil // stale or duplicate (UDP reordering)
		}
		s.lastSeq, s.haveSeq, s.lastSeen = st.Seq, true, now
		if err := s.pad.Update(st); err != nil {
			h.cfg.Log.Error("pad update failed", "from", from, "player", s.slot+1, "err", err)
		}
	case proto.TypeBye:
		h.drop(from, "bye")
	case proto.TypeDiscover:
		return h.discover(from, now)
	}
	return nil
}

func (h *Hub) discover(from netip.AddrPort, now time.Time) []byte {
	ip := from.Addr().Unmap()
	if last, ok := h.lastDiscover[ip]; ok && now.Sub(last) < discoverMinGap {
		h.cfg.Log.Debug("discover rate limited", "from", from)
		return nil
	}
	h.lastDiscover[ip] = now
	h.cfg.Log.Info("discover probe answered", "from", from)
	return proto.MarshalAnnounce(h.cfg.Port, h.cfg.Hostname)
}

func (h *Hub) hello(pkt []byte, from netip.AddrPort, now time.Time) []byte {
	token, name, err := proto.ParseHello(pkt)
	if err != nil {
		h.cfg.Log.Debug("bad hello packet", "from", from, "err", err)
		return nil
	}
	if subtle.ConstantTimeCompare([]byte(token), []byte(h.cfg.Token)) != 1 {
		h.cfg.Log.Warn("bad token", "from", from)
		return []byte{proto.Magic, proto.TypeReject, proto.RejectBadToken}
	}
	s := h.sessions[from]
	if s == nil {
		slot, ok := h.freeSlot()
		if !ok {
			h.cfg.Log.Warn("rejected, no free slot", "from", from, "max", h.cfg.MaxPads)
			return []byte{proto.Magic, proto.TypeReject, proto.RejectFull}
		}
		name = clean(name)
		pad, err := h.cfg.New(fmt.Sprintf("XPadLink - Xbox Controller %d (%s)", slot+1, name))
		if err != nil {
			h.cfg.Log.Error("create pad failed", "from", from, "err", err)
			return nil
		}
		s = &session{pad: pad, slot: slot, name: name}
		h.sessions[from] = s
		h.cfg.Log.Info("client joined", "from", from, "player", slot+1, "name", name)
	}
	s.lastSeen = now
	return []byte{proto.Magic, proto.TypeAck, s.slot}
}

// Reap drops clients that went silent.
func (h *Hub) Reap(now time.Time) {
	for addr, s := range h.sessions {
		if now.Sub(s.lastSeen) > h.cfg.Timeout {
			h.drop(addr, "timeout")
		}
	}
	for ip, t := range h.lastDiscover {
		if now.Sub(t) > time.Minute {
			delete(h.lastDiscover, ip)
		}
	}
}

func (h *Hub) Close() {
	for addr := range h.sessions {
		h.drop(addr, "shutdown")
	}
}

func (h *Hub) Len() int { return len(h.sessions) }

func (h *Hub) drop(addr netip.AddrPort, why string) {
	s := h.sessions[addr]
	if s == nil {
		return
	}
	s.pad.Close()
	delete(h.sessions, addr)
	h.cfg.Log.Info("client left", "from", addr, "player", s.slot+1, "name", s.name, "reason", why)
}

func (h *Hub) freeSlot() (byte, bool) {
	used := map[byte]bool{}
	for _, s := range h.sessions {
		used[s.slot] = true
	}
	for i := 0; i < h.cfg.MaxPads; i++ {
		if !used[byte(i)] {
			return byte(i), true
		}
	}
	return 0, false
}

func clean(name string) string {
	name = strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return -1
		}
		return r
	}, name)
	if len(name) > 32 {
		name = name[:32]
	}
	if name == "" {
		name = "phone"
	}
	return name
}
