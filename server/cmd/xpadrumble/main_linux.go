// xpadrumble plays a rumble effect on the XPadLink virtual pad, the way a game
// would. Use it to check that vibration reaches the phone:
//
//	xpadrumble              # finds the XPadLink pad itself
//	xpadrumble /dev/input/event21 -ms 1500
package main

import (
	"bufio"
	"flag"
	"fmt"
	"log"
	"os"
	"regexp"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

const (
	evFF     = 0x15
	ffRumble = 0x50
)

// Mirrors struct ff_effect (linux/input.h); see vpad/uinput_linux.go.
type ffEffect struct {
	Type            uint16
	ID              int16
	Direction       uint16
	TriggerButton   uint16
	TriggerInterval uint16
	ReplayLength    uint16
	ReplayDelay     uint16
	U               struct {
		Strong, Weak uint16
		_            [20]byte
		CustomData   uintptr
	}
}

type inputEvent struct {
	Time  syscall.Timeval
	Type  uint16
	Code  uint16
	Value int32
}

func ioc(dir, nr, size uintptr) uintptr { return dir<<30 | size<<16 | 'E'<<8 | nr }

// findPad returns the /dev/input/eventN of the first XPadLink pad.
func findPad() (string, error) {
	f, err := os.Open("/proc/bus/input/devices")
	if err != nil {
		return "", err
	}
	defer f.Close()
	event := regexp.MustCompile(`event\d+`)
	isPad := false
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		switch {
		case strings.HasPrefix(line, "N: "):
			isPad = strings.Contains(line, "XPadLink")
		case isPad && strings.HasPrefix(line, "H: "):
			if m := event.FindString(line); m != "" {
				return "/dev/input/" + m, nil
			}
		}
	}
	return "", fmt.Errorf("no XPadLink pad found: connect a phone first")
}

func main() {
	ms := flag.Uint("ms", 800, "rumble length in milliseconds")
	strong := flag.Uint("strong", 0xC000, "strong motor, 0 to 65535")
	weak := flag.Uint("weak", 0x4000, "weak motor, 0 to 65535")
	flag.Parse()

	path := flag.Arg(0)
	if path == "" {
		var err error
		if path, err = findPad(); err != nil {
			log.Fatal(err)
		}
	}
	fd, err := syscall.Open(path, syscall.O_RDWR, 0)
	if err != nil {
		log.Fatalf("open %s: %v", path, err)
	}
	defer syscall.Close(fd)

	e := ffEffect{Type: ffRumble, ID: -1, ReplayLength: uint16(*ms)}
	e.U.Strong, e.U.Weak = uint16(*strong), uint16(*weak)
	eviocsff := ioc(1, 0x80, unsafe.Sizeof(e))
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), eviocsff, uintptr(unsafe.Pointer(&e))); errno != 0 {
		log.Fatalf("upload effect (does the pad support force feedback?): %v", errno)
	}
	log.Printf("%s: uploaded effect %d, strong=%d weak=%d length=%dms", path, e.ID, *strong, *weak, *ms)

	play := inputEvent{Type: evFF, Code: uint16(e.ID), Value: 1}
	buf := unsafe.Slice((*byte)(unsafe.Pointer(&play)), unsafe.Sizeof(play))
	if _, err := syscall.Write(fd, buf); err != nil {
		log.Fatalf("play: %v", err)
	}
	log.Print("playing, your phone should vibrate")
	time.Sleep(time.Duration(*ms)*time.Millisecond + 300*time.Millisecond)

	id := int32(e.ID)
	eviocrmff := ioc(1, 0x81, 4)
	syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), eviocrmff, uintptr(id))
}
