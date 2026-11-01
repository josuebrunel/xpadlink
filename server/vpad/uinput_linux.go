package vpad

import (
	"encoding/binary"
	"fmt"
	"os"
	"syscall"
	"unsafe"

	"xpadlink/proto"
)

// uinput ioctls and event codes (linux/uinput.h, linux/input-event-codes.h).
const (
	uiDevCreate  = 0x5501
	uiDevDestroy = 0x5502
	uiSetEvBit   = 0x40045564
	uiSetKeyBit  = 0x40045565
	uiSetAbsBit  = 0x40045567
	uiSetFFBit   = 0x4004556b

	evSyn = 0x00
	evKey = 0x01
	evAbs = 0x03
	evFF  = 0x15

	// uinput event type and codes used for force feedback requests.
	evUinput   = 0x0101
	uiFFUpload = 1
	uiFFErase  = 2

	ffRumble = 0x50
	ffGain   = 0x60

	ffEffectsMax = 16

	absX, absY, absZ        = 0x00, 0x01, 0x02
	absRX, absRY, absRZ     = 0x03, 0x04, 0x05
	absHat0X, absHat0Y      = 0x10, 0x11
	absCnt                  = 64
	busUSB                  = 0x03
	xboxVendor, xboxProduct = 0x045e, 0x028e // looks like an Xbox 360 pad to SDL/Steam/xpad-aware games
)

var buttonMap = []struct {
	bit  uint32
	code uint16
}{
	{proto.BtnA, 0x130},     // BTN_SOUTH
	{proto.BtnB, 0x131},     // BTN_EAST
	{proto.BtnX, 0x133},     // BTN_NORTH
	{proto.BtnY, 0x134},     // BTN_WEST
	{proto.BtnLB, 0x136},    // BTN_TL
	{proto.BtnRB, 0x137},    // BTN_TR
	{proto.BtnBack, 0x13a},  // BTN_SELECT
	{proto.BtnStart, 0x13b}, // BTN_START
	{proto.BtnGuide, 0x13c}, // BTN_MODE
	{proto.BtnL3, 0x13d},    // BTN_THUMBL
	{proto.BtnR3, 0x13e},    // BTN_THUMBR
}

type inputEvent struct {
	Time  syscall.Timeval
	Type  uint16
	Code  uint16
	Value int32
}

// kffEffect and ffUpload mirror struct ff_effect and struct uinput_ff_upload
// from linux/input.h and linux/uinput.h. The union is sized by its largest
// member (ff_periodic_effect), so the layout follows the host pointer size.
type kffEffect struct {
	Type            uint16
	ID              int16
	Direction       uint16
	TriggerButton   uint16
	TriggerInterval uint16
	ReplayLength    uint16
	ReplayDelay     uint16
	U               struct {
		Waveform   uint16 // for FF_RUMBLE: strong_magnitude
		Period     uint16 // for FF_RUMBLE: weak_magnitude
		Magnitude  int16
		Offset     int16
		Phase      uint16
		Envelope   [4]uint16
		CustomLen  uint32
		CustomData uintptr
	}
}

type ffUpload struct {
	RequestID uint32
	Retval    int32
	Effect    kffEffect
	Old       kffEffect
}

type ffErase struct {
	RequestID uint32
	Retval    int32
	EffectID  uint32
}

// ioc builds an ioctl number (linux/ioctl.h): dir 1 = write, 3 = read+write.
func ioc(dir, nr, size uintptr) uintptr { return dir<<30 | size<<16 | 'U'<<8 | nr }

var (
	uiBeginFFUpload = ioc(3, 200, unsafe.Sizeof(ffUpload{}))
	uiEndFFUpload   = ioc(1, 201, unsafe.Sizeof(ffUpload{}))
	uiBeginFFErase  = ioc(3, 202, unsafe.Sizeof(ffErase{}))
	uiEndFFErase    = ioc(1, 203, unsafe.Sizeof(ffErase{}))
)

type uinputPad struct {
	f     *os.File
	rc    syscall.RawConn
	last  proto.State
	fresh bool
	ff    *ffTracker
}

// NewUinput is the real Factory. It needs write access to /dev/uinput.
func NewUinput(name string) (Pad, error) {
	// Read and write: games send force feedback requests back on this descriptor.
	f, err := os.OpenFile("/dev/uinput", os.O_RDWR|syscall.O_NONBLOCK, 0)
	if err != nil {
		return nil, fmt.Errorf("open /dev/uinput: %w (see README: modprobe uinput + udev rule)", err)
	}
	rc, err := f.SyscallConn()
	if err != nil {
		f.Close()
		return nil, err
	}
	p := &uinputPad{f: f, rc: rc, fresh: true, ff: newFFTracker()}
	fail := func(what string, err error) (Pad, error) {
		f.Close()
		return nil, fmt.Errorf("%s: %w", what, err)
	}

	for _, t := range []int{evKey, evAbs, evFF, evSyn} {
		if err := p.ioctl(uiSetEvBit, uintptr(t)); err != nil {
			return fail("UI_SET_EVBIT", err)
		}
	}
	if err := p.ioctl(uiSetFFBit, ffRumble); err != nil {
		return fail("UI_SET_FFBIT", err)
	}
	for _, b := range buttonMap {
		if err := p.ioctl(uiSetKeyBit, uintptr(b.code)); err != nil {
			return fail("UI_SET_KEYBIT", err)
		}
	}
	for _, a := range []int{absX, absY, absZ, absRX, absRY, absRZ, absHat0X, absHat0Y} {
		if err := p.ioctl(uiSetAbsBit, uintptr(a)); err != nil {
			return fail("UI_SET_ABSBIT", err)
		}
	}

	// Legacy uinput_user_dev layout (1116 bytes), works on every kernel.
	const (
		offID     = 80
		offFF     = 88
		offAbsMax = 92
		offAbsMin = offAbsMax + 4*absCnt
		offFuzz   = offAbsMin + 4*absCnt
		offFlat   = offFuzz + 4*absCnt
		size      = offFlat + 4*absCnt
	)
	dev := make([]byte, size)
	copy(dev[:79], name)
	binary.LittleEndian.PutUint32(dev[offFF:], ffEffectsMax)
	binary.LittleEndian.PutUint16(dev[offID:], busUSB)
	binary.LittleEndian.PutUint16(dev[offID+2:], xboxVendor)
	binary.LittleEndian.PutUint16(dev[offID+4:], xboxProduct)
	binary.LittleEndian.PutUint16(dev[offID+6:], 0x0110)
	setAbs := func(code int, min, max, fuzz, flat int32) {
		binary.LittleEndian.PutUint32(dev[offAbsMax+4*code:], uint32(max))
		binary.LittleEndian.PutUint32(dev[offAbsMin+4*code:], uint32(min))
		binary.LittleEndian.PutUint32(dev[offFuzz+4*code:], uint32(fuzz))
		binary.LittleEndian.PutUint32(dev[offFlat+4*code:], uint32(flat))
	}
	for _, a := range []int{absX, absY, absRX, absRY} {
		setAbs(a, -32768, 32767, 16, 128)
	}
	setAbs(absZ, 0, 255, 0, 0)
	setAbs(absRZ, 0, 255, 0, 0)
	setAbs(absHat0X, -1, 1, 0, 0)
	setAbs(absHat0Y, -1, 1, 0, 0)

	if _, err := f.Write(dev); err != nil {
		return fail("write uinput_user_dev", err)
	}
	if err := p.ioctl(uiDevCreate, 0); err != nil {
		return fail("UI_DEV_CREATE", err)
	}
	go p.readLoop()
	return p, nil
}

// OnRumble implements Rumbler.
func (p *uinputPad) OnRumble(fn func(strong, weak, ms uint16)) { p.ff.setHandler(fn) }

// readLoop serves the kernel's force feedback requests until the pad closes.
// Uploads and erases must be answered, or the game blocks on its ioctl.
func (p *uinputPad) readLoop() {
	size := int(unsafe.Sizeof(inputEvent{}))
	buf := make([]byte, size*8)
	for {
		n, err := p.f.Read(buf)
		if err != nil {
			return // closed
		}
		for off := 0; off+size <= n; off += size {
			ev := *(*inputEvent)(unsafe.Pointer(&buf[off]))
			switch {
			case ev.Type == evUinput && ev.Code == uiFFUpload:
				p.handleUpload(uint32(ev.Value))
			case ev.Type == evUinput && ev.Code == uiFFErase:
				p.handleErase(uint32(ev.Value))
			case ev.Type == evFF && ev.Code == ffGain:
				p.ff.setGain(uint32(ev.Value))
			case ev.Type == evFF:
				p.ff.play(int16(ev.Code), ev.Value)
			}
		}
	}
}

func (p *uinputPad) handleUpload(id uint32) {
	up := ffUpload{RequestID: id}
	if err := p.ioctlPtr(uiBeginFFUpload, unsafe.Pointer(&up)); err != nil {
		return
	}
	if up.Effect.Type == ffRumble {
		p.ff.upload(up.Effect.ID, ffEffect{
			strong: up.Effect.U.Waveform, weak: up.Effect.U.Period, length: up.Effect.ReplayLength,
		})
		up.Retval = 0
	} else {
		up.Retval = -int32(syscall.EINVAL) // only rumble is supported
	}
	p.ioctlPtr(uiEndFFUpload, unsafe.Pointer(&up))
}

func (p *uinputPad) handleErase(id uint32) {
	er := ffErase{RequestID: id}
	if err := p.ioctlPtr(uiBeginFFErase, unsafe.Pointer(&er)); err != nil {
		return
	}
	p.ff.erase(int16(er.EffectID))
	er.Retval = 0
	p.ioctlPtr(uiEndFFErase, unsafe.Pointer(&er))
}

func (p *uinputPad) ioctl(req, arg uintptr) error {
	var err error
	if cerr := p.rc.Control(func(fd uintptr) { err = ioctl(int(fd), req, arg) }); cerr != nil {
		return cerr
	}
	return err
}

func (p *uinputPad) ioctlPtr(req uintptr, arg unsafe.Pointer) error {
	return p.ioctl(req, uintptr(arg))
}

func (p *uinputPad) Update(s proto.State) error {
	var evs []inputEvent
	add := func(typ, code uint16, v int32) {
		evs = append(evs, inputEvent{Type: typ, Code: code, Value: v})
	}
	changed := func(a, b uint32) bool { return p.fresh || a != b }

	for _, b := range buttonMap {
		if changed(s.Buttons&b.bit, p.last.Buttons&b.bit) {
			v := int32(0)
			if s.Buttons&b.bit != 0 {
				v = 1
			}
			add(evKey, b.code, v)
		}
	}
	hat := func(neg, pos uint32) int32 {
		return int32(b2i(s.Buttons&pos != 0) - b2i(s.Buttons&neg != 0))
	}
	dpadMask := proto.BtnDUp | proto.BtnDDown | proto.BtnDLeft | proto.BtnDRight
	if changed(s.Buttons&dpadMask, p.last.Buttons&dpadMask) {
		add(evAbs, absHat0X, hat(proto.BtnDLeft, proto.BtnDRight))
		add(evAbs, absHat0Y, hat(proto.BtnDUp, proto.BtnDDown))
	}
	axis := func(code uint16, v, old int32) {
		if p.fresh || v != old {
			add(evAbs, code, v)
		}
	}
	axis(absX, int32(s.LX), int32(p.last.LX))
	axis(absY, int32(s.LY), int32(p.last.LY))
	axis(absRX, int32(s.RX), int32(p.last.RX))
	axis(absRY, int32(s.RY), int32(p.last.RY))
	axis(absZ, int32(s.LT), int32(p.last.LT))
	axis(absRZ, int32(s.RT), int32(p.last.RT))

	p.last, p.fresh = s, false
	if len(evs) == 0 {
		return nil
	}
	add(evSyn, 0, 0)
	size := int(unsafe.Sizeof(inputEvent{}))
	buf := unsafe.Slice((*byte)(unsafe.Pointer(&evs[0])), len(evs)*size)
	_, err := p.f.Write(buf)
	return err
}

func (p *uinputPad) Close() error {
	p.ioctl(uiDevDestroy, 0)
	return p.f.Close()
}

func b2i(b bool) int {
	if b {
		return 1
	}
	return 0
}

func ioctl(fd int, req, arg uintptr) error {
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), req, arg); e != 0 {
		return e
	}
	return nil
}
