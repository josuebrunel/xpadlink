package vpad

import "sync"

// Rumbler is implemented by pads that receive force feedback from games.
type Rumbler interface {
	// OnRumble sets the callback for vibration requests. ms 0 means "until
	// stopped"; strong and weak both 0 means stop. It may be called from any
	// goroutine.
	OnRumble(fn func(strong, weak, ms uint16))
}

type ffEffect struct{ strong, weak, length uint16 }

// ffTracker turns the kernel's force feedback protocol (upload, play, erase,
// gain) into rumble requests. It is pure logic so it can be tested without uinput.
type ffTracker struct {
	mu      sync.Mutex
	effects map[int16]ffEffect
	gain    uint32 // 0..0xFFFF
	fn      func(strong, weak, ms uint16)
}

func newFFTracker() *ffTracker {
	return &ffTracker{effects: map[int16]ffEffect{}, gain: 0xFFFF}
}

func (t *ffTracker) setHandler(fn func(strong, weak, ms uint16)) {
	t.mu.Lock()
	t.fn = fn
	t.mu.Unlock()
}

func (t *ffTracker) upload(id int16, e ffEffect) {
	t.mu.Lock()
	t.effects[id] = e
	t.mu.Unlock()
}

func (t *ffTracker) erase(id int16) {
	t.mu.Lock()
	delete(t.effects, id)
	t.mu.Unlock()
}

func (t *ffTracker) setGain(g uint32) {
	t.mu.Lock()
	t.gain = g & 0xFFFF
	t.mu.Unlock()
}

// play handles an EV_FF event: count is the repeat count, 0 stops.
func (t *ffTracker) play(id int16, count int32) {
	t.mu.Lock()
	fn, e, ok, gain := t.fn, t.effects[id], false, t.gain
	_, ok = t.effects[id]
	t.mu.Unlock()
	if fn == nil {
		return
	}
	if count <= 0 {
		fn(0, 0, 0)
		return
	}
	if !ok {
		return
	}
	scale := func(v uint16) uint16 { return uint16(uint32(v) * gain / 0xFFFF) }
	ms := uint32(e.length)
	if count > 1 && ms > 0 {
		ms *= uint32(count)
	}
	if ms > 0xFFFF {
		ms = 0xFFFF
	}
	fn(scale(e.strong), scale(e.weak), uint16(ms))
}
