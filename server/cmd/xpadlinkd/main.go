// xpadlinkd receives controller state over UDP or Bluetooth and exposes each
// client as a virtual gamepad through /dev/uinput.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/netip"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"xpadlink/bt"
	"xpadlink/dsu"
	"xpadlink/hub"
	"xpadlink/vpad"
)

func main() {
	if len(os.Args) > 1 && !strings.HasPrefix(os.Args[1], "-") {
		if err := runSubcommand(os.Args[1], os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, "xpadlinkd:", err)
			os.Exit(1)
		}
		return
	}

	listen := flag.String("listen", ":9777", "UDP listen address")
	token := flag.String("token", "", "shared token clients must send (default: $XPADLINK_TOKEN, else a token saved in the config dir)")
	maxPads := flag.Int("max", 4, "max simultaneous controllers")
	timeout := flag.Duration("timeout", 3*time.Second, "drop a client after this much silence")
	dsuAddr := flag.String("dsu", "127.0.0.1:26760", "Cemuhook DSU address serving phone motion to Cemu (empty to disable)")
	useBT := flag.Bool("bt", true, "accept phones over Bluetooth (Linux, needs bluetoothd)")
	dry := flag.Bool("dry", false, "log input instead of creating uinput devices")
	level := flag.String("log-level", "", "debug, info, warn or error (default info, debug with -dry)")
	flag.Parse()

	lvl := slog.LevelInfo
	if *dry {
		lvl = slog.LevelDebug
	}
	if *level != "" {
		if err := lvl.UnmarshalText([]byte(*level)); err != nil {
			fatal("invalid -log-level", err)
		}
	}
	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: lvl}))
	slog.SetDefault(log)

	path, err := tokenPath()
	if err != nil {
		fatal("locate config dir", err)
	}
	tok, tokSrc, err := resolveToken(*token, os.Getenv("XPADLINK_TOKEN"), path)
	if err != nil {
		fatal("resolve token", err)
	}
	*token = tok

	factory := vpad.Factory(vpad.NewUinput)
	if *dry {
		factory = vpad.NewLog
	}

	addr, err := net.ResolveUDPAddr("udp", *listen)
	if err != nil {
		fatal("resolve listen address", err)
	}
	conn, err := net.ListenUDP("udp", addr)
	if err != nil {
		fatal("listen", err)
	}
	log.Info("listening", "addr", conn.LocalAddr().String(), "token", *token, "token_source", tokSrc, "dry", *dry)
	logLANAddrs(addr.Port)

	var sink hub.MotionSink
	if *dsuAddr != "" {
		ds, err := dsu.Listen(*dsuAddr, log)
		if err != nil {
			log.Warn("motion server disabled", "addr", *dsuAddr, "err", err)
		} else {
			defer ds.Close()
			sink = ds
			log.Info("motion (DSU) listening", "addr", ds.Addr().String())
		}
	}

	host, _ := os.Hostname()
	in := make(chan inbound, 256)
	var btl *bt.Listener
	h := hub.New(hub.Config{
		Motion: sink,
		Token:  *token, MaxPads: *maxPads, Timeout: *timeout,
		New: factory, Log: log,
		Port: uint16(addr.Port), Hostname: host,
		Send: func(to hub.Peer, pkt []byte) { send(conn, btl, to, pkt) },
	})
	defer h.Close()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if *useBT {
		l, err := bt.Listen(log, func(mac string, pkt []byte) {
			select {
			case in <- inbound{pkt, hub.BTPeer(mac)}:
			case <-ctx.Done():
			}
		})
		if err != nil {
			log.Warn("bluetooth disabled", "err", err)
		} else {
			btl = l
			defer l.Close()
			log.Info("bluetooth listening", "uuid", bt.ServiceUUID)
		}
	}

	go readUDP(ctx, conn, in)

	tick := time.NewTicker(500 * time.Millisecond)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case m := <-in:
			now := time.Now()
			if reply := h.Handle(m.pkt, m.from, now); reply != nil {
				send(conn, btl, m.from, reply)
			}
			h.Reap(now)
		case now := <-tick.C:
			h.Reap(now)
		}
	}
}

// inbound is one packet from any link. Only the main goroutine drives the hub.
type inbound struct {
	pkt  []byte
	from hub.Peer
}

// readUDP feeds datagrams to in until ctx ends.
func readUDP(ctx context.Context, conn *net.UDPConn, in chan<- inbound) {
	go func() { <-ctx.Done(); conn.Close() }()
	buf := make([]byte, 512)
	for {
		n, from, err := conn.ReadFromUDPAddrPort(buf)
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return
			}
			slog.Error("read failed", "err", err)
			continue
		}
		select {
		case in <- inbound{append([]byte(nil), buf[:n]...), hub.UDPPeer(from)}:
		case <-ctx.Done():
			return
		}
	}
}

// send routes a packet to a peer by link. Safe to call from any goroutine.
func send(conn *net.UDPConn, btl *bt.Listener, to hub.Peer, pkt []byte) {
	switch link, addr, _ := strings.Cut(string(to), ":"); link {
	case "udp":
		if ap, err := netip.ParseAddrPort(addr); err == nil {
			conn.WriteToUDPAddrPort(pkt, ap)
		}
	case "bt":
		if btl != nil {
			btl.Send(addr, pkt)
		}
	}
}

func logLANAddrs(port int) {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		slog.Warn("list interfaces", "err", err)
		return
	}
	for _, a := range addrs {
		if ipn, ok := a.(*net.IPNet); ok && !ipn.IP.IsLoopback() && ipn.IP.To4() != nil {
			slog.Info("enter in the app", "addr", net.JoinHostPort(ipn.IP.String(), strconv.Itoa(port)))
		}
	}
}

func fatal(msg string, err error) {
	slog.Error(msg, "err", err)
	os.Exit(1)
}
