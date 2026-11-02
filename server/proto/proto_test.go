package proto

import (
	"bytes"
	"testing"
)

func TestStateRoundTrip(t *testing.T) {
	in := State{Seq: 513, Buttons: BtnA | BtnDRight, LX: -32768, LY: 32767, RX: -1, RY: 1, LT: 255, RT: 3}
	out, err := ParseState(in.Marshal())
	if err != nil || out != in {
		t.Fatalf("got %+v err %v", out, err)
	}
	if len(in.Marshal()) != StateLen {
		t.Fatal("wrong length")
	}
}

func TestParseStateRejectsGarbage(t *testing.T) {
	if _, err := ParseState([]byte{1, 2, 3}); err == nil {
		t.Fatal("expected error")
	}
}

func TestHelloRoundTrip(t *testing.T) {
	tok, name, err := ParseHello(MarshalHello("abc123", "my phone"))
	if err != nil || tok != "abc123" || name != "my phone" {
		t.Fatalf("%q %q %v", tok, name, err)
	}
	tok, name, err = ParseHello(MarshalHello("", ""))
	if err != nil || tok != "" || name != "" {
		t.Fatalf("empty: %q %q %v", tok, name, err)
	}
}

func TestNewer(t *testing.T) {
	if !Newer(1, 0) || Newer(0, 1) || !Newer(0, 65535) || Newer(5, 5) {
		t.Fatal("Newer is wrong")
	}
}

func TestAnnounceRoundTrip(t *testing.T) {
	port, host, err := ParseAnnounce(MarshalAnnounce(9777, "my-pc"))
	if err != nil || port != 9777 || host != "my-pc" {
		t.Fatalf("%d %q %v", port, host, err)
	}
	if _, _, err := ParseAnnounce([]byte{Magic, TypeAnnounce, 1}); err == nil {
		t.Fatal("short announce must fail")
	}
}

func TestRumbleRoundTrip(t *testing.T) {
	st, wk, ms, err := ParseRumble(MarshalRumble(65535, 1234, 500))
	if err != nil || st != 65535 || wk != 1234 || ms != 500 {
		t.Fatalf("%d %d %d %v", st, wk, ms, err)
	}
	if _, _, _, err := ParseRumble([]byte{Magic, TypeRumble, 1}); err == nil {
		t.Fatal("short rumble must fail")
	}
}

func TestMotionRoundTrip(t *testing.T) {
	in := Motion{Seq: 65535, Accel: [3]float32{0.1, -1, 0.5}, Gyro: [3]float32{-90, 0, 360}}
	b := in.Marshal()
	if len(b) != MotionLen {
		t.Fatalf("len %d", len(b))
	}
	out, err := ParseMotion(b)
	if err != nil || out != in {
		t.Fatalf("got %+v %v", out, err)
	}
	if _, err := ParseMotion(b[:10]); err == nil {
		t.Error("short packet accepted")
	}
}

func TestReplyPackets(t *testing.T) {
	for name, tc := range map[string]struct {
		got  []byte
		want []byte
	}{
		"ack":       {MarshalAck(2), []byte{Magic, TypeAck, 2}},
		"needhello": {MarshalNeedHello(), []byte{Magic, TypeNeedHello}},
		"reject":    {MarshalReject(RejectFull), []byte{Magic, TypeReject, RejectFull}},
	} {
		if !bytes.Equal(tc.got, tc.want) {
			t.Errorf("%s: got % x, want % x", name, tc.got, tc.want)
		}
	}
}
