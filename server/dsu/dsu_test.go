package dsu

import (
	"encoding/binary"
	"hash/crc32"
	"io"
	"log/slog"
	"math"
	"net"
	"testing"
	"time"

	"xpadlink/proto"
)

func clientPacket(typ uint32, payload []byte) []byte {
	b := make([]byte, headerLen)
	copy(b, "DSUC")
	binary.LittleEndian.PutUint16(b[4:], version)
	binary.LittleEndian.PutUint16(b[6:], uint16(4+len(payload)))
	binary.LittleEndian.PutUint32(b[12:], 7)
	b = binary.LittleEndian.AppendUint32(b, typ)
	b = append(b, payload...)
	binary.LittleEndian.PutUint32(b[8:], crc32.ChecksumIEEE(b))
	return b
}

func checkServerPacket(t *testing.T, b []byte, typ uint32, total int) {
	t.Helper()
	if len(b) != total || string(b[:4]) != "DSUS" {
		t.Fatalf("got %d bytes %q, want %d bytes DSUS", len(b), b[:4], total)
	}
	if int(binary.LittleEndian.Uint16(b[6:])) != total-headerLen {
		t.Fatalf("length field %d, want %d", binary.LittleEndian.Uint16(b[6:]), total-headerLen)
	}
	want := binary.LittleEndian.Uint32(b[8:])
	c := append([]byte(nil), b...)
	binary.LittleEndian.PutUint32(c[8:], 0)
	if crc32.ChecksumIEEE(c) != want {
		t.Fatal("bad crc")
	}
	if got := binary.LittleEndian.Uint32(b[16:]); got != typ {
		t.Fatalf("type %#x, want %#x", got, typ)
	}
}

func TestHandshakeAndData(t *testing.T) {
	srv, err := Listen("127.0.0.1:0", slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}
	defer srv.Close()
	c, err := net.DialUDP("udp", nil, srv.Addr().(*net.UDPAddr))
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	buf := make([]byte, 256)
	read := func() []byte {
		c.SetReadDeadline(time.Now().Add(2 * time.Second))
		n, err := c.Read(buf)
		if err != nil {
			t.Fatal(err)
		}
		return buf[:n]
	}

	c.Write(clientPacket(msgVersion, nil))
	checkServerPacket(t, read(), msgVersion, 22)

	srv.Update(1, proto.State{}, proto.Motion{})
	c.Write(clientPacket(msgPorts, []byte{1, 0, 0, 0, 1}))
	p := read()
	checkServerPacket(t, p, msgPorts, 32)
	if p[20] != 1 || p[21] != 2 || p[22] != 2 {
		t.Fatalf("slot 1 should be connected with full gyro: % x", p[20:32])
	}

	c.Write(clientPacket(msgData, []byte{1, 1, 0, 0, 0, 0, 0, 0}))
	time.Sleep(100 * time.Millisecond)
	srv.Update(1,
		proto.State{Buttons: proto.BtnA, LX: 32767, LY: -32768},
		proto.Motion{Accel: [3]float32{0, 0, 1}, Gyro: [3]float32{0, 10, 0}})
	p = read()
	checkServerPacket(t, p, msgData, 100)
	if p[16+4+11+1+4+1]&(1<<5) == 0 {
		t.Error("A button not set")
	}
	if p[16+4+11+1+4+4] != 255 || p[16+4+11+1+4+5] != 255 {
		t.Errorf("sticks: lx=%d ly=%d, want 255 255", p[16+4+11+1+4+4], p[16+4+11+1+4+5])
	}
	f := func(off int) float32 { return math.Float32frombits(binary.LittleEndian.Uint32(p[off:])) }
	motion := 16 + 4 + 56 // accel x
	// accel z (out of the screen) becomes DSU y; gyro y (up the screen) becomes -z.
	if f(motion+4) != 1 || f(motion+12+8) != -10 {
		t.Errorf("motion mapping: accel y=%v gyro z=%v", f(motion+4), f(motion+12+8))
	}
}

func TestPhoneToDSURightHanded(t *testing.T) {
	x, y := phoneToDSU([3]float32{1, 0, 0}), phoneToDSU([3]float32{0, 1, 0})
	// cross(x, y) must equal the image of z.
	cross := [3]float32{x[1]*y[2] - x[2]*y[1], x[2]*y[0] - x[0]*y[2], x[0]*y[1] - x[1]*y[0]}
	if z := phoneToDSU([3]float32{0, 0, 1}); cross != z {
		t.Errorf("not right handed: %v vs %v", cross, z)
	}
}
