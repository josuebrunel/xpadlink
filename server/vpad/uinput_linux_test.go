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

// The kernel ABI: on 64-bit, uinput_ff_upload is 104 bytes and the ioctl
// numbers below come from linux/uinput.h.
func TestFFStructLayout(t *testing.T) {
	if unsafe.Sizeof(uintptr(0)) != 8 {
		t.Skip("64-bit layout only")
	}
	if got := unsafe.Sizeof(kffEffect{}); got != 48 {
		t.Fatalf("ff_effect is %d bytes, want 48", got)
	}
	if got := unsafe.Sizeof(ffUpload{}); got != 104 {
		t.Fatalf("uinput_ff_upload is %d bytes, want 104", got)
	}
	if uiBeginFFUpload != 0xc06855c8 || uiEndFFUpload != 0x406855c9 {
		t.Fatalf("upload ioctls: %#x %#x", uiBeginFFUpload, uiEndFFUpload)
	}
	if uiBeginFFErase != 0xc00c55ca || uiEndFFErase != 0x400c55cb {
		t.Fatalf("erase ioctls: %#x %#x", uiBeginFFErase, uiEndFFErase)
	}
}
