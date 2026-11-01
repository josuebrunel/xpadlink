package vpad

import "testing"

type rumbleCall struct{ strong, weak, ms uint16 }

func trackerWithLog() (*ffTracker, *[]rumbleCall) {
	var calls []rumbleCall
	t := newFFTracker()
	t.setHandler(func(s, w, ms uint16) { calls = append(calls, rumbleCall{s, w, ms}) })
	return t, &calls
}

func TestFFPlayAndStop(t *testing.T) {
	tr, calls := trackerWithLog()
	tr.upload(3, ffEffect{strong: 40000, weak: 10000, length: 250})
	tr.play(3, 1)
	tr.play(3, 0)
	want := []rumbleCall{{40000, 10000, 250}, {0, 0, 0}}
	if len(*calls) != 2 || (*calls)[0] != want[0] || (*calls)[1] != want[1] {
		t.Fatalf("calls: %+v", *calls)
	}
}

func TestFFGainAndRepeat(t *testing.T) {
	tr, calls := trackerWithLog()
	tr.upload(1, ffEffect{strong: 60000, weak: 30000, length: 100})
	tr.setGain(0x8000)
	tr.play(1, 3)
	got := (*calls)[0]
	if got.ms != 300 || got.strong < 29000 || got.strong > 30001 || got.weak < 14500 || got.weak > 15001 {
		t.Fatalf("gain/repeat: %+v", got)
	}
}

func TestFFUnknownAndErased(t *testing.T) {
	tr, calls := trackerWithLog()
	tr.play(9, 1) // never uploaded
	tr.upload(2, ffEffect{strong: 1, length: 10})
	tr.erase(2)
	tr.play(2, 1)
	if len(*calls) != 0 {
		t.Fatalf("unexpected calls: %+v", *calls)
	}
}
