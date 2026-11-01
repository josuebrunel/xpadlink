package proto

import "testing"

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
