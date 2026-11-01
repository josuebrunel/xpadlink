// Package vpad creates virtual gamepads on the host.
package vpad

import (
	"fmt"
	"log/slog"

	"xpadlink/proto"
)

// Pad is one virtual gamepad.
type Pad interface {
	Update(proto.State) error
	Close() error
}

// Factory creates a pad with the given device name.
type Factory func(name string) (Pad, error)

type logPad struct {
	name string
	last proto.State
}

// NewLog is a dry-run Factory: it logs state changes instead of touching uinput.
func NewLog(name string) (Pad, error) {
	slog.Info("dry pad created", "name", name)
	return &logPad{name: name}, nil
}

func (p *logPad) Update(s proto.State) error {
	s.Seq = p.last.Seq
	if s != p.last {
		slog.Debug("dry pad state", "name", p.name,
			"buttons", fmt.Sprintf("%015b", s.Buttons),
			"lx", s.LX, "ly", s.LY, "rx", s.RX, "ry", s.RY, "lt", s.LT, "rt", s.RT)
		p.last = s
	}
	return nil
}

func (p *logPad) Close() error {
	slog.Info("dry pad destroyed", "name", p.name)
	return nil
}

// OnRumble is a no-op: a dry-run pad never receives force feedback.
func (p *logPad) OnRumble(func(strong, weak, ms uint16)) {}
