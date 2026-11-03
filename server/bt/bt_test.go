package bt

import (
	"bytes"
	"errors"
	"io"
	"testing"
)

func TestFrameRoundTrip(t *testing.T) {
	var buf bytes.Buffer
	a, b := []byte{0xA7, 4, 1, 2}, []byte{0xA7, 5}
	buf.Write(Frame(a))
	buf.Write(Frame(b))
	for _, want := range [][]byte{a, b} {
		got, err := ReadFrame(&buf)
		if err != nil || !bytes.Equal(got, want) {
			t.Fatalf("got %v, %v want %v", got, err, want)
		}
	}
	if _, err := ReadFrame(&buf); err != io.EOF {
		t.Fatalf("empty stream: %v", err)
	}
}

func TestReadFrameShortRead(t *testing.T) {
	f := Frame([]byte{1, 2, 3, 4})
	if _, err := ReadFrame(bytes.NewReader(f[:4])); !errors.Is(err, io.ErrUnexpectedEOF) {
		t.Fatalf("truncated payload: %v", err)
	}
	if _, err := ReadFrame(bytes.NewReader(f[:1])); !errors.Is(err, io.ErrUnexpectedEOF) {
		t.Fatalf("truncated header: %v", err)
	}
}

func TestReadFrameRejectsBadLengths(t *testing.T) {
	for _, n := range []int{0, MaxPacket + 1, 65535} {
		h := []byte{byte(n), byte(n >> 8)}
		if _, err := ReadFrame(bytes.NewReader(append(h, make([]byte, 600)...))); !errors.Is(err, ErrBadFrame) {
			t.Fatalf("len %d: %v", n, err)
		}
	}
	if _, err := ReadFrame(bytes.NewReader(Frame(make([]byte, MaxPacket)))); err != nil {
		t.Fatalf("max size must pass: %v", err)
	}
}
