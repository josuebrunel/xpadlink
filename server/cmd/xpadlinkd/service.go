package main

import (
	"errors"
	"fmt"
	"html"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
)

const (
	serviceName  = "xpadlinkd"
	launchdLabel = "com.xpadlink.xpadlinkd"
)

// runSubcommand handles `xpadlinkd install|uninstall|token`.
func runSubcommand(cmd string, args []string) error {
	switch cmd {
	case "install":
		return installService(args)
	case "uninstall":
		return uninstallService()
	case "token":
		path, err := tokenPath()
		if err != nil {
			return err
		}
		t, _, err := resolveToken("", os.Getenv("XPADLINK_TOKEN"), path)
		if err != nil {
			return err
		}
		fmt.Println(t)
		return nil
	}
	return fmt.Errorf("unknown command %q (use install, uninstall or token)", cmd)
}

func installService(args []string) error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if exe, err = filepath.EvalSymlinks(exe); err != nil {
		return err
	}
	// Make sure the token exists before the service starts, and show it once.
	path, err := tokenPath()
	if err != nil {
		return err
	}
	tok, _, err := resolveToken("", os.Getenv("XPADLINK_TOKEN"), path)
	if err != nil {
		return err
	}
	if runtime.GOOS != "linux" {
		fmt.Fprintln(os.Stderr, "note: virtual pads need Linux (uinput); on this OS the service can only run with -dry")
	}

	switch runtime.GOOS {
	case "linux":
		err = installSystemd(exe, args)
	case "darwin":
		err = installLaunchd(exe, args)
	case "windows":
		err = installTask(exe, args)
	default:
		err = fmt.Errorf("service install is not supported on %s", runtime.GOOS)
	}
	if err != nil {
		return err
	}
	fmt.Printf("installed and started. token: %s\n", tok)
	return nil
}

func uninstallService() error {
	switch runtime.GOOS {
	case "linux":
		return uninstallSystemd()
	case "darwin":
		return uninstallLaunchd()
	case "windows":
		return uninstallTask()
	}
	return fmt.Errorf("service uninstall is not supported on %s", runtime.GOOS)
}

func run(name string, args ...string) error {
	out, err := exec.Command(name, args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return nil
}

// ---- Linux: systemd user unit ----

func systemdQuote(s string) string {
	if s != "" && !strings.ContainsAny(s, " \t\"'\\") {
		return s
	}
	return strconv.Quote(s)
}

func systemdUnit(exe string, args []string) string {
	parts := []string{systemdQuote(exe)}
	for _, a := range args {
		parts = append(parts, systemdQuote(a))
	}
	return "[Unit]\nDescription=XPadLink daemon (phone as gamepad)\nAfter=network-online.target\n\n" +
		"[Service]\nExecStart=" + strings.Join(parts, " ") + "\nRestart=on-failure\nRestartSec=2\n\n" +
		"[Install]\nWantedBy=default.target\n"
}

func systemdUnitPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "systemd", "user", serviceName+".service"), nil
}

func installSystemd(exe string, args []string) error {
	p, err := systemdUnitPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(p, []byte(systemdUnit(exe, args)), 0o644); err != nil {
		return err
	}
	if err := run("systemctl", "--user", "daemon-reload"); err != nil {
		return err
	}
	return run("systemctl", "--user", "enable", "--now", serviceName+".service")
}

func uninstallSystemd() error {
	p, err := systemdUnitPath()
	if err != nil {
		return err
	}
	_ = run("systemctl", "--user", "disable", "--now", serviceName+".service")
	if err := os.Remove(p); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return run("systemctl", "--user", "daemon-reload")
}

// ---- macOS: launchd LaunchAgent ----

func launchdPlist(exe string, args []string, logPath string) string {
	var b strings.Builder
	b.WriteString(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>` + launchdLabel + `</string>
  <key>ProgramArguments</key>
  <array>
`)
	for _, a := range append([]string{exe}, args...) {
		b.WriteString("    <string>" + html.EscapeString(a) + "</string>\n")
	}
	b.WriteString(`  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>` + html.EscapeString(logPath) + `</string>
</dict>
</plist>
`)
	return b.String()
}

func launchdPaths() (plist, logPath string, err error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", "", err
	}
	return filepath.Join(home, "Library", "LaunchAgents", launchdLabel+".plist"),
		filepath.Join(home, "Library", "Logs", "xpadlinkd.log"), nil
}

func installLaunchd(exe string, args []string) error {
	plist, logPath, err := launchdPaths()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(plist), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(plist, []byte(launchdPlist(exe, args, logPath)), 0o644); err != nil {
		return err
	}
	domain := "gui/" + strconv.Itoa(os.Getuid())
	_ = run("launchctl", "bootout", domain, plist) // replace a previous install
	return run("launchctl", "bootstrap", domain, plist)
}

func uninstallLaunchd() error {
	plist, _, err := launchdPaths()
	if err != nil {
		return err
	}
	_ = run("launchctl", "bootout", "gui/"+strconv.Itoa(os.Getuid()), plist)
	if err := os.Remove(plist); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

// ---- Windows: scheduled task at logon (no extra dependencies) ----

func windowsTaskCommand(exe string, args []string) string {
	parts := []string{`"` + exe + `"`}
	for _, a := range args {
		if strings.ContainsAny(a, " \t") {
			a = `\"` + a + `\"`
		}
		parts = append(parts, a)
	}
	return strings.Join(parts, " ")
}

func installTask(exe string, args []string) error {
	if err := run("schtasks", "/Create", "/F", "/SC", "ONLOGON", "/TN", serviceName,
		"/TR", windowsTaskCommand(exe, args)); err != nil {
		return err
	}
	return run("schtasks", "/Run", "/TN", serviceName)
}

func uninstallTask() error {
	_ = run("schtasks", "/End", "/TN", serviceName)
	return run("schtasks", "/Delete", "/F", "/TN", serviceName)
}
