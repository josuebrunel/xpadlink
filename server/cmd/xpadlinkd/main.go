// xpadlinkd receives controller state over UDP and exposes each client as a
// virtual gamepad through /dev/uinput.
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"flag"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"xpadlink/hub"
	"xpadlink/vpad"
)

func main() {
	listen := flag.String("listen", ":9777", "UDP listen address")
	token := flag.String("token", "", "shared token clients must send (random if empty)")
	maxPads := flag.Int("max", 4, "max simultaneous controllers")
	timeout := flag.Duration("timeout", 3*time.Second, "drop a client after this much silence")
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

	if *token == "" {
		b := make([]byte, 3)
		if _, err := rand.Read(b); err != nil {
			fatal("generate token", err)
		}
		*token = hex.EncodeToString(b)
	}

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
	log.Info("listening", "addr", conn.LocalAddr().String(), "token", *token, "dry", *dry)
	logLANAddrs(addr.Port)

	h := hub.New(hub.Config{
		Token: *token, MaxPads: *maxPads, Timeout: *timeout,
		New: factory, Log: log,
	})
	defer h.Close()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() { <-ctx.Done(); conn.Close() }()

	buf := make([]byte, 512)
	for {
		conn.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
		n, from, err := conn.ReadFromUDPAddrPort(buf)
		now := time.Now()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return
			}
			var ne net.Error
			if !errors.As(err, &ne) || !ne.Timeout() {
				log.Error("read failed", "err", err)
			}
			h.Reap(now)
			continue
		}
		if reply := h.Handle(buf[:n], from, now); reply != nil {
			conn.WriteToUDPAddrPort(reply, from)
		}
		h.Reap(now)
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
