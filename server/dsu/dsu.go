// Package dsu serves controller motion to Cemu (and other emulators) using the
// Cemuhook DSU protocol, https://v1993.github.io/cemuhook-protocol/.
// Cemu has no way to read a gyro from an evdev pad, so motion travels this way.
package dsu

import (
	"encoding/binary"
	"hash/crc32"
	"log/slog"
	"math"
	"net"
	"net/netip"
	"sync"
	"time"

	"xpadlink/proto"
)

const (
	version = 1001

	msgVersion = 0x100000
	msgPorts   = 0x100001
	msgData    = 0x100002

	headerLen = 16
	maxSlots  = 4

	// Clients re-request pad data constantly; one that goes quiet is gone.
	subTimeout = 5 * time.Second
)

type slotState struct {
	on     bool
	packet uint32
	st     proto.State
	motion proto.Motion
}

type sub struct {
	seen time.Time
	slot int // -1 for all slots
}

// Server is safe for concurrent use.
type Server struct {
	conn *net.UDPConn
	id   uint32
	log  *slog.Logger
	t0   time.Time

	mu    sync.Mutex
	slots [maxSlots]slotState
	subs  map[netip.AddrPort]sub
}

// Listen starts serving on addr (use a loopback address unless Cemu runs elsewhere).
func Listen(addr string, log *slog.Logger) (*Server, error) {
	ua, err := net.ResolveUDPAddr("udp", addr)
	if err != nil {
		return nil, err
	}
	c, err := net.ListenUDP("udp", ua)
	if err != nil {
		return nil, err
	}
	s := &Server{conn: c, id: uint32(time.Now().UnixNano()), log: log, t0: time.Now(), subs: map[netip.AddrPort]sub{}}
	go s.serve()
	return s, nil
}

func (s *Server) Addr() net.Addr { return s.conn.LocalAddr() }

func (s *Server) Close() error { return s.conn.Close() }

// Update records the latest state and motion of a pad and pushes it to subscribers.
func (s *Server) Update(slot byte, st proto.State, m proto.Motion) {
	if int(slot) >= maxSlots {
		return
	}
	s.mu.Lock()
	sl := &s.slots[slot]
	sl.on, sl.st, sl.motion = true, st, m
	sl.packet++
	pkt := s.padData(int(slot))
	var to []netip.AddrPort
	now := time.Now()
	for a, sb := range s.subs {
		if now.Sub(sb.seen) > subTimeout {
			delete(s.subs, a)
			continue
		}
		if sb.slot < 0 || sb.slot == int(slot) {
			to = append(to, a)
		}
	}
	s.mu.Unlock()
	for _, a := range to {
		s.conn.WriteToUDPAddrPort(pkt, a)
	}
}

// Remove marks a slot as disconnected.
func (s *Server) Remove(slot byte) {
	if int(slot) >= maxSlots {
		return
	}
	s.mu.Lock()
	s.slots[slot] = slotState{}
	s.mu.Unlock()
}

func (s *Server) serve() {
	buf := make([]byte, 1024)
	for {
		n, from, err := s.conn.ReadFromUDPAddrPort(buf)
		if err != nil {
			if opErr, ok := err.(*net.OpError); ok && !opErr.Temporary() {
				return
			}
			continue
		}
		s.handle(buf[:n], from)
	}
}

func (s *Server) handle(b []byte, from netip.AddrPort) {
	if len(b) < headerLen+4 || string(b[:4]) != "DSUC" {
		return
	}
	plen := int(binary.LittleEndian.Uint16(b[6:]))
	if headerLen+plen > len(b) || plen < 4 {
		return
	}
	b = b[:headerLen+plen]
	want := binary.LittleEndian.Uint32(b[8:])
	c := make([]byte, len(b))
	copy(c, b)
	binary.LittleEndian.PutUint32(c[8:], 0)
	if crc32.ChecksumIEEE(c) != want {
		s.log.Debug("dsu: bad crc", "from", from)
		return
	}
	body := b[headerLen+4:]
	switch binary.LittleEndian.Uint32(b[headerLen:]) {
	case msgVersion:
		s.send(from, msgVersion, binary.LittleEndian.AppendUint16(nil, version))
	case msgPorts:
		if len(body) < 4 {
			return
		}
		count := int(int32(binary.LittleEndian.Uint32(body)))
		if count < 0 || count > maxSlots || len(body) < 4+count {
			return
		}
		s.mu.Lock()
		for _, id := range body[4 : 4+count] {
			if int(id) < maxSlots {
				s.send(from, msgPorts, append(s.info(int(id)), 0))
			}
		}
		s.mu.Unlock()
	case msgData:
		if len(body) < 8 {
			return
		}
		sb := sub{seen: time.Now(), slot: -1}
		if body[0]&1 != 0 {
			sb.slot = int(body[1])
		}
		s.mu.Lock()
		if _, known := s.subs[from]; !known {
			s.log.Info("dsu: client subscribed", "from", from, "slot", sb.slot)
		}
		s.subs[from] = sb
		s.mu.Unlock()
	}
}

// info is the 11 byte controller description shared by two messages. Caller holds mu.
func (s *Server) info(slot int) []byte {
	b := make([]byte, 11)
	b[0] = byte(slot)
	if s.slots[slot].on {
		b[1], b[2], b[3], b[10] = 2, 2, 2, 5 // connected, full gyro, bluetooth, battery full
	}
	return b
}

// padData builds a whole controller data packet. Caller holds mu.
func (s *Server) padData(slot int) []byte {
	sl := &s.slots[slot]
	p := make([]byte, 0, 80)
	p = append(p, s.info(slot)...)
	p = append(p, 1)
	p = binary.LittleEndian.AppendUint32(p, sl.packet)
	p = append(p, dsuButtons(sl.st)...)
	p = append(p, 0, 0) // home, touch button
	p = append(p, stick(int(sl.st.LX)), stick(-int(sl.st.LY)), stick(int(sl.st.RX)), stick(-int(sl.st.RY)))
	p = append(p, analog(sl.st)...)
	p = append(p, make([]byte, 12)...) // touches
	p = binary.LittleEndian.AppendUint64(p, uint64(time.Since(s.t0).Microseconds()))
	// Cemu treats DSU motion like SDL gamepad sensors: x right, y toward the top,
	// z toward the player, gyro counter-clockwise positive. That is the pad frame the
	// app already sends, so the values pass through untouched.
	for _, v := range append(sl.motion.Accel[:], sl.motion.Gyro[:]...) {
		p = binary.LittleEndian.AppendUint32(p, math.Float32bits(v))
	}
	return s.packet(msgData, p)
}

func (s *Server) send(to netip.AddrPort, typ uint32, payload []byte) {
	s.conn.WriteToUDPAddrPort(s.packet(typ, payload), to)
}

func (s *Server) packet(typ uint32, payload []byte) []byte {
	b := make([]byte, headerLen, headerLen+4+len(payload))
	copy(b, "DSUS")
	binary.LittleEndian.PutUint16(b[4:], version)
	binary.LittleEndian.PutUint16(b[6:], uint16(4+len(payload)))
	binary.LittleEndian.PutUint32(b[12:], s.id)
	b = binary.LittleEndian.AppendUint32(b, typ)
	b = append(b, payload...)
	binary.LittleEndian.PutUint32(b[8:], crc32.ChecksumIEEE(b))
	return b
}

// stick maps -32768..32768 to 0..255 with 128 at rest.
func stick(v int) byte { return byte(min(v/256+128, 255)) }

// padButtons maps every pad button to its place in the DSU packet: byte 0 or 1 of
// the button bytes, and the bit inside it. Order follows the protocol, which also
// gives each of these (except the triggers) an analog pressure byte.
var padButtons = []struct {
	bit  uint32
	byte int // 0: dpad and system buttons, 1: face buttons and shoulders
	pos  uint
}{
	{proto.BtnDLeft, 0, 7}, {proto.BtnDDown, 0, 6}, {proto.BtnDRight, 0, 5}, {proto.BtnDUp, 0, 4},
	{proto.BtnStart, 0, 3}, {proto.BtnR3, 0, 2}, {proto.BtnL3, 0, 1}, {proto.BtnBack, 0, 0},
	{proto.BtnY, 1, 7}, {proto.BtnB, 1, 6}, {proto.BtnA, 1, 5}, {proto.BtnX, 1, 4},
	{proto.BtnRB, 1, 3}, {proto.BtnLB, 1, 2},
}

// analogOrder is the order of the analog pressure bytes: D-pad L, D, R, U, then Y, B, A, X, R1, L1.
var analogOrder = []uint32{
	proto.BtnDLeft, proto.BtnDDown, proto.BtnDRight, proto.BtnDUp,
	proto.BtnY, proto.BtnB, proto.BtnA, proto.BtnX, proto.BtnRB, proto.BtnLB,
}

func dsuButtons(st proto.State) []byte {
	var b [2]byte
	for _, pb := range padButtons {
		if st.Buttons&pb.bit != 0 {
			b[pb.byte] |= 1 << pb.pos
		}
	}
	// The triggers are analog on the pad but digital bits here.
	if st.RT > 0 {
		b[1] |= 1 << 1
	}
	if st.LT > 0 {
		b[1] |= 1 << 0
	}
	return b[:]
}

func analog(st proto.State) []byte {
	b := make([]byte, 12)
	for i, bit := range analogOrder {
		if st.Buttons&bit != 0 {
			b[i] = 255
		}
	}
	b[10], b[11] = st.RT, st.LT
	return b
}
