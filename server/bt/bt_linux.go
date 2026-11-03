package bt

import (
	"bufio"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/godbus/dbus/v5"
)

const profilePath = dbus.ObjectPath("/xpadlink/profile")

// channel is the RFCOMM channel in the SDP record. The phone finds it by UUID.
const channel = 22

// sdpRecord is published by hand: BlueZ doesn't build a record for a custom UUID,
// and without one the phone's service lookup fails.
var sdpRecord = fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8" ?>
<record>
  <attribute id="0x0001"><sequence><uuid value="%s"/></sequence></attribute>
  <attribute id="0x0004"><sequence>
    <sequence><uuid value="0x0100"/></sequence>
    <sequence><uuid value="0x0003"/><uint8 value="%d"/></sequence>
  </sequence></attribute>
  <attribute id="0x0005"><sequence><uuid value="0x1002"/></sequence></attribute>
  <attribute id="0x0100"><text value="XPadLink"/></attribute>
</record>`, ServiceUUID, channel)

// writeTimeout bounds a send so a stalled link can't block the hub.
const writeTimeout = 200 * time.Millisecond

// Handler receives each packet read from the device with the given MAC.
type Handler func(mac string, pkt []byte)

// Listener accepts Bluetooth connections through a BlueZ profile.
type Listener struct {
	bus *dbus.Conn
	log *slog.Logger
	on  Handler

	mu    sync.Mutex
	conns map[string]*conn
}

type conn struct {
	mac string
	f   *os.File
	wmu sync.Mutex
}

// Listen registers the XPadLink RFCOMM service with BlueZ. Pair the phone with
// the PC in the system settings first.
func Listen(log *slog.Logger, on Handler) (*Listener, error) {
	bus, err := dbus.SystemBus()
	if err != nil {
		return nil, fmt.Errorf("system bus: %w", err)
	}
	l := &Listener{bus: bus, log: log, on: on, conns: map[string]*conn{}}
	if err := bus.Export(&profile{l}, profilePath, "org.bluez.Profile1"); err != nil {
		return nil, fmt.Errorf("export profile: %w", err)
	}
	opts := map[string]dbus.Variant{
		"Name":          dbus.MakeVariant("XPadLink"),
		"Role":          dbus.MakeVariant("server"),
		"Channel":       dbus.MakeVariant(uint16(channel)),
		"ServiceRecord": dbus.MakeVariant(sdpRecord),
		// Pairing is required. Authorization is not: it would make BlueZ ask a
		// desktop agent on every connection, and the connect fails if nobody answers.
		"RequireAuthentication": dbus.MakeVariant(true),
		"RequireAuthorization":  dbus.MakeVariant(false),
	}
	call := bus.Object("org.bluez", "/org/bluez").Call("org.bluez.ProfileManager1.RegisterProfile", 0, profilePath, ServiceUUID, opts)
	if call.Err != nil {
		return nil, fmt.Errorf("register profile (is bluetoothd running?): %w", call.Err)
	}
	return l, nil
}

// Send writes a packet to the device, if it is connected.
func (l *Listener) Send(mac string, pkt []byte) {
	l.mu.Lock()
	c := l.conns[mac]
	l.mu.Unlock()
	if c == nil {
		return
	}
	if err := c.write(pkt); err != nil {
		l.log.Debug("bt write failed", "mac", mac, "err", err)
		c.f.Close() // the reader sees the error and cleans up
	}
}

func (l *Listener) Close() error {
	l.bus.Object("org.bluez", "/org/bluez").Call("org.bluez.ProfileManager1.UnregisterProfile", 0, profilePath)
	l.mu.Lock()
	for _, c := range l.conns {
		c.f.Close()
	}
	l.mu.Unlock()
	return l.bus.Close()
}

func (c *conn) write(pkt []byte) error {
	c.wmu.Lock()
	defer c.wmu.Unlock()
	c.f.SetWriteDeadline(time.Now().Add(writeTimeout))
	_, err := c.f.Write(Frame(pkt))
	return err
}

func (l *Listener) add(mac string, fd int) {
	// The fd must be non-blocking for os.NewFile to make it pollable, otherwise
	// Close can't wake the reader and shutdown hangs.
	if err := syscall.SetNonblock(fd, true); err != nil {
		syscall.Close(fd)
		l.log.Error("bt set nonblock failed", "mac", mac, "err", err)
		return
	}
	c := &conn{mac: mac, f: os.NewFile(uintptr(fd), "bt:"+mac)}
	l.mu.Lock()
	old := l.conns[mac]
	l.conns[mac] = c
	l.mu.Unlock()
	if old != nil {
		old.f.Close()
	}
	l.log.Info("bt connected", "mac", mac)
	go l.read(c)
}

func (l *Listener) read(c *conn) {
	r := bufio.NewReader(c.f)
	var err error
	for {
		var pkt []byte
		if pkt, err = ReadFrame(r); err != nil {
			break
		}
		l.on(c.mac, pkt)
	}
	c.f.Close()
	l.mu.Lock()
	// A reconnect may already have replaced us: only remove our own entry.
	if l.conns[c.mac] == c {
		delete(l.conns, c.mac)
	}
	l.mu.Unlock()
	l.log.Info("bt disconnected", "mac", c.mac, "err", err)
}

func (l *Listener) drop(mac string) {
	l.mu.Lock()
	c := l.conns[mac]
	l.mu.Unlock()
	if c != nil {
		c.f.Close()
	}
}

// profile implements org.bluez.Profile1.
type profile struct{ l *Listener }

func (p *profile) NewConnection(dev dbus.ObjectPath, fd dbus.UnixFD, _ map[string]dbus.Variant) *dbus.Error {
	p.l.add(macOf(dev), int(fd))
	return nil
}

func (p *profile) RequestDisconnection(dev dbus.ObjectPath) *dbus.Error {
	p.l.drop(macOf(dev))
	return nil
}

func (p *profile) Release() *dbus.Error { return nil }

// macOf turns /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF into AA:BB:CC:DD:EE:FF.
func macOf(dev dbus.ObjectPath) string {
	s := string(dev)
	s = s[strings.LastIndexByte(s, '/')+1:]
	return strings.ReplaceAll(strings.TrimPrefix(s, "dev_"), "_", ":")
}
