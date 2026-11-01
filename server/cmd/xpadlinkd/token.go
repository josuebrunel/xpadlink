package main

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"strings"
)

// tokenPath is where the generated token persists, so restarts (and the
// background service) keep the token the phone already saved.
func tokenPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "xpadlink", "token"), nil
}

func randomToken() (string, error) {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// resolveToken picks the token in this order: the -token flag, the
// XPADLINK_TOKEN environment variable, the token file (created on first use).
// src says where it came from, for the startup log.
func resolveToken(flagValue, envValue, path string) (token, src string, err error) {
	if flagValue != "" {
		return flagValue, "flag", nil
	}
	if envValue != "" {
		return envValue, "env XPADLINK_TOKEN", nil
	}
	if b, rerr := os.ReadFile(path); rerr == nil {
		if t := strings.TrimSpace(string(b)); t != "" {
			return t, "file " + path, nil
		}
	} else if !errors.Is(rerr, os.ErrNotExist) {
		return "", "", rerr
	}
	t, err := randomToken()
	if err != nil {
		return "", "", err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return t, "random (not saved: " + err.Error() + ")", nil
	}
	if err := os.WriteFile(path, []byte(t+"\n"), 0o600); err != nil {
		return t, "random (not saved: " + err.Error() + ")", nil
	}
	return t, "new file " + path, nil
}
