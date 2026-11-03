//go:build !linux

package bt

import (
	"errors"
	"log/slog"
)

type Handler func(mac string, pkt []byte)

type Listener struct{}

// Listen is not supported off Linux: BlueZ is the only backend.
func Listen(*slog.Logger, Handler) (*Listener, error) {
	return nil, errors.New("bluetooth is only supported on Linux")
}

func (*Listener) Send(string, []byte) {}
func (*Listener) Close() error        { return nil }
