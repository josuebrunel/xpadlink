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
