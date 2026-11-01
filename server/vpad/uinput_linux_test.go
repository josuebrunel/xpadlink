package vpad

import (
	"testing"
	"unsafe"
)

// The kernel's struct input_event is timeval + 8 bytes; 24 bytes on 64-bit.
func TestInputEventSize(t *testing.T) {
	if got, want := unsafe.Sizeof(inputEvent{}), unsafe.Sizeof(uintptr(0))*2+8; got != want {
		t.Fatalf("inputEvent is %d bytes, want %d", got, want)
	}
}
