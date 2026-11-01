// Package proto defines the XPadLink wire format (UDP, little endian).
// Keep in sync with app/lib/protocol.dart and the Kotlin button bits.
package proto

import (
	"bytes"
	"encoding/binary"
	"errors"
)

const (
	Magic byte = 0xA7

	TypeHello     byte = 1 // client -> server: magic, 1, token, 0x00, name
	TypeAck       byte = 2 // server -> client: magic, 2, slot
	TypeNeedHello byte = 3 // server -> client: magic, 3 (state from unknown address)
	TypeState     byte = 4 // client -> server: see State.Marshal
	TypeBye       byte = 5 // client -> server: magic, 5

	StateLen = 18
)

// Button bits, Xbox 360 layout.
const (
	BtnA uint32 = 1 << iota
	BtnB
	BtnX
	BtnY
	BtnLB
	BtnRB
	BtnBack
	BtnStart
	BtnGuide
	BtnL3
	BtnR3
	BtnDUp
	BtnDDown
	BtnDLeft
	BtnDRight
)

var ErrBadPacket = errors.New("bad packet")

// State is the full controller state. Sticks are -32768..32767 (Y positive is
// down, like evdev), triggers are 0..255.
type State struct {
	Seq            uint16
	Buttons        uint32
	LX, LY, RX, RY int16
	LT, RT         uint8
}

func (s State) Marshal() []byte {
	b := make([]byte, StateLen)
	b[0], b[1] = Magic, TypeState
	binary.LittleEndian.PutUint16(b[2:], s.Seq)
	binary.LittleEndian.PutUint32(b[4:], s.Buttons)
	binary.LittleEndian.PutUint16(b[8:], uint16(s.LX))
	binary.LittleEndian.PutUint16(b[10:], uint16(s.LY))
	binary.LittleEndian.PutUint16(b[12:], uint16(s.RX))
	binary.LittleEndian.PutUint16(b[14:], uint16(s.RY))
	b[16], b[17] = s.LT, s.RT
	return b
}

func ParseState(b []byte) (State, error) {
	if len(b) != StateLen || b[0] != Magic || b[1] != TypeState {
		return State{}, ErrBadPacket
	}
	return State{
		Seq:     binary.LittleEndian.Uint16(b[2:]),
		Buttons: binary.LittleEndian.Uint32(b[4:]),
		LX:      int16(binary.LittleEndian.Uint16(b[8:])),
		LY:      int16(binary.LittleEndian.Uint16(b[10:])),
		RX:      int16(binary.LittleEndian.Uint16(b[12:])),
		RY:      int16(binary.LittleEndian.Uint16(b[14:])),
		LT:      b[16],
		RT:      b[17],
	}, nil
}

func MarshalHello(token, name string) []byte {
	b := []byte{Magic, TypeHello}
	b = append(b, token...)
	b = append(b, 0)
	return append(b, name...)
}

func ParseHello(b []byte) (token, name string, err error) {
	if len(b) < 3 || b[0] != Magic || b[1] != TypeHello {
		return "", "", ErrBadPacket
	}
	tok, nm, ok := bytes.Cut(b[2:], []byte{0})
	if !ok {
		return "", "", ErrBadPacket
	}
	return string(tok), string(nm), nil
}

// Newer reports whether sequence a is newer than b, handling uint16 wraparound.
func Newer(a, b uint16) bool { return int16(a-b) > 0 }
