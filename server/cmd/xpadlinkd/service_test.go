package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestResolveTokenPrecedenceAndPersistence(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cfg", "token")

	if tok, src, _ := resolveToken("flag", "env", path); tok != "flag" || src != "flag" {
		t.Fatalf("flag must win: %q %q", tok, src)
	}
	if tok, _, _ := resolveToken("", "env", path); tok != "env" {
		t.Fatalf("env must win over file: %q", tok)
	}
	if _, err := os.Stat(path); err == nil {
		t.Fatal("flag/env must not create the token file")
	}

	first, src, err := resolveToken("", "", path)
	if err != nil || len(first) != 8 || !strings.HasPrefix(src, "new file") {
		t.Fatalf("first run: %q %q %v", first, src, err)
	}
	second, src, _ := resolveToken("", "", path)
	if second != first || !strings.HasPrefix(src, "file") {
		t.Fatalf("token must persist: %q vs %q (%s)", second, first, src)
	}
	if fi, _ := os.Stat(path); fi.Mode().Perm() != 0o600 && os.PathSeparator == '/' {
		t.Fatalf("token file mode %v", fi.Mode().Perm())
	}
}

func TestSystemdUnit(t *testing.T) {
	u := systemdUnit("/opt/my dir/xpadlinkd", []string{"-listen", ":9777", "-max", "2"})
	for _, want := range []string{
		`ExecStart="/opt/my dir/xpadlinkd" -listen :9777 -max 2`,
		"Restart=on-failure",
		"WantedBy=default.target",
	} {
		if !strings.Contains(u, want) {
			t.Errorf("unit missing %q:\n%s", want, u)
		}
	}
}

func TestLaunchdPlistEscapes(t *testing.T) {
	p := launchdPlist("/usr/local/bin/xpadlinkd", []string{"-token", "a&b"}, "/tmp/x.log")
	if !strings.Contains(p, "<string>a&amp;b</string>") || !strings.Contains(p, "<key>KeepAlive</key>") {
		t.Fatalf("plist:\n%s", p)
	}
}

func TestWindowsTaskCommand(t *testing.T) {
	got := windowsTaskCommand(`C:\Program Files\x\xpadlinkd.exe`, []string{"-listen", ":9777"})
	if got != `"C:\Program Files\x\xpadlinkd.exe" -listen :9777` {
		t.Fatal(got)
	}
}
