// xpadsim is a fake client for testing the server without a phone.
// It sweeps the left stick in a circle, taps A once a second and prints any
// rumble the server forwards.
package main

import (
	"flag"
	"log"
	"math"
	"net"
	"time"

	"xpadlink/proto"
)

func main() {
	server := flag.String("server", "127.0.0.1:9777", "server host:port")
	token := flag.String("token", "", "server token")
	dur := flag.Duration("for", 10*time.Second, "how long to run")
	flag.Parse()

	conn, err := net.Dial("udp", *server)
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()

	buf := make([]byte, 64)
	conn.Write(proto.MarshalHello(*token, "xpadsim"))
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	n, err := conn.Read(buf)
	if err != nil || n < 3 || buf[1] != proto.TypeAck {
		log.Fatalf("no ack from server (wrong token or server down): %v", err)
	}
	log.Printf("joined as player %d", buf[2]+1)
	conn.SetReadDeadline(time.Time{})

	// Show vibration requests, so a game's rumble can be checked without a phone.
	go func() {
		b := make([]byte, 64)
		for {
			n, err := conn.Read(b)
			if err != nil {
				return
			}
			if strong, weak, ms, err := proto.ParseRumble(b[:n]); err == nil {
				log.Printf("rumble: strong=%d weak=%d ms=%d", strong, weak, ms)
			}
		}
	}()

	start := time.Now()
	var seq uint16
	for t := range time.Tick(16 * time.Millisecond) {
		el := t.Sub(start)
		if el > *dur {
			break
		}
		a := el.Seconds() * 2
		s := proto.State{
			Seq: seq,
			LX:  int16(math.Cos(a) * 32000),
			LY:  int16(math.Sin(a) * 32000),
		}
		if el%time.Second < 200*time.Millisecond {
			s.Buttons |= proto.BtnA
		}
		seq++
		conn.Write(s.Marshal())
	}
	conn.Write([]byte{proto.Magic, proto.TypeBye})
}
