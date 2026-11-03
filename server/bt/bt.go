// Package bt carries the XPadLink packets over a Bluetooth RFCOMM stream.
// A stream has no datagram boundaries, so each packet is prefixed with its
// length (u16, little endian). The packet bytes are the same as over UDP.
package bt

import (
	"encoding/binary"
	"errors"
	"io"
)

// MaxPacket is the largest packet accepted, the size of the UDP read buffer.
const MaxPacket = 512

// ServiceUUID is the RFCOMM service the phone looks for. Keep in sync with
// app/kotlin/MainActivity.kt.
const ServiceUUID = "6f1d8a52-3c1e-4b7a-9e0d-5a7c2f4b8d11"

var ErrBadFrame = errors.New("bad frame length")

// Frame returns pkt with its length prefix.
func Frame(pkt []byte) []byte {
	b := make([]byte, 2, 2+len(pkt))
	binary.LittleEndian.PutUint16(b, uint16(len(pkt)))
	return append(b, pkt...)
}

// ReadFrame reads one packet. A zero or oversized length means the stream is
// out of sync or hostile: the caller must close the connection.
func ReadFrame(r io.Reader) ([]byte, error) {
	var h [2]byte
	if _, err := io.ReadFull(r, h[:]); err != nil {
		return nil, err
	}
	n := int(binary.LittleEndian.Uint16(h[:]))
	if n == 0 || n > MaxPacket {
		return nil, ErrBadFrame
	}
	pkt := make([]byte, n)
	if _, err := io.ReadFull(r, pkt); err != nil {
		return nil, err
	}
	return pkt, nil
}
